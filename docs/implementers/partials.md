---
title: "Partials: include vs render"
description: >
  The critical differences between include (deprecated, shares scope, propagates interrupts) and
  render (recommended, isolated scope, contained interrupts). Understanding these differences is
  essential for correct partial template handling.
optional: false
order: 5
---

# Partials: `include` vs `render`

This document explains the differences between Liquid's two partial rendering tags and provides implementation guidance for new Liquid implementations.

## Quick Reference

| Feature | `include` | `render` |
|---------|-----------|----------|
| Variable scope | Outer visible, local assigns | Isolated (outer assigns hidden) |
| Template name | Dynamic (variable) | Static (string literal) |
| `break`/`continue` | Propagate to caller | Contained within partial |
| Nested `include` | Allowed | **Disallowed** |
| `forloop` access | None | Provided for `for` variant |
| `assign` side effects | Local to include | Local to render |
| `increment`/`decrement` | Shared counters | Isolated counters |
| Status | **Deprecated** | Recommended |

## Pseudocode Implementation

Both `include` and `render` can be compiled to method/function calls. The key difference is what state gets passed to the partial.

### Shared State Structure

First, define what state exists in a Liquid execution context:

```
ExecutionState:
  # MUTABLE - changes during rendering
  variables: Map<String, Any>          # assigned variables (scopes stack)
  interrupts: Stack<Interrupt>         # break/continue signals
  counters: Map<String, Int>           # increment/decrement state
  
  # IMMUTABLE/SHARED - same across all partials
  static_env: Map<String, Any>         # global objects (shop, theme, etc.)
  registers: RegisterStore             # host application state (copy-on-write in render)
  resource_limits: ResourceLimits      # memory/time limits
  disabled_tags: Set<String>           # tags that cannot execute
  filters: List<FilterModule>          # available filters
  errors: List<Error>                  # error collection (append-only)
```

### `include` Implementation

`include` shares the execution state but pushes a new variable scope:

```
function compile_include(partial_name, with_expr, for_expr, alias, attributes):
  return:
    """
    # Resolve template name (can be dynamic)
    template_name = evaluate(partial_name)
    partial = load_partial(template_name)
    
    # Determine the binding variable name
    var_name = alias ?? basename(template_name)
    
    # Get the value to bind
    if for_expr:
      collection = evaluate(for_expr)
    else if with_expr:
      value = evaluate(with_expr)
    else:
      value = variables[template_name]  # auto-bind by name
    
    # Execute partial inside a new local scope
    with_scope(state):
      # Assign attributes to local scope
      for (key, expr) in attributes:
        variables[key] = evaluate(expr)
      
      if for_expr and is_iterable(collection):
        for item in collection:
          variables[var_name] = item
          call partial(state)  # SAME state object
          if interrupts.has_break():
            break  # propagates to caller's loop!
      else:
        variables[var_name] = value
        call partial(state)  # SAME state object
    """

# The partial receives:
#   - NEW local scope (outer variables readable, inner assignments don't escape)
#   - SAME interrupts (break/continue propagate up)
#   - SAME counters (increment/decrement shared)
#   - SAME everything else
```

### `render` Implementation

`render` creates **isolated** mutable state; shared state is copied or referenced (registers are copy-on-write):

```
function compile_render(partial_name, with_expr, for_expr, alias, attributes):
  # Template name MUST be a string literal (checked at parse time)
  assert partial_name.is_string_literal()
  
  return:
    """
    partial = load_partial(partial_name)  # known at compile time
    var_name = alias ?? basename(partial_name)
    
    # Get the value to bind (evaluate in OUTER context)
    if for_expr:
      collection = evaluate(for_expr)
      is_for_loop = true
    else if with_expr:
      value = evaluate(with_expr)
      is_for_loop = false
    else:
      value = nil
      is_for_loop = false
    
    # Evaluate attributes in OUTER context
    evaluated_attrs = {}
    for (key, expr) in attributes:
      evaluated_attrs[key] = evaluate(expr)
    
    # Create isolated state for partial
    function make_inner_state(forloop = nil):
      return ExecutionState(
        variables: {},                    # FRESH - empty scope
        interrupts: Stack(),              # FRESH - isolated interrupts
        counters: {},                     # FRESH - isolated counters
        
        static_env: state.static_env,     # SHARED
        registers: copy_on_write(state.registers),
        resource_limits: state.resource_limits,  # SHARED
        disabled_tags: state.disabled_tags + {"include"},  # SHARED + include disabled
        filters: state.filters,           # SHARED
        errors: state.errors,             # SHARED (append-only)
      )
    
    # Execute partial
    if is_for_loop and is_iterable(collection):
      forloop = ForloopDrop(partial_name, collection.count)
      for item in collection:
        inner = make_inner_state(forloop)
        inner.variables[var_name] = item
        inner.variables["forloop"] = forloop
        for (key, val) in evaluated_attrs:
          inner.variables[key] = val
        call partial(inner)
        forloop.increment()
        # NOTE: any break in partial is in inner.interrupts, discarded here
    else:
      inner = make_inner_state()
      if value != nil:
        inner.variables[var_name] = value
      for (key, val) in evaluated_attrs:
        inner.variables[key] = val
      call partial(inner)
    """

# The partial receives:
#   - FRESH variables (no leakage in or out)
#   - FRESH interrupts (break/continue contained)
#   - FRESH counters (isolated increment/decrement)
#   - SHARED static_env, COPY-ON-WRITE registers, limits, filters, errors
#   - MODIFIED disabled_tags (include is prohibited)
```

### Key Implementation Rules

1. **Variable isolation in `render`:**
   - Expressions are evaluated in the OUTER context
   - Results are assigned to the INNER context
   - The partial never sees the outer variables map

2. **Interrupt containment in `render`:**
   - Each `render` call gets a fresh interrupt stack
   - When the partial returns, its interrupt stack is discarded
   - The caller's loop never sees `break`/`continue` from the partial

3. **The `include` prohibition:**
   - When entering `render`, add "include" to `disabled_tags`
   - Before executing `include`, check if "include" is in `disabled_tags`
   - This must propagate through nested `render` calls (shared set)

4. **`forloop` in `render for`:**
   - Only `render` with `for` provides a `forloop` object
   - `include` with `for` does NOT provide `forloop`

### Compiled Output Example

For a template like:
```liquid
{% render 'product', title: item.name, price: item.price %}
```

The compiled output might look like:
```
# Assuming partial is pre-resolved to a callable
function render_product(inner_state):
  # ... partial body ...

# At call site:
inner = new_isolated_subcontext(state)
inner.variables["title"] = evaluate(item_name_expr, state)
inner.variables["price"] = evaluate(item_price_expr, state)
render_product(inner)
```

For `include`:
```liquid
{% include 'product', title: item.name %}
```

```
# At call site - same context, but a new local scope is pushed
with_scope(state):
  state.variables["title"] = evaluate(item_name_expr, state)
  state.variables["product"] = find_variable("product", state)
  include_product(state)  # same state, potential break propagation
```

## Behavioral Specifications

### Variable Scoping

**`include`: Outer Scope Visible, Local Assigns**

Variables assigned outside are visible inside:
```liquid
{% assign outer = "visible" %}
{% include 'snippet' %}
{%- # Inside snippet: {{ outer }} renders "visible" -%}
```

Variables assigned inside are NOT visible outside:
```liquid
{% include 'snippet' %}
{%- # snippet contains: {% assign inner = "leaked" %} -%}
{{ inner }}  {%- # Renders "" (empty) -%}
```

Automatic variable binding - if a variable exists with the same name as the partial:
```liquid
{% assign product = "My Product" %}
{% include 'product' %}
{%- # Inside product partial: {{ product }} renders "My Product" -%}
```

**`render`: Isolated Scope**

Variables assigned outside are NOT visible inside:
```liquid
{% assign outer = "not visible" %}
{% render 'snippet' %}
{%- # Inside snippet: {{ outer }} renders "" (empty) -%}
```

Variables assigned inside are NOT visible outside:
```liquid
{% render 'snippet' %}
{%- # snippet contains: {% assign inner = "contained" %} -%}
{{ inner }}  {%- # Renders "" (empty) -%}
```

Explicit parameter passing required:
```liquid
{% render 'product', title: product.title, price: product.price %}
```

### Control Flow: `break` and `continue`

**`include`: Interrupts Propagate**

A `break` inside an included partial will break the caller's loop:
```liquid
{% for i in (1..3) %}
  {{ i }}{% include 'break_partial' %}{{ i }}
{% endfor %}
{%- # break_partial contains: {% break %} -%}
{%- # Output: "1" (loop exits after first iteration) -%}
```

**Hard part to get right:** `include` must share the same interrupt stack as the caller. If you isolate interrupts here, `break` and `continue` will not reach the outer loop.

**`render`: Interrupts Are Contained**

A `break` inside a rendered partial has no effect on the caller:
```liquid
{% for i in (1..3) %}
  {{ i }}{% render 'break_partial' %}{{ i }}
{% endfor %}
{%- # break_partial contains: {% break %} -%}
{%- # Output: "112233" (all iterations complete) -%}
```

**Hard part to get right:** `render` must create a fresh interrupt stack per call. If you share interrupts, breaks will escape the partial and behave like `include`.

### Template Name Resolution

**`include`: Dynamic Names**
```liquid
{% assign template_name = 'product' %}
{% include template_name %}                    {%- # Works -%}
{% include product.template %}                 {%- # Works -%}
```

**`render`: Static Names Only**
```liquid
{% render 'product' %}                         {%- # Works -%}
{% assign template_name = 'product' %}
{% render template_name %}                     {%- # Syntax Error -%}
```

### The `with` and `for` Variants

**`with` - Single Value Binding**
```liquid
{% include 'product' with featured_product %}
{% render 'product' with featured_product %}
```
Both bind the value to a variable named after the partial (e.g., `product`).

**`for` - Iteration**
```liquid
{% include 'product' for products %}
{% render 'product' for products %}
```

| Aspect | `include for` | `render for` |
|--------|---------------|--------------|
| `forloop` available | No | Yes |
| `break` behavior | Propagates to caller | Contained |
| Scope per iteration | Same local scope | Fresh isolated scope |

Note on `break` behavior: In `include for`, a `break` propagates up through the caller's loop stack. If there's an outer `for` loop, it exits that loop. If there's no outer loop, it stops rendering the rest of the template. In `render for`, the break only affects loops within the partial itself.

**`as` - Alias**
```liquid
{% render 'card' with product as item %}
{% render 'card' for products as item %}
```
Binds to `item` instead of inferring from partial name.

### `increment`/`decrement` Counter Isolation

Counters are **isolated** in `render` but **shared** in `include`:
```liquid
{% increment %}{% increment %}{% render 'incr' %}
{%- # incr contains: {% increment %} -%}
{%- # Output: "010" (isolated counter starts at 0) -%}

{% increment %}{% increment %}{% include 'incr' %}
{%- # Output: "012" (shared counter continues) -%}
```

### The `include` Prohibition Inside `render`

Using `include` inside a rendered partial produces an error:
```liquid
{% render 'outer' %}
{%- # outer contains: {% include 'inner' %} -%}
{%- # Output: "Liquid error: include usage is not allowed in this context" -%}
```

This applies transitively through nested `render` calls.

## Summary

| Choose `render` when... | Choose `include` when... |
|------------------------|-------------------------|
| Building new templates | Maintaining legacy code |
| Security matters | N/A (avoid if possible) |
| Predictable behavior needed | Intentionally sharing scope |
| Performance is critical | N/A |
| Want static analysis | Need dynamic template names |

**The `include` tag is deprecated.** New code should always use `render`.

See also:
- [Scopes](scopes.md)
- [Interrupts](interrupts.md)
- [Core Abstractions](core-abstractions.md)
