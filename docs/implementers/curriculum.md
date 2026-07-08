---
title: "Implementation Curriculum"
position: 0
description: "Start here. Explains how to use the complexity ramp as a flexible learning path and how to choose which guide to read next."
optional: false
---

# Liquid Implementation Curriculum

liquid-spec is not just a compatibility test suite. It is also a curriculum for building
a production-grade Liquid implementation incrementally.

The runner orders specs by `complexity`. In the common case, the first failure is the
best next lesson: read the spec, read its `hint:`, implement the smallest missing
observable behavior, and rerun. This is guidance, not a mandatory architecture. You can
batch related fixes, prototype ahead, or prioritize product-specific features; just keep
returning to the ordered ramp so earlier semantics stay solid.

## High-Level Principles

- **Specs define behavior, not internals.** The docs use names like `to_output` and
  `to_iterable` for clarity; your implementation can expose different APIs.
- **Centralize the value model somehow.** Liquid repeatedly asks the same questions:
  how does this value print, iterate, compare, coerce, or count as empty/blank?
  Bugs multiply when each tag/filter answers those independently.
- **Keep parsing, rendering, and host integration separable.** The exact boundary is up
  to you, but clear seams make error handling, partials, drops, and JSON-RPC adapters easier.
- **Use feature gates deliberately.** `config.missing_features` is not failure; it is a way
  to keep the curriculum aligned with the kind of Liquid you are building right now.
- **Prefer observable compatibility over implementation mimicry.** Reproduce Ruby internals
  only when your compatibility target requires them.

## The Loop

```bash
liquid-spec run my_adapter.rb
```

1. Run the suite.
2. Usually start with the first/lowest-complexity failure.
3. Read the full spec: template, environment, filesystem, expected output, errors, and hint.
4. If the rule is unclear, read the relevant guide below.
5. Reproduce a tiny case with `liquid-spec eval` when useful.
6. Implement the general behavior behind the failure, not a one-off special case.
7. Rerun and judge progress by `Complexity level cleared`, not raw pass count.

For a one-off experiment, feed `eval` a YAML spec:

```bash
cat <<'EOF' | liquid-spec eval my_adapter.rb --compare
name: scratch_assign
template: "{% assign x = 1 %}{{ x }}"
expected: "1"
complexity: 40
hint: "Assign stores a value in the current scope."
EOF
```

## Curriculum Map

| Stage | Complexity | Build | Read |
|---|---:|---|---|
| 0 | 0-20 | Adapter pipeline, raw text, object tags, literal output, nil-as-empty | `core-abstractions`, `grammar` |
| 1 | 30-50 | Variable lookup, missing variables, simple filters, `assign` | `scopes`, `filters` |
| 2 | 55-100 | `if`/`unless`, comparisons, `for`, `case`, `capture`, `forloop` basics | `for-loops`, `scopes` |
| 3 | 105-180 | Standard tags/filters, `comment`, `raw`, whitespace control, `break`/`continue`, collection helpers | `interrupts`, `filters`, `grammar` |
| 4 | 190-400 | Includes/renders, filesystem lookup, scope isolation, generated compatibility breadth | `partials`, `filesystem`, `cycle`, `tablerow` |
| 5 | 500-900 | Parser recovery/error matrices, recursion/depth limits, security quirks, date/time/Ruby compatibility | `ruby-quirks`, `parsing` |
| 6 | 1000 | Production recordings, Shopify theme behavior, performance work | `shopify-theme-filters`, `il` |

## Many Valid Implementation Paths

The guides describe Liquid's observable semantics. They do not require a particular internal
architecture. For example, all of these are reasonable choices:

- Tree-walking AST first, then bytecode/IL later.
- Bytecode or compiled templates from the start, if your project already has that machinery.
- Strict2-first parsing for a new implementation.
- Compatibility-first parsing if your users need legacy lax or strict behavior.
- Portable Liquid without Ruby internals.
- Full Ruby-compatible behavior, including Ruby type/output quirks.
- Shopify-theme support early because your product needs it, even though the generic ramp
  treats it as optional later work.

Use `config.missing_features` to keep the suite focused on the route you have chosen.
Remove missing-feature entries as those capabilities become part of your implementation.

## What to Read First

A useful starting set is:

1. `liquid-spec docs core-abstractions` — value conversion, truthiness, iteration, emptiness, scope shape.
2. `liquid-spec docs grammar` — what the language looks like and where it is irregular.
3. `liquid-spec docs complexity` — why a spec appears when it does.

Then let the failing spec choose the next guide. For example:

- Loop or `forloop` failure → `liquid-spec docs for-loops`
- Assignment/scope/partial visibility failure → `liquid-spec docs scopes` and `partials`
- Include/render lookup failure → `liquid-spec docs filesystem`
- Break/continue failure → `liquid-spec docs interrupts`
- Strange Ruby-looking output → `liquid-spec docs ruby-quirks`
- Parser error or strict2 behavior → `liquid-spec docs parsing`

## Good Candidates to Defer

Unless your project specifically needs them early, these are often worth deferring:

- Lax parsing and legacy `:raise` mode.
- Shopify-specific `shopify_*` features.
- Ruby-only compatibility (`ruby_types`, `ruby_drops`, `drop_class_output`) if you are
  not trying to reproduce Ruby internals.
- A bytecode/IL engine. A tree-walking renderer is often easier to make correct first,
  but a compiled approach is fine if it fits your implementation. Read `liquid-spec docs il`
  when performance or architecture needs justify it.

## Checkpoints

Useful checkpoints:

```bash
# See the current lesson/ramp position
liquid-spec run my_adapter.rb

# Audit accidental passes when building early behavior
liquid-spec run my_adapter.rb -s basics --list-passed --json

# Validate liquid-spec/spec changes when contributing to this repository
rake check
```

`rake check` is for liquid-spec contributors. Adapter authors usually want
`liquid-spec run my_adapter.rb`; that is the real curriculum loop.
