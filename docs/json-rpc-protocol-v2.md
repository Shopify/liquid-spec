# liquid-spec JSON-RPC protocol v2

Protocol v2 is the only adapter boundary used by the Rust `liquid-spec` binary.
An adapter is a child process. The runner writes one JSON-RPC 2.0 message per line
to stdin and reads one response per line from stdout. Adapter diagnostics belong on
stderr; any non-JSON-RPC stdout is a protocol failure.

The protocol intentionally has no callbacks. In particular, a server must not ask
the runner to resolve Ruby objects (`_rpc_drop`, `drop_get`, and `drop_call` were
removed). Portable object behavior is represented by versioned standard fixtures.
See `docs/test_drops.md` for the fixture catalog.

## Lifecycle

The client starts a fresh process for each adapter run and sends:

1. `initialize`
2. zero or more compile/render/release requests
3. the `shutdown` notification

Every request has a monotonically increasing unsigned integer `id`. A notification
has no `id` and receives no response. The server must keep template handles private
to the process and release them after `template.release`.

### initialize

```json
{"jsonrpc":"2.0","id":1,"method":"initialize","params":{
  "protocol_versions":["2"],
  "client":{"name":"liquid-spec","version":"2.0.0","language":"rust"}
}}
```

The result selects exactly one protocol version and identifies the implementation:

```json
{"jsonrpc":"2.0","id":1,"result":{
  "protocol_version":"2",
  "implementation":{"name":"my-liquid","version":"1.4.0","language":"go"},
  "capabilities":{
    "parse_modes":["strict2"],
    "features":["core","standard-drops"],
    "fixture_sets":{"standard-drops":1},
    "artifacts":false,
    "benchmark":false
  }
}}
```

`parse_modes` and `features` are positive claims. The runner skips a spec only when
the adapter does not advertise a feature required by that spec. `fixture_sets` maps
fixture-set names to supported versions. `artifacts` and `benchmark` advertise the
optional artifact and timing extensions.

The built-in standard drop catalog is advertised as `fixture_sets:
{"standard-drops":1}` and satisfies specs tagged `drops`. Ruby-only fixture
descriptors are tagged `ruby_compat` by the loader and are expected to be offered
only by the external Ruby reference adapter.

### protocol.echo

The runner uses this method during conformance checks. The server must return the
`params` value byte-for-byte in meaning (including typed values):

```json
{"jsonrpc":"2.0","id":2,"method":"protocol.echo","params":{
  "value":{"$liquid-spec":{"type":"bytes","base64":"AP8="}}
}}
```

### template.compile

```json
{"jsonrpc":"2.0","id":3,"method":"template.compile","params":{
  "bundle":{"entry":"main","sources":{"main":"Hello {{ name }}!"}},
  "options":{"parse_mode":"strict2","line_numbers":true}
}}
```

`bundle.sources` contains the entry and all filesystem/partial sources. The server
must parse/prepare every supplied source before returning. A syntax error in an
unused partial is retained as a deferred compiled failure and is reported when
that partial is rendered; it must not cause parsing work during render timing.

Success returns an opaque handle:

```json
{"jsonrpc":"2.0","id":3,"result":{"ok":{"template_id":"t1"}}}
```

Liquid parse failures are valid Liquid outcomes, not JSON-RPC failures:

```json
{"jsonrpc":"2.0","id":3,"result":{"error":{
  "phase":"parse","code":"syntax_error","message":"Unknown tag",
  "location":{"template":"main","line":1,"column":1},"causes":[]
}}}
```

### template.render

```json
{"jsonrpc":"2.0","id":4,"method":"template.render","params":{
  "template_id":"t1","environment":{"name":"Ada"},
  "options":{"error_policy":"raise","now":"2024-01-01T00:00:00Z"}
}}
```

The result is either `{ "ok": { "output": VALUE, "diagnostics": [] } }` or
`{ "error": LIQUID_ERROR }`. `error_policy` is `raise` (default) or `inline`;
inline errors stay in the successful output and are also listed in `diagnostics`.
`now` freezes the Liquid clock for this render. `resource_limits` is an opaque
object whose keys are defined by the advertised implementation.

Rendering is independent of parsing: a render request receives only a compiled
handle and must not parse source or consult the source bundle. This invariant lets
the benchmark command time compilation and rendering separately.

### template.release

```json
{"jsonrpc":"2.0","id":5,"method":"template.release","params":{"template_id":"t1"}}
```

The result is `{ "ok": {} }`. Releasing an unknown or already released handle is
JSON-RPC `-32602` (invalid params), as is rendering an unknown handle.

### shutdown

```json
{"jsonrpc":"2.0","method":"shutdown"}
```

The server should stop reading after flushing outstanding responses. A response to
this notification is not allowed.

## Errors and framing

JSON-RPC errors are reserved for protocol failures: malformed JSON (`-32700`),
unknown method (`-32601`), invalid parameters/handles (`-32602`), and implementation
errors (`-32603`). Their shape is the standard JSON-RPC object:

```json
{"jsonrpc":"2.0","id":7,"error":{"code":-32602,"message":"unknown template_id"}}
```

Liquid errors use the typed result union above. A `LiquidError` has `phase` (`parse`
or `render`), stable `code`, human `message`, optional source `location`, and nested
`causes`. Clients should match `code` and stable message substrings rather than full
runtime wording.

The runner validates response IDs, rejects duplicate/missing result and error fields,
enforces an adapter timeout, and fails the run before loading Liquid specs when the
protocol conformance gate fails.

## Typed values

Strings, booleans, null, finite JSON numbers, arrays, and string-keyed objects use
ordinary JSON. Values JSON cannot represent are encoded with the collision-safe
`$liquid-spec` envelope:

```json
{"$liquid-spec":{"type":"integer","value":"9007199254740993"}}
{"$liquid-spec":{"type":"bytes","base64":"AAE="}}
{"$liquid-spec":{"type":"symbol","value":"draft"}}
{"$liquid-spec":{"type":"range","start":1,"end":4,"exclusive":true}}
{"$liquid-spec":{"type":"fixture","set":"standard-drops","version":1,
  "name":"BooleanDrop","params":{"value":false}}}
```

An ordinary object containing a `$liquid-spec` key is escaped as
`{"$liquid-spec":{"type":"object","value":{...}}}`. Unknown envelope types are
invalid parameters. The complete JSON Schema is in
`docs/json-rpc-protocol-v2.schema.json`; executable echo and lifecycle vectors are
in `docs/json-rpc-protocol-v2-vectors.json`.

## Capability and extension policy

Adapters may advertise `artifacts` or `benchmark`; the core protocol does not require
either extension. A benchmark-capable adapter implements the `benchmark.run` method
with a request shaped like this:

```json
{"jsonrpc":"2.0","id":20,"method":"benchmark.run","params":{
  "version":"1","operation":"render","template_id":"t1",
  "environment":{"name":"Ada"},"render_options":{"error_policy":"raise"},
  "iterations":1000,"warmup_iterations":20
}}
```

`operation` is `compile`, `render`, or `artifact_load`. Compile receives `bundle` and
`compile_options`; render receives only an existing `template_id` (never a source
bundle); artifact load receives an implementation-owned typed `artifact`. The result
reports `{ "version":"1", "operation":..., "iterations":..., "batches":
[{"iterations":N,"elapsed_ns":N}], "digest": VALUE }`, and may include an
artifact for compile/load operations. `digest` must change when the operation's
observable result changes, preventing no-op benchmark servers from reporting
plausible timings.

`liquid-spec bench` measures server-side monotonic-clock batches: compile timing
includes parsing, render timing starts from an existing handle, and transport latency
is reported separately. A render batch must not parse source. Fresh render context
creation belongs inside the render timer; request decoding and fixture construction
belong outside it.
