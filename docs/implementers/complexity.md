---
title: Complexity Scoring
description: How spec complexity scores work and how to assign them. Specs run in complexity order - lower scores first.
order: 5
---

# Complexity Scoring Guide

liquid-spec is a harness for the gradual construction of a full, production-ready Liquid implementation. Complexity scores are the backbone of that workflow: they make the runner present small, confidence-building specs first, then progressively introduce real Liquid syntax, standard-library behavior, compatibility quirks, and finally production recordings.

A good score answers: **"When should a new implementation reasonably be expected to pass this spec?"** Lower scores are not a statement that the behavior is more important; they are an implementation ramp.

## Overview

Every spec should have a `complexity` field indicating how difficult the behavior is to implement. Lower scores represent simpler features that should be implemented first; higher scores represent advanced features, edge cases, and compatibility behaviors.

**Default complexity:** If no complexity is specified, the spec defaults to **1000** (undefined/unscored). The complexity ceiling is **1000**; do not assign scores above 1000.

## Suite-Level Minimum Complexity

Suites can define a `minimum_complexity` in their `suite.yml` file. This value is applied to specs in that suite that do not have an explicit complexity:

```yaml
# suite.yml
name: "My Suite"
minimum_complexity: 1000
```

This is useful for suites where most specs are edge cases, generated compatibility cases, or production recordings.

## Complexity Ranges

### 0-1: The Foundation

Can the adapter compile and render at all? These are deliberately trivial and should pass even for a toy implementation.

| Score | Feature | Examples |
|-------|---------|----------|
| 0 | Empty template | `""` → `""` |
| 1 | Literal passthrough | `"hello"` → `"hello"`, spaces preserved, newlines preserved |

A correct implementation at complexity 1 can accept a template string and output static text unchanged.

### 5: First Object Output

The first Liquid syntax: `{{ expression }}` with literal values only.

| Score | Feature | Examples |
|-------|---------|----------|
| 5 | String/number/nil literals | `{{ 'world' }}`, `{{ 42 }}`, `{{ nil }}` outputs nothing |
| 5 | Mixed text and object output | `hello {{ 'world' }}` → `hello world` |

### 10-20: Basic Literals and Raw Output Breadth

More coverage for the same beginner concepts, still without variables or control flow.

| Score | Feature | Examples |
|-------|---------|----------|
| 10 | Raw text breadth | Special characters, unicode, multi-line static text |
| 20 | Literal breadth | Strings, integers, booleans, nil, simple output tags |

A correct implementation at complexity 20 can tokenize object tags and render literal values.

### 30-50: Variables, Simple Filters, Assignment

The first dynamic templates.

| Score | Feature | Examples |
|-------|---------|----------|
| 30 | Variable lookup | `{{ name }}`, `hello {{ missing }}` → `hello ` |
| 35 | More literal/expression forms | Floats, quoted strings, boolean literals |
| 40 | Very simple filters | `{{ 'x' | upcase }}`, `{{ x | size }}`, one filter argument |
| 50 | Basic assign and comments-as-no-output | `{% assign x = 'foo' %}{{ x }}` |

Do **not** put drop protocol behavior, `to_liquid`, dynamic bracket lookup, parser recovery, or generated filter matrices here. A local LLM-created implementation should be able to get through this range with a small lexer/parser, a variable environment, and a handful of straightforward filters.

### 55-65: Basic Control Flow

Simple conditional execution. Whitespace-control syntax is **not** beginner control flow and belongs later.

| Score | Feature | Examples |
|-------|---------|----------|
| 55 | Basic truthiness checks | `if true`, `if false`, simple variable truthiness |
| 60 | If/else/unless | `{% if x %}...{% else %}...{% endif %}`, `{% unless x %}` |
| 65 | Basic boolean composition | Simple `and`/`or` without precedence edge cases |

Only `nil` and `false` are falsy in Liquid. Empty strings, zero, and empty arrays/hashes are truthy; edge cases for that behavior can be later than the first happy-path conditionals.

### 70-100: Simple Loops, Comparisons, Early Feature Composition

Iteration and modest composition. Keep the early loop ramp gentle.

| Score | Feature | Examples |
|-------|---------|----------|
| 70 | Basic for loops | `{% for i in items %}{{ i }}{% endfor %}`, simple `else` block |
| 80 | Straightforward comparisons/operators | `==`, `!=`, `<`, `>`, `contains`, simple filter chains |
| 90 | Forloop object, capture, simple case | `forloop.index`, `{% capture x %}`, basic `{% case %}` |
| 100 | Slightly richer variants | `elsif`, range loops, simple loop helpers |

Move these later than 100 unless they are intentionally gentle first-contact specs: `break`, `continue`, `limit`, `offset`, `offset:continue`, `parentloop` chains, whitespace trimming inside loops, unusual loop variable spacing, nil ordering comparisons, and complex boolean precedence.

### 105-150: Common Standard Library and Syntax Breadth

Practical Liquid features once the core language works.

| Score | Feature | Examples |
|-------|---------|----------|
| 105 | Beginner string filters | `append`, `prepend`, `replace`, `strip` |
| 110 | Comment/raw basics and first special tags | `{% comment %}`, `{% raw %}`, inline `{% # %}` |
| 115 | Increment/decrement basics | Counter semantics independent of `assign` |
| 120 | Loop interrupts and simple math generated cases | `{% break %}`, `{% continue %}`, basic arithmetic filters |
| 130 | Multiline/liquid/echo syntax, loop modifiers | `{% liquid %}`, `limit:`, `offset:`, `reversed` |
| 140 | Whitespace control and simple collection filters | `{{- x -}}`, `join`, `first`, `last`, simple array cases |
| 150 | Basic property/bracket access breadth | `user.name`, `user['name']`, array index access |

Generated compatibility specs should usually start no earlier than this band unless they are clearly simple duplicates of curated beginner specs.

### 160-220: Advanced Core Compatibility

Harder standard behaviors and interactions between features.

| Score | Feature | Examples |
|-------|---------|----------|
| 160 | Generated filter breadth | Coercion-heavy math/string cases, parser punctuation quirks |
| 170 | Truthy/falsy and `blank`/`empty` edge cases | Empty string is truthy; `empty` comparisons |
| 180 | Cycle, tablerow, drop boundary basics | `{% cycle %}`, `{% tablerow %}`, simple drop/to_liquid behavior |
| 190 | Filesystem/partials first contact | Gentle `{% render 'x' %}` / `{% include 'x' %}` with `.liquid` fixtures |
| 200 | Ruby/reference quirks and math edge cases | Integer-size quirks, divide-by-zero behavior |
| 210 | Partial scope and parameter interactions | include vs render scope, parameter passing |
| 220 | Complex interactions | Multiple features interacting in non-obvious ways |

### 230-400: Long-Tail Standard Behavior

Subtle, but still part of a serious standard Liquid implementation.

| Score | Feature | Examples |
|-------|---------|----------|
| 230-260 | Advanced lookup and filesystem behavior | Subpaths, dynamic include names, parentloop interactions |
| 270-320 | Parser and syntax edge cases | Trailing punctuation, odd whitespace, strict-mode unknown tags |
| 330-400 | Obscure filter/type coercion behavior | Hash/array/drop coercions, generated matrix edge cases |

### 500-900: Compatibility, Legacy, and Deep Edge Cases

These specs validate mature compatibility. They should not block the first implementation ramp.

| Score | Feature | Examples |
|-------|---------|----------|
| 500 | Parser error mutation/fuzz matrices and resource-limit accounting | Generated malformed syntax cases, precise parse errors, render-score limits |
| 600 | Recursion and deep partial behavior | Nesting too deep, deep include/render chains |
| 700 | Security-sensitive/reference quirks | Literal `..` filesystem lookup behavior, surprising compatibility choices |
| 800 | Date/time and platform-specific quirks | Timezones, invalid date behavior, Ruby-specific `strftime` flags |
| 900 | Rare Ruby/drop/protocol quirks | Behaviors needed for high-fidelity liquid-ruby compatibility |

### 1000: Production Recordings and Unscored Specs

Specs without an explicit complexity score default to 1000. Use 1000 for:

- Shopify production recordings
- Full theme/page recordings
- Specs whose implementation order has not been evaluated yet
- Behaviors that are real and worth preserving but not useful as an implementation milestone

Do not assign scores above 1000.

## Edge Cases Within a Feature

When a feature has both a happy path and edge cases, the first spec for that feature should be gentle and one point lower than nearby follow-up specs when useful. The first spec should include a hint that names the feature and points to the relevant implementer doc.

**Example: filesystem partials**

| Complexity | Test |
|------------|------|
| 189 | First gentle filesystem render/include spec with hint and doc pointer |
| 190 | Basic `.liquid` extension lookup |
| 240 | Subpath lookup |
| 300 | Not-found errors |
| 600 | Recursion/nesting-too-deep |
| 700 | Literal `..` lookup compatibility quirk |

## Guidelines for Spec Authors

1. **Preserve the ramp:** A dumb adapter should pass only the truly trivial first specs, then fail with an actionable message.
2. **Start every feature gently:** The first spec for a major feature should be minimal and well-hinted.
3. **Curate before generated matrices:** Put handcrafted basics early; generated reference matrices generally belong at 120+ or much later.
4. **Edge cases add +10 to +50:** The stranger the behavior, the farther it moves from the first-contact score.
5. **Combinations are higher:** When two features interact, use the higher feature's score plus 10-50.
6. **Quirks go late:** Ruby-specific, drop-protocol, date/time, parser recovery, and production/platform behavior usually belongs at 500-1000.
7. **Document unusual scores:** Use `hint` to explain why a spec is early or late.
8. **Stay within the ceiling:** Complexity must be between 0 and 1000.

## Implementation Order Recommendation

When building a new Liquid implementation, work through specs in complexity order:

1. **Phase 0 (0-20):** Pipeline, static text, object tags, literal output, nil-as-empty.
2. **Phase 1 (30-50):** Variables, missing variables, simple filters, assign.
3. **Phase 2 (55-100):** Basic conditionals, loops, comparisons, capture/case/forloop basics.
4. **Phase 3 (105-180):** Standard filters, comments/raw, whitespace control, interrupts, collection helpers, cycle/tablerow.
5. **Phase 4 (190-400):** Partials/filesystem, scope interactions, generated compatibility breadth.
6. **Phase 5 (500-900):** Parser error matrices, resource-limit accounting, recursion/deep nesting, security/reference quirks, date/time and Ruby compatibility.
7. **Phase 6 (1000):** Production recordings and unscored mature-compatibility checks.

Fix failures in the order they appear. If the first failure is surprising, the spec probably needs a better hint or a higher complexity score.
