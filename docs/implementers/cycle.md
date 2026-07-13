---
title: "The cycle Tag"
position: 10
description: "Read when cycle specs fail. Explains named and unnamed cycle groups, counter keys, variable groups, and state isolation."
optional: false
---

# The `cycle` Tag

The `cycle` tag rotates through a list of values. The tricky part is understanding **when two cycle tags share a counter** vs **when they get independent counters**. The counter tables and `registers` references below describe observable state, not a required JSON-RPC or host-language data structure.

## Surface Syntax

```liquid
{# Unnamed form - values only #}
{% cycle 'one', 'two', 'three' %}

{# Named form - group name before colon #}
{% cycle 'row-colors': 'odd', 'even' %}

{# Group name can be a variable #}
{% cycle varname: 'a', 'b', 'c' %}
```

## The Grouping Rules (The Key to Understanding Cycle)

Two cycle tags share a counter **if and only if** they resolve to the same **group key**. The rules for computing the group key differ based on the cycle form:

### Decision Table

| Cycle Form | Group Key | Counter Sharing |
|------------|-----------|-----------------|
| Named: `{% cycle 'grp': 'a', 'b' %}` | Evaluated group expression (`"grp"`) | All cycles with same evaluated name share |
| Named with variable: `{% cycle myvar: 'a', 'b' %}` | Evaluated variable value | All cycles evaluating to same value share |
| Unnamed with literals: `{% cycle 'a', 'b' %}` | String representation of values (`"'a''b'"`) | **All identical literal cycles share** |
| Unnamed with variables: `{% cycle x, 'b' %}` | Unique per tag instance | **Each tag gets its own counter** |

### Decision Flowchart

```
Is there a group name (colon syntax)?
├── YES → Group key = evaluate(name_expression)
│         All cycles with same evaluated name share counter
│
└── NO (unnamed cycle)
    │
    └── Do ANY values contain variable lookups?
        ├── NO (all literals) → Group key = stable string of parameters
        │                       All textually identical cycles share counter
        │
        └── YES (has variables) → Each tag instance gets unique key
                                  Independent counters per tag
```

### Why unnamed cycles with variables are independent

The observable rule is that an unnamed cycle containing a variable lookup has an
independent counter for each tag instance. This prevents a runtime value from
accidentally merging unrelated cycle sites. The rule is intentionally phrased in
terms of syntax and tag identity; it must not depend on host object addresses,
debug strings, hash iteration, or memory layout.

An implementation can record the distinction during parsing, assign each tag a
stable instance identifier, or carry equivalent metadata into its evaluator. Do
not reproduce a Ruby object-id string or parse an address-shaped substring to get
the behavior.

## Examples That Clarify the Rules

### Named Cycles: Evaluated Name is the Key

```liquid
{% cycle "group1": "a", "b" %}  → "a" (key="group1", index 0→1)
{% cycle "group1": "a", "b" %}  → "b" (key="group1", index 1→0)
{% cycle "group2": "a", "b" %}  → "a" (key="group2", new counter)
```

### Named Cycles with Variable Names

```liquid
{% assign g = "colors" %}
{% cycle g: "red", "blue" %}   → "red"  (key="colors", index 0→1)
{% cycle g: "red", "blue" %}   → "blue" (key="colors", index 1→0)
```

Both cycles evaluate `g` to `"colors"`, so they share a counter.

### Unnamed Cycles with Literals: SHARED Counter

```liquid
{% cycle "a", "b" %}  → "a" (index 0→1)
{% cycle "a", "b" %}  → "b" (index 1→0)
{% cycle "a", "b" %}  → "a" (index 0→1)
```

All three share one counter because the literal string `"'a''b'"` is identical.

### Unnamed Cycles with Variables: INDEPENDENT Counters

```liquid
{% assign x = "1" %}
{% cycle x, "2" %}    → "1" (tag A, index 0→1)
{% cycle x, "2" %}    → "1" (tag B, index 0→1)  ← NOT "2"!
```

Each `{% cycle x, "2" %}` has its own counter, so both output `"1"`.

### The Contrast in a Loop

```liquid
{# With literals - shared counter, alternates #}
{% for i in (1..4) %}{% cycle "1", "2" %}{% cycle "1", "2" %}{% endfor %}
→ "12121212"

{# With variables - independent counters, each tag cycles independently #}
{% assign a = "1" %}
{% for i in (1..4) %}{% cycle a, "2" %}{% cycle a, "2" %}{% endfor %}
→ "11221122"
```

## State Storage

Cycle counters are stored in `registers["cycle"]` as a hash mapping group keys to current indices:

```
registers["cycle"] = {
  "group1" => 2,           # Named cycle at index 2
  "'a''b'" => 0,           # Unnamed literal cycle at index 0
  "#<unique_id_1>" => 1,   # Unnamed variable cycle instance 1
  "#<unique_id_2>" => 0,   # Unnamed variable cycle instance 2
}
```

### Persistence Rules

| Context | Behavior |
|---------|----------|
| Same template | Counter persists across all occurrences |
| Multiple loops | Counter continues (doesn't reset per loop) |
| `{% include %}` | **Shares** registers with parent |
| `{% render %}` | **Isolated** - gets fresh registers |
| Different render calls | Fresh start each time |

### Include vs Render Example

```liquid
{% cycle "a", "b" %}     → "a" (index 0→1)
{% include 'snippet' %}  → "b" (shares counter, index 1→0)
{% cycle "a", "b" %}     → "a" (index 0→1)

{# But with render: #}
{% cycle "a", "b" %}     → "a" (index 0→1)
{% render 'snippet' %}   → "a" (isolated, fresh counter, index 0→1)
{% cycle "a", "b" %}     → "b" (back in parent, index 1→0)
```

## Render Algorithm

```
function render_cycle(tag, context):
    # 1. Compute group key
    if tag.is_named:
        key = evaluate(tag.group_name, context)
    else if tag.has_stable_key:  # all literals
        key = tag.precomputed_key
    else:  # has variables - unique per instance
        key = tag.unique_instance_id

    # 2. Get current index (default 0)
    cycles = context.registers["cycle"] ||= {}
    index = cycles[key] || 0

    # 3. Evaluate value at current index
    value = evaluate(tag.values[index], context)

    # 4. Output the value
    if value.is_array:
        output(value.join(""))
    else:
        output(to_string(value))

    # 5. Advance counter with wraparound
    cycles[key] = (index + 1) % tag.values.length
```

## Common Mistakes

| Mistake | Why It's Wrong | Correct Behavior |
|---------|----------------|------------------|
| All unnamed cycles share counter | Only literal-only cycles share | Variables cause independent counters |
| Evaluate values before computing key | Key must be computed at parse time for literals | Parse-time key for literals, render-time uniqueness for variables |
| Reset counter each loop iteration | Counter is persistent | Counter continues across entire render |
| `render` shares cycle state | `render` isolates registers | Only `include` shares cycle state |
| Increment before output | Would skip first value | Output THEN increment |
| Named cycle key = literal string | Key is the evaluated expression | `{% cycle myvar: ... %}` uses myvar's value |

## Implementation Checklist

1. **Parse time**:
   - [ ] Detect named vs unnamed form (presence of colon)
   - [ ] For unnamed: check if all values are literals
   - [ ] For unnamed with variables: assign unique instance ID or clone variable nodes

2. **Render time**:
   - [ ] Compute group key (evaluate for named, use precomputed/unique for unnamed)
   - [ ] Look up counter in `registers["cycle"]`
   - [ ] Evaluate value at current index
   - [ ] Output value (join arrays)
   - [ ] Increment counter with modulo wraparound

3. **Context handling**:
   - [ ] `include` shares registers
   - [ ] `render` creates fresh registers

## Related Specs

These specs test cycle behavior - run them to verify your implementation:

- `specs/basics/cycle.yml` - Core cycle grouping rules
  - `cycle_unnamed_literals_share_counter` - Literals share
  - `cycle_unnamed_variables_independent_counters` - Variables don't share
  - `cycle_unnamed_variable_in_loop` - The tricky interleaved case
  - `cycle_isolated_in_render` / `cycle_shared_in_include` - Isolation rules
- `specs/liquid_ruby/specs.yml` - Additional edge cases from Shopify/liquid

## See Also

- [Core Abstractions](core-abstractions.md) - Registers and context
- [For Loops](for-loops.md) - Common cycle usage context
- [Partials](partials.md) - Include vs render isolation
