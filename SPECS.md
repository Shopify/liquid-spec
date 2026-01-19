# Writing Great Specs

This guide explains how to write specs that help implementers build correct Liquid implementations. A great spec doesn't just verify correctness—it teaches implementers what to build and helps them understand *why* Liquid behaves the way it does.

## Why Specs Matter More Than Ad-hoc Testing

Ad-hoc testing answers: "Does this work?"
Specs answer: "What should I build next, and how?"

When you write a spec, you're not just testing—you're creating a curriculum. Each spec is a lesson that teaches one concept. The complexity score determines when that lesson appears. The hint explains what to implement.

**Bad approach:** Run random templates, check if output looks right
**Good approach:** Write specs that progressively teach the language

## The Spec Writing Workflow

### Step 1: Identify What to Test

Before writing a spec, ask:

1. **Is this novel?** Does an existing spec already cover this?
2. **Is this a real behavior?** Test against liquid-ruby first
3. **Where does this fit?** What complexity makes sense?

Use the tools to explore existing coverage:

```bash
# Search existing specs for a concept
grep -r "offset:continue" specs/

# Check what's covered at a complexity level
./bin/complexity-ramp -g 25 -t | grep "190 -" -A 50

# See what filters/tags are tested
./bin/liquid-spec-browse tags
./bin/liquid-spec-browse filters
```

### Step 2: Verify Against Reference

**Always test against liquid-ruby first.** Never guess what the output should be.

```bash
# Quick inline test with automatic comparison
liquid-spec eval examples/liquid_ruby.rb --compare <<EOF
name: test_my_feature
template: "{{ items | sort | first }}"
environment:
  items: [3, 1, 2]
EOF
```

The `--compare` flag runs your template against the reference implementation and shows the actual output. Use this to discover the correct expected value.

### Step 3: Write the Spec

Once you know the correct behavior, write the full spec:

```yaml
- name: sort_then_first
  template: "{{ items | sort | first }}"
  environment:
    items: [3, 1, 2]
  expected: "1"
  complexity: 85
  hint: |
    Filter chains apply left-to-right. sort orders the array [1, 2, 3],
    then first takes the first element. Implement filter chaining by
    passing each filter's output as the next filter's input.
```

### Step 4: Verify Placement

Run the complexity ramp analysis to verify your spec fits:

```bash
# Does this complexity make sense?
./bin/complexity-ramp -t | grep "85"

# Are there gaps this spec could fill?
./bin/complexity-ramp -g 10
```

---

## The Three Pillars of a Great Spec

### 1. Test Something Novel

Every spec should teach the implementer something new. Ask: "If an implementer passes all lower-complexity specs, what new concept does this spec introduce?"

**Good:** Tests a new feature, edge case, or interaction
```yaml
- name: for_offset_continue_basic
  template: "{% for i in items limit:3 %}{{ i }}{% endfor %}|{% for i in items offset:continue limit:3 %}{{ i }}{% endfor %}"
  environment: { items: [1, 2, 3, 4, 5, 6, 7, 8, 9] }
  expected: "123|456"
  complexity: 190
  hint: |
    offset:continue resumes from where the previous loop left off.
    First loop takes 1,2,3. Second loop continues with 4,5,6.
```

**Bad:** Redundant with other specs
```yaml
# If you already have {{ 'hello' | upcase }}, you don't need
# separate specs for {{ 'world' | upcase }} and {{ 'foo' | upcase }}
```

### 2. Well-Chosen Complexity

Complexity determines learning order. A spec at complexity 70 (for loops) should not require understanding features at complexity 140 (array filters).

| Range | What It Should Test |
|-------|---------------------|
| 0-20 | Literals, raw text output—no logic needed |
| 25-50 | Variables, basic output, simple filters |
| 55-70 | Whitespace control, if/else/unless, basic operators |
| 75-90 | For loops, forloop object, filter arguments |
| 95-130 | Math filters, capture, case/when, string filters |
| 140-180 | Array filters, property access, truthy/falsy, tablerow |
| 190-220 | offset:continue, parentloop, partials (render/include) |
| 225-290 | String filter edge cases, advanced filter usage |
| 300-400 | Filter chains, complex transformations, edge cases |
| 500+ | Advanced drops, recursion, deprecated features |
| 1000 | Unscored specs, production recordings |

**Rule:** If your spec fails for an implementer who passed all lower-complexity specs, your complexity is too low. If it passes without implementing anything new, it's too high.

### 3. Actionable Hints

Hints appear when a spec fails. They must tell the implementer **what to implement**, not just describe the behavior.

**Bad hint:** Just restates the expected output
```yaml
hint: "The template should output 'empty' when the string is empty."
```

**Good hint:** Explains the implementation
```yaml
hint: |
  Recognize 'empty' as a keyword representing the empty state.
  An empty string "" should equal the 'empty' keyword. Create
  an EmptyLiteral node during parsing. During evaluation, compare
  the variable's value against emptiness: empty strings, empty
  arrays, and empty hashes all equal 'empty'.
```

---

## Hint Writing Guide

### Structure of a Great Hint

1. **State the key insight** (first sentence)
2. **Explain the implementation** (what code to write)
3. **Clarify edge cases** (what makes this tricky)

```yaml
hint: |
  The `first` filter returns the first element of an array or string.
  For arrays, return index 0. For strings, return the first character.
  For nil or empty collections, return nil (renders as empty string).
  Numbers and other types return nil—only arrays and strings work.
```

### Flag Surprising Behaviors with WART

Some Liquid behaviors are counterintuitive. Flag these so implementers know the spec is correct:

```yaml
- name: int_size_returns_byte_size
  template: "{{ num | size }}"
  environment: { num: 42 }
  expected: "8"
  complexity: 150
  hint: |
    WART: int | size returns 8 because Ruby's Integer#size returns
    the byte representation size (8 bytes on 64-bit systems), NOT
    the number of digits. This is surprising but matches liquid-ruby.
```

See [WARTS.md](WARTS.md) for a catalog of known surprising behaviors.

### Link to Documentation for Complex Topics

For concepts too large for a hint:

```yaml
_metadata:
  doc: implementers/for-loops.md

specs:
- name: forloop_parentloop_chain
  hint: |
    parentloop can be chained for deeply nested loops. For full
    details on forloop scope and nesting, see the linked doc.
```

---

## Spec Structure Reference

### Basic Spec

```yaml
- name: descriptive_snake_case_name
  template: "{{ x | upcase }}"
  environment: { x: "hello" }
  expected: "HELLO"
  complexity: 40
  hint: |
    The upcase filter converts a string to uppercase.
```

### Spec with Filesystem (for partials)

```yaml
- name: render_with_variable
  template: "{% render 'greeting', name: 'World' %}"
  expected: "Hello, World!"
  complexity: 200
  filesystem:
    greeting.liquid: "Hello, {{ name }}!"
  hint: |
    The render tag loads a partial and passes variables to it.
    Variables are scoped—the partial cannot access outer variables.
```

### Spec Expecting Errors

```yaml
- name: undefined_variable_strict
  template: "{{ undefined_var }}"
  errors:
    render_error: ["undefined"]
  complexity: 120
  hint: |
    In strict mode, accessing undefined variables raises an error.
```

### Source-Level Metadata

Apply settings to all specs in a file:

```yaml
_metadata:
  doc: implementers/core-abstractions.md
  hint: "All specs in this file test empty/blank semantics."
  required_options:
    error_mode: :lax

specs:
- name: first_spec
  # inherits metadata settings
```

---

## Valid Keys Reference

### File-Level Keys

| Key | Description |
|-----|-------------|
| `_metadata` | File-level settings applied to all specs |
| `specs` | Array of spec objects |

### _metadata Keys

| Key | Description |
|-----|-------------|
| `hint` | Default hint for all specs in this file |
| `doc` | Documentation link for all specs |
| `complexity` | Default complexity for specs without explicit complexity |
| `minimum_complexity` | Alias for `complexity` |
| `render_errors` | Default render_errors setting |
| `required_options` | Options applied to all specs (e.g., `error_mode: :lax`) |

### Spec Keys

| Key | Required | Description |
|-----|----------|-------------|
| `name` | Yes | Unique identifier (snake_case) |
| `template` | Yes | The Liquid template to render |
| `expected` | * | Expected output (required unless `errors` is set) |
| `errors` | * | Error patterns to match (required unless `expected` is set) |
| `environment` | No | Variables available to the template |
| `filesystem` | No | Virtual filesystem for partials |
| `complexity` | No | Difficulty score (defaults to 1000) |
| `hint` | No | Explanation shown on failure |
| `doc` | No | Link to documentation |
| `error_mode` | No | `:strict` or `:lax` parsing mode |
| `render_errors` | No | If true, errors render inline instead of throwing |
| `required_features` | No | Features needed to run this spec |

---

## Common Mistakes

### 1. Wrong Complexity

**Problem:** Spec requires features not yet introduced
```yaml
# BAD: Uses filter chains (complexity 80) but marked as complexity 40
- name: variable_with_chained_filters
  template: "{{ name | downcase | capitalize }}"
  complexity: 40  # Should be 80+
```

### 2. Redundant Specs

**Problem:** Multiple specs testing the same concept
```yaml
# BAD: All testing basic filter application
- name: upcase_hello
  template: "{{ 'hello' | upcase }}"
- name: upcase_world
  template: "{{ 'world' | upcase }}"
```

**Better:** One basic case, additional specs for edge cases
```yaml
- name: filter_upcase_basic
  template: "{{ 'hello' | upcase }}"
  complexity: 40
- name: filter_upcase_empty_string
  template: "{{ '' | upcase }}"
  complexity: 45
- name: filter_upcase_unicode
  template: "{{ 'café' | upcase }}"
  complexity: 50
```

### 3. Unhelpful Hints

**Problem:** Hint doesn't explain implementation
```yaml
# BAD
hint: "Empty arrays should be considered empty."

# GOOD
hint: |
  Arrays with no elements should equal 'empty'. When evaluating
  the comparison, check if the array's length is zero.
```

### 4. Guessing Expected Values

**Problem:** Expected value wasn't verified against liquid-ruby
```yaml
# BAD: Assumed behavior
- name: split_at_end
  expected: "ab-"  # WRONG - Ruby's split strips trailing empties
```

**Solution:** Always use `--compare` first
```bash
liquid-spec eval examples/liquid_ruby.rb --compare <<EOF
name: split_at_end
template: "{{ 'abc' | split: 'c' | join: '-' }}"
EOF
# Shows actual output: "ab"
```

### 5. Missing WART Flag

**Problem:** Surprising behavior without explanation
```yaml
# BAD: Implementer will think spec is wrong
- name: false_is_blank
  template: "{% if false == blank %}yes{% endif %}"
  expected: "yes"

# GOOD: Explains the surprise
- name: false_is_blank
  template: "{% if false == blank %}yes{% endif %}"
  expected: "yes"
  hint: |
    WART: The boolean false is considered blank. The blank keyword
    matches nil, false, empty strings, whitespace-only strings, and
    empty collections.
```

---

## Using the Tools

### liquid-spec eval

Quick testing with automatic comparison:

```bash
# Inline template
liquid-spec eval examples/liquid_ruby.rb --compare <<EOF
name: my_test
template: "{{ x | size }}"
environment: { x: [1, 2, 3] }
EOF

# From file
liquid-spec eval examples/liquid_ruby.rb --spec=my_test.yml --compare
```

Saved specs go to `/tmp/liquid-spec-{date}.yml`. Browse them:

```bash
./bin/liquid-spec-browse ls           # List saved files
./bin/liquid-spec-browse show         # Show today's specs
./bin/liquid-spec-browse stats        # Tag/filter statistics
./bin/liquid-spec-browse search sort  # Find specs by content
```

### Complexity Analysis

```bash
# See the complexity ramp
./bin/complexity-ramp -g 25

# Find misordered specs
./bin/fix-misordered -o summary

# Score unscored specs
./bin/score-unscored -o summary

# Calibrate based on pass/fail data
./bin/calibrate-complexity -m suggest
```

### Running Specs

```bash
# Run all specs
bundle exec rake run

# Run specific suite
liquid-spec examples/liquid_ruby.rb -s basics

# Filter by name pattern
liquid-spec examples/liquid_ruby.rb -n tablerow

# Compare multiple adapters
liquid-spec matrix --adapters=a.rb,b.rb -s basics
```

---

## Spec File Organization

```
specs/
├── basics/                    # Core Liquid features
│   ├── specs.yml             # Variables, filters, control flow
│   ├── for-loops.yml         # Advanced for loop features
│   ├── tablerow.yml          # Tablerow tag
│   ├── filter-chains.yml     # Multi-filter combinations
│   ├── string-filters.yml    # String filter edge cases
│   └── ...
├── liquid_ruby/              # Specs from Shopify/liquid tests
├── liquid_ruby_lax/          # Lax mode specs
├── shopify_production_recordings/  # Real-world behaviors
├── shopify_theme_dawn/       # Shopify-specific features
└── benchmarks/               # Performance benchmarks
```

Each suite has a `suite.yml`:

```yaml
name: "Basics"
description: "Core Liquid features every implementation needs"
default: true
required_features: [core]
minimum_complexity: 1000
```

---

## Submitting Specs

### Checklist

- [ ] **Novel:** Not covered by existing specs
- [ ] **Verified:** Passes against liquid-ruby with `--compare`
- [ ] **Correct complexity:** Doesn't require higher-complexity features
- [ ] **Actionable hint:** Explains what to implement
- [ ] **Warts flagged:** Surprising behaviors marked with `WART:`
- [ ] **Fits the ramp:** Checked with `./bin/complexity-ramp`

### Process

1. Write spec and verify with `liquid-spec eval --compare`
2. Add to appropriate file in `specs/basics/` or create new file
3. Run `bundle exec rake run` to verify no regressions
4. Submit PR with description of what the spec teaches

---

## Philosophy

The goal of liquid-spec is to make implementing Liquid straightforward. An implementer should be able to:

1. Start at complexity 0
2. Run specs in complexity order
3. Implement whatever each failing spec needs
4. End up with a complete, correct implementation

Every spec you write is a step in that curriculum. Make each step clear, necessary, and actionable.
