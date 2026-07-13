# Autoresearch/controller issues

These are not all liquid-spec defects, but liquid-spec can supply signals and
guardrails that make autonomous implementation runs much more productive.

## AUTO-01: No plateau termination or escalation

The controller produced 728 commits with the normalized message `Kept:
Complexity 240 stable.` Complexity 240 accounted for 841 of 1,133 measured
runs. Most of those commits recorded no source change or new evidence.

After a small number of identical result fingerprints, stop confirmation runs
and switch strategy: inspect all failures at the first blocking level, compare
their modes/options, consult linked docs, or emit a blocked report.

## AUTO-02: No post-goal termination

After first reaching 1000 with zero failures at run 992, the controller made
roughly 140 more measured runs and 133 normalized `Stable: 1000/1000` commits.
The goal condition was already satisfied and repeatedly acknowledged.

Terminate immediately after a configurable confirmation count (two or three
runs is ample), unless nondeterminism was detected.

## AUTO-03: Identical no-op commits pollute the history

The repository has 1,121 commits, dominated by stable confirmations. This
obscures the meaningful semantic history and makes later forensic analysis
harder. A no-change evaluation should be an event-log entry, not a Git commit.

Commit only source/config changes or a deliberate checkpoint with novel
diagnostic evidence.

## AUTO-04: The optimizer overfit the scalar metric

Useful fixes that increased passes but left complexity at 240 were “kept,” yet
the controller had no principled way to rank them or decide which blocker to
attack. Conversely, enabling optional features lowered the scalar metric and
looked like regression even when capability increased.

Use a multi-component objective: core level, first-level failures, total
failures, supported capability count, and skipped count. Never compare runs
with different capability profiles as if they share one scalar objective.

## AUTO-05: It treated apparent contradictions as globally impossible

The controller repeatedly concluded that `col_last`, boolean coercion, and
short-circuit cases had mutually exclusive expectations. In each case a hidden
input dimension reconciled them: explicit/default options, error mode, or full
expression-chain behavior.

When two tests conflict, automatically diff all inputs and metadata: suite,
mode, features, render options, explicit versus omitted arguments, source
metadata, and reference version. Liquid-spec's inspect output should make this
comparison directly available.

## AUTO-06: It changed the adapter default to satisfy an unannotated spec

The final fix was effective but exposed an ambiguity: the controller changed
global default semantics to pass one recording. In a less fortunate corpus,
that could hide incorrect behavior elsewhere.

The controller should prefer adding/using explicit mode declarations and
should flag any score change caused solely by an adapter default. The harness
should make such ambiguity impossible by resolving modes itself.

## AUTO-07: Initial server crashes were costly and poorly localized

The earliest logs show many Python arity errors for missing filter arguments,
integer parse exceptions, and abnormal process exits. A single implementation
exception could abort the run at an unrelated later spec.

Provide a JSON-RPC conformance smoke test before the full suite: lifecycle,
compile/render error envelopes, false option transport, timeout recovery,
missing filter arguments, and subprocess restart behavior.

## AUTO-08: Broad fixes were inferred from individual failures

The model repeatedly patched one observed value conversion or parser edge case
at a time. Large later pass jumps show that it eventually discovered shared
rules. Give agents a cluster view of failures by normalized template shape,
hint/doc, exception, feature, and likely subsystem.

## AUTO-09: Confidence did not control behavior

The event log contains confidence values and hypotheses, but hundreds of
unchanged runs continued after the controller explicitly wrote that exploration
was exhausted. Confidence and “no further paths” assertions had no operational
effect.

Treat repeated blocked hypotheses as a state transition that triggers a new
diagnostic action or clean termination.

