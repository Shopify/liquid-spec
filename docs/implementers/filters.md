---
title: "Filter Reference"
position: 5
description: "Read when filter specs fail. Covers dispatch, arguments, coercion, and edge cases for the filters that usually trip implementations."
optional: false
---

# Filter Reference

This document covers filters with non-obvious behavior that commonly cause implementation issues.

For Ruby-specific type quirks (like `int | size = 8`), see [Ruby Quirks](ruby-quirks.md).

---

## Numeric Filters

### `sum`

Sums all numeric values in an array. Added in Liquid 5.5.0.

#### Type Coercion Rules

| Input Type | Behavior |
|------------|----------|
| Array of numbers | Sum all values |
| Array with strings | Coerce strings to numbers, non-numeric strings become 0 |
| Array with non-numeric values | Non-numeric values contribute 0 |
| Single number | Returns that number |
| Empty array | Returns 0 |
| nil | Returns 0 |

#### Examples

```liquid
{{ [1, 2, 3] | sum }}           → 6
{{ [1, "2", 3] | sum }}         → 6  (string "2" coerced to number)
{{ ["foo", "bar"] | sum }}      → 0  (non-numeric strings = 0)
{{ [0.1, 0.2, 0.3] | sum }}     → 0.6
{{ 42 | sum }}                  → 42 (single value)
{{ nil | sum }}                 → 0
```

#### With Property

```liquid
{{ items | sum: "quantity" }}   → Sum of item.quantity for each item
```

#### Implementation Notes

- Must handle mixed arrays gracefully
- String-to-number coercion: use standard numeric parsing, default to 0 on failure
- Property access variant: `sum: "property"` extracts that property from each object

---

### `plus`, `minus`, `times`, `divided_by`, `modulo`

Arithmetic filters with type coercion.

#### Type Coercion

Both the input and argument are coerced to numbers:

| Input | Argument | Result Type |
|-------|----------|-------------|
| Integer | Integer | Integer |
| Float | Integer | Float |
| Integer | Float | Float |
| String | Number | Coerced to number |

#### Division Special Cases

```liquid
{{ 10 | divided_by: 3 }}        → 3   (integer division)
{{ 10.0 | divided_by: 3 }}      → 3.333...
{{ 10 | divided_by: 3.0 }}      → 3.333...
{{ 10 | divided_by: 0 }}        → Error in strict mode, "Infinity" or error text in lax
```

---

### `round`, `ceil`, `floor`, `abs`

Numeric formatting filters.

```liquid
{{ 4.6 | round }}     → 5
{{ 4.3 | round }}     → 4
{{ 4.5612 | round: 2 }} → 4.56
{{ 4.6 | ceil }}      → 5
{{ 4.3 | floor }}     → 4
{{ -5 | abs }}        → 5
```

---

## Encoding Filters

### `base64_encode` / `base64_decode`

Standard Base64 encoding per RFC 4648.

```liquid
{{ "hello" | base64_encode }}   → aGVsbG8=
{{ "aGVsbG8=" | base64_decode }} → hello
```

### `base64_url_safe_encode` / `base64_url_safe_decode`

URL-safe Base64 variant (RFC 4648 Section 5):
- Uses `-` instead of `+`
- Uses `_` instead of `/`
- May omit padding `=`

```liquid
{{ "hello?" | base64_encode }}           → aGVsbG8/
{{ "hello?" | base64_url_safe_encode }}  → aGVsbG8_
```

#### Implementation Notes

Most languages have both variants in their standard library:
- Ruby: `Base64.urlsafe_encode64` / `Base64.urlsafe_decode64`
- Python: `base64.urlsafe_b64encode` / `base64.urlsafe_b64decode`
- Go: `base64.URLEncoding`
- JavaScript: Manual replacement of `+/` with `-_`

---

## String Filters

### `split`

`split` uses ordinary delimiter splitting **without** a keep-trailing-empty
option. An empty delimiter splits into characters, and trailing empty fields are
dropped:

```liquid
{{ "hi" | split: "" | join: "-" }}   → h-i
{{ "a,b," | split: "," | join: "-" }} → a-b
```

### `escape` / `escape_once` / `h`

HTML entity encoding.

```liquid
{{ "<p>Hello</p>" | escape }}       → &lt;p&gt;Hello&lt;/p&gt;
{{ "&lt;p&gt;" | escape }}          → &amp;lt;p&amp;gt;
{{ "&lt;p&gt;" | escape_once }}     → &lt;p&gt; (doesn't double-escape)
```

The `h` filter is an alias for `escape`.

#### Characters Escaped

| Character | Escaped |
|-----------|---------|
| `<` | `&lt;` |
| `>` | `&gt;` |
| `&` | `&amp;` |
| `"` | `&quot;` |
| `'` | `&#39;` |

### `url_encode` / `url_decode`

URL percent-encoding per RFC 3986.

```liquid
{{ "hello world" | url_encode }}    → hello%20world
{{ "a&b=c" | url_encode }}          → a%26b%3Dc
{{ "hello%20world" | url_decode }}  → hello world
```

### `strip_html`

Removes HTML tags from a string.

```liquid
{{ "<p>Hello <b>World</b></p>" | strip_html }}  → Hello World
```

### `newline_to_br`

Converts newlines to `<br />` tags.

```liquid
{{ "line1\nline2" | newline_to_br }}  → line1<br />\nline2
```

Note: The newline is preserved after the `<br />` tag.

---

## Array Filters

### Shared Input Normalization

Most array-style filters do **not** use the same conversion as a `for` loop. The
reference normalizes filter input through an `InputIterator`-like abstraction:

| Input | Filter iterator sees |
|-------|----------------------|
| Array | Recursively flattened elements |
| Hash/map | One element: the whole hash (`[hash]`), not key/value pairs |
| Other enumerable | The enumerable itself |
| nil | Empty sequence |
| Other scalar | One element (`[value]`) |

This affects `join`, `sort`, `map`, `where`, `find`, `compact`, `concat`,
`reverse`, `uniq`, and `sum`. For example, mapping property `"a"` over
`{"a": "b"}` returns `b`, because the hash is the single item whose property is
looked up. By contrast, iterating a hash with `{% for %}` may yield key/value
pairs. Keep filter normalization separate from general loop iteration.

### `sort` / `sort_natural`

Both sort arrays, but with different comparison rules:

| Filter | Comparison |
|--------|------------|
| `sort` | Case-sensitive (`A` < `Z` < `a`) |
| `sort_natural` | Case-insensitive (`A` = `a` < `B` = `b`) |

```liquid
{% assign items = "Zebra,apple,Banana" | split: "," %}
{{ items | sort | join: ", " }}         → Banana, Zebra, apple
{{ items | sort_natural | join: ", " }} → apple, Banana, Zebra
```

#### With Property

```liquid
{{ products | sort: "title" }}
{{ products | sort_natural: "title" }}
```

### `reverse`

Reverses an array. Does NOT reverse strings.

```liquid
{{ "abc" | split: "" | reverse | join: "" }}  → cba
{{ "abc" | reverse }}                          → "abc" (no change!)
```

### `uniq`

Removes duplicates.

```liquid
{{ "a,b,a,c,b" | split: "," | uniq | join: "," }}  → a,b,c
```

### `compact`

Removes nil values.

```liquid
{% assign items = "a,,b,,c" | split: "," %}
{{ items | compact | join: "," }}  → a,b,c
```

### `where` / `find`

Filter arrays by property value.

```liquid
{{ products | where: "available", true }}   → All available products
{{ products | find: "id", 123 }}             → First product with id=123
```

### `map`

Extract a property from each item.

```liquid
{{ products | map: "title" | join: ", " }}  → "Shirt, Pants, Hat"
```

### `concat`

Concatenate two arrays.

```liquid
{% assign all = array1 | concat: array2 %}
```

---

## Date Filter

See the dedicated date filter tests for format string behavior.

The `date` filter accepts:
- Unix timestamps (integers)
- ISO 8601 strings
- The special value `"now"` for current time
- Time objects from the environment

### Deterministic current time

All liquid-spec execution surfaces—including normal runs, inspect, matrix, and
JSON-RPC—execute date specs against exactly `2024-01-01 00:01:58 UTC`. An
adapter must obtain `now`/`today` from the supplied `registers[:current_time]`,
not cache or read the host wall clock outside the render operation. Registers
are host context: unlike assigns, templates cannot resolve them directly, but
filters and drops can read them from their render context.

These specs assert the formatted value for that exact instant. Agreement between
adapters is insufficient if they all return the real current date.

The override is scoped to a spec execution. Outside that scope liquid-spec does
not set a timezone or substitute `Time.now`; the clock must again track the host
machine's realtime clock. Harness tests cover dates before and after the canonical
instant, positive and negative UTC offsets, and unfrozen execution without an
explicit timezone so clock or timezone state cannot leak between runs.

```liquid
{{ "2024-01-15" | date: "%Y-%m-%d" }}  → 2024-01-15
{{ "now" | date: "%Y" }}                → (current year)
{{ article.created_at | date: "%B %d" }} → January 15
```

---

## Default Filter

Returns the default value if the input is nil, false, or empty.

```liquid
{{ nil | default: "N/A" }}       → N/A
{{ false | default: "N/A" }}     → N/A
{{ "" | default: "N/A" }}        → N/A
{{ "hello" | default: "N/A" }}   → hello
```

### `allow_false` Option

```liquid
{{ false | default: "N/A", allow_false: true }}  → false
```

---

## JSON Filter

Converts a value to JSON.

```liquid
{{ product | json }}  → {"title":"Shirt","price":29.99}
```

---

## Implementation Checklist

1. **Type coercion**: Most filters coerce inputs; document your coercion rules
2. **Nil handling**: Most filters return empty string or nil for nil input
3. **Array vs string**: Some filters work differently (`reverse`, `first`, `last`)
4. **Encoding variants**: Implement both standard and URL-safe Base64
5. **Error modes**: Filters may behave differently in lax vs strict mode

---

See also:
- [Ruby Quirks](ruby-quirks.md) - Type-specific edge cases
- [Core Abstractions](core-abstractions.md) - to_output and type handling
