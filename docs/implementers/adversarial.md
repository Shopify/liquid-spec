---
title: "Generated Adversarial Testing"
position: 16
description: "Use deterministic mutation, seeded differential fuzz-style runs, and bounded structural stress to find behavior missing from the recorded corpus."
optional: true
---

# Generated Adversarial Testing

The normal complexity ramp asks whether an implementation accepts the recorded Liquid
contract. Adversarial commands ask a second question: **what happens just outside the
recorded examples?**

The Rust rewrite keeps these commands deliberately small and deterministic. They run
generated probes through the selected JSON-RPC adapter; use `tools eval --compare` or
`tools matrix` when a reference oracle is needed. This keeps protocol and acceptance
coverage ahead of optional fuzzing breadth.

## Commands

```bash
# Deterministically enumerate mutations around matching seed specs.
liquid-spec tools mutate --adapter candidate --around=for_loops --limit=100

# Randomly chain mutations. The printed seed reproduces the same generated corpus.
liquid-spec tools fuzz --adapter candidate --seed=1234 --rounds=500

# Exercise bounded valid nesting and template repetition.
liquid-spec tools stress --adapter candidate --depth=64 --repetitions=100
```

All three commands are bounded probes, not coverage-guided fuzzers. JSON-RPC adapters
can override their subprocess command by placing it after `--`, as with `check`.

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

These are bounded transformations over templates that already exist. liquid-spec does
not invent a second Liquid grammar; generated cases are ordinary compile/render requests.

## Result Semantics

A generated probe is reported as a failure when:

- The selected adapter output does not match the generated expectation
- The selected adapter returns a protocol, compile, or render error

Raw error wording is diagnostic; use the stable protocol error phase/code when promoting
a generated case into a permanent spec.

Use `--json` for a stable summary suitable for an agent or CI:

```bash
liquid-spec tools fuzz --adapter candidate --seed=1234 --rounds=200 --json
```

The summary includes generated names, complexity, and adapter failures.

## Reproduction and Regression Specs

Generated probes are not persisted automatically. Promote an interesting case by saving
its YAML and evaluating it through the same adapter:

```bash
liquid-spec tools eval --adapter candidate --spec=tmp/adversarial.yml
```

The file is an ordinary spec and can be run directly:

```bash
liquid-spec check --adapter candidate --name adversarial
```

## Selecting Seeds

`--around` searches names, templates, paths, docs, hints, and feature tags. Use it to
select a small deterministic seed set:

```bash
liquid-spec tools mutate --adapter candidate --around=partials
liquid-spec tools mutate --adapter candidate --around='offset.*continue'
liquid-spec tools fuzz --adapter candidate --seed=99
```

Generated cases inherit the selected probe's core feature tag and are subject to the
adapter's advertised capabilities.

## Stress Is Bounded Differential Stress

`stress` currently generates bounded nested `if` wrappers and repeated templates. It is
useful for stack-depth, state leakage, and accidental quadratic behavior near ordinary
semantics.

It is **not** a memory-leak soak test, native coverage-guided fuzzer, or resource-limit
benchmark. Use the benchmark namespaces and platform-specific profilers for those jobs.

## Turning a Discovery Into a Permanent Spec

Generated files are candidates, not automatically curated lessons. Before contributing
one:

1. Reproduce it with its printed seed and source template.
2. Remove irrelevant environment, filesystem, and syntax.
3. Confirm the behavior against Shopify/liquid with `liquid-spec tools eval --compare`.
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
liquid-spec tools fuzz --adapter candidate --seed=847293 --rounds=500
```

This is generated differential fuzz-style testing—not coverage-guided fuzzing. The name
reflects the workflow, while the seed and mutation provenance keep every finding
reviewable.
