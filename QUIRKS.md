# Liquid Quirks

A collection of surprising, inconsistent, or quirky behaviors in Liquid that implementers should be aware of. These are documented here to help alternative implementations match the reference behavior, even when that behavior is counterintuitive.

## Table of Contents

1. [Integer vs Float Size](#integer-vs-float-size)
2. [Hash First/Last Asymmetry](#hash-firstlast-asymmetry)
3. [Filter vs Property Access Differences](#filter-vs-property-access-differences)
4. [Case Has No Break](#case-has-no-break)
5. [Blank Bodies Suppress Render-Error Text](#blank-bodies-suppress-render-error-text)
6. [Tablerow vs For Attribute Coercion](#tablerow-vs-for-attribute-coercion)

---

## Integer vs Float Size

**Severity:** Surprising
**Discovered:** Testing `| size` filter across types

### The Quirk

`int | size` returns `8` (Ruby's byte representation size), while `float | size` returns `0` (because Float doesn't respond to `.size`).

```liquid
{{ 42 | size }}      => 8
{{ 3.14 | size }}    => 0
```

### Why This Happens

The `size` filter in Ruby Liquid calls `input.respond_to?(:size) ? input.size : 0`:

- **Integer#size** exists in Ruby and returns the byte representation size (8 bytes on 64-bit systems)
- **Float#size** does not exist in Ruby, so the filter returns `0`

### Impact

- All integers return `8` regardless of their actual value (`0`, `1`, `999999999` all return `8`)
- This is *not* the number of digits
- Implementers might expect `size` to fail or return `nil` for numbers, not return arbitrary values

### Related Quirk: Property Access

Using `.size` property access differs from the filter:

```liquid
{{ 42.size }}    => 8    (Integer has .size)
{{ 3.14.size }}  => ""   (Float has no .size, returns nil)
```

But with the filter:

```liquid
{{ 42 | size }}    => 8
{{ 3.14 | size }}  => 0  (filter returns 0, not empty)
```

---

## Hash First/Last Asymmetry

**Severity:** Inconsistent
**Discovered:** Testing `first`/`last` on hashes

### The Quirk

`hash | first` returns the first key+value concatenated, but `hash | last` returns empty string.

```liquid
{% assign h = "a" | split: "" %}
{{ h | first }}  => Works for arrays

{% capture json %}{"a": 1, "b": 2}{% endcapture %}
{% assign h = json | parse_json %}
{{ h | first }}  => "a1"   (key + value concatenated)
{{ h | last }}   => ""     (empty!)
```

### Why This Happens

Hashes in Ruby respond to `first` (returns `[key, value]`) but not to `last` in the same way. When rendered, the array `[key, value]` gets joined without a separator.

### Impact

- Asymmetric behavior between `first` and `last` on the same data structure
- Hash's `first` output format is rarely useful (key and value mashed together)
- Alternative implementations might expect `last` to work if `first` does

---

## Filter vs Property Access Differences

**Severity:** Inconsistent
**Discovered:** Comparing `| filter` vs `.property` behavior

### The Quirk

The `| size` filter and `.size` property access behave differently for types without a native `.size` method.

| Type    | `x \| size` | `x.size` |
|---------|-------------|----------|
| Array   | 3           | 3        |
| Hash    | 2           | 2        |
| String  | 5           | 5        |
| Integer | 8           | 8        |
| Float   | **0**       | **""**   |
| Boolean | 0           | ""       |

### Why This Happens

- **Filter behavior:** Returns `0` when `respond_to?(:size)` is false
- **Property access:** Returns `nil` (rendered as empty) when method doesn't exist

### Impact

- Cannot reliably use property access and filter interchangeably
- Implementers must handle both cases differently
- `0` vs empty string can cause different behavior in conditionals

---

## Case Has No Break

**Severity:** Surprising
**Discovered:** Differential fuzzing (four independent triage passes converged on it)

### The Quirk

`{% case %}` is not a first-match switch. Each when-VALUE is an independent
condition; every match renders the body, in order:

```liquid
{% case "a" %}{% when "a" %}1{% when "a" %}2{% endcase %}
→ "12"

{% case "a" %}{% when "a", "a" %}M{% endcase %}
→ "MM"
```

`{% else %}` runs only when nothing before it matched. The per-match renders
are real renders — stateful tags (cycle, increment) advance each time.

### Why This Happens

Reference builds one condition block per when value and iterates all of them
without breaking (`Liquid::Case#render_to_output_buffer` flips an
`execute_else_block` flag but keeps going).

### Impact

Implementers who lower case to an if/elsif chain silently drop the extra
renders. Specs: `liquid_ruby/case_when_matching.yml`.

---

## Blank Bodies Suppress Render-Error Text

**Severity:** Surprising (and mode-dependent by spec decision)
**Discovered:** Differential fuzzing; root-caused to `BlockBody.rescue_render_node`'s `unless blank_tag` guard ("conditional for backwards compatibility")

### The Quirk

A block tag whose entire body is blank (whitespace, comments, assigns,
captures) suppresses the TEXT of any render error raised while evaluating it:

```liquid
{% if 5 > "x" %}{% endif %}     → ""
{% if 5 > "x" %}X{% endif %}    → "Liquid error (line 1): comparison of Integer with String failed"
```

The condition IS evaluated: the error is recorded on the template and
`render!` raises. Only the inline error text disappears. Output variables
(`{{ ... }}`, `{% echo %}`) are never blank, so their errors always print —
even `{{ "" }}` in the body makes the tag non-blank.

### Why This Happens

Reference's block-body rescue path appends the error message to output
`unless blank_tag` — a backwards-compatibility carve-out so invisible tags
stay invisible when they error.

### Impact

Silent failure of erroring conditions. **Spec decision (2026-07-05, rev. 2):**
the historical suppression is specified for lax AND strict (both matching
current reference liquid); strict2 is the new contract where an evaluated
error must surface regardless of body blankness. Raised-error mode is
orthogonal — all modes raise. Full matrix:
`liquid_ruby/blank_body_error_handling.yml`.

---

## Tablerow vs For Attribute Coercion

**Severity:** Surprising
**Discovered:** Differential fuzzing

### The Quirk

The same attribute value is an error in one tag and silently coerced in its
sibling:

```liquid
{% for a in (1..4) offset: str %}...       → Liquid error: invalid integer
{% tablerow a in (1..4) offset: str %}...  → renders all four items
```
(with `str = "bad"`.)

### Why This Happens

`Liquid::TableRow#to_integer` is duck-typed — `value.to_i rescue
NoMethodError => raise "invalid integer"` — so any String coerces
("bad".to_i == 0) and only #to_i-less values (booleans, hashes) raise. The
for tag validates integers strictly. A cols of 0 additionally means
"never wrap": one row.

### Impact

Implementations that share one attribute-validation helper between for and
tablerow get one of the two wrong. Specs:
`liquid_ruby/tablerow_attribute_coercion.yml` (coercion side) and
`liquid_ruby/manual.yml` (the boolean error side).

---

## Contributing Quirks

When you discover a new Liquid quirk, document it here with:

1. **Severity:** How surprising/problematic is this?
2. **Example:** Minimal reproduction showing the unexpected behavior
3. **Why This Happens:** Technical explanation of the root cause
4. **Impact:** What problems this causes for implementers/users
