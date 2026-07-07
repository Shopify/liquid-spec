# Liquid Truthiness, Empty, Blank, and Default

Liquid has **four distinct "is this nothing?" concepts** that look similar but
behave differently. Getting them confused is one of the most common
implementation bugs. This document covers all four with the exact reference
behavior.

## 1. Truthiness (`{% if %}`)

**Only `false` and `nil` are falsy. Everything else is truthy.**

This matches Ruby semantics, not JavaScript or Python.

| Value        | Truthy? | Notes                                  |
|--------------|---------|----------------------------------------|
| `false`      | No      | One of two falsy values                |
| `nil`        | No      | The other falsy value                  |
| `true`       | Yes     |                                        |
| `0`          | Yes     | NOT falsy (unlike JS/Python)           |
| `""`         | Yes     | Empty string is truthy                 |
| `"0"`        | Yes     | String zero is truthy                  |
| `"   "`      | Yes     | Whitespace string is truthy            |
| `[]`         | Yes     | Empty array is truthy                  |
| `[1]`        | Yes     |                                        |
| `{}`         | Yes     | Empty hash is truthy                   |
| undefined    | No      | Resolves to nil → falsy                |

**Common pitfall:** Implementers from JS/Python backgrounds make `0`, `""`, and
`[]` falsy. This breaks hundreds of specs. Only `false` and `nil`.

**Idiomatic "variable exists?" check:** `{% if maybe %}` — undefined resolves
to nil, which is falsy.

## 2. The `empty` Keyword

`empty` is a **value comparison keyword** used with `==` and `!=`. It matches
**only empty collections**: empty strings, empty arrays, and empty hashes.

| Value        | `== empty`? | Notes                              |
|--------------|-------------|------------------------------------|
| `""`         | Yes         | Empty string                       |
| `[]`         | Yes         | Empty array                        |
| `{}`         | Yes         | Empty hash                         |
| `"   "`      | No          | Has characters (whitespace)        |
| `nil`        | No          | Not a collection                   |
| `false`      | No          | Not a collection                   |
| `0`          | No          | Not a collection                   |
| `"a"`        | No          | Non-empty string                   |
| `[1]`        | No          | Non-empty array                    |

**Use case:** Distinguish "exists but empty" from "doesn't exist":
```liquid
{% if items == empty %}No items found{% endif %}
{% if items != empty %}{{ items | size }} items{% endif %}
```

**Key point:** `empty` does NOT match `nil` or `false`. It's strictly about
collection emptiness.

## 3. The `blank` Keyword (Shopify Extension)

`blank` is a **Shopify extension**, broader than `empty`. It matches everything
`empty` matches, PLUS `nil`, `false`, and whitespace-only strings.

| Value        | `== blank`? | `== empty`? | Difference          |
|--------------|-------------|-------------|---------------------|
| `nil`        | Yes         | No          | blank includes nil  |
| `false`      | Yes         | No          | blank includes false|
| `""`         | Yes         | Yes         | same                |
| `"   "`      | Yes         | No          | blank catches whitespace |
| `[]`         | Yes         | Yes         | same                |
| `{}`         | Yes         | Yes         | same                |
| `0`          | No          | No          | 0 is never blank    |
| `"a"`        | No          | No          | non-empty           |

**Use case:** Detect "nothing meaningful here" including whitespace-only input:
```liquid
{% if description == blank %}No description{% endif %}
{# catches "", "   ", nil, false in one check #}
```

**The `blank` vs `empty` difference is whitespace strings and nil/false.** Use
`blank` when you want to treat whitespace-only as empty; use `empty` when you
need strict collection emptiness.

## 4. The `default` Filter

`default` replaces values that are "empty-ish" with a fallback. But its
blankness check is **different from both `empty` and `blank`**.

| Value        | `default` replaces? | `== empty`? | `== blank`? |
|--------------|---------------------|-------------|-------------|
| `nil`        | Yes → fallback      | No          | Yes         |
| `false`      | Yes → fallback      | No          | Yes         |
| `""`         | Yes → fallback      | Yes         | Yes         |
| `"   "`      | No — passes through | No          | Yes         |
| `[]`         | Yes → fallback      | Yes         | Yes         |
| `{}`         | Yes → fallback      | Yes         | Yes         |
| `0`          | No — passes through | No          | No          |
| `"a"`        | No — passes through | No          | No          |
| undefined    | Yes → fallback      | No          | Yes         |

**The critical distinction:** `default` replaces `nil`, `false`, and
empty collections (`""`, `[]`, `{}`). But it does **NOT** replace
whitespace-only strings — those pass through unchanged. The `blank` keyword
*does* match whitespace strings, but `default` does not.

```liquid
{{ "" | default: 'x' }}        {# → "x"  (empty string replaced) #}
{{ "   " | default: 'x' }}     {# → "   " (whitespace passes through!) #}
{{ str == blank }}             {# → true (but default won't replace it) #}
```

**If you need whitespace-only strings replaced too**, you must combine filters:
```liquid
{{ str | strip | default: 'x' }}
```
But note this strips whitespace from ALL strings, not just blank ones.

## Summary Table

| Concept        | Falsy/Replaced values                           | Not replaced          |
|----------------|-------------------------------------------------|-----------------------|
| Truthiness     | `false`, `nil`                                  | everything else       |
| `empty`        | `""`, `[]`, `{}`                                | nil, false, 0, "   "  |
| `blank`        | nil, false, `""`, `"   "`, `[]`, `{}`           | 0, non-empty          |
| `default`      | nil, false, `""`, `[]`, `{}`, undefined         | 0, `"   "`, non-empty |

**The three-way split on whitespace strings:**
- `"   " == empty` → **false** (has characters)
- `"   " == blank` → **true** (whitespace is blank)
- `"   " | default: 'x'` → **"   "** (passes through, not replaced)

## Implementation Guidance

When implementing these in your Liquid engine:

1. **Truthiness:** Boolean check — `value == false || value == nil`. Nothing
   else is falsy. No coercion of 0, "", or [].

2. **`empty` keyword:** Compare against the empty state of the value's type.
   String length 0, array size 0, hash size 0. Non-collections (nil, false,
   numbers) never equal `empty`.

3. **`blank` keyword:** Check nil || false || empty-string || whitespace-only-
   string || empty-array || empty-hash. A string is blank if it's empty or
   contains only whitespace characters. 0 is never blank.

4. **`default` filter:** Replace if nil || false || (== empty). Do NOT check
   for whitespace-only strings — those pass through. This means `default`'s
   check is: `value.nil? || value == false || value == empty`, NOT
   `value == blank`.
