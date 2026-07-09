---
title: "Generated Adversarial Testing"
position: 16
description: "Use deterministic mutation, seeded differential fuzz-style runs, and bounded structural stress to find behavior missing from the recorded suite."
optional: true
---

# Generated Adversarial Testing

The normal complexity ramp asks whether an implementation accepts the recorded Liquid
contract. Adversarial commands ask a second question: **what happens just outside the
recorded examples?**

liquid-spec uses existing specs as a seed corpus, changes their templates, and runs each
generated case through both Shopify/liquid and your adapter. The reference result becomes
the oracle. This preserves the seed's environment, filesystem, parse mode, and feature
tags while exploring nearby syntax and values.

## Commands

```bash
# Deterministically enumerate mutations around matching seed specs.
liquid-spec mutate liquid_adapter_jsonrpc.rb --around=for_loops --limit=100

# Randomly chain mutations. The printed seed reproduces the same generated corpus.
liquid-spec fuzz liquid_adapter_jsonrpc.rb --seed=1234 --rounds=500

# Exercise bounded valid nesting and template repetition.
liquid-spec stress liquid_adapter_jsonrpc.rb --depth=64 --repetitions=100
```

All three commands are differential by default. `--compare` is accepted for readability
but is not required. JSON-RPC adapters can override their subprocess command with
`--command=...`, as with `run`.

## What Gets Mutated

The initial corpus mutators cover:

- Unicode and newline text composed around an existing template
- Whitespace at output/tag delimiter boundaries
- Whitespace-control markers (`{{-`, `-}}`, `{%-`, `-%}`)
- String and numeric boundary values
- Dot versus bracket lookup and missing variables
- Removed, duplicated, unknown, and extra-argument filters
- `if`/`unless` and comparison operators
- `for` limits, offsets, reversal, and missing collections
- Missing and incorrect block end tags
- Liquid-looking syntax inside `raw` and `comment` bodies

These are scanner-based transformations over templates that already exist. liquid-spec
does not invent a second Liquid grammar, and it does not assume a generated case should
succeed. Both implementations rejecting malformed syntax with the same coarse error
category is a match.

## Result Semantics

A discrepancy is reported when:

- Both implementations render, but outputs differ
- Shopify/liquid renders and the subject errors, times out, or crashes
- Shopify/liquid errors and the subject renders
- Both error but in different known categories

Raw error wording is diagnostic. Error outcomes are compared using coarse categories
such as syntax, render, unknown tag, unknown filter, timeout, and crash so host-language
class names do not create noise. A reference timeout or crash is inconclusive and skipped.

Use `--json` for a stable summary suitable for an agent or CI:

```bash
liquid-spec fuzz adapter.rb --seed=1234 --limit=200 --json
```

The summary includes the seed, parent spec, mutation chain, classification, both outcomes,
and saved regression path.

## Reproduction and Regression Specs

Discrepancies are saved under a timestamped `/tmp/liquid-spec-<mode>-...` directory by
default. Override or disable this behavior with:

```bash
liquid-spec mutate adapter.rb --save=tmp/adversarial
liquid-spec mutate adapter.rb --no-save
```

When the reference renders successfully, the generated YAML records its output as
`expected`. When the reference raises, the YAML records a parse or render error pattern.
The files are ordinary additional specs:

```bash
liquid-spec run adapter.rb --add-specs='tmp/adversarial/*.yml'
```

`--minimize` performs bounded, best-effort delta debugging before saving. It keeps only
reductions that preserve the same discrepancy classification. The result is a smaller
reproducer, not a promise of global minimality:

```bash
liquid-spec fuzz adapter.rb --seed=1234 --minimize --minimize-budget=60
```

## Selecting Seeds

`--around` searches names, templates, paths, docs, hints, and feature tags. Underscores
and punctuation are treated as spaces, so `--around=for_loops` finds loop-related seeds.
Use `-n` for a name regexp or `--features` to require feature tags:

```bash
liquid-spec mutate adapter.rb --around=partials
liquid-spec mutate adapter.rb -n 'offset.*continue'
liquid-spec fuzz adapter.rb --features=drops --seed=99
```

Generated cases inherit feature tags. If the subject adapter honestly opts out of one of
those features, the case is skipped rather than reported as an implementation failure.

## Stress Is Bounded Differential Stress

`stress` currently generates valid nested `if` wrappers and repeated templates. Every
case has a per-adapter timeout and still compares observable output against the reference.
It is useful for stack-depth, state leakage, and accidental quadratic behavior near
ordinary semantics.

It is **not** a memory-leak soak test, native coverage-guided fuzzer, or resource-limit
benchmark. Use the benchmark suites and platform-specific profilers for those jobs.

## Turning a Discovery Into a Permanent Spec

Generated files are candidates, not automatically curated lessons. Before contributing
one:

1. Reproduce it with its printed seed and saved YAML.
2. Remove irrelevant environment, filesystem, and syntax.
3. Confirm the behavior against Shopify/liquid with `liquid-spec eval --compare`.
4. Give it a unique descriptive name, an actionable hint, and the correct complexity.
5. Place it after its prerequisites rather than at the parent seed's score by reflex.
6. Add a verifier if the discovery exposes a recurring spec-quality rule.
7. Run `rake prepush`.

The goal is not to accumulate random cases. It is to turn each useful difference into a
small, teachable, permanent regression boundary.

## Reproducibility

`mutate` and `stress` are deterministic. `fuzz` chooses a random seed when none is
provided and always prints it. Supply that seed to regenerate the same case selection and
mutation chains:

```bash
liquid-spec fuzz adapter.rb --seed=847293 --limit=100 --rounds=500
```

This is generated differential fuzz-style testing—not coverage-guided fuzzing. The name
reflects the workflow, while the seed and mutation provenance keep every finding
reviewable.
