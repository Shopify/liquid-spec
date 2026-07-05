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
    "features": ["runtime_drops"]
  }
}
```

**Features:**

`features` is informational metadata reported by the subprocess. The Ruby adapter file still controls which specs run via `config.missing_features` because spec selection happens in liquid-spec, not inside the subprocess.

Common feature names:
- `runtime_drops` - Supports bidirectional drop callbacks (see Drop Callbacks section)
- `lax_parsing` - Supports `error_mode: lax`

For a minimal JSON-RPC server, start with `features: []` and set the adapter's `config.missing_features` to skip unsupported capabilities such as `:runtime_drops`, `:lax_parsing`, `:ruby_types`, `:ruby_drops`, `:binary_data`, and Shopify-specific features.

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
| `options.error_mode` | string | no | `"strict2"` (recommended default), `"strict"`, `"lax"`, `"raise"`, or omitted/null |
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
      "strict_errors": true
    },
    "frozen_time": "2024-01-01T00:01:58Z"
  }
}
```

**Parameters:**
| Name | Type | Required | Description |
|------|------|----------|-------------|
| `template_id` | string | yes | ID from compile response |
| `environment` | object | no | Variables available to the template |
| `options.strict_errors` | boolean | no | If true, render errors should be reported as errors; if false, render them inline in `output` when possible |
| `frozen_time` | string | no | ISO 8601 timestamp for `now` keyword |

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

Liquid has complex error handling that implementers need to understand:

1. **Parse errors** - Syntax problems that prevent compilation. Prefer `result.error` with `type: "parse_error"`.

2. **Render errors with `strict_errors: true`** - Problems during rendering should be reported as `result.error` with `type: "render_error"`.

3. **Render errors with `strict_errors: false`** - Render the inline Liquid error text into `output` and optionally include details in `result.errors`.

4. **Protocol errors** - Only malformed JSON-RPC usage should use JSON-RPC `error`, except for tolerated legacy `-32000` / `-32001` Liquid errors.

### Time Handling

The `frozen_time` parameter allows deterministic testing of date/time filters:

```liquid
{{ 'now' | date: '%Y-%m-%d' }}
```

When `frozen_time: "2024-01-01T00:01:58Z"` is passed:
- `now` keyword should return this timestamp
- All date operations use this as "current time"

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
