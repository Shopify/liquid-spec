# Writing Great Specs

This guide explains what makes a liquid-spec test valuable. A great spec doesn't just verify correctness—it teaches implementers what to build next and helps them understand *why* Liquid behaves the way it does.

## The Three Pillars of a Great Spec

### 1. Test Something Novel

Every spec should teach the implementer something new. Ask yourself: "If an implementer passes all specs with lower complexity, what new concept does this spec introduce?"

**Good:** Tests a new feature, edge case, or interaction
```yaml
- name: for_offset_continue_basic
  template: "{% for i in items limit:3 %}{{ i }}{% endfor %}|{% for i in items offset:continue limit:3 %}{{ i }}{% endfor %}"
  environment: { items: [1, 2, 3, 4, 5, 6, 7, 8, 9] }
  expected: "123|456"
  complexity: 190
  hint: |
    offset:continue resumes from where the previous loop left off.
    First loop takes 1,2,3. Second loop continues with 4,5,6.
```

**Bad:** Redundant with other specs at the same complexity
```yaml
# If you already have a spec for {{ 'hello' | upcase }}, you don't need
# separate specs for {{ 'world' | upcase }} and {{ 'foo' | upcase }}
```

### 2. Well-Chosen Complexity

Specs run in complexity order. An implementer working through specs should encounter exactly what they need to implement next—not features that depend on unimplemented prerequisites.

**Complexity determines learning order.** A spec at complexity 70 (for loops) should not require understanding features at complexity 140 (array filters). If it does, the spec's complexity is wrong.

| Range | What It Should Test |
|-------|---------------------|
| 10-20 | Literals, raw text—no logic needed |
| 30-50 | Variables, filters, assign |
| 55-60 | Whitespace control, if/else/unless |
| 70-80 | For loops, operators, filter chains |
| 85-100 | Math filters, forloop object, capture, case/when |
| 105-130 | String filters, increment, comment, raw, echo |
| 140-180 | Array filters, property access, truthy/falsy edge cases |
| 190-220 | offset:continue, parentloop, partials |
| 300-500 | Edge cases, deprecated features |
| 1000+ | Production recordings, unscored specs |

**Rule of thumb:** If your spec fails for an implementer who has passed all lower-complexity specs, your complexity is too low. If it passes trivially without implementing anything new, your complexity is too high.

### 3. Actionable Hints

Hints are displayed when a spec fails. They should tell the implementer exactly what to do—not just describe the expected behavior.

**Good hint:** Explains what to implement
```yaml
hint: |
  Recognize 'empty' as a keyword representing the empty state.
  An empty string "" should equal the 'empty' keyword. Create
  an EmptyLiteral node during parsing. During evaluation, compare
  the variable's value against emptiness: empty strings, empty
  arrays, and empty hashes all equal 'empty'.
```

**Bad hint:** Just restates the expected output
```yaml
hint: |
  The template should output "empty" when the string is empty.
```

## Hint Writing Guide

### Structure of a Great Hint

1. **State the key insight** (first sentence)
2. **Explain the implementation** (what code to write)
3. **Clarify edge cases** (what makes this tricky)

### When to Flag Warts

Some Liquid behaviors are surprising or counterintuitive. Flag these with `WART:` so implementers know the behavior is intentional, not a bug in the spec:

```yaml
- name: int_size_returns_byte_size
  template: "{{ num | size }}"
  environment: { num: 42 }
  expected: "8"
  complexity: 150
  hint: |
    WART: int | size returns 8 because Ruby's Integer#size returns
    the byte representation size (8 bytes on 64-bit systems), NOT
    the number of digits. This is surprising but matches liquid-ruby.
```

### When to Link Documentation

For complex concepts that can't fit in a hint, link to a doc file:

```yaml
_metadata:
  doc: implementers/for-loops.md

specs:
- name: forloop_parentloop_chain
  # ...
  hint: |
    parentloop can be chained for deeply nested loops. For full
    details on forloop scope and nesting, see the linked doc.
```

Available documentation:
- `implementers/core-abstractions.md` - Empty, blank, nil, truthy/falsy
- `implementers/for-loops.md` - Loops, forloop object, parentloop
- `implementers/scopes.md` - Variable scoping rules
- `implementers/partials.md` - Include/render behavior
- `implementers/interrupts.md` - Break/continue semantics
- `implementers/cycle.md` - Cycle tag behavior
- `implementers/parsing.md` - Parser implementation details

## Spec Structure

### Basic Spec

```yaml
- name: descriptive_snake_case_name
  template: "{{ x | upcase }}"
  environment: { x: "hello" }
  expected: "HELLO"
  complexity: 40
  hint: |
    The upcase filter converts a string to uppercase. Implement a
    filter registry and add 'upcase' that calls the string's
    uppercase method.
```

### Spec with Filesystem (for partials)

```yaml
- name: render_with_variable
  template: "{% render 'greeting', name: 'World' %}"
  expected: "Hello, World!"
  complexity: 200
  filesystem:
    greeting.liquid: "Hello, {{ name }}!"
  hint: |
    The render tag loads a partial and passes variables to it.
    Variables are scoped—the partial cannot access outer variables.
```

### Source-Level Metadata

Apply settings to all specs in a file:

```yaml
_metadata:
  doc: implementers/core-abstractions.md
  hint: "All specs in this file test empty/blank semantics."
  required_options:
    error_mode: :lax

specs:
- name: first_spec
  # ...
```

## Common Mistakes

### Wrong Complexity

**Problem:** Spec requires features not yet introduced
```yaml
# BAD: Uses filter chains (complexity 80) but marked as complexity 40
- name: variable_with_chained_filters
  template: "{{ name | downcase | capitalize }}"
  complexity: 40  # Should be 80+
```

### Redundant Specs

**Problem:** Multiple specs testing the same concept
```yaml
# BAD: These are all testing the same thing (basic filter application)
- name: upcase_hello
  template: "{{ 'hello' | upcase }}"
- name: upcase_world
  template: "{{ 'world' | upcase }}"
- name: upcase_foo
  template: "{{ 'foo' | upcase }}"
```

**Better:** One spec for the basic case, additional specs only for edge cases
```yaml
- name: filter_upcase_basic
  template: "{{ 'hello' | upcase }}"
  complexity: 40
- name: filter_upcase_empty_string
  template: "{{ '' | upcase }}"
  complexity: 45  # Edge case
- name: filter_upcase_with_unicode
  template: "{{ 'café' | upcase }}"
  complexity: 50  # Unicode edge case
```

### Unhelpful Hints

**Problem:** Hint doesn't explain implementation
```yaml
# BAD: Just describes the behavior
hint: "Empty arrays should be considered empty."

# GOOD: Explains what to implement
hint: |
  Arrays with no elements should equal 'empty'. When evaluating
  the comparison, check if the array's length is zero. An empty
  array [] is considered empty. This is distinct from an array
  containing empty strings, which would not be empty.
```

### Missing Context for Surprising Behavior

**Problem:** Implementer assumes the spec is wrong
```yaml
# BAD: No explanation for surprising behavior
- name: false_is_blank
  template: "{% if false == blank %}yes{% else %}no{% endif %}"
  expected: "yes"
  hint: "false equals blank"

# GOOD: Explains why
- name: false_is_blank
  template: "{% if flag == blank %}blank{% else %}not{% endif %}"
  environment: { flag: false }
  expected: "blank"
  hint: |
    The boolean false is blank. The blank keyword matches values that
    are nil, false, empty strings, whitespace-only strings, and empty
    collections. False is considered blank because it represents a
    falsy/absent value.
```

## Testing Your Specs

Before submitting specs, verify them against liquid-ruby:

```bash
# Test a single spec
liquid-spec eval examples/liquid_ruby.rb --compare <<EOF
name: my_new_spec
template: "{{ x | upcase }}"
environment: { x: "hello" }
expected: "HELLO"
complexity: 40
hint: |
  Upcase converts to uppercase.
EOF

# Run all specs and check for regressions
bundle exec rake run
```

## Spec File Organization

- `specs/basics/` - Core Liquid features every implementation needs
- `specs/liquid_ruby/` - Specs extracted from Shopify/liquid tests
- `specs/shopify_production_recordings/` - Real-world behaviors from production
- `specs/shopify_theme_dawn/` - Shopify-specific features (tags, objects, filters)

Each directory contains a `suite.yml` with suite-level configuration:

```yaml
name: "Liquid Ruby"
description: "Core Liquid template engine behavior"
default: true
required_features: [core]
minimum_complexity: 1000
```

## Summary Checklist

Before submitting a spec, verify:

- [ ] **Novel:** Tests something not covered by existing specs
- [ ] **Correct complexity:** Doesn't require features above its complexity level
- [ ] **Actionable hint:** Tells implementers what to build, not just what's expected
- [ ] **Warts flagged:** Surprising behaviors marked with `WART:`
- [ ] **Docs linked:** Complex concepts reference documentation
- [ ] **Verified:** Passes against liquid-ruby with `--compare`
