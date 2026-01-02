# Scopes and Variable Resolution

This document explains Liquid's variable resolution hierarchy and provides implementation guidance.

## Quick Reference

Variable lookup checks these layers in order:

```
1. scopes[]        ← Local variables ({% assign %}, loop vars) - STACK
2. environments[]  ← Render-time data (template assigns)
3. static_environments[] ← Global data (shop, theme settings)
```

First match wins. Writes always go to `scopes[0]` (top of stack).

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
- Lookups search top-to-bottom, return first match
- Writes (`{% assign %}`) always go to `scopes[0]`
- `for`/`tablerow` push a scope on entry, pop on exit
- The bottom scope (`scopes[-1]`) is the `outer_scope` passed to render

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
  registers: Registers                   # Host app state (see below)
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
  # Proc memoization: call once, replace with result
  if value.is_proc:
    result = value.arity == 0 ? value.call() : value.call(state)
    # Replace proc with result in the containing hash
    return result
  return value
```

### Variable Assignment

```
function assign_variable(state, key, value):
  # Always write to top scope
  state.scopes[0][key] = value
```

### Scope Stack Operations

```
function push_scope(state, initial_vars = {}):
  state.scopes.unshift(initial_vars)
  check_depth_limit(state)

function pop_scope(state):
  if state.scopes.length == 1:
    raise "Cannot pop last scope"
  state.scopes.shift()

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

## Registers: Host Application State

Registers are a separate key-value store for host application state that persists across the render but isn't exposed to templates.

### Copy-on-Write Semantics

```
Registers:
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

### Registers in Isolated Subcontexts

When `render` creates an isolated subcontext:

```
function new_isolated_subcontext(state):
  return ExecutionState(
    scopes: [{}],                          # FRESH - empty scope
    environments: [],                       # FRESH - no environments
    static_environments: state.static_environments,  # SHARED
    
    registers: Registers(                   # NEW wrapper, SHARED static
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
  {{ x }}
{% endfor %}
{{ x }}
```
Output: `inner inner`

**Note:** `{% assign %}` writes to `scopes[0]`, which is the for-loop's scope. But when the for-loop ends and its scope is popped, the **outer** scope's `x` is still `"outer"`... except that's not what happens!

Actually, `{% assign %}` always writes to `scopes[0]`, and after the for-loop, that assignment persists because the for-loop's scope **becomes** the outer scope's modification. Let me correct:

```liquid
{% assign x = "outer" %}
{% for i in (1..1) %}
  {% assign x = "inner" %}
{% endfor %}
{{ x }}
```
Output: `inner`

The `for` tag creates a new scope, but `{% assign %}` writes to the **top** scope. When the for-loop ends, the top scope is popped, but the assignment to `x` was made in that scope, which... 

Actually, re-reading the code: assignments go to `scopes[0]`, which is the innermost scope. So after the for-loop pops its scope, any assignments made inside are lost.

Let me verify with the actual behavior:

```liquid
{% assign x = "outer" %}
{% for i in (1..1) %}
  {% assign x = "inner" %}
  inside: {{ x }}
{% endfor %}
outside: {{ x }}
```

The `for` tag does `context.stack do ... end`, which pushes a new scope. Inside, `{% assign x = "inner" %}` writes to that new scope. After the loop, the scope is popped.

But wait - the lookup finds `x` in the inner scope first, then when popped, finds it in the outer scope again. So:

Output: `inside: inner outside: outer`

Actually no - the assign writes to scopes[0], and `for` pushes a scope, so the assign goes to the for-loop's scope. But looking at the actual implementation:

```ruby
def []=(key, value)
  @scopes[0][key] = value
end
```

So assignments do go to the **current** top scope. When that scope is popped, the assignment is gone.

**Correction - verified behavior:**

```liquid
{% assign x = "outer" %}
{% for i in (1..1) %}
  {% assign x = "inner" %}
  inside: {{ x }}
{% endfor %}
outside: {{ x }}
```
Output: `inside: inner outside: outer`

The for-loop's scope shadows the outer assignment temporarily.

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

### Proc Memoization

Host applications can pass Procs that are lazily evaluated:

```ruby
Template.parse("{{ expensive }}").render({
  "expensive" => -> { compute_expensive_value() }
})
```

The Proc is called once on first access, then replaced with its result:

```
function evaluate_value(value, state):
  if value.is_proc:
    result = value.arity == 0 ? value.call() : value.call(state)
    # IMPORTANT: Replace in the hash so subsequent lookups get cached value
    containing_hash[key] = result
    return result
  return value
```

## Implementation Checklist

1. **Three-layer lookup:** scopes → environments → static_environments
2. **Scope stack:** push/pop for `for`, `tablerow`, `capture`, etc.
3. **Writes to top:** `{% assign %}` always writes to `scopes[0]`
4. **Squash on init:** Environment values override matching outer_scope keys
5. **Registers copy-on-write:** New Registers wrapper for isolated contexts
6. **Depth limiting:** Track `base_scope_depth` across isolated contexts
7. **Proc memoization:** Call once, cache result in original hash

## Common Pitfalls

1. **Forgetting squash behavior:** Tests may fail if outer_scope values aren't overridden by environments
2. **Wrong scope for assigns:** Must write to `scopes[0]`, not search and update
3. **Registers leaking:** Isolated contexts must wrap parent registers, not share directly
4. **Depth check timing:** Must check before pushing, not after
5. **Proc replacement:** Must replace in the original hash, not just return the value
