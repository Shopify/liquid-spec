---
title: Ruby Quirks
description: >
  Liquid inherits several surprising behaviors from Ruby. This document catalogs these quirks
  with exact input/output tables so implementers can match Ruby's behavior precisely.
  Essential reading for anyone implementing Liquid outside of Ruby.
optional: false
order: 7
---

# Ruby Quirks

Liquid was originally implemented in Ruby, and some Ruby-specific behaviors leaked into the language semantics. These aren't bugs—they're documented behaviors that implementations must match for compatibility.

This document provides exact input/output tables for each quirk.

---

## 1. Integer Size Returns Byte Count

Ruby's `Integer#size` returns the number of bytes used to represent the integer in memory (8 bytes on 64-bit systems), **not** the number of digits.

### Behavior Table

| Input | `{{ input \| size }}` | Explanation |
|-------|----------------------|-------------|
| `0` | `8` | 8 bytes on 64-bit |
| `1` | `8` | 8 bytes on 64-bit |
| `42` | `8` | 8 bytes on 64-bit |
| `999999999` | `8` | 8 bytes on 64-bit |
| `-1` | `8` | 8 bytes on 64-bit |
| `-999999999` | `8` | 8 bytes on 64-bit |

### Property Access Equivalent

| Input | `{{ input.size }}` |
|-------|-------------------|
| `42` | `8` |

### Why This Exists

In Ruby:
```ruby
42.size  # => 8 (bytes needed to store the integer)
```

Liquid doesn't override this—it just calls Ruby's method directly.

### Implementation Guidance

If your language doesn't have this concept, return `8` for all integers to match Ruby behavior. Alternatively, document the difference and accept that some specs will fail.

---

## 2. Float Size Returns Zero (or Empty)

Ruby's `Float` class doesn't have a `size` method that returns a meaningful value. Liquid handles this gracefully.

### Behavior Table

| Input | `{{ input \| size }}` | `{{ input.size }}` |
|-------|----------------------|-------------------|
| `3.14` | `0` | `` (empty) |
| `0.0` | `0` | `` (empty) |
| `-2.5` | `0` | `` (empty) |

### Why The Difference?

- **Filter**: `| size` catches the missing method and returns `0`
- **Property**: `.size` returns `nil` (rendered as empty string)

### Implementation Guidance

For floats:
- `| size` filter should return `0`
- `.size` property access should return `nil`/empty

---

## 3. Boolean/Nil Size Returns Zero

Booleans and nil don't have a size concept.

### Behavior Table

| Input | `{{ input \| size }}` |
|-------|----------------------|
| `true` | `0` |
| `false` | `0` |
| `nil` | `0` |

---

## 4. Integer/Float First and Last Return Empty

The `first` and `last` filters only work on arrays and strings. For other types, they return empty.

### Behavior Table

| Input | `{{ input \| first }}` | `{{ input \| last }}` |
|-------|------------------------|----------------------|
| `42` | `` (empty) | `` (empty) |
| `3.14` | `` (empty) | `` (empty) |
| `true` | `` (empty) | `` (empty) |
| `false` | `` (empty) | `` (empty) |
| `nil` | `` (empty) | `` (empty) |

---

## 5. String First and Last Return Characters

Unlike arrays, strings return individual characters.

### Behavior Table

| Input | `{{ input \| first }}` | `{{ input \| last }}` | `{{ input \| size }}` |
|-------|------------------------|----------------------|----------------------|
| `"hello"` | `h` | `o` | `5` |
| `"a"` | `a` | `a` | `1` |
| `""` | `` (empty) | `` (empty) | `0` |

### Property Access Equivalent

| Input | `{{ input.first }}` | `{{ input.last }}` | `{{ input.size }}` |
|-------|---------------------|-------------------|-------------------|
| `"hello"` | `h` | `o` | `5` |

---

## 6. Hash First Returns Key+Value Concatenated

This is one of the most surprising behaviors. `hash | first` returns the first key-value pair **concatenated as a string**.

### Behavior Table

| Input | `{{ input \| first }}` | `{{ input \| last }}` | `{{ input \| size }}` |
|-------|------------------------|----------------------|----------------------|
| `{a: 1, b: 2}` | `a1` | `` (empty) | `2` |
| `{foo: "bar"}` | `foobar` | `` (empty) | `1` |
| `{}` | `` (empty) | `` (empty) | `0` |

### Why `last` Returns Empty

Ruby's `Hash#last` is not defined in older Ruby versions, and Liquid doesn't provide a fallback. So `hash | last` returns empty/nil.

### Property Access Equivalent

| Input | `{{ input.first }}` | `{{ input.last }}` | `{{ input.size }}` |
|-------|---------------------|-------------------|-------------------|
| `{a: 1}` | `a1` | `` (empty) | `1` |

### Implementation Guidance

When implementing `hash | first`:
1. Get the first key-value pair
2. Convert both to strings
3. Concatenate: `to_s(key) + to_s(value)`

---

## 7. Hash Rendering Uses Ruby Inspect Format

When a hash is rendered directly (not via a filter), it uses Ruby's inspect format.

### Behavior Table

| Input | `{{ input }}` |
|-------|--------------|
| `{a: 1}` | `{"a"=>1}` |
| `{foo: "bar"}` | `{"foo"=>"bar"}` |

Note: The exact format may vary between Ruby versions. Ruby 2.x uses `{:foo=>"bar"}` while Ruby 3.x may use `{foo: "bar"}`.

---

## 8. Array Last Element Hash Rendering

When the last element of an array is a hash, it renders with Ruby's inspect format.

### Behavior Table

| Input | `{{ input \| last }}` |
|-------|----------------------|
| `[1, 2, {a: 1}]` | `{"a"=>1}` |

---

## 9. Range Size

Ranges have a size equal to their length.

### Behavior Table

| Expression | `{{ expr \| size }}` |
|------------|---------------------|
| `(1..5)` | `5` |
| `(1..1)` | `1` |
| `(5..1)` | `0` (descending ranges are empty) |

---

## Complete Type Reference

### `| size` Filter

| Type | Returns | Example |
|------|---------|---------|
| String | Character count | `"hello"` → `5` |
| Array | Element count | `[1,2,3]` → `3` |
| Hash | Key count | `{a:1, b:2}` → `2` |
| Integer | **8** (byte size) | `42` → `8` |
| Float | **0** | `3.14` → `0` |
| Boolean | **0** | `true` → `0` |
| Nil | **0** | `nil` → `0` |
| Range | Element count | `(1..5)` → `5` |

### `| first` Filter

| Type | Returns | Example |
|------|---------|---------|
| String | First character | `"hello"` → `h` |
| Array | First element | `[1,2,3]` → `1` |
| Hash | **Key+value concatenated** | `{a:1}` → `a1` |
| Integer | Empty | `42` → `` |
| Float | Empty | `3.14` → `` |
| Boolean | Empty | `true` → `` |
| Nil | Empty | `nil` → `` |
| Range | First value | `(1..5)` → `1` |

### `| last` Filter

| Type | Returns | Example |
|------|---------|---------|
| String | Last character | `"hello"` → `o` |
| Array | Last element | `[1,2,3]` → `3` |
| Hash | **Empty** | `{a:1}` → `` |
| Integer | Empty | `42` → `` |
| Float | Empty | `3.14` → `` |
| Boolean | Empty | `true` → `` |
| Nil | Empty | `nil` → `` |
| Range | Last value | `(1..5)` → `5` |

---

## Implementation Checklist

1. **Integer size = 8**: Always return 8 for integer size
2. **Float size = 0**: Return 0 for float size filter, empty for property
3. **Hash first = key+value**: Concatenate first pair as string
4. **Hash last = empty**: Return empty/nil
5. **String first/last = char**: Return single characters
6. **Non-collection first/last = empty**: Return empty for int/float/bool/nil

---

## Testing Your Implementation

```bash
# Test integer size quirk
liquid-spec my_adapter.rb -n filter_int

# Test hash first/last
liquid-spec my_adapter.rb -n filter_hash

# Test all type filters
liquid-spec my_adapter.rb -n filter_ -n variable_type
```

See also:
- [Core Abstractions](core-abstractions.md)
- [For Loops](for-loops.md)
- [Filter Reference](filters.md)
