# The `for` Loop

This document explains Liquid's `for` loop, including `offset: continue`, `forloop` object, and `parentloop` tracking.

## Quick Reference

```liquid
{% for item in collection %}
  {{ forloop.index }}: {{ item }}
{% endfor %}
```

Options: `limit`, `offset`, `reversed`, `offset: continue`

## Basic Behavior

```liquid
{% for item in items %}
  {{ item }}
{% endfor %}
```

Iterates over `items`, binding each element to `item`.

### Parameters

| Parameter | Effect |
|-----------|--------|
| `limit:N` | Only iterate N times |
| `offset:N` | Skip first N items |
| `reversed` | Iterate in reverse order |
| `offset:continue` | Resume from last position (see below) |

```liquid
{% for item in items limit:2 offset:1 %}{{ item }}{% endfor %}
```
Given `items = [a, b, c, d, e]`, outputs: `bc`

## The `forloop` Object

Inside a for loop, `forloop` provides iteration metadata:

| Property | Description |
|----------|-------------|
| `forloop.index` | 1-based index (1, 2, 3...) |
| `forloop.index0` | 0-based index (0, 1, 2...) |
| `forloop.rindex` | Reverse 1-based index (N, N-1, ... 1) |
| `forloop.rindex0` | Reverse 0-based index (N-1, N-2, ... 0) |
| `forloop.first` | `true` if first iteration |
| `forloop.last` | `true` if last iteration |
| `forloop.length` | Total number of iterations |
| `forloop.parentloop` | Parent's forloop (nested loops) |

## The `parentloop` Chain

In nested loops, each `forloop` has a reference to its parent:

```liquid
{% for i in outer %}
  {% for j in inner %}
    {{ forloop.parentloop.index }}.{{ forloop.index }}
  {% endfor %}
{% endfor %}
```
Output: `1.1 1.2 1.3 2.1 2.2 2.3` (for 2x3 arrays)

### How parentloop Works

The implementation maintains a **stack** of forloop objects in registers:

```
registers[:for_stack] = [
  outer_forloop,   # bottom
  inner_forloop    # top (current)
]
```

When creating a new forloop, the previous top becomes its `parentloop`.

## The `offset: continue` Feature

This feature allows resuming iteration from where a previous loop left off:

```liquid
{% for i in items limit:3 %}{{ i }}{% endfor %}
next:
{% for i in items offset:continue limit:3 %}{{ i }}{% endfor %}
next:
{% for i in items offset:continue limit:3 %}{{ i }}{% endfor %}
```
Given `items = [1,2,3,4,5,6,7,8,9,0]`, outputs: `123 next: 456 next: 789`

### How offset:continue Works

Position is tracked in `registers[:for]` using the loop's **name** as key:

```
registers[:for] = {
  "i-items" => 3,    # "variable_name-collection_expression"
  "j-other" => 5,
  # ...
}
```

The loop name is constructed as `"#{variable_name}-#{collection_expression}"`.

## Pseudocode Implementation

### Data Structures

```
ForTag:
  variable_name: String           # e.g., "item"
  collection_expr: Expression     # e.g., VariableLookup("items")
  limit_expr: Expression | nil
  offset_expr: Expression | :continue | nil
  reversed: Boolean
  body: BlockBody
  else_body: BlockBody | nil
  name: String                    # "variable_name-collection_expression"

ForloopDrop:
  name: String
  length: Integer
  parentloop: ForloopDrop | nil
  index: Integer  # 0-based internal counter
```

### Rendering

```
function render_for(tag, state, output):
  # Get the collection
  collection = state.evaluate(tag.collection_expr)
  if collection is Range:
    collection = collection.to_array()
  
  # Calculate slice bounds
  (from, to) = calculate_bounds(tag, state)
  
  # Slice the collection
  segment = slice_collection(collection, from, to)
  if tag.reversed:
    segment = segment.reverse()
  
  # Update continue offset for next time
  offsets = state.registers[:for] ||= {}
  offsets[tag.name] = from + segment.length
  
  # Handle empty collection
  if segment.empty():
    if tag.else_body:
      render_block(tag.else_body, state, output)
    return
  
  # Get forloop stack for parentloop tracking
  for_stack = state.registers[:for_stack] ||= []
  
  # Create forloop drop
  parent = for_stack.last()  # nil if not nested
  forloop = ForloopDrop(tag.name, segment.length, parent)
  for_stack.push(forloop)
  
  try:
    # Push a new scope for loop variables
    with_scope(state):
      state.variables["forloop"] = forloop
      
      for item in segment:
        state.variables[tag.variable_name] = item
        
        render_block(tag.body, state, output)
        forloop.increment()
        
        # Handle interrupts
        if state.interrupts.not_empty():
          interrupt = state.interrupts.pop()
          if interrupt.type == :break:
            break
          # :continue just proceeds to next iteration
  finally:
    for_stack.pop()

function calculate_bounds(tag, state):
  offsets = state.registers[:for] ||= {}
  
  # Calculate 'from'
  if tag.offset_expr == :continue:
    from = offsets[tag.name] || 0
  else if tag.offset_expr:
    from = to_integer(state.evaluate(tag.offset_expr))
  else:
    from = 0
  
  # Calculate 'to'
  if tag.limit_expr:
    limit = to_integer(state.evaluate(tag.limit_expr))
    to = from + limit
  else:
    to = nil  # no limit
  
  return (from, to)

function slice_collection(collection, from, to):
  # If collection supports lazy loading, use it
  if collection.responds_to(:load_slice):
    return collection.load_slice(from, to)
  
  # Otherwise, slice normally
  if to == nil:
    return collection[from..]
  else:
    return collection[from...to]
```

### ForloopDrop

```
class ForloopDrop:
  def initialize(name, length, parentloop):
    @name = name
    @length = length
    @parentloop = parentloop
    @index = 0  # internal 0-based
  
  def index():  return @index + 1      # 1-based
  def index0(): return @index          # 0-based
  def rindex(): return @length - @index
  def rindex0(): return @length - @index - 1
  def first():  return @index == 0
  def last():   return @index == @length - 1
  def length(): return @length
  def parentloop(): return @parentloop
  
  def increment():
    @index += 1
```

## Behavioral Specifications

### Basic Iteration

```liquid
{% for i in (1..3) %}{{ i }}{% endfor %}
```
Output: `123`

### With Limit and Offset

```liquid
{% for i in (1..10) limit:3 offset:2 %}{{ i }}{% endfor %}
```
Output: `345` (skip 1,2, take 3 items)

### Reversed

```liquid
{% for i in (1..3) reversed %}{{ i }}{% endfor %}
```
Output: `321`

### The else Block

```liquid
{% for item in empty_array %}
  {{ item }}
{% else %}
  No items!
{% endfor %}
```
Output: `No items!`

### offset:continue Across Loops

```liquid
{% for i in items limit:2 %}{{ i }}{% endfor %}
|{% for i in items offset:continue limit:2 %}{{ i }}{% endfor %}
|{% for i in items offset:continue %}{{ i }}{% endfor %}
```
Given `items = [1,2,3,4,5]`, outputs: `12|34|5`

### offset:continue with Different Collections

The continue position is keyed by `"variable-collection"`, so different collections have independent positions:

```liquid
{% for i in a limit:2 %}{{ i }}{% endfor %}
{% for i in b limit:2 %}{{ i }}{% endfor %}
{% for i in a offset:continue %}{{ i }}{% endfor %}
```
Given `a = [1,2,3,4]`, `b = [x,y,z]`, outputs: `12 xy 34`

### parentloop Access

```liquid
{% for i in (1..2) %}
  {% for j in (1..3) %}
    {{ forloop.parentloop.index }}-{{ forloop.index }}
  {% endfor %}
{% endfor %}
```
Output: `1-1 1-2 1-3 2-1 2-2 2-3`

### parentloop is nil at Top Level

```liquid
{% for i in (1..2) %}
  {{ forloop.parentloop.index }}-{{ forloop.index }}
{% endfor %}
```
Output: `-1 -2` (parentloop is nil, `.index` returns nil/empty)

### forloop.length Reflects Limit

```liquid
{% for i in (1..10) limit:3 %}{{ forloop.length }}{% endfor %}
```
Output: `333` (length is 3, not 10)

### Interrupted Loops Clean Up

If an error occurs mid-loop, the for_stack must still be cleaned up:

```
try:
  for item in segment:
    # ... render body ...
finally:
  for_stack.pop()  # MUST happen even on error
```

## Interaction with Other Tags

### break and continue

See [interrupts.md](interrupts.md). The for loop consumes interrupts after each iteration.

### render Tag

The `render` tag creates an isolated context with fresh registers, so:
- `offset:continue` position is not shared
- `forloop.parentloop` is nil (no access to outer loop)

### include Tag

The `include` tag shares registers, so:
- `offset:continue` position IS shared
- But there's a quirk: `include` with `for` does NOT provide `forloop`

```liquid
{% include 'item' for items %}
{# Inside item.liquid, there is NO forloop object #}
```

Compare to `render`:

```liquid
{% render 'item' for items %}
{# Inside item.liquid, forloop IS available #}
```

## Implementation Checklist

1. **Collection slicing:** Support `limit`, `offset`, and `offset:continue`
2. **Continue tracking:** Store position in `registers[:for][loop_name]`
3. **ForloopDrop:** All index/rindex/first/last properties
4. **parentloop stack:** Track in `registers[:for_stack]`
5. **Stack cleanup:** Always pop for_stack, even on error/interrupt
6. **else block:** Render when collection is empty/nil
7. **Range support:** Convert Range to array before iteration
8. **load_slice support:** For paginated collections

## Common Pitfalls

1. **Forgetting stack cleanup:** Must pop for_stack in finally block
2. **Wrong loop name:** Must use consistent `"var-collection"` format for continue
3. **Length calculation:** `forloop.length` is segment length, not collection length
4. **Parentloop nil:** Don't crash when accessing parentloop at top level
5. **Continue across renders:** Position doesn't persist across `render` boundaries
6. **Include vs render forloop:** `include for` has no forloop, `render for` does
