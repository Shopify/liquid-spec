# Liquid JSON-RPC Protocol Specification

This document specifies the JSON-RPC 2.0 protocol for implementing Liquid template engines that can be tested with liquid-spec.

## Design Principles

1. **Protocol errors are for protocol failures** - Invalid JSON, malformed requests, missing methods, and invalid parameters use JSON-RPC `error` responses.
2. **Liquid errors are test behavior** - Parse/render errors should be reported in a stable shape so liquid-spec can match them. The preferred shape is `result.error` / `result.errors`; liquid-spec also accepts legacy `-32000` / `-32001` JSON-RPC errors from older servers.
3. **Explicit over implicit** - All options are documented and validated.
4. **Helpful error messages** - Invalid requests explain what went wrong.
5. **Deterministic testing** - Time can be frozen for reproducible tests.

## Methods

### `initialize`

Called once when the connection starts.

**Request:**
```json
{
  "jsonrpc": "2.0",
  "id": 1,
  "method": "initialize",
  "params": {
    "version": "1.0"
  }
}
```

**Response:**
```json
{
  "jsonrpc": "2.0",
  "id": 1,
  "result": {
    "version": "1.0",
    "implementation": "my-liquid",
    "liquid_version": "6.0.0",
    "features": ["drops"]
  }
}
```

**Features:**

`features` is informational metadata reported by the subprocess. Spec selection
happens in the Ruby adapter: use `config.error_modes` for parse modes,
`config.render_error_modes` for raised/inline render behavior, and
`config.missing_features` for other capabilities.

Common feature names:
- `drops` - Supports Liquid drop objects. Portable standard test drops are documented in `docs/test_drops.md`; the callback protocol below supports host-owned runtime drops.

Parse-mode support is declared by the Ruby adapter's `config.error_modes`, not
the subprocess feature list.

For a minimal JSON-RPC server, start with `features: []`, declare
`config.error_modes = [:strict2]` and `config.render_error_modes = [:raise]`,
then use `config.missing_features` for unsupported capabilities such as drops,
Ruby types, binary data, and Shopify-specific features.

### `compile`

Parse a Liquid template and store it for later rendering.

**Request:**
```json
{
  "jsonrpc": "2.0",
  "id": 2,
  "method": "compile",
  "params": {
    "template": "Hello {{ name | upcase }}!",
    "options": {
      "error_mode": "strict",
      "line_numbers": true
    },
    "filesystem": {
      "greeting.liquid": "Hello {{ name }}!"
    }
  }
}
```

**Parameters:**
| Name | Type | Required | Description |
|------|------|----------|-------------|
| `template` | string | yes | The Liquid template source |
| `options.error_mode` | string | no | `"strict2"`, `"strict"`, `"lax"`, or omitted/null |
| `options.line_numbers` | boolean | no | Track line numbers for errors |
| `filesystem` | object | no | Map of filename → content for includes/renders |

**Success Response:**
```json
{
  "jsonrpc": "2.0",
  "id": 2,
  "result": {
    "template_id": "tmpl_1"
  }
}
```

**Parse Error Response:**
```json
{
  "jsonrpc": "2.0",
  "id": 2,
  "result": {
    "template_id": null,
    "error": {
      "type": "syntax_error",
      "message": "Unknown tag 'invalid_tag'",
      "line": 1
    }
  }
}
```

Preferred: return parse errors in `result.error` rather than as JSON-RPC errors. This keeps Liquid syntax failures separate from transport/protocol failures. For compatibility with older JSON-RPC servers, liquid-spec also accepts JSON-RPC error code `-32000` with `data.type: "parse_error"`.

### `render`

Render a compiled template with environment variables.

**Request:**
```json
{
  "jsonrpc": "2.0",
  "id": 3,
  "method": "render",
  "params": {
    "template_id": "tmpl_1",
    "environment": {
      "name": "World",
      "items": [1, 2, 3]
    },
    "options": {
      "strict_errors": true,
      "registers": {
        "current_time": "2024-01-01T00:01:58Z"
      }
    }
  }
}
```

**Parameters:**
| Name | Type | Required | Description |
|------|------|----------|-------------|
| `template_id` | string | yes | ID from compile response |
| `environment` | object | no | Variables available to the template |
| `options.strict_errors` | boolean | no | If true, render errors should be reported as errors; if false, render them inline in `output` when possible |
| `options.resource_limits` | object | no | Resource limits: `render_score_limit` (int), `cumulative_render_score_limit` (int) |
| `options.registers` | object | no | Host render context, separate from template variables; primitive values only |
| `options.registers.current_time` | string | no | ISO 8601 clock for date/time filters and drops |

**Response (always success for valid template_id):**
```json
{
  "jsonrpc": "2.0",
  "id": 3,
  "result": {
    "output": "Hello WORLD!",
    "errors": []
  }
}
```

**Response with an inline render error (`strict_errors: false`):**
```json
{
  "jsonrpc": "2.0",
  "id": 3,
  "result": {
    "output": "Liquid error (line 1): cannot sort values of incompatible types",
    "errors": [
      {
        "type": "render_error",
        "message": "cannot sort values of incompatible types",
        "line": 1
      }
    ]
  }
}
```

**Response with a raised render error (`strict_errors: true`):**
```json
{
  "jsonrpc": "2.0",
  "id": 3,
  "result": {
    "output": null,
    "error": {
      "type": "render_error",
      "message": "cannot sort values of incompatible types",
      "line": 1
    }
  }
}
```

Preferred: return raised render errors in `result.error`. For compatibility with older servers, liquid-spec also accepts JSON-RPC error code `-32001` with `data.type: "render_error"`. If `strict_errors` is false and an older server sends a render error as a JSON-RPC error, liquid-spec converts it to inline `Liquid error: ...` output.

### `quit` (notification)

Gracefully shutdown the server. No response expected.

```json
{
  "jsonrpc": "2.0",
  "method": "quit"
}
```

## Drop Callbacks

Drops are Ruby objects that need dynamic property access during rendering. When the environment contains a drop marker:

```json
{
  "environment": {
    "user": {
      "_rpc_drop": "drop_1",
      "type": "UserDrop"
    }
  }
}
```

The server must call back to the client to access properties.

### `drop_get` (server → client)

Request a property from a drop.

**Request (from server):**
```json
{
  "jsonrpc": "2.0",
  "id": 100,
  "method": "drop_get",
  "params": {
    "drop_id": "drop_1",
    "property": "name"
  }
}
```

**Response (from client):**
```json
{
  "jsonrpc": "2.0",
  "id": 100,
  "result": {
    "value": "Alice"
  }
}
```

If the value is itself a drop:
```json
{
  "jsonrpc": "2.0",
  "id": 100,
  "result": {
    "value": {
      "_rpc_drop": "drop_2",
      "type": "AddressDrop"
    }
  }
}
```

### `drop_iterate` (server → client)

Get all items from an iterable drop (for `{% for %}` loops).

**Request:**
```json
{
  "jsonrpc": "2.0",
  "id": 101,
  "method": "drop_iterate",
  "params": {
    "drop_id": "drop_1"
  }
}
```

**Response:**
```json
{
  "jsonrpc": "2.0",
  "id": 101,
  "result": {
    "items": [1, 2, 3, 4, 5]
  }
}
```

### `drop_call` (server → client)

Call a method on a drop with arguments.

**Request:**
```json
{
  "jsonrpc": "2.0",
  "id": 102,
  "method": "drop_call",
  "params": {
    "drop_id": "drop_1",
    "method": "calculate",
    "args": [10, 20]
  }
}
```

**Response:**
```json
{
  "jsonrpc": "2.0",
  "id": 102,
  "result": {
    "value": 30
  }
}
```

## Protocol Errors

Use JSON-RPC errors for actual protocol failures. liquid-spec also tolerates the legacy Liquid error codes listed below, but new servers should prefer `result.error` for Liquid parse/render errors.

| Code | Meaning | When to use |
|------|---------|-------------|
| -32700 | Parse error | Invalid JSON received |
| -32600 | Invalid request | Missing required fields |
| -32601 | Method not found | Unknown method name |
| -32602 | Invalid params | Parameter validation failed |
| -32000 | Legacy Liquid parse error | Compatibility only; prefer `result.error` |
| -32001 | Legacy Liquid render error | Compatibility only; prefer `result.error` |

**Example validation error:**
```json
{
  "jsonrpc": "2.0",
  "id": 5,
  "error": {
    "code": -32602,
    "message": "Invalid params",
    "data": {
      "param": "options.error_mode",
      "message": "Expected 'strict' or 'lax', got 'invalid'"
    }
  }
}
```

## Implementation Notes

### Error Handling

Liquid has two orthogonal error axes that interact through the protocol:

**Parse mode** (set at compile time via `options.error_mode`):
- `strict` — reject invalid syntax with a parse error
- `strict2` — like strict but with relaxed trailing comma/colon syntax (default)
- `lax` — recover from syntax errors, render what parsed

The Ruby adapter declares which of these the server implements. Ordinary specs
run once in its highest supported mode (`strict2`, then `strict`, then `lax`).
Explicit multi-mode specs run once per supported declared mode.

**Error rendering** (set at render time via `options.strict_errors`):
- `true` (default) — render errors are raised as `result.error`
- `false` — render errors are rendered inline as `Liquid error: ...` text in `output`

**How errors flow through the protocol:**

1. **Parse errors** — returned in `result.error` with `type: "parse_error"`.
   The template fails to compile. `template_id` is null.

2. **Render errors with `strict_errors: true`** — returned in `result.error`
   with `type: "render_error"`. `output` is null.

3. **Render errors with `strict_errors: false`** — rendered inline as
   `Liquid error (line N): <message>` in `output`. The error is also
   reported in `result.errors[]` for structured access.

4. **Protocol errors** — only for malformed JSON-RPC usage. Legacy
   `-32000` (parse error) and `-32001` (render error) codes are
   tolerated for backwards compatibility; liquid-spec converts them
   to the appropriate inline output or raised error.

**Subprocess crashes and stalls** — if the subprocess exits unexpectedly or a
request makes no progress before the timeout, liquid-spec raises a
`SubprocessError` that includes the spec name and source file for correlation:
`[spec 'test_foo' at specs/basics/x.yml:42] Subprocess closed stdout unexpectedly`.
A timed-out subprocess is killed immediately. The next spec starts a fresh server,
so one infinite loop cannot turn every remaining request into another timeout or
leave liquid-spec blocked while writing to a full stdin pipe.

**Resource limits** — forwarded as `options.resource_limits` with
`render_score_limit` and `cumulative_render_score_limit` (integers).
The server should enforce these and raise a render error when exceeded.
### Registers and time handling

Registers are host-owned render context. They are passed alongside assigns but
are not template variables: `{{ current_time }}` must not resolve from this
value. Filters and drops receive the render context and can use
`registers.current_time` instead.

liquid-spec supplies `options.registers.current_time` for deterministic date/time filters:

```liquid
{{ 'now' | date: '%Y-%m-%d' }}
```

When `options.registers.current_time: "2024-01-01T00:01:58Z"` is passed:
- `now` keyword should return this timestamp
- All date operations use this as "current time"
- `now` and `today` must resolve from this exact instant, never server wall time
- The requirement applies equally to normal, inspect, and matrix runs

Servers should scope any internal clock override to the render request and
restore their normal clock afterward. The date specs validate the expected
calendar values at this instant; merely returning the same wall-clock value as
another adapter does not pass.

When `current_time` is omitted, the protocol does not imply a timezone or frozen
date. The server should use its ordinary machine clock and timezone behavior.

### Type Coercion

JSON has limited types. Map them to Liquid types:
- JSON `null` → Liquid `nil`
- JSON `true`/`false` → Liquid boolean
- JSON number → Liquid Integer or Float (preserve decimal distinction)
- JSON string → Liquid String
- JSON array → Liquid Array
- JSON object → Liquid Hash (unless it has `_rpc_drop` key)

### Common Mistakes

The server should detect and report common caller mistakes:

1. **Rendering unknown template_id:**
   ```json
   {"error": {"code": -32602, "message": "Unknown template_id 'tmpl_999'. Call compile first."}}
   ```

2. **Missing required parameter:**
   ```json
   {"error": {"code": -32602, "message": "Missing required parameter 'template' in compile request"}}
   ```

3. **Invalid option value:**
   ```json
   {"error": {"code": -32602, "message": "Invalid error_mode: expected 'strict' or 'lax', got 'foo'"}}
   ```

## Transport Limitations

JSON-RPC uses JSON as its transport, which cannot represent all Liquid values. This means **~7% of liquid-spec tests cannot be run over JSON-RPC** due to transport limitations, not implementation issues.

### What JSON Cannot Represent

| Liquid Value | JSON Limitation | Impact |
|--------------|-----------------|--------|
| Symbol keys `{:foo => 1}` | JSON only has string keys | Hash key notation differs in output |
| Binary strings `"\xFF"` | JSON requires valid UTF-8 | Binary data gets replacement characters |
| Circular references | JSON has no reference concept | Self-referential structures truncated |
| Ruby object notation | JSON has no equivalent | `#<Object:0x...>` format untestable |

### Example: Symbol Keys

Liquid inherited Ruby's distinction between symbol and string hash keys:

```liquid
{{ hash }}
```

With environment `{foo: "bar"}`:
- **Correct Liquid output:** `{:foo=>"bar"}`
- **JSON-RPC output:** `{"foo"=>"bar"}`

Both implementations render the hash correctly, but JSON converted the symbol key `:foo` to string `"foo"` during transport.

### Example: Binary Data

```liquid
{{ data | base64_decode }}
```

With environment `{data: "//8="}` (base64 for `\xFF\xFF`):
- **Correct Liquid output:** `\xFF\xFF` (raw bytes)
- **JSON-RPC output:** `��` (replacement characters)

The implementation decoded correctly, but JSON cannot transport raw bytes.

### Implications

1. **These are transport limitations, not spec failures** - The underlying Liquid behavior is correct
2. **Non-Ruby implementations must still match this behavior** - Symbol notation, binary handling, etc. are part of Liquid
3. **Use direct adapters for full coverage** - JSON-RPC is useful for cross-language testing but has inherent limits
4. **~93% of specs work over JSON-RPC** - Most Liquid behavior is testable; only edge cases with Ruby-inherited types fail
