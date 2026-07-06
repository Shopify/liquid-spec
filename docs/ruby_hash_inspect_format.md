# Ruby `Hash#inspect` / `Hash#to_s` format

Several specs render a hash (or array of hashes) through `{{ var }}` and expect
Ruby's `Hash#inspect` output — **not** JSON. In Ruby, `Hash#to_s` is an alias
for `Hash#inspect`, so `{{ my_hash }}` (which calls `to_s` on the resolved
value) produces the format below. A non-Ruby Liquid implementation must
reproduce it exactly to pass these specs.

This is a cross-language correctness bar: Liquid defers object rendering to the
host language's `to_s`, and the reference implementation is Ruby, so the
expected strings are Ruby's `inspect` output.

## Grammar

```
hash_inspect  = "{" pairs? "}"
pairs         = pair (", " pair)*
pair          = key_inspect "=>" value_inspect
array_inspect = "[" elements? "]"
elements      = elem_inspect (", " elem_inspect)*
```

`=>` is the **rocket**, never `:`. Pairs are in **insertion order**. The
separator is `", "` (comma + one space). The whole thing is wrapped in `{` `}`.

## Scalar inspect rules

| Ruby type   | Inspect output        | Notes |
|-------------|-----------------------|-------|
| `String`    | `"foo"`               | double-quoted, with escapes (below) |
| `Symbol`    | `:foo`                | leading colon, no quotes |
| `Integer`   | `42`                  | bare |
| `Float`     | `1.0`                 | always has a decimal part (`1.0`, not `1`) |
| `nil`       | `nil`                 | the literal word |
| `true`      | `true`                | |
| `false`     | `false`               | |
| `Array`     | `[a, b, c]`           | each element via its own inspect, `, ` separated |
| `Hash`      | `{k=>v, ...}`         | recursive |
| self-ref    | `{...}`               | a hash that refers to an ancestor in the same inspect call renders as `{...}` |

## String escapes (inside double quotes)

The string's `inspect` doubles `\\` and `\"`, and turns control characters into
their escaped forms: `\n`, `\t`, `\r`, `\f`, `\b`, `\a`, `\e`, `\v`, `\0` /
`\u0000`-style for other non-printables. Printable ASCII is emitted literally.
This matters for specs where the hash is piped through `escape`/`url_encode`
*after* being stringified — the inspect output is the input to those filters.

## Worked examples (all drawn from real specs)

| Input (Ruby)                                  | Expected output                        |
|-----------------------------------------------|----------------------------------------|
| `{}`                                          | `{}`                                   |
| `{"key1"=>"value1", "key2"=>"value2"}`        | `{"key1"=>"value1", "key2"=>"value2"}` |
| `{"numbers"=>[1, 2, 3]}`                      | `{"numbers"=>[1, 2, 3]}`               |
| `{"numbers"=>[]}`                             | `{"numbers"=>[]}`                      |
| `{"outer"=>{"inner"=>"value"}}`               | `{"outer"=>{"inner"=>"value"}}`        |
| `{{"foo"=>"bar"}=>42}` (hash key)             | `{{"foo"=>"bar"}=>42}`                 |
| `{:key1=>1, :key2=>2}` (symbol keys)          | `{:key1=>1, :key2=>2}`                 |
| recursive `{"self"=>{"self"=>{...}}}`         | `{"self"=>{"self"=>{...}}}`            |

## How filters interact

When a hash is the input to a string filter, the hash is **first** stringified
via `inspect`, **then** the filter runs on that string. Examples:

- `{{ my_hash | upcase }}` → `{"KEY1"=>"VALUE1", ...}` (inspect, then uppercased)
- `{{ my_hash | downcase }}` → `{"key1"=>"value1", ...}`
- `{{ my_hash | append: " text" }}` → `{"Key"=>"Value"} text`
- `{{ my_hash | replace: "key", "KEY" }}` → replaces inside the inspect string
- `{{ my_hash | escape }}` → HTML-escapes the inspect string
  (`{&quot;Key&quot;=&gt;&quot;Value&quot;}`)

So the inspect format is the *substrate* every string filter operates on when the
input is a hash.

## Pseudocode for a non-Ruby implementation

```text
function rubyInspect(value, seen = new Set()):
  if value is a Hash/Map:
    if value in seen: return "{...}"        # cycle guard
    seen.add(value)
    if value is empty: return "{}"
    parts = []
    for (k, v) in value in insertion order:
      parts.push(rubyInspect(k, seen) + "=>" + rubyInspect(v, seen))
    return "{" + parts.join(", ") + "}"
  if value is an Array:
    if value is empty: return "[]"
    return "[" + value.map(rubyInspect).join(", ") + "]"
  if value is a String:  return rubyStringInspect(value)   # double-quoted + escapes
  if value is a Symbol:  return ":" + value.name            # no quotes
  if value is null/nil:  return "nil"
  if value is Boolean:   return value ? "true" : "false"
  if value is Integer:   return String(value)
  if value is Float:     return floatInspect(value)         # always show a decimal
  # other objects: defer to the host's inspect/to_s if you emulate ruby_types
```

`rubyStringInspect(s)` wraps `s` in `"..."`, escaping `\\` and `"` and control
chars as above. `floatInspect` must always include a decimal point (`1.0`, not
`1`; `0.2`, not `0.2` rendered as a bare fraction — match Ruby's `Float#inspect`,
which uses the shortest representation that round-trips).

## When you need this

These specs are gated behind the **Ruby/reference-quirk** complexity band
(~220+) and most are tagged `features: [ruby_types]`. JSON-RPC adapters skip
`ruby_types` by default. If you opt in (remove `:ruby_types` from
`missing_features`), the JSON-RPC transport delivers non-string hash keys to you
as their Ruby `inspect` string, and your engine is expected to render hashes and
those keys per the rules above.
