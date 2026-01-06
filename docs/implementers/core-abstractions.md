---
title: Core Abstractions
description: >
  The five foundational functions every Liquid implementation needs: to_output, to_iterable,
  is_empty, is_blank, and scope management. Implement these correctly and you're 90% done.
  This is the most important document for new implementers - read it first.
optional: false
order: 1
---

# Core Abstractions

If you implement these five abstractions correctly, you're 90% of the way to a working Liquid implementation. Everything else—individual tags, filters, operators—builds on top of these foundations.

## The Key Insight

Liquid has many "weird" type coercion rules. The trick is to **centralize all the weirdness** into a few core functions. Once these handle all the edge cases, everything else becomes simple.

Consider a range like `(1..5)`:
- `to_output((1..5))` → `"1..5"` (string representation)
- `to_iterable((1..5))` → `[1, 2, 3, 4, 5]` (expanded for iteration)

Same value, completely different behavior depending on context. By handling this in ONE place, your `{{ }}` output tag and `{% for %}` tag don't need to know anything about ranges—they just call the appropriate abstraction.

## The Five Foundations

1. **`to_output(value)`** - Convert any value to output string
2. **`to_iterable(value)`** - Convert any value to something enumerable
3. **`is_empty(value)`** - Check if a value equals `empty`
4. **`is_blank(value)`** - Check if a value equals `blank`
5. **Scope stack** - Variable lookup with proper scoping

Plus the **for loop state machine** that ties it all together.

---

## 1. to_output(value)

When rendering `{{ value }}`, convert any value to a string for output.

### The Rules

| Input | Output |
|-------|--------|
| `nil` | `""` (empty string, not "nil") |
| `true` | `"true"` |
| `false` | `"false"` |
| Integer `42` | `"42"` |
| Float `3.14` | `"3.14"` |
| String `"hello"` | `"hello"` |
| Range `(1..5)` | `"1..5"` (NOT expanded) |
| Array `[a, b, c]` | Recursive: `to_output(a) + to_output(b) + to_output(c)` |
| Object/Hash | Implementation-defined (rarely output directly) |

### Critical: Arrays Are Recursive

```liquid
{% assign items = "a,b,c" | split: "," %}
{{ items }}
```
Output: `abc` (not `["a", "b", "c"]`)

### Critical: Ranges Are NOT Expanded

```liquid
{{ (1..5) }}
```
Output: `1..5` (not `12345`)

### Pseudocode

```
function to_output(value):
    if value is nil:
        return ""
    if value is boolean true:
        return "true"
    if value is boolean false:
        return "false"
    if value is integer:
        return integer_to_string(value)
    if value is float:
        return float_to_string(value)
    if value is string:
        return value
    if value is range(start, end):
        return to_output(start) + ".." + to_output(end)
    if value is array:
        result = ""
        for item in value:
            result = result + to_output(item)
        return result
    if value is hash:
        return hash_to_debug_string(value)  // rarely used
    // For custom objects, call their string representation
    return value.to_string()
```

---

## 2. to_iterable(value)

The `{% for %}` tag needs to iterate over collections. Convert any value to something enumerable.

### The Rules

| Input | Iterable Result |
|-------|-----------------|
| Array `[1, 2, 3]` | `[1, 2, 3]` |
| Range `(1..3)` | `[1, 2, 3]` (EXPANDED) |
| Hash/Object | Array of key-value pairs |
| String `"hello"` | `["hello"]` (ONE item, the whole string) |
| `nil` | `[]` (empty, no iterations) |
| Number `42` | `[]` (empty, no iterations) |
| Boolean | `[]` (empty, no iterations) |

### Critical: Strings Are Atomic

```liquid
{% for char in "hello" %}{{ char }}{% endfor %}
```
Output: `hello` (ONE iteration with the whole string)

### Critical: Ranges ARE Expanded

```liquid
{% for i in (1..3) %}{{ i }}{% endfor %}
```
Output: `123` (three iterations: 1, 2, 3)

### The Duality

| Value | to_output | to_iterable |
|-------|-----------|-------------|
| `(1..5)` | `"1..5"` | `[1, 2, 3, 4, 5]` |
| `"hello"` | `"hello"` | `["hello"]` |
| `[a, b]` | `"ab"` | `[a, b]` |
| `nil` | `""` | `[]` |

### Pseudocode

```
function to_iterable(value):
    if value is nil:
        return []
    if value is boolean:
        return []
    if value is integer:
        return []
    if value is float:
        return []
    if value is string:
        if length(value) == 0:
            return []
        return [value]  // Single-element array containing the string
    if value is range(start, end):
        result = []
        i = start
        while i <= end:
            result.append(i)
            i = i + 1
        return result
    if value is array:
        return value
    if value is hash:
        result = []
        for key, val in value:
            result.append([key, val])
        return result
    // Unknown type
    return []
```

---

## 3. is_empty(value)

The `empty` keyword checks if a collection has zero elements.

### The Rules

| Input | `== empty` |
|-------|------------|
| `nil` | `false` |
| `true` | `false` |
| `false` | `false` |
| Integer `0` | `false` |
| Integer `42` | `false` |
| Float `0.0` | `false` |
| String `""` | `true` |
| String `"hello"` | `false` |
| String `"   "` | `false` (has characters) |
| Array `[]` | `true` |
| Array `[1, 2]` | `false` |
| Hash `{}` | `true` |
| Hash `{a: 1}` | `false` |
| Range | `false` (ranges are never empty) |

### Critical: nil Is NOT Empty

```liquid
{% if missing == empty %}yes{% else %}no{% endif %}
```
Output: `no`

### Pseudocode

```
function is_empty(value):
    if value is nil:
        return false
    if value is boolean:
        return false
    if value is integer:
        return false
    if value is float:
        return false
    if value is string:
        return length(value) == 0
    if value is array:
        return length(value) == 0
    if value is hash:
        return size(value) == 0
    if value is range:
        return false
    // Unknown type - not empty
    return false
```

---

## 4. is_blank(value)

The `blank` keyword is more permissive. It includes nil, false, and whitespace-only strings.

### The Rules

| Input | `== blank` |
|-------|------------|
| `nil` | `true` |
| `true` | `false` |
| `false` | `true` |
| Integer `0` | `false` |
| Integer `42` | `false` |
| Float `0.0` | `false` |
| String `""` | `true` |
| String `"hello"` | `false` |
| String `"   "` | `true` (whitespace only) |
| String `"\n\t"` | `true` (whitespace only) |
| Array `[]` | `true` |
| Array `[1, 2]` | `false` |
| Hash `{}` | `true` |
| Hash `{a: 1}` | `false` |
| Range | `false` |

### The Hierarchy

**blank = empty + nil + false + whitespace**

```
blank includes:
  ├── nil
  ├── false
  ├── empty string ""
  ├── whitespace-only strings
  ├── empty arrays []
  └── empty hashes {}

blank excludes:
  ├── true
  ├── any number (including 0)
  ├── non-empty strings with content
  └── non-empty collections
```

### Pseudocode

```
function is_blank(value):
    if value is nil:
        return true
    if value is boolean true:
        return false
    if value is boolean false:
        return true
    if value is integer:
        return false
    if value is float:
        return false
    if value is string:
        if length(value) == 0:
            return true
        // Check if all characters are whitespace
        for char in value:
            if char is not whitespace:
                return false
        return true
    if value is array:
        return length(value) == 0
    if value is hash:
        return size(value) == 0
    if value is range:
        return false
    // Unknown type - not blank
    return false
```

---

## 5. Scope Stack

Liquid uses a stack of scopes for variable lookup.

### The Structure

```
┌─────────────────────────────────┐
│ Scope 2 (for loop)              │  ← Top (searched first)
│   item = "apple"                │
│   forloop = {...}               │
├─────────────────────────────────┤
│ Scope 1 (include)               │
│   title = "Products"            │
├─────────────────────────────────┤
│ Scope 0 (root environment)      │  ← Bottom (searched last)
│   products = [...]              │
└─────────────────────────────────┘
```

### Lookup Rules

1. Search from top of stack (current scope) downward
2. First match wins
3. If not found anywhere, return `nil`

### Assignment Rules

- **`{% assign x = value %}`** - Assigns to current (top) scope
- **`{% capture x %}`** - Assigns to current (top) scope
- **`{% for %}`** - Pushes a new scope, pops when done

### Pseudocode

```
Context:
    scopes = [root_environment]  // Stack of dictionaries

    function push_scope(scope):
        scopes.push_front(scope)

    function pop_scope():
        scopes.pop_front()

    function lookup(key):
        for scope in scopes:  // Top to bottom
            if key in scope:
                return scope[key]
        return nil

    function assign(key, value):
        scopes[0][key] = value  // Always top scope
```

---

## 6. For Loop State Machine

The for loop brings everything together.

### The Flow

```
1. Evaluate collection expression
2. Convert: items = to_iterable(collection)
3. Push new scope
4. Create forloop object

   ┌─────────────────────────────────┐
   │  FOR EACH item IN items:        │
   │    a. Set loop variable         │
   │    b. Render body               │
   │    c. Increment forloop         │
   │    d. Check interrupts:         │
   │       - break → exit loop       │
   │       - continue → next item    │
   └─────────────────────────────────┘

5. Pop scope
```

### The forloop Object

| Property | Description | Example (3 items, on 2nd) |
|----------|-------------|---------------------------|
| `index` | 1-based position | `2` |
| `index0` | 0-based position | `1` |
| `rindex` | 1-based from end | `2` |
| `rindex0` | 0-based from end | `1` |
| `first` | Is first? | `false` |
| `last` | Is last? | `false` |
| `length` | Total items | `3` |
| `parentloop` | Outer loop's forloop | `nil` or `{...}` |

### Break and Continue

Use an interrupt mechanism:

```
// break tag
push_interrupt(BREAK)

// continue tag
push_interrupt(CONTINUE)

// for loop, after rendering body
if has_interrupt():
    interrupt = pop_interrupt()
    if interrupt is BREAK:
        exit loop
    if interrupt is CONTINUE:
        skip to next iteration
```

---

## The Architecture

Here's why this works:

```
┌─────────────────────────────────────────────────────────┐
│                    YOUR LIQUID IMPLEMENTATION           │
├─────────────────────────────────────────────────────────┤
│                                                         │
│   Tags call these:          Abstractions handle all     │
│                             type weirdness:             │
│   {{ value }}        →      to_output(value)            │
│   {% for x in y %}   →      to_iterable(y)              │
│   {% if x == empty %}→      is_empty(x)                 │
│   {% if x == blank %}→      is_blank(x)                 │
│   {% assign x = y %} →      scope.assign(x, y)          │
│                                                         │
├─────────────────────────────────────────────────────────┤
│                                                         │
│   Tags are now trivial:                                 │
│                                                         │
│   {{ x }}           = output(to_output(lookup(x)))      │
│   {% for %}         = iterate(to_iterable(expr))        │
│   {% if %}          = branch on truthiness              │
│   {% assign %}      = scope.assign(name, eval(expr))    │
│   {% capture %}     = scope.assign(name, rendered_body) │
│                                                         │
└─────────────────────────────────────────────────────────┘
```

All the complex type coercion rules live in five functions. Everything else just calls them.

---

## Common Mistakes

| Mistake | Correct Behavior |
|---------|------------------|
| `nil == empty` returns true | `false` - nil is NOT empty |
| `{% for c in "hi" %}` iterates `h`, `i` | One iteration: `"hi"` |
| `{{ (1..3) }}` outputs `123` | `1..3` (string repr) |
| `{{ [a,b,c] }}` outputs `[a,b,c]` | `abc` (concatenated) |
| `"   " == empty` returns true | `false` - has characters |
| `"   " == blank` returns false | `true` - only whitespace |
| `0 == blank` returns true | `false` - numbers aren't blank |

---

## Testing Your Implementation

Use liquid-spec to verify:

```bash
# Test output conversion
liquid-spec my_adapter.rb -n literal_
liquid-spec my_adapter.rb -n range

# Test iteration
liquid-spec my_adapter.rb -n for_

# Test empty/blank
liquid-spec my_adapter.rb -n empty
liquid-spec my_adapter.rb -n blank

# Test scoping
liquid-spec my_adapter.rb -n scope
liquid-spec my_adapter.rb -n assign
```

See also:
- [For Loops](for-loops.md)
- [Scopes](scopes.md)
- [Interrupts](interrupts.md)
- [Partials](partials.md)
- [Cycle](cycle.md)
- [Parsing](parsing.md)
