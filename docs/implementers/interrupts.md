# Interrupts: `break` and `continue`

This document explains how Liquid's `break` and `continue` tags work and provides implementation guidance for new Liquid implementations.

## Quick Reference

| Tag | Effect | Scope |
|-----|--------|-------|
| `break` | Exit the innermost loop immediately | Propagates through blocks until consumed by a loop |
| `continue` | Skip to the next iteration | Propagates through blocks until consumed by a loop |

## Pseudocode Implementation

### Core Concept: The Interrupt Stack

Interrupts are **not** exceptions. They are signals pushed onto a stack that propagate upward through the render tree until a loop consumes them.

```
ExecutionState:
  interrupts: Stack<Interrupt>   # stack of pending interrupts
  # ... other fields ...

Interrupt:
  type: :break | :continue
```

### `break` and `continue` Tags

Both tags simply push an interrupt onto the stack:

```
function compile_break():
  return:
    """
    state.interrupts.push(Interrupt(:break))
    return  # stop rendering current block
    """

function compile_continue():
  return:
    """
    state.interrupts.push(Interrupt(:continue))
    return  # stop rendering current block
    """
```

### Block Body Rendering

Every block body must check for interrupts after each node:

```
function render_block_body(nodes, state, output):
  for node in nodes:
    render_node(node, state, output)
    
    # CRITICAL: Check for interrupts after each node
    if state.interrupts.not_empty():
      return  # stop rendering, let interrupt propagate up
  
  return output
```

This is what allows interrupts to "bubble up" through nested structures.

### Loop Tags (`for`, `tablerow`)

Loops are the **consumers** of interrupts. They pop and handle interrupts after each iteration:

```
function compile_for(var_name, collection_expr, body):
  return:
    """
    collection = evaluate(collection_expr)
    forloop = ForloopDrop(collection.length)
    
    for item in collection:
      state.variables[var_name] = item
      state.variables["forloop"] = forloop
      
      render_block_body(body, state, output)
      forloop.increment()
      
      # CONSUME interrupts here
      if state.interrupts.not_empty():
        interrupt = state.interrupts.pop()
        
        if interrupt.type == :break:
          break  # exit the loop entirely
        
        if interrupt.type == :continue:
          next   # skip to next iteration (interrupt is consumed)
    """
```

### Key Implementation Rules

1. **Interrupts propagate until consumed:**
   - Block bodies check `interrupts.not_empty()` and return early
   - Only loop tags (`for`, `tablerow`) pop and consume interrupts

2. **Block bodies must always check:**
   - After rendering each node, check for pending interrupts
   - If an interrupt exists, stop rendering and return immediately

3. **Loops consume exactly one interrupt per check:**
   - Pop the interrupt from the stack
   - Handle it (break or continue)
   - Don't propagate further

4. **Interrupts outside loops are harmless:**
   - If `break` or `continue` is used outside any loop, it simply stops rendering the current block
   - No error is raised

## Behavioral Specifications

### Basic Usage

```liquid
{% for i in (1..5) %}
  {% if i == 3 %}
    {% break %}
  {% endif %}
  {{ i }}
{% endfor %}
```
Output: `1 2` (loop exits when i reaches 3)

```liquid
{% for i in (1..5) %}
  {% if i == 3 %}
    {% continue %}
  {% endif %}
  {{ i }}
{% endfor %}
```
Output: `1 2 4 5` (3 is skipped)

### Propagation Through Nested Blocks

Interrupts propagate through `if`, `case`, `unless`, and other non-loop blocks:

```liquid
{% for item in items %}
  {% if item.featured %}
    {% if item.sold_out %}
      {% break %}
    {% endif %}
    {{ item.name }}
  {% endif %}
{% endfor %}
```

The `break` inside the nested `if` blocks propagates up and breaks out of the `for` loop.

### Nested Loops

Each loop handles interrupts independently. An interrupt only affects the innermost loop:

```liquid
{% for i in (1..3) %}
  {% for j in (1..3) %}
    {% if j == 2 %}{% break %}{% endif %}
    {{ i }}-{{ j }}
  {% endfor %}
{% endfor %}
```
Output: `1-1 2-1 3-1` (inner loop breaks at j=2, outer loop continues)

To break out of an outer loop, you need additional logic:

```liquid
{% assign done = false %}
{% for i in (1..3) %}
  {% unless done %}
    {% for j in (1..3) %}
      {% if some_condition %}
        {% assign done = true %}
        {% break %}
      {% endif %}
    {% endfor %}
    {% if done %}{% break %}{% endif %}
  {% endunless %}
{% endfor %}
```

### `tablerow` Tag

The `tablerow` tag also consumes interrupts:

```liquid
<table>
{% tablerow item in items cols:3 %}
  {% if item.skip %}{% continue %}{% endif %}
  {% if item.stop %}{% break %}{% endif %}
  {{ item.name }}
{% endtablerow %}
</table>
```

Note: `tablerow` handles `break` but typically ignores `continue` in terms of table structure (the cell is still rendered, just empty).

### Outside Loops

Using `break` or `continue` outside a loop simply stops rendering the current block:

```liquid
before{% break %}after
```
Output: `before` (no error, "after" is not rendered)

```liquid
{% continue %}hello
```
Output: `` (empty, no error)

This behavior exists for pragmatic reasons - it allows partials containing `break` to work correctly whether or not they're inside a loop.

### Interaction with `include`

With `include`, interrupts **propagate** to the caller because they share the same execution state:

```liquid
{% for i in (1..3) %}
  {{ i }}
  {% include 'maybe_break' %}
{% endfor %}

{%- # maybe_break.liquid contains: -%}
{% if some_condition %}{% break %}{% endif %}
```

If `some_condition` is true, the `break` propagates and breaks the outer loop.

### Interaction with `render`

With `render`, interrupts are **contained** because `render` creates an isolated execution state with its own interrupt stack:

```liquid
{% for i in (1..3) %}
  {{ i }}
  {% render 'maybe_break' %}
{% endfor %}

{%- # maybe_break.liquid contains: -%}
{% break %}
```

Output: `1 2 3` (the `break` in the partial doesn't affect the outer loop)

The inner `break`:
1. Pushes to the **inner** state's interrupt stack
2. Inner state is discarded when `render` returns
3. Outer loop never sees the interrupt

## Compiled Output Examples

### Simple Break

```liquid
{% for item in items %}
  {% if item.stop %}{% break %}{% endif %}
  {{ item.name }}
{% endfor %}
```

Compiles conceptually to:

```ruby
items.each do |item|
  state.variables["item"] = item
  
  # {% if item.stop %}
  if state.evaluate(item_stop_expr)
    # {% break %}
    state.interrupts.push(:break)
    # block body returns early due to interrupt
  end
  
  # Check interrupt before continuing
  break if state.interrupts.pop_if(:break)
  
  # {{ item.name }}
  output << state.evaluate(item_name_expr)
end
```

### Nested Structure

```liquid
{% for i in outer %}
  {% for j in inner %}
    {% if done %}{% break %}{% endif %}
    {{ j }}
  {% endfor %}
  still in outer
{% endfor %}
```

Compiles conceptually to:

```ruby
outer.each do |i|
  state.variables["i"] = i
  
  # Inner for loop
  inner.each do |j|
    state.variables["j"] = j
    
    if state.evaluate(done_expr)
      state.interrupts.push(:break)
      break  # exit inner block body
    end
    
    break if state.interrupts.pop_if(:break)  # consume break, exit inner loop
    
    output << j
  end
  # After inner loop, interrupt has been consumed
  
  # Check for any propagating interrupt (there isn't one)
  break if state.interrupts.not_empty?
  
  output << "still in outer"
end
```

## Implementation Checklist

1. **Interrupt stack in execution state:**
   - Simple stack (array) of interrupt types
   - Methods: `push(type)`, `pop()`, `not_empty?`

2. **`break` tag:**
   - Push `:break` interrupt
   - Return from current render method

3. **`continue` tag:**
   - Push `:continue` interrupt
   - Return from current render method

4. **Block body rendering:**
   - After each node, check `interrupts.not_empty?`
   - If true, return immediately (don't render remaining nodes)

5. **`for` tag:**
   - After each iteration body renders, check for interrupt
   - Pop and handle: `:break` exits loop, `:continue` goes to next iteration

6. **`tablerow` tag:**
   - Same interrupt handling as `for`
   - Must still output table structure even when breaking

7. **`render` tag:**
   - Creates fresh interrupt stack for inner state
   - Inner interrupts don't propagate to outer

8. **`include` tag:**
   - Uses same state, so interrupts propagate

## Common Pitfalls

1. **Forgetting to check interrupts in block bodies:**
   - Without this check, `break` inside an `if` won't propagate to the loop

2. **Not consuming interrupts in loops:**
   - If you only check but don't pop, the interrupt will be seen again

3. **Propagating consumed interrupts:**
   - After a loop handles an interrupt, it should be gone from the stack

4. **Raising errors for interrupts outside loops:**
   - Liquid intentionally allows this - it's not an error

## Summary

| Component | Responsibility |
|-----------|---------------|
| `break`/`continue` tags | Push interrupt onto stack, stop current block |
| Block body | Check for interrupts after each node, return early if present |
| `for`/`tablerow` | Pop and consume interrupts, break or continue accordingly |
| `render` | Isolate interrupt stack (fresh stack for partial) |
| `include` | Share interrupt stack (interrupts propagate) |

The key insight: **interrupts are a simple stack-based signaling mechanism, not exceptions**. They propagate by block bodies returning early, and are consumed by loop constructs.
