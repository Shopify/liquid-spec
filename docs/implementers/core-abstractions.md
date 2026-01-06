# Core Abstractions

If you implement these five abstractions correctly, you're 90% of the way to a working Liquid implementation. Everything else—individual tags, filters, operators—builds on top of these foundations.

## The Five Foundations

1. **`to_output(value)`** - Convert any value to output string
2. **`to_iterable(value)`** - Convert any value to something enumerable
3. **`is_empty(value)`** - Check if a value equals `empty`
4. **`is_blank(value)`** - Check if a value equals `blank`
5. **Scope stack** - Variable lookup with proper scoping

Plus the **for loop state machine** that ties it all together.

---

## 1. to_output(value)

When rendering `{{ value }}`, Liquid needs to convert any value to a string for output.

### Rules

| Input Type | Output |
|------------|--------|
| `nil` | `""` (empty string, not "nil") |
| `true` | `"true"` |
| `false` | `"false"` |
| Integer | `"42"` |
| Float | `"3.14"` |
| String | The string itself |
| Range | `"1..5"` (string representation, NOT expanded) |
| Array | **Recursive**: output each element concatenated |
| Hash | `"{"a"=>1}"` (inspect-style, rarely used) |
| Drop | Call `.to_s` or `.to_liquid` on it |

### Critical Detail: Arrays Are Recursive

```liquid
{% assign items = "a,b,c" | split: "," %}
{{ items }}
```
Output: `abc` (not `["a", "b", "c"]`)

Arrays output their elements concatenated, not a string representation of the array.

### Implementation Sketch

```ruby
def to_output(value)
  case value
  when nil then ""
  when Array then value.map { |v| to_output(v) }.join
  when Range then "#{value.first}..#{value.last}"
  else value.to_s
  end
end
```

---

## 2. to_iterable(value)

The `{% for %}` tag needs to iterate over collections. This abstraction converts any value to something enumerable.

### Rules

| Input Type | Iterable Result |
|------------|-----------------|
| Array | The array itself |
| Range | Expanded to array: `(1..3)` → `[1, 2, 3]` |
| Hash | Array of `[key, value]` pairs |
| String | `[string]` - the whole string as ONE item |
| `nil` | `[]` - empty, no iterations |
| Number | `[]` - empty, no iterations |
| Object with `.each` | Iterate using `.each` |

### Critical Detail: Strings Are Atomic

```liquid
{% for char in "hello" %}{{ char }}{% endfor %}
```
Output: `hello` (one iteration with the whole string, NOT `h e l l o`)

Strings are treated as a single item, not a character sequence. This is intentional—it prevents accidental character iteration.

### Implementation Sketch

```ruby
def to_iterable(value)
  case value
  when Array then value
  when Range then value.to_a
  when Hash then value.to_a  # [[k1,v1], [k2,v2], ...]
  when String then value.empty? ? [] : [value]
  when nil then []
  else
    value.respond_to?(:each) ? value : []
  end
end
```

---

## 3. is_empty(value)

The `empty` keyword checks if a collection has zero elements.

### Rules

| Input Type | `== empty` Result |
|------------|-------------------|
| `""` (empty string) | `true` |
| `"hello"` | `false` |
| `"   "` (whitespace) | `false` - has characters |
| `[]` (empty array) | `true` |
| `[1, 2]` | `false` |
| `{}` (empty hash) | `true` |
| `{a: 1}` | `false` |
| `nil` | **`false`** - nil is NOT empty |
| `false` | `false` |
| `0` | `false` |
| Range | `false` - ranges are never empty |

### Critical Detail: nil Is NOT Empty

```liquid
{% if missing == empty %}yes{% else %}no{% endif %}
```
Output: `no` (undefined variables are nil, nil ≠ empty)

Empty strictly means "has zero length". Nil is the absence of a value, which is a different concept.

### Implementation Sketch

```ruby
def is_empty(value)
  case value
  when String, Array, Hash
    value.empty?
  else
    value.respond_to?(:empty?) ? value.empty? : false
  end
end
```

---

## 4. is_blank(value)

The `blank` keyword is more permissive than `empty`. It includes nil, false, and whitespace-only strings.

### Rules

| Input Type | `== blank` Result |
|------------|-------------------|
| `nil` | `true` |
| `false` | `true` |
| `true` | `false` |
| `""` (empty string) | `true` |
| `"   "` (whitespace) | `true` |
| `"hello"` | `false` |
| `[]` (empty array) | `true` |
| `[1, 2]` | `false` |
| `{}` (empty hash) | `true` |
| `0` | `false` - numbers are never blank |
| `1` | `false` |

### The Blank Hierarchy

Think of it as: **blank = empty + nil + false + whitespace**

```
blank includes:
  ├── nil
  ├── false
  ├── empty string ""
  ├── whitespace-only strings "   ", "\n", "\t"
  ├── empty arrays []
  └── empty hashes {}

blank excludes:
  ├── true
  ├── any number (including 0)
  ├── non-empty strings
  ├── non-empty arrays
  └── non-empty hashes
```

### Implementation Sketch

```ruby
def is_blank(value)
  case value
  when nil, false then true
  when true, Numeric then false
  when String then value.empty? || value.match?(/\A\s*\z/)
  when Array, Hash then value.empty?
  else
    value.respond_to?(:empty?) ? value.empty? : false
  end
end
```

---

## 5. Scope Stack

Liquid uses a stack of scopes for variable lookup. This enables proper scoping for loops, includes, and captures.

### How It Works

```
┌─────────────────────────────────┐
│ Scope 2 (for loop)              │  ← Current scope (searched first)
│   item = "apple"                │
│   forloop = {...}               │
├─────────────────────────────────┤
│ Scope 1 (include)               │  ← Parent scope
│   title = "Products"            │
├─────────────────────────────────┤
│ Scope 0 (root environment)      │  ← Root scope (searched last)
│   products = [...]              │
│   settings = {...}              │
└─────────────────────────────────┘
```

### Lookup Rules

1. Search from current scope (top of stack) downward
2. First match wins
3. If not found in any scope, return `nil`

### Assignment Rules

- **`{% assign %}`**: Always assigns to the **current** scope
- **`{% capture %}`**: Always assigns to the **current** scope
- For loops: Create a **new scope** that's popped when the loop ends

### Why This Matters

```liquid
{% for item in items %}
  {% assign temp = item | upcase %}
  {{ temp }}
{% endfor %}
{{ temp }}  <!-- Still accessible! Assigned to parent scope -->
```

Wait, that's not quite right. Let me clarify:

```liquid
{% assign outer = "before" %}
{% for item in items %}
  {% assign outer = item %}  <!-- Modifies outer scope -->
{% endfor %}
{{ outer }}  <!-- Last item value -->
```

The `assign` inside the loop modifies the variable in the scope where it's visible, which may be a parent scope.

### Implementation Sketch

```ruby
class Context
  def initialize(environment)
    @scopes = [environment]  # Stack of hashes
  end

  def push_scope(scope = {})
    @scopes.unshift(scope)
  end

  def pop_scope
    @scopes.shift
  end

  def [](key)
    @scopes.each do |scope|
      return scope[key] if scope.key?(key)
    end
    nil
  end

  def []=(key, value)
    # Find existing scope with this key, or use current scope
    target = @scopes.find { |s| s.key?(key) } || @scopes.first
    target[key] = value
  end
end
```

---

## 6. For Loop State Machine

The for loop is where everything comes together. It uses:
- `to_iterable()` to get the collection
- Scope stack to isolate loop variables
- Interrupts for `break` and `continue`
- The `forloop` object for loop metadata

### The State Machine

```
┌──────────────────────────────────────────────────────┐
│                    FOR LOOP                          │
├──────────────────────────────────────────────────────┤
│                                                      │
│   1. Evaluate collection                             │
│   2. Convert to iterable: to_iterable(collection)   │
│   3. Apply limit/offset if present                   │
│   4. Push new scope                                  │
│   5. Create forloop object                           │
│                                                      │
│   ┌────────────────────────────────────────────┐    │
│   │  FOR EACH ITEM:                            │    │
│   │                                            │    │
│   │  a. Set loop variable: item = current      │    │
│   │  b. Render body                            │    │
│   │  c. Increment forloop                      │    │
│   │  d. Check for interrupts:                  │    │
│   │     - BreakInterrupt → exit loop           │    │
│   │     - ContinueInterrupt → next iteration   │    │
│   └────────────────────────────────────────────┘    │
│                                                      │
│   6. Pop scope                                       │
│   7. Render else block if no iterations             │
│                                                      │
└──────────────────────────────────────────────────────┘
```

### The forloop Object

Every for loop creates a `forloop` object with these properties:

| Property | Description | Example (3 items, currently on 2nd) |
|----------|-------------|-------------------------------------|
| `index` | 1-based position | `2` |
| `index0` | 0-based position | `1` |
| `rindex` | 1-based from end | `2` |
| `rindex0` | 0-based from end | `1` |
| `first` | Is first iteration? | `false` |
| `last` | Is last iteration? | `false` |
| `length` | Total items | `3` |
| `parentloop` | Parent forloop or nil | `nil` or `{...}` |

### Break and Continue

These work via an **interrupt system**:

```ruby
# In break tag
context.push_interrupt(BreakInterrupt.new)

# In continue tag
context.push_interrupt(ContinueInterrupt.new)

# In for loop, after rendering body
if context.interrupt?
  interrupt = context.pop_interrupt
  break if interrupt.is_a?(BreakInterrupt)
  next if interrupt.is_a?(ContinueInterrupt)
end
```

### Implementation Sketch

```ruby
def render_for(collection_expr, variable_name, body, else_body, context)
  collection = to_iterable(context.evaluate(collection_expr))

  return render(else_body, context) if collection.empty?

  context.push_scope
  forloop = ForloopDrop.new(variable_name, collection.length)
  context['forloop'] = forloop

  output = ""
  collection.each_with_index do |item, index|
    context[variable_name] = item
    forloop.index = index

    output << render(body, context)

    if context.interrupt?
      interrupt = context.pop_interrupt
      break if interrupt.is_a?(BreakInterrupt)
      # ContinueInterrupt just continues to next iteration
    end
  end

  context.pop_scope
  output
end
```

---

## Putting It Together

With these five abstractions implemented correctly:

| You Get | Because |
|---------|---------|
| `{{ variable }}` works | `to_output()` handles all types |
| `{% for %}` works | `to_iterable()` + scope stack + state machine |
| `{% if x == empty %}` works | `is_empty()` |
| `{% if x == blank %}` works | `is_blank()` |
| Variables scope correctly | Scope stack |
| `break`/`continue` work | Interrupt system |
| `forloop` object works | State machine |
| Filters work | They operate on values, output via `to_output()` |
| Nested loops work | Scope stack + `parentloop` |

The remaining 10% is implementing individual tags and filters, which are straightforward once these foundations are solid.

---

## Common Mistakes

1. **Treating nil as empty**: `nil == empty` should be `false`
2. **Iterating string characters**: `{% for c in "hi" %}` should output `hi`, not `h i`
3. **Range output**: `{{ (1..3) }}` should output `1..3`, not `123`
4. **Array output**: `{{ array }}` should concatenate elements, not show `[...]`
5. **Scope leakage**: Variables assigned in for loops should follow proper scoping rules
6. **Missing parentloop**: Nested loops need access to their parent's forloop object

---

## Testing Your Implementation

Use liquid-spec to verify your implementation:

```bash
# Test core abstractions
liquid-spec my_adapter.rb -n literal_  # Output conversion
liquid-spec my_adapter.rb -n for_      # For loops
liquid-spec my_adapter.rb -n empty     # Empty checking
liquid-spec my_adapter.rb -n blank     # Blank checking
liquid-spec my_adapter.rb -n scope     # Scoping
```

See also:
- [For Loops](for-loops.md) - Detailed for loop behavior
- [Scopes](scopes.md) - Variable scoping rules
- [Interrupts](interrupts.md) - Break and continue behavior
