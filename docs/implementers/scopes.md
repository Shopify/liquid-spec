---
title: "Scopes and Variable Resolution"
position: 4
description: "Read when variables, assign, capture, or partial visibility fail. Covers scope stacks, environments, registers, and lookup order."
optional: false
---

# Scopes and Variable Resolution

This document explains Liquid's variable resolution hierarchy and provides implementation guidance.

## Quick Reference

Variable lookup checks these layers in order:

```
1. scopes[]        ← Local variables ({% assign %}, loop vars) - STACK
2. environments[]  ← Render-time data (template assigns)
3. static_environments[] ← Global data (shop, theme settings)
```

First match wins. Do not use one generic write rule: loop-local bindings go to
`scopes[0]` (the top), while `{% assign %}` and `{% capture %}` deliberately write
to `scopes[-1]` (the persistent template scope).

## The Three Layers

### Layer 1: Scopes (Stack)

A stack of hash maps for local variables. Tags like `for`, `tablerow`, and `capture` push/pop scopes.

```
scopes = [
  { "item" => current_item, "forloop" => loop_drop },  ← top (most recent)
  { "temp" => "value" },                                ← pushed by outer for
  { "x" => 1, "y" => 2 }                                ← bottom (outer_scope from render)
]
```

**Key behaviors:**
- Lookups search top-to-bottom and return the first match.
- `for`/`tablerow` push a temporary top scope for their loop variable and loop drop,
  then pop it on exit.
- `{% assign %}` and `{% capture %}` write to the bottom scope (`scopes[-1]`), so
  their values survive a loop scope being popped.
- The bottom scope is the persistent `outer_scope` passed to render.
- A low-level context setter may still target `scopes[0]`; the reference uses that
  path for loop-local bindings. It is not the semantics of the `assign` tag.

### Layer 2: Environments

Render-time data passed by the host application. Typically template-specific variables.

```
environments = [
  { "product" => product_obj, "collection" => coll_obj }
]
```

**Key behaviors:**
- Searched after all scopes are exhausted
- Read-only during template execution
- Can be an array of hashes (searched in order)

### Layer 3: Static Environments

Global, immutable data shared across all renders. Things like shop settings, theme config.

```
static_environments = [
  { "shop" => shop_obj, "settings" => theme_settings }
]
```

**Key behaviors:**
- Searched last
- Shared across isolated subcontexts (`render` tag)
- Frozen after context creation

## Pseudocode Implementation

### Data Structures

```
ExecutionState:
  # Variable resolution (in lookup order)
  scopes: Stack<Map<String, Any>>       # Local variables
  environments: List<Map<String, Any>>  # Render-time data
  static_environments: List<Map<String, Any>>  # Global data
  
  # Other state
  registers: RegisterStore               # Host app state (see below)
  # ... interrupts, counters, etc.
```

### Variable Lookup

```
function find_variable(state, key):
  # 1. Search scopes (top to bottom)
  for scope in state.scopes:
    if scope.has_key(key):
      return evaluate_value(scope[key], state)
  
  # 2. Search environments
  for env in state.environments:
    value = evaluate_value(env[key], state)
    if value != nil:
      return value
  
  # 3. Search static_environments
  for env in state.static_environments:
    value = evaluate_value(env[key], state)
    if value != nil:
      return value
  
  # 4. Not found
  return nil

function evaluate_value(value, state):
  # Callable memoization: call once, replace with result
  if value.is_callable:
    result = value.call(state)  // call with state if supported
    # Replace callable with result in the containing hash
    containing_hash[key] = result
    return result
  return value
```

### Variable Writes

Keep persistent template assignment separate from temporary local binding:

```
function assign_tag_variable(state, key, value):
  # {% assign %} and {% capture %}: survives temporary loop scopes
  state.scopes[-1][key] = value

function set_local_variable(state, key, value):
  # for/tablerow variables and their loop metadata
  state.scopes[0][key] = value
```

Collapsing these operations into one setter is a common implementation bug. For
example, an assignment made inside `for` must remain visible after `endfor`, while
the loop variable itself must disappear.

### Scope Stack Operations

```
function push_scope(state, initial_vars = {}):
  state.scopes.push_front(initial_vars)
  check_depth_limit(state)

function pop_scope(state):
  if state.scopes.length == 1:
    raise "Cannot pop last scope"
  state.scopes.pop_front()

function with_scope(state, initial_vars = {}):
  push_scope(state, initial_vars)
  try:
    yield
  finally:
    pop_scope(state)
```

### The Squash Behavior

On context initialization, if the outer_scope has keys that also exist in environments, the environment values **replace** the outer_scope values:

```
function squash_instance_assigns(state):
  outer_scope = state.scopes[-1]  # bottom of stack
  
  for key in outer_scope.keys():
    for env in state.environments:
      if env.has_key(key):
        outer_scope[key] = evaluate_value(env[key], state)
        break  # first environment wins
```

**Why?** This allows host applications to pass default values in `outer_scope` that can be overridden by `environments`. The environments take precedence.

## Register Store: Host Application State

The register store is a separate key-value map for host application state that persists across the render but isn't exposed to templates.

### Copy-on-Write Semantics

```
RegisterStore:
  static: Map<String, Any>   # Original values (shared)
  changes: Map<String, Any>  # Local modifications

function registers_get(registers, key):
  if registers.changes.has_key(key):
    return registers.changes[key]
  return registers.static[key]

function registers_set(registers, key, value):
  registers.changes[key] = value  # Never modifies static
```

### Common Register Keys

| Key | Purpose |
|-----|---------|
| `:for` | Tracks `offset: continue` positions |
| `:for_stack` | Stack of `forloop` drops for `parentloop` |
| `:cycle` | Cycle tag counter state |
| `:cached_partials` | Partial template cache |
| `:file_system` | Template file system |
| `:template_factory` | Template factory |

### Register Store in Isolated Subcontexts

When `render` creates an isolated subcontext:

```
function new_isolated_subcontext(state):
  return ExecutionState(
    scopes: [{}],                          # FRESH - empty scope
    environments: [],                       # FRESH - no environments
    static_environments: state.static_environments,  # SHARED
    
    registers: RegisterStore(               # NEW wrapper, SHARED static
      static: state.registers,              # Parent's registers become static
      changes: {}                           # Fresh changes
    ),
    # ...
  )
```

This means:
- Reads can see parent's register values
- Writes don't affect parent's registers
- The partial cache is shared (via static)

## Depth Limiting

To prevent stack overflow from recursive templates:

```
MAX_DEPTH = 100

function check_depth_limit(state):
  total_depth = state.base_scope_depth + state.scopes.length
  if total_depth > MAX_DEPTH:
    raise StackLevelError("Nesting too deep")
```

`base_scope_depth` is incremented when creating isolated subcontexts, ensuring the limit applies across `render` boundaries.

## Behavioral Specifications

### Basic Variable Resolution

```liquid
{% assign x = "local" %}
{{ x }}
```
Output: `local` (found in scopes)

### Scope Shadowing

```liquid
{% assign x = "outer" %}
{% for i in (1..1) %}
  {% assign x = "inner" %}
  inside: {{ x }}
{% endfor %}
outside: {{ x }}
```
Output: `inside: inner outside: inner`

The `for` tag pushes a temporary scope for `i` and `forloop`, but `{% assign %}`
writes to the persistent bottom scope. The assignment therefore changes `x` for
the rest of the loop and remains visible after the loop. This asymmetry is
intentional reference behavior.

### Environment Override

If you pass `outer_scope: { "x" => 1 }` and `environments: { "x" => 2 }`:

```liquid
{{ x }}
```
Output: `2`

Because of the squash behavior - the environment value replaces the outer_scope value during initialization.

### Static Environments in Isolated Contexts

```liquid
{% assign shop_name = "modified" %}
{% render 'snippet' %}

{# snippet.liquid: #}
{{ shop.name }}
```

The `render` tag creates an isolated context:
- `scopes` is fresh (empty)
- `environments` is empty
- `static_environments` is **shared**

So `shop` (from static_environments) is still accessible, but `shop_name` (assigned in outer scope) is not.

### Lazy Value Memoization

Host applications can pass lazy values (callables) that are evaluated on first access:

```
render(template, {
  "expensive": () => compute_expensive_value()
})
```

The callable is invoked once on first access, then replaced with its result:

```
function evaluate_value(value, state):
  if value.is_callable:
    result = value.call(state)  // call with state if supported
    # IMPORTANT: Replace in the hash so subsequent lookups get cached value
    containing_hash[key] = result
    return result
  return value
```

## Implementation Checklist

1. **Three-layer lookup:** scopes → environments → static_environments
2. **Scope stack:** push/pop temporary scopes for `for` and `tablerow`; `capture`
   captures output but does not isolate assignments.
3. **Two write paths:** loop locals → `scopes[0]`; `assign`/`capture` → `scopes[-1]`.
4. **Squash on init:** Environment values override matching outer_scope keys
5. **Register store copy-on-write:** New wrapper for isolated contexts
6. **Depth limiting:** Track `base_scope_depth` across isolated contexts
7. **Callable memoization:** Call once, cache result in original hash

## Common Pitfalls

1. **Forgetting squash behavior:** Tests may fail if outer_scope values aren't overridden by environments
2. **Wrong scope for assigns:** `assign`/`capture` must write to the persistent
   bottom scope; only temporary loop bindings belong in the top scope.
3. **Register store leaking:** Isolated contexts must wrap parent registers, not share directly
4. **Depth check timing:** Must check before pushing, not after
5. **Callable replacement:** Must replace in the original hash, not just return the value

See also:
- [Core Abstractions](core-abstractions.md)
- [For Loops](for-loops.md)
- [Partials](partials.md)
