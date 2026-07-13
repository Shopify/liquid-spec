+# Standard Test Drop Library

## What drops are and why you need them

Without drops, Liquid is **static**: templates can only output literal text,
variables passed in the environment hash, and filtered values. The environment
is a flat hash of strings, numbers, and arrays — set once before render and
never changes.

Drops make Liquid **dynamic**. A drop is an object whose properties are
computed on access — each property lookup is a method call, not a field
read. This enables:

- **Computed properties** — `product.price` calculates tax on access
- **Lazy loading** — `collection.products` fetches from a database only if
  the template actually uses it
- **Enumerable iteration** — `{% for item in collection %}` calls `each` on
  the drop, yielding dynamic data
- **Stateful objects** — a drop can track access counts, cache results, or
  raise errors based on internal state
- **Security boundaries** — drops expose only whitelisted methods; internal
  state (`class`, `send`, `instance_eval`) is blocked

In real-world Liquid (Shopify, storefronts, CMS), **everything the template
touches is a drop**: `product`, `cart`, `customer`, `collection`, `page`,
`settings`, `request`, etc. Without drops, your Liquid implementation can
only render static templates with pre-computed data. With drops, it becomes
a full template engine that calls into your application layer.

A drop's property is not a static field; it is a **method invocation**. When
the template does `{{ product.title }}`, Liquid calls `product.title` (or
`product["title"]`), which runs your code and returns the result. This is
the primary extensibility mechanism in Liquid.

## The standard test library

To test drop behavior portably (without Ruby-specific RPC callbacks),
liquid-spec defines a **standard library of test drops**. Each drop has
deterministic, documented behavior that the implementer replicates natively
in their language. No bidirectional RPC is needed.

## The `drops` feature

Adapters declare drop support by advertising the portable fixture set in their
JSON-RPC `initialize` response:

```json
{"fixture_sets":{"standard-drops":1},"features":["core","drops"]}
```

All drop specs are scored at complexity 200+. Implement the standard library
when your Liquid core (variables, filters, control flow) is solid.

## Standard Drops

### Value drops (boxed values)

Test `to_liquid_value` — the method that materializes a drop into a
primitive Liquid value (boolean, integer, string).

| Drop | Constructor | `to_liquid_value` | `to_s` | Truthy? |
|---|---|---|---|---|
| `BooleanDrop` | `{value: bool}` | `value` | `"true"`/`"false"` | follows value |
| `NumberDrop` | `{value: int}` | `value` | `value.to_s` | yes (0 is truthy in Liquid) |
| `StringDrop` | `{value: str}` | `value` | `value` | yes (non-nil) |

> **Note:** NumberDrop also implements `to_number` (returning the integer)
> because Liquid's numeric filters (`plus`, `minus`, `abs`, etc.) call
> `Utils.to_number(input)`, not `to_liquid_value`. The `to_liquid_value`
> method is used for truthiness checks (`{% if %}`) and the `default` filter,
> but not for numeric filter compatibility.

**YAML format:**
```yaml
environment:
  flag:
    instantiate:BooleanDrop:
      value: false
  count:
    instantiate:NumberDrop:
      value: 42
  name:
    instantiate:StringDrop:
      value: hello
```

**Behavior:**
- `{{ flag }}` → `"false"` (materialized via `to_liquid_value`, then `to_s`)
- `{% if flag %}yes{% else %}no{% endif %}` → `"no"` (false is falsy)
- `{{ count }}` → `"42"`
- `{{ count | plus: 1 }}` → `"43"` (filters see the materialized integer)
- `{{ name | upcase }}` → `"HELLO"`

### MethodDrop (property access with deterministic transforms)

Tests `.method` access on drops. The property name encodes an operation and
an integer argument; the drop parses it and returns the result as a string.

| Property pattern | Output | Rule |
|---|---|---|
| `drop.echo_N` | `"N"` | identity: returns N |
| `drop.square_N` | `"N*N"` | square: returns N² |
| `drop.double_N` | `"N*2"` | double: returns 2N |

**YAML format:**
```yaml
environment:
  drop:
    instantiate:MethodDrop: {}
```

**Behavior:**
- `{{ drop.echo_42 }}` → `"42"`
- `{{ drop.square_5 }}` → `"25"`
- `{{ drop.double_7 }}` → `"14"`

The implementer parses the property name: split on `_`, take the first part
as the operation name and the rest as the integer argument. Apply the
operation and return the result as a string.

### IndexDrop (bracket access)

Tests `[int]` and `['string']` access on drops.

| Access | Output | Rule |
|---|---|---|
| `drop[0]` | `"zero"` | integer index → number word |
| `drop[1]` | `"one"` | |
| `drop[2]` | `"two"` | |
| `drop["foo"]` | `"foo"` | string index → the string itself |

**YAML format:**
```yaml
environment:
  drop:
    instantiate:IndexDrop: {}
```

**Behavior:**
- `{{ drop[0] }}` → `"zero"`
- `{{ drop["foo"] }}` → `"foo"`

### SequenceDrop (enumerable)

Tests `for` loop iteration. Yields three fixed strings.

| Property | Output |
|---|---|
| Iteration | `"first"`, `"second"`, `"third"` |
| `drop.size` | `3` |
| `drop.first` | `"first"` |
| `drop.last` | `"third"` |

**YAML format:**
```yaml
environment:
  items:
    instantiate:SequenceDrop: {}
```

**Behavior:**
```liquid
{% for item in items %}{{ item }} {% endfor %}
```
→ `"first second third "`

### NilDrop (nil materialization)

Tests `to_liquid` → nil. The drop materializes to nothing.

**YAML format:**
```yaml
environment:
  drop:
    instantiate:NilDrop: {}
```

**Behavior:**
- `{{ drop }}` → `""` (nil renders as empty string)
- `{% if drop %}yes{% else %}no{% endif %}` → `"no"` (nil is falsy)

### OpaqueDrop (no to_liquid_value)

Tests that drops without `to_liquid_value` are truthy and render via `to_s`.

**YAML format:**
```yaml
environment:
  drop:
    instantiate:OpaqueDrop: {}
```

**Behavior:**
- `{{ drop }}` → `"opaque"` (renders via `to_s`)
- `{% if drop %}yes{% else %}no{% endif %}` → `"yes"` (drops are truthy)

### ErrorDrop (error on access)

Tests error handling. Any access raises a `RuntimeError`.

**YAML format:**
```yaml
environment:
  drop:
    instantiate:ErrorDrop: {}
```

**Behavior:**
- `{{ drop.foo }}` → raises an error
- Use with `errors: render_error:` to test error propagation.

## Deterministic fixtures, not generated values

The Rust loader sends the values recorded in each spec exactly as written. It does
not currently expand a `generate:` field or advertise a `randomness` capability.
Keep standard-drop fixtures deterministic and add several explicit cases when a
property needs breadth. If generated cases are introduced in the future, they must
be seeded and included in the result log so a failing run can be reproduced.

## Migration from Ruby-specific drops

Existing specs use Ruby-specific drop classes (`ToSDrop`, `SecurityVictimDrop`,
`BooleanDrop`, etc.). Portable behavior uses versioned `standard-drops` fixture
values over JSON-RPC; there are no bidirectional RPC callbacks. Ruby-only security
coverage remains behind the `ruby_compat` capability:

| Old drop | New drop | What changes |
|---|---|---|
| `BooleanDrop` | `BooleanDrop` (standard) | Same behavior, no Ruby needed |
| `IntegerDrop` | `NumberDrop` | Renamed, same behavior |
| `StringDrop` | `StringDrop` (standard) | Same behavior, no Ruby needed |
| `ToSDrop` | `MethodDrop` | Tests `to_s` via deterministic transforms |
| `TestDrop` | `OpaqueDrop` | Tests truthy drops without `to_liquid_value` |
| `TestEnumerable` | `SequenceDrop` | Tests iteration with fixed sequence |
| `ErrorDrop` | `ErrorDrop` (standard) | Same behavior, no Ruby needed |
| `SecurityVictimDrop` | (keep as `ruby_drops`) | Ruby-specific security tests |
| `LoaderDrop` | (keep as `ruby_drops`) | Ruby-specific dynamic loading |

Specs that test Ruby-specific security boundaries (SecurityVictimDrop,
WideOpenObject, UnsafeHashLikeObject, etc.) remain tagged `ruby_drops` and
are skipped by adapters that do not advertise the Ruby-compatibility capability.

## Implementation notes

You don't have to implement drops as objects — use whatever mechanism your
implementation language has that suits best. Closures, maps of functions,
prototype chains, interfaces, records, or any other pattern all work. The
only requirement is that the mechanism supports:

1. Property access (`drop.foo` or `drop["foo"]`) that runs code
2. Enumerable iteration (`{% for item in drop %}`) that yields values
3. Materialization to a primitive (boolean, integer, string, nil) for
   truthiness checks and filter compatibility

**Be mindful of performance.** Producing Liquid templates can use a lot of
drops — a single page render might access hundreds of drop properties.
Each access is a method call (not a field read), so the overhead of your
dispatch mechanism matters. In hot paths, prefer direct dispatch over
reflection or hash lookups where possible.

## Implementer checklist

To support the `drops` feature, provide these fixture behaviors natively (the
names below are protocol identifiers, not required class names):

- [ ] `BooleanDrop(value)` — `to_liquid_value` returns the boolean
- [ ] `NumberDrop(value)` — `to_liquid_value` returns the integer
- [ ] `StringDrop(value)` — `to_liquid_value` returns the string
- [ ] `MethodDrop` — parse `op_N` property names, apply transform
- [ ] `IndexDrop` — bracket access with int→word and string→identity
- [ ] `SequenceDrop` — enumerable yielding "first", "second", "third"
- [ ] `NilDrop` — `to_liquid` returns nil
- [ ] `OpaqueDrop` — truthy, `to_s` returns "opaque"
- [ ] `ErrorDrop` — raises on any access

Each fixture must expose the corresponding observable operations:
- materialization to a primitive for truthiness and filter compatibility
- string conversion for `{{ drop }}` output
- property or bracket lookup where the fixture defines it
- enumerable iteration for sequence fixtures

The adapter can represent these operations with objects, maps, closures, tagged
values, or another native mechanism. The typed fixture envelope is the stable
boundary; host-language method names such as `to_liquid_value`, `to_s`, `[]`, and
`each` are explanatory labels only.
