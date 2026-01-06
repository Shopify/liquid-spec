---
title: The cycle Tag
description: >
  How the cycle tag rotates through values, including its quirky identity rules where unnamed cycles
  with variables get independent counters. Covers named vs unnamed cycles, counter persistence, and
  isolation in render vs include.
optional: false
order: 6
---

# The `cycle` Tag

This document explains Liquid's `cycle` tag, including its counter-intuitive identity rules.

## Quick Reference

```liquid
{% cycle "a", "b", "c" %}  → outputs "a", then "b", then "c", then "a"...
{% cycle name: "a", "b" %} → named cycle, independent counter
```

## Basic Behavior

The `cycle` tag outputs values in rotation. Each call advances to the next value:

```liquid
{% for i in (1..4) %}
  {% cycle "odd", "even" %}
{% endfor %}
```
Output: `odd even odd even`

## Counter Identity: The Tricky Part

Cycle counters are stored in `registers["cycle"]` keyed by a **cycle identity**. Two cycle tags share a counter if and only if they have the same identity.

### Named Cycles

Named cycles use the **evaluated name** as their identity:

```liquid
{% cycle "group1": "a", "b" %}
{% cycle "group1": "a", "b" %}
{% cycle "group2": "a", "b" %}
```
Output: `a b a`

- First two cycles share counter (same name "group1")
- Third cycle has independent counter (name "group2")

The name can be a variable:

```liquid
{% assign name = "mygroup" %}
{% cycle name: "a", "b" %}
{% cycle name: "a", "b" %}
```
Output: `a b` (both evaluate to "mygroup", share counter)

### Unnamed Cycles: The Quirk

Unnamed cycles have surprising identity rules that differ based on whether the values are **literals** or **variables**:

**Literal values → Shared counter:**
```liquid
{% cycle "a", "b" %}
{% cycle "a", "b" %}
{% cycle "a", "b" %}
```
Output: `a b a` (all three share one counter)

**Variable lookups → Independent counters:**
```liquid
{% assign x = "a" %}
{% cycle x, "b" %}
{% cycle x, "b" %}
```
Output: `a a` (each cycle has its own counter!)

### Why This Quirk Exists

The identity for unnamed cycles is computed by stringifying the expression list.

For literals like `"a"`, the string is consistent, so `{% cycle "a", "b" %}` always has the same identity.

For variable reference nodes, the stringification includes an internal identity token, so each tag gets a distinct identity even if the expressions are textually identical. To preserve backwards compatibility, implementations **clone** variable references for unnamed cycles before computing the identity.

## Pseudocode Implementation

### Data Structures

```
# In registers
registers["cycle"] = {
  "cycle_identity_1" => 0,  # current index
  "cycle_identity_2" => 1,
  # ...
}

CycleTag:
  name: Expression | nil      # The cycle name (for named cycles)
  variables: List<Expression> # The values to cycle through
  is_named: Boolean           # Whether this is a named cycle

UNIQUE_REFERENCE_TOKEN_PATTERN = /.../  # implementation-defined unique token pattern
```

### Parsing

```
function parse_cycle(markup):
  tag = CycleTag()
  
  # Check for named syntax: name: value1, value2, ...
  if markup matches "expr: expr, expr, ...":
    tag.name = parse_expression(name_part)
    tag.variables = parse_values(values_part)
    tag.is_named = true
  else:
    # Unnamed syntax: value1, value2, ...
    tag.variables = parse_values(markup)
    tag.is_named = false
    
    # Compute identity from variables array
    # CRITICAL: Clone variable references to ensure unique identity per tag
    tag.variables = tag.variables.map(v => maybe_clone_reference(v))
    tag.name = tag.variables.to_string()
    
    # Check if the name includes a unique reference token
    # If it doesn't, treat it as named (shared counter)
    if not tag.name.matches(UNIQUE_REFERENCE_TOKEN_PATTERN):
      tag.is_named = true
  
  return tag

function maybe_clone_reference(var):
  if var is VariableReference:
    return clone(var)  # New identity token
  return var
```

### Rendering

```
function render_cycle(tag, state, output):
  # Get or create cycle counters map
  cycles = state.registers["cycle"]
  if cycles is nil:
    cycles = {}
    state.registers["cycle"] = cycles
  
  # Evaluate the cycle identity key
  key = state.evaluate(tag.name)
  
  # Get current position, default to 0
  index = cycles[key] || 0
  
  # Get the value at current position
  value = state.evaluate(tag.variables[index])
  
  # Output the value
  if value is Array:
    output.append(value.join(""))
  else:
    output.append(value.to_string())
  
  # Advance counter (wrap around)
  index = (index + 1) % tag.variables.length
  cycles[key] = index
```

## Behavioral Specifications

### Basic Cycling

```liquid
{% for i in (1..5) %}{% cycle "a", "b", "c" %}{% endfor %}
```
Output: `abcab`

### Named Cycles Stay Separate

```liquid
{% for i in (1..3) %}
  {% cycle "row": "odd", "even" %}
  {% cycle "col": "left", "right" %}
{% endfor %}
```
Output: `odd left even right odd left`

### Shared Counter Across Loops

```liquid
{% for i in (1..2) %}{% cycle "a", "b" %}{% endfor %}
{% for i in (1..2) %}{% cycle "a", "b" %}{% endfor %}
```
Output: `abab`

The counter continues from where it left off (2 % 2 = 0, so back to "a").

### Variable Names Create Shared Counters

```liquid
{% assign group = "colors" %}
{% cycle group: "red", "blue" %}
{% cycle group: "red", "blue" %}
{% cycle group: "red", "blue" %}
```
Output: `red blue red`

The variable `group` evaluates to `"colors"` both times, so they share a counter.

### Different Variable Values = Different Counters

```liquid
{% assign g1 = "colors" %}
{% assign g2 = "sizes" %}
{% cycle g1: "red", "blue" %}
{% cycle g2: "red", "blue" %}
{% cycle g1: "red", "blue" %}
```
Output: `red red blue`

- First cycle: g1="colors", index 0 → "red", advance to 1
- Second cycle: g2="sizes", index 0 → "red", advance to 1  
- Third cycle: g1="colors", index 1 → "blue", advance to 0

### The Unnamed Variable Quirk

```liquid
{% assign a = "1" %}
{% for i in (1..3) %}
  {% cycle a, "2" %}
  {% cycle a, "2" %}
{% endfor %}
```
Output: `1 1 2 2 1 1`

Each `{% cycle a, "2" %}` has a **different** identity because the variable reference for `a` is cloned, giving each tag a unique identity token.

Compare to literals:

```liquid
{% for i in (1..3) %}
  {% cycle "1", "2" %}
  {% cycle "1", "2" %}
{% endfor %}
```
Output: `1 2 1 2 1 2`

Same identity string, shared counter.

## Counter Persistence

Cycle counters persist across:
- Multiple loops in the same render
- Different locations in the same template

But NOT across:
- Different render calls
- Isolated subcontexts (`render` tag creates fresh registers)

```liquid
{% cycle "a", "b" %}
{% render 'snippet' %}
{% cycle "a", "b" %}

{# snippet.liquid #}
{% cycle "a", "b" %}
```
Output: `a a b`

- First cycle: index 0 → "a"
- Rendered snippet: fresh registers, index 0 → "a"
- Third cycle: back in main context, index 1 → "b"

## Implementation Checklist

1. **Named cycles:** Use evaluated name as counter key
2. **Unnamed cycles:** Use variables array string representation as key
3. **Variable reference cloning:** Clone references to give each tag unique identity
4. **Counter storage:** Use `registers["cycle"]` hash
5. **Wrap-around:** `(index + 1) % variables.length`
6. **Array output:** Join arrays to string when outputting

## Common Pitfalls

1. **Forgetting to clone variable references:** Unnamed cycles with variables will incorrectly share counters
2. **String representation inconsistency:** The identity string must be consistent for the same literals
3. **Register isolation:** `render` tag must create fresh cycle counters
4. **Counter not incrementing:** Must increment AFTER getting the value, not before

See also:
- [Core Abstractions](core-abstractions.md)
- [For Loops](for-loops.md)
- [Partials](partials.md)
