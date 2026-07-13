# Python autoresearch run audit (2026-07-13)

This directory records the issues exposed while a small local model built a
substantive Liquid implementation in Python against liquid-spec 2.0.0.

The run is valuable precisely because it succeeded: it reached complexity
1000 with 4,248 passing, zero failing, and 1,050 skipped specs. The path there
shows where the curriculum taught well and where the model succeeded despite
the harness rather than because of it.

## Source material

- Implementation repository:
  `/home/tobi/src/tries/2026-07-13-liquid-py-qwen27-dflash`
- Autoresearch event log: `.auto/log.jsonl` in that repository
- 1,121 Git commits, from `c3c256d` through the final stable commits
- Process logs: `err.log`, `err2.log` through `err6.log`, and `stderr.log`
- Shared result log: `/tmp/liquid-spec-results.jsonl` (4.3 GB at audit time)
- The liquid-spec 2.0.0 spec files embedded in the installed gem

The event log is the most useful canonical source. It has 1,133 measured runs,
including pass/fail totals, complexity, hypotheses, and keep/discard status.
The large JSONL result file corroborates individual results but contains many
repeated full-suite runs, so it should not be checked into this repository.

## Headline findings

1. Complexity 240 was a severe false plateau: 841 measured runs reported 240.
   The model made hundreds of useful fixes while the headline metric did not
   move. A four-spec correction eventually jumped the metric directly from
   240 to 800.
2. Several apparent contradictions were actually missing discriminators:
   explicit versus default `tablerow cols`, parse mode, and expression-chain
   evaluation rules. The next-best failure and its hint did not expose those
   discriminators.
3. Specs without an explicit `error_mode` inherited the adapter default. A
   production recording requiring strict/lax syntax therefore blocked a
   strict2-first implementation at complexity 1000. Changing one adapter
   default from strict2 to strict made the entire suite green.
4. The optimization controller failed to stop or diversify. It produced 728
   commits named `Kept: Complexity 240 stable.` and 133 equivalent post-goal
   stable commits. This inflated the 4.3 GB result log and spent most of the
   run repeating identical evidence.
5. The JSON-RPC path exposed a real option-serialization defect: a false
   `strict_errors` value was dropped. The generated adapter needed a manual
   string-key workaround.

## Files

- [curriculum-issues.md](curriculum-issues.md): ramp ordering, hints,
  prerequisites, conflicts, and missing mode isolation.
- [harness-issues.md](harness-issues.md): runner, JSON-RPC, metrics, logging,
  and feature-selection defects.
- [autoresearch-issues.md](autoresearch-issues.md): controller pathologies and
  diagnostics that would help weak models recover.
- [implementation-obstacles.md](implementation-obstacles.md): the complete
  issue-family inventory encountered by the Python implementation.
- [timeline.md](timeline.md): evidence-backed milestones and plateaus.
- [full-history-findings.md](full-history-findings.md): review of all 1,133
  measured events, with every meaningful run range mapped to a curriculum or
  tooling action.

## Recommended order of work

1. Make supported parse modes an explicit adapter capability and execute only
   those modes, ordered strict2, strict, lax.
2. Annotate every mode-sensitive recording; do not let adapter defaults choose
   the semantics of a supposedly fixed expected result.
3. Repair the three 240-plateau lessons with focused prerequisite specs and
   discriminating hints.
4. Fix false-valued JSON-RPC render option serialization.
5. Add plateau diagnostics and no-change termination to autoresearch tooling.
