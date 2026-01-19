---
title: Complexity Scoring
description: How spec complexity scores work and how to assign them. Specs run in complexity order - lower scores first.
order: 5
---

# Complexity Scoring Guide

This document defines the complexity scoring system used in liquid-spec to order and prioritize test specs. Complexity scores help implementers build Liquid parsers incrementally by tackling simpler features first.

## Overview

Every spec should have a `complexity` field indicating how difficult the feature is to implement. Lower scores represent simpler features that should be implemented first; higher scores represent advanced features and edge cases.

**Default complexity:** If no complexity is specified, the spec defaults to **1000** (undefined/unscored).

## Suite-Level Minimum Complexity

Suites can define a `minimum_complexity` in their `suite.yml` file. This value is applied to all specs in that suite that don't have an explicit complexity:

```yaml
# suite.yml
name: "My Suite"
minimum_complexity: 1000
```

This avoids restating the same complexity on every spec in suites where most specs are edge cases or production recordings.

## Complexity Ranges

### 0-1: The Foundation
Can your implementation compile and render at all? These are the first specs any implementation should pass.

| Range | Feature | Examples |
|-------|---------|----------|
| 0 | Empty template | `""` → `""` |
| 1 | Literal passthrough | `"hello"` → `"hello"`, whitespace preserved, newlines preserved |

A correct implementation at complexity 1 can accept a template string and output it unchanged.

### 5: Basic Object Output
The first Liquid syntax: `{{ expression }}` for outputting values.

| Range | Feature | Examples |
|-------|---------|----------|
| 5 | String/number literals | `{{ 'world' }}`, `{{ 42 }}`, `{{ nil }}` outputs nothing |
| 5 | Mixed text and objects | `"hello {{ 'world' }}"` → `"hello world"` |

### 10-20: Literals and Raw Output (thorough tests)
More comprehensive tests of the basics. Edge cases for raw text and literals.

| Range | Feature | Examples |
|-------|---------|----------|
| 10 | Raw text edge cases | Special characters, unicode, multi-line |
| 20 | All literal types | `{{ 'hello' }}`, `{{ 42 }}`, `{{ true }}`, `{{ false }}`, `{{ nil }}` |

A correct implementation at complexity 20 can output literal strings, numbers, booleans, and nil.

### 30-50: Variables and Assignment
Looking up values and storing them.

| Range | Feature | Examples |
|-------|---------|----------|
| 30 | Variable lookup | `{{ name }}`, undefined variables return nil |
| 40 | Basic filters | `{{ 'x' \| upcase }}`, `{{ x \| size }}`, single filter with argument |
| 50 | Assign tag | `{% assign x = 'foo' %}`, assign with filter |

### 55-60: Basic Control Flow
Making decisions.

| Range | Feature | Examples |
|-------|---------|----------|
| 55 | Whitespace control | `{{- x -}}`, `{%- tag -%}` |
| 60 | If/else/unless | `{% if true %}`, `{% unless x %}`, equality operators |

### 70-80: Loops and Operators
Iteration and more comparison logic.

| Range | Feature | Examples |
|-------|---------|----------|
| 70 | Basic for loops | `{% for i in items %}`, ranges `(1..3)`, else block |
| 75 | Loop modifiers | `limit:`, `offset:`, `reversed`, `{% break %}`, `{% continue %}` |
| 80 | Filter chains, operators | `{{ x \| a \| b }}`, `and`/`or`, `contains`, `>`, `<`, `>=`, `<=` |

### 85-100: Math, Forloop Object, Capture
Numeric operations and loop metadata.

| Range | Feature | Examples |
|-------|---------|----------|
| 85 | Math filters | `plus`, `minus`, `times`, `divided_by`, `modulo`, `round`, `ceil`, `floor` |
| 90 | Forloop object | `forloop.index`, `forloop.first`, `forloop.last`, `forloop.length` |
| 90 | Capture tag | `{% capture x %}...{% endcapture %}` |
| 100 | Complex conditionals | `elsif`, `case/when`, multiple `when` values |

### 105-130: String Manipulation and Special Tags
String processing and specialized constructs.

| Range | Feature | Examples |
|-------|---------|----------|
| 105 | String filters | `append`, `prepend`, `replace`, `split`, `slice`, `truncate` |
| 110 | HTML/URL filters | `escape`, `strip_html`, `url_encode`, `newline_to_br` |
| 115 | Increment/decrement | Counter semantics, independence from assign |
| 120 | Comment/raw tags | `{% comment %}`, `{% raw %}`, inline `{% # %}` |
| 130 | Echo/liquid tags | `{% echo x %}`, `{% liquid ... %}` multiline syntax |

### 140-180: Arrays, Properties, and Iteration Helpers
Complex data access and advanced loops.

| Range | Feature | Examples |
|-------|---------|----------|
| 140 | Array filters | `first`, `last`, `join`, `sort`, `uniq`, `compact`, `map`, `where` |
| 150 | Property access | Dot notation `user.name`, bracket notation `user['key']`, negative indices |
| 170 | Truthy/falsy edge cases | Empty string is truthy, zero is truthy, `empty` comparisons |
| 180 | Cycle and tablerow | `{% cycle %}`, `{% tablerow %}`, named cycles |

### 190-220: Advanced Features
Complex interactions and edge cases of standard features.

| Range | Feature | Examples |
|-------|---------|----------|
| 190 | Offset:continue | `offset:continue` for pagination, `forloop.parentloop` basics |
| 200 | Partials basics | `{% render 'x' %}`, `{% include 'x' %}`, parameter passing |
| 210 | Partial edge cases | Scope isolation, parentloop chains, forloop.length with limit |
| 220 | Complex interactions | Multiple features interacting in non-obvious ways |

### 300-400: Implementation Edge Cases
Subtle behaviors that may trip up implementations.

| Range | Feature | Examples |
|-------|---------|----------|
| 300 | Scope edge cases | Nested includes sharing state, parameter evaluation context |
| 350 | Parser edge cases | Unusual whitespace, malformed input handling |
| 400 | Obscure filter behaviors | Unusual argument combinations, type coercion edge cases |

### 500: Deprecated or Legacy Features
Features that are deprecated or exist only for backwards compatibility.

### 1000 (Default): Unscored Specs
Specs without an explicit complexity score default to 1000. This is intentional:
- It keeps unscored specs separate from the progression
- It encourages spec authors to explicitly think about complexity
- Use `minimum_complexity` in suite.yml for suites where most specs are edge cases

### 1000-1500: Production Edge Cases and Random Behaviors
Edge cases recorded from production that don't fit into the standard progression.

| Range | Feature | Examples |
|-------|---------|----------|
| 1000-1100 | Shopify production recordings | Real-world template behaviors |
| 1100-1200 | Integration test recordings | Behaviors captured from the reference implementation |
| 1200-1500 | Obscure edge cases | Unusual combinations, random behaviors |

Use this range for specs that:
- Were recorded from production and don't have a clear "standard" status
- Test behaviors that may be implementation-specific
- Cover random combinations that were discovered in the wild

## Edge Cases Within a Feature

When a feature has both a "happy path" and edge cases, the edge case should be scored slightly higher but stay within the same general range.

**Example: For loops at complexity 70-75**

| Complexity | Test |
|------------|------|
| 70 | Basic `for` over array |
| 70 | Range `(1..3)` |
| 70 | Else block for empty arrays |
| 75 | `limit:` modifier |
| 75 | `offset:` modifier |
| 75 | `reversed` keyword |
| 75 | `{% break %}` |
| 75 | `{% continue %}` |

Edge cases of for loops (like `offset:continue` or `parentloop`) are more advanced and belong in the 190-210 range.

## Guidelines for Spec Authors

1. **Start simple**: Basic usage of a feature should be the lowest complexity in its range
2. **Edge cases add +5 to +10**: Unusual inputs or corner cases within the same feature
3. **Combinations are higher**: When two features interact, use the higher feature's complexity + 10-20
4. **Production recordings default to 1000+**: Unless they clearly test a specific standard feature
5. **Document unusual scores**: Use the `hint` field to explain why a spec has its complexity

## Implementation Order Recommendation

When building a new Liquid implementation, work through specs in complexity order:

1. **Phase 1 (10-60)**: Get basic output and assignment working
2. **Phase 2 (70-100)**: Add loops and control flow
3. **Phase 3 (105-150)**: String and array manipulation
4. **Phase 4 (170-220)**: Advanced features and partials
5. **Phase 5 (300+)**: Edge cases and production compatibility

This ordering ensures you build a solid foundation before tackling complex interactions.
