# JSON-RPC v2 typed values and fixtures

Protocol v2 keeps ordinary JSON compact and uses a collision-safe `$liquid-spec`
envelope for values that JSON cannot preserve. The wire-level shapes are defined in
[`json-rpc-protocol-v2.md`](json-rpc-protocol-v2.md) and its
[JSON Schema](json-rpc-protocol-v2.schema.json).

```json
{"$liquid-spec":{"type":"integer","value":"9007199254740993"}}
{"$liquid-spec":{"type":"bytes","base64":"AP8="}}
{"$liquid-spec":{"type":"datetime","value":"2024-01-01T00:00:00Z"}}
{"$liquid-spec":{"type":"fixture","set":"standard-drops","version":1,
  "name":"BooleanDrop","params":{"value":false}}}
```

Supported envelope types are `object`, `integer`, `float`, `bytes`, `symbol`,
`date`, `time`, `datetime`, `range`, `map`, and `fixture`. An ordinary object with a
`$liquid-spec` key must be escaped as an `object` envelope, so user data cannot be
mistaken for a typed value. Adapters must preserve these values in
`protocol.echo`, environment values, and render output.

## Standard fixtures instead of RPC drops

Protocol v2 has no server-to-client callbacks and does not accept `_rpc_drop`,
`_ruby_type`, `drop_get`, `drop_iterate`, or `drop_call`. Those mechanisms made a
Ruby object graph part of the transport and could not be implemented consistently
by non-Ruby engines. Use versioned `standard-drops` fixtures instead:

```json
{"$liquid-spec":{"type":"fixture","set":"standard-drops","version":1,
  "name":"SequenceDrop","params":{"items":["a","b"]}}}
```

Each adapter materializes a fixture natively. The fixture name, version, params,
property lookups, iteration, and string conversion are language-neutral; the
catalog and expected behavior live in [`test_drops.md`](test_drops.md). Advertise
supported sets and versions in `initialize.capabilities.fixture_sets`.

## Migrating old specs

Specs that only observed a drop's portable behavior should use a standard fixture.
Specs that asserted Ruby exception classes, `Hash#inspect`, `SafeBuffer`, symbols,
or other runtime details belong to the optional `ruby_compat` feature and may be
skipped by non-Ruby adapters. Do not invent a marker that asks the runner to create
an object or call back into the adapter.
