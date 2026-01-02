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

Cycle counters are stored in `registers[:cycle]` keyed by a **cycle identity**. Two cycle tags share a counter if and only if they have the same identity.

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

The identity for unnamed cycles is computed as `@variables.to_s` - the string representation of the variables array.

For literals like `"a"`, `to_s` produces a consistent string, so `{% cycle "a", "b" %}` always has the same identity.

For `VariableLookup` objects, each instance has a different `object_id`, so `to_s` includes that ID. To preserve backwards compatibility, Liquid **duplicates** each VariableLookup, ensuring each cycle tag gets unique object IDs and thus a unique identity.

```ruby
# From cycle.rb
def maybe_dup_lookup(var)
  var.is_a?(VariableLookup) ? var.dup : var
end
```

The code comment acknowledges this is a quirk preserved for backwards compatibility.

## Pseudocode Implementation

### Data Structures

```
# In registers
registers[:cycle] = {
  "cycle_identity_1" => 0,  # current index
  "cycle_identity_2" => 1,
  # ...
}

CycleTag:
  name: Expression | nil      # The cycle name (for named cycles)
  variables: List<Expression> # The values to cycle through
  is_named: Boolean           # Whether this is a named cycle
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
    # CRITICAL: Duplicate VariableLookups to ensure unique identity per tag
    tag.variables = tag.variables.map(v => maybe_dup_lookup(v))
    tag.name = tag.variables.to_string()
    
    # Check if the name looks like a unique object ID pattern
    # If so, this is effectively a named cycle (shares counter)
    if not tag.name.matches(/\w+:0x[0-9a-f]{8}/):
      tag.is_named = true
  
  return tag

function maybe_dup_lookup(var):
  if var is VariableLookup:
    return var.duplicate()  # New object with new object_id
  return var
```

### Rendering

```
function render_cycle(tag, state, output):
  # Get or create cycle counters map
  cycles = state.registers[:cycle] ||= {}
  
  # Evaluate the cycle identity key
  key = state.evaluate(tag.name)
  
  # Get current position, default to 0
  index = cycles[key] || 0
  
  # Get the value at current position
  value = state.evaluate(tag.variables[index])
  
  # Output the value
  if value is Array:
    output << value.join("")
  else:
    output << value.to_string()
  
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
Output: `ab ab`

Wait, that's wrong. Let me reconsider. The cycle counter persists in registers, so:

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

Each `{% cycle a, "2" %}` has a **different** identity because the VariableLookup for `a` is duplicated, giving each tag a unique object ID.

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
3. **VariableLookup duplication:** Duplicate lookups to give each tag unique identity
4. **Counter storage:** Use `registers[:cycle]` hash
5. **Wrap-around:** `(index + 1) % variables.length`
6. **Array output:** Join arrays to string when outputting

## Common Pitfalls

1. **Forgetting to duplicate VariableLookups:** Unnamed cycles with variables will incorrectly share counters
2. **String representation inconsistency:** The identity string must be consistent for the same literals
3. **Register isolation:** `render` tag must create fresh cycle counters
4. **Counter not incrementing:** Must increment AFTER getting the value, not before
