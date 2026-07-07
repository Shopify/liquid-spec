# JSON-RPC Type Transport: instantiate: and _ruby_type

When liquid-spec sends spec data to a JSON-RPC server, Ruby-specific values
that can't be faithfully represented in JSON need special handling. This
document covers the two mechanisms: `instantiate:` for spec YAML, and
`_ruby_type` markers for JSON-RPC transport.

## instantiate: in spec YAML

Specs can include Ruby objects (drops, custom types) in their environment
using the `instantiate:ClassName` format. This is **spec-side** — it tells
liquid-spec's test harness what to create before rendering.

### Format

```yaml
# No arguments (uses defaults)
my_var: "instantiate:TestDrop"

# With arguments (hash params)
my_var:
  instantiate:BooleanDrop:
    value: false

# With string argument
my_var: "instantiate:CountingDrop.new(5)"
```

The `instantiate:ClassName` string format creates the object with no args.
The `instantiate:ClassName:` hash format passes the nested hash as constructor
params. The `instantiate:ClassName.new(arg)` format passes a single argument.

### What instantiate: creates

| Class | Purpose | Requires feature |
|---|---|---|
| `TestDrop`, `ToSDrop`, `ThingWithValue` | Generic test drops | `ruby_drops` |
| `BooleanDrop` | Wraps a boolean; `to_liquid_value` returns it | `ruby_drops` |
| `IntegerDrop` | Wraps an integer; `to_liquid_value` returns it | `ruby_drops` |
| `StringDrop` | Wraps a string; comparable | `ruby_drops` |
| `ValueDrop` | Wraps any value; `to_liquid_value` returns it | `ruby_drops` |
| `CountingDrop` | Counts `[]` accesses | `ruby_drops` |
| `LoaderDrop` | Lazy-loading collection | `ruby_drops` |
| `ArrayDrop` | Enumerable drop | `ruby_drops` |
| `TestEnumerable` | Enumerable for loop tests | `ruby_drops` |
| `ErrorDrop` | Raises errors during render | `runtime_drops` |
| `StubTemplateFactory` | Template factory for partials | `template_factory` |
| `SettingsDrop` | Shopify settings drop | `shopify_objects` |
| `SecurityVictimDrop` | Security boundary tests | `ruby_drops` |
| `LongString` | Very long string for filter tests | `ruby_drops` |
| `SafeBuffer` | ActiveSupport SafeBuffer | `ruby_types` |
| `LiquidDropClass` | The Liquid::Drop class itself | `ruby_types` |

### When to implement each

**Without `ruby_types` or `ruby_drops`** (most JSON-RPC adapters):
- All `instantiate:` specs are **skipped** — you don't need to handle them.
- Add `:ruby_drops` and `:ruby_types` to `missing_features`.

**With `ruby_drops`** (adapter implements boxed drop objects):
- Instead of bidirectional RPC callbacks, the server implements its own
  equivalents of the test drop classes as boxed objects.
- The adapter sends drop metadata: class name + constructor params.
- The server creates a native implementation with matching behavior.
- This is faster (no round-trips), simpler, and more portable than RPC callbacks.

The drop classes you need to implement (pseudocode):

```
// BooleanDrop: wraps a boolean, to_liquid_value returns it
class BooleanDrop:
    value: bool  // constructor param "value", default false
    to_liquid_value() -> value
    to_s() -> value ? "Yay" : "Nay"
    ==(other) -> value == other

// IntegerDrop: wraps an integer, to_liquid_value returns it
class IntegerDrop:
    value: int  // constructor param "value", default 0
    to_liquid_value() -> value
    to_s() -> number_to_word(value)  // 0→"zero", 1→"one", etc.

// StringDrop: wraps a string, comparable
class StringDrop:
    value: string  // constructor param "value", default nil
    to_liquid_value() -> value
    to_s() -> value
    <=>(other) -> value <=> other

// ValueDrop: wraps any value, to_liquid_value returns it
class ValueDrop:
    value: any  // constructor param (positional)
    to_liquid_value() -> value

// TestDrop: generic drop, no to_liquid_value (always truthy)
class TestDrop:
    // no to_liquid_value — the drop object itself is the value
    // truthy, not empty, not blank

// ToSDrop: has a configurable to_s
class ToSDrop:
    foo: int  // constructor param "foo"
    to_s() -> "woot: #{foo + 1}"

// ThingWithValue: has a value property
class ThingWithValue:
    value() -> "1 2 3"
```

Pseudocode for handling drop markers in environment:

```
function unwrap_value(value):
    if value is Hash and value["_rpc_drop"] exists:
        return create_drop(value["type"], value["params"] or {})
    if value is Hash and value["_ruby_type"] exists:
        return unwrap_ruby_type(value)
    if value is Hash:
        return { k: unwrap_value(v) for k, v in value }
    if value is Array:
        return [unwrap_value(v) for v in value]
    return value
```

> **Note on `runtime_drops`:** The bidirectional RPC callback mechanism
> (`drop_get`, `drop_call`, `drop_iterate`) is an alternative to boxed
> objects. It's more flexible (the drop logic stays in Ruby) but slower
> (every access is a round-trip) and more complex. For most implementations,
> boxed objects are recommended. Only use `runtime_drops` if you need
> drop behavior that can't be replicated with a static boxed implementation.

**With `ruby_types`** (adapter handles Ruby-specific value formats):
- You must handle `_ruby_type` markers (see below).

### Range

`(1..5)` is sent as:
```json
{
  "_ruby_type": "Range",
  "begin": 1,
  "end": 5,
  "exclude_end": false,
  "inspect": "(1..5)"
}
```

The server can:
- Reconstruct: `Range(begin, end, exclude_end)` → `(1..5)`
- Use directly: ranges support iteration, comparison, and `to_a`
- Fall back: convert to array `[1, 2, 3, 4, 5]` (loses Range type, breaks `==` comparison)
- You must reproduce Ruby's `Hash#inspect` format in output.
- **Discouraged outside of Ruby** unless you must be Shopify-compatible.
- A non-Ruby implementation that claims `ruby_types` must:
  1. Parse `_ruby_type` markers and reconstruct the Ruby types
  2. Produce `Hash#inspect` output (`{:foo=>"bar"}`, `{1=>1}`, etc.)
  3. Handle symbols, non-string hash keys, and custom `to_s` methods

## _ruby_type markers in JSON-RPC transport

When the JSON-RPC adapter wraps environment values for transport, values
that can't be faithfully represented in JSON are sent as `_ruby_type`
markers. This gives the server enough data to optionally reconstruct the
Ruby type.

### Symbol

`:foo` is sent as:
```json
{
  "_ruby_type": "Symbol",
  "value": "foo",
  "inspect": ":foo"
}
```

The server can:
- Reconstruct: `Symbol(value)` → `:foo`
- Output directly: use `inspect` field for `{{ v }}` → `:foo`
- Fall back: treat as string `"foo"` (loses Ruby-ness but doesn't crash)

### Hash with non-string keys

`{:foo=>"bar"}` or `{1=>1}` is sent as:
```json
{
  "_ruby_type": "Hash",
  "inspect": "{:foo => \"bar\"}",
  "data": { "foo": "bar" }
}
```

The server can:
- Reconstruct: parse `inspect` to get the real hash (Ruby can `eval` it)
- Output directly: use `inspect` field for `{{ v }}` → `{:foo => "bar"}`
- Access by key: use `data` field for `{{ v.foo }}` → `"bar"` (keys are strings)
- Fall back: use `data` as a normal hash (loses key type info but works for access)

### Pseudocode for server-side handling

```
function unwrap_ruby_type(marker):
    type = marker["_ruby_type"]
    
    if type == "Symbol":
        # Reconstruct the symbol
        return Symbol(marker["value"])
    
    if type == "Hash":
        # Option A: reconstruct from inspect (Ruby server can eval)
        # Option B: use data field for access, inspect for output
        if server_supports_eval:
            return eval(marker["inspect"])
        else:
            return RubyHashProxy(
                inspect: marker["inspect"],
                data: marker["data"]
            )
    
    # Unknown type — fall back to inspect string
    return marker["inspect"] or marker["data"] or to_string(marker)
```

### RubyHashProxy pseudocode (for non-Ruby servers)

If your server can't reconstruct the Ruby hash, create a proxy object that:
1. Renders as the inspect string when output (`{{ v }}` → `{:foo=>"bar"}`)
2. Delegates key access to the `data` field (`{{ v.foo }}` → `data["foo"]`)

```
class RubyHashProxy:
    inspect_string  # "{:foo => \"bar\"}"
    data            # {"foo": "bar"}
    
    to_liquid_output():
        return inspect_string
    
    [](key):
        return data[key] or data[key.to_s]
    
    size():
        return length(data)
    
    # For filters that call to_s or inspect
    to_s():
        return inspect_string
```

## Feature decision tree for implementers

```
Do you need Shopify production compatibility?
├── NO → Skip ruby_types. Add :ruby_types, :ruby_drops to missing_features.
│        You won't see instantiate: or _ruby_type markers at all.
│
└── YES → You need ruby_types and ruby_drops.
         ├── Can you implement bidirectional drop callbacks?
         │   ├── YES → Remove :ruby_drops from missing_features.
         │   │        Implement drop_get, drop_call, drop_iterate.
         │   │        Handle _rpc_drop markers in environment.
         │   └── NO  → Keep :ruby_drops in missing_features.
         │            Drop specs will be skipped (you lose ~200 specs).
         │
         ├── Can you reproduce Ruby's Hash#inspect format?
         │   ├── YES → Remove :ruby_types from missing_features.
         │   │        Handle _ruby_type markers (Symbol, Hash).
         │   │        Implement Ruby inspect format for hash output.
         │   └── NO  → Keep :ruby_types in missing_features.
         │            Ruby-type specs will be skipped (you lose ~50 specs).
         │
         └── Do you need template_factory?
             ├── YES → Remove :template_factory from missing_features.
             │        Implement template creation callbacks.
             └── NO  → Keep :template_factory in missing_features.
```

## Summary: what each feature requires

| Feature | What you must implement | Specs gained | Difficulty |
|---|---|---|---|
| (none) | Basic compile + render | ~4900 | Moderate |
| `ruby_drops` | Drop callbacks + `_rpc_drop` handling | ~200 | Hard |
| `ruby_types` | `_ruby_type` markers + Hash#inspect format | ~50 | Very hard (non-Ruby) |
| `runtime_drops` | Bidirectional drop callbacks | ~20 | Hard |
| `template_factory` | Template creation callbacks | ~10 | Moderate |
| `lax_parsing` | Lax error mode (inline errors) | ~100 | Moderate |
| `strict2_parsing` | Strict2 error mode | ~50 | Easy |

**Recommendation for non-Ruby implementations:**
1. Start with `missing_features = [:ruby_types, :ruby_drops, :binary_data, :runtime_drops, :template_factory, :lax_parsing, ...shopify_*]`
2. Remove `:lax_parsing` first (easy, big gain).
3. Remove `:ruby_drops` next (requires drop callbacks, big gain).
4. Remove `:runtime_drops` (requires bidirectional callbacks).
5. Remove `:ruby_types` last (requires Ruby inspect emulation, small gain, hard).
6. Only remove `:ruby_types` if you must be Shopify-production-compatible.
