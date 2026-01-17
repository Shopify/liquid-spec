# Liquid JSON-RPC Protocol Specification

This document specifies the JSON-RPC 2.0 protocol for implementing Liquid template engines that can be tested with liquid-spec.

## Design Principles

1. **Liquid errors are NOT protocol errors** - Parse/render errors are part of the result, not JSON-RPC exceptions
2. **Explicit over implicit** - All options are documented and validated
3. **Helpful error messages** - Invalid requests explain what went wrong
4. **Deterministic testing** - Time can be frozen for reproducible tests

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
    "features": ["core", "runtime_drops"]
  }
}
```

**Features:**
- `core` - Full Liquid implementation
- `runtime_drops` - Supports bidirectional drop callbacks (see Drop Callbacks section)
- `lax_parsing` - Supports `error_mode: lax`

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
| `options.error_mode` | string | no | `"strict"` (default) or `"lax"` |
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

Note: Parse errors are returned in `result.error`, not as JSON-RPC errors. This makes it easier for the client to handle them uniformly.

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
      "strict_variables": false,
      "strict_filters": false
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
| `options.strict_variables` | boolean | no | Error on undefined variables |
| `options.strict_filters` | boolean | no | Error on undefined filters |
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

**Response with render errors:**
```json
{
  "jsonrpc": "2.0",
  "id": 3,
  "result": {
    "output": "Liquid error (line 1): cannot sort values of incompatible types",
    "errors": [
      {
        "type": "argument_error",
        "message": "cannot sort values of incompatible types",
        "line": 1
      }
    ]
  }
}
```

**Key point:** Render errors are Liquid behavior, not protocol failures. The `errors` array captures what went wrong for test assertions, while `output` contains whatever Liquid actually rendered (which may include inline error messages).

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

Use JSON-RPC errors only for actual protocol failures:

| Code | Meaning | When to use |
|------|---------|-------------|
| -32700 | Parse error | Invalid JSON received |
| -32600 | Invalid request | Missing required fields |
| -32601 | Method not found | Unknown method name |
| -32602 | Invalid params | Parameter validation failed |

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

1. **Parse errors** - Syntax problems that prevent compilation. Return in `result.error`.

2. **Render errors** - Problems during rendering (undefined variable, filter error, etc.). These are:
   - Rendered inline as "Liquid error (line N): message"
   - Captured in `result.errors` array
   - NOT raised as JSON-RPC errors

3. **The output always reflects what Liquid would actually produce** - including error messages rendered inline.

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
