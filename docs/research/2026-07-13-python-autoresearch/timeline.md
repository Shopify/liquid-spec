# Run timeline and quantitative evidence

## Summary

- First measured run: complexity 5, 2,067 passes, 2,134 failures.
- Final meaningful run: complexity 1000, 4,248 passes, zero failures.
- Skipped at the end: 1,050.
- Measured runs: 1,133.
- Git commits: 1,121.
- Wall-clock span to first success: about 12 hours 41 minutes.

## Complexity milestones

| Run | Complexity | Pass / fail | Main lesson |
|---:|---:|---:|---|
| 1 | 5 | 2067 / 2134 | Baseline server and expression safety |
| 2 | 35 | 1974 / 2227 | Liquid truthiness and comparisons |
| 3 | 55 | 2610 / 1591 | Filter argument parsing |
| 4 | 80 | 2653 / 1548 | Loops, ranges, dynamic brackets |
| 8 | 105 | 2705 / 1496 | Whitespace and invalid range bounds |
| 31 | 125 | 3136 / 1065 | Scope architecture and counters |
| 41 | 140 | 3186 / 1015 | Tokenizer/raw architecture |
| 43 | 155 | 3191 / 1010 | Cycle identity and state |
| 74 | 165 | 3435 / 766 | Filter/stringification breadth |
| 76 | 175 | 3474 / 727 | Include and tablerow basics |
| 97 | 189 | 3535 / 666 | Tablerow properties and option transport |
| 114 | 190 | 3639 / 562 | Render aliases and iteration |
| 117 | 205 | 3645 / 556 | Argument order and state isolation |
| 119 | 240 | 3656 / 545 | Render static scope and default columns |
| 974 | 800 | 4246 / 2 | Explicit/default `col_last` rule |
| 992 | 1000 | 4248 / 0 | Strict default and mode propagation |

Pass counts are not monotonic because feature opt-ins changed the selected
corpus during the run.

## Plateau distribution

The event log groups measured runs by reported complexity as follows:

| Complexity | Runs |
|---:|---:|
| 240 | 841 |
| 1000 | 142 |
| 155 | 31 |
| 175 | 29 |
| 800 | 17 |
| 189 | 17 |
| 105 | 12 |
| 115 | 10 |

The 240 and post-goal 1000 counts dominate the experiment. They are controller
failures as much as curriculum evidence.

## The 240 plateau

At run 183, the event log explicitly named three perceived blockers:

- complexity 250: `tablerowloop.col_last`;
- complexity 300: short-circuit/precedence;
- complexity 700: tablerow integer coercion.

The model believed all three contradicted lower-level generated specs. It then
made hundreds of unchanged confirmation runs. Later, targeted fixes showed
that each had a missing discriminator:

- `d8cd01e`: whole-chain left-to-right short circuit, +186 passes;
- `bc6f8bc`: mode-sensitive boolean coercion, +2 passes;
- `017267d`: explicit versus default columns, +4 passes and complexity
  240 to 800.

This is the strongest evidence that focused prerequisite specs and comparative
failure diagnostics would improve the ramp.

## The 800 plateau

Two failures remained at first: Ruby gsub replacement escaping and indirect
bare-bracket lookup. `8adb40f` fixed gsub behavior. The remaining production
recording was incompatible with the adapter's strict2 default, while strict2
rejection specs correctly demanded rejection.

The controller declared the case unresolvable repeatedly. `3afef1c` propagated
parse mode through the parser and changed the unannotated default to strict;
the run immediately reached 1000. This is direct evidence for explicit
supported-mode execution and mode annotation of recordings.

## Process failures

The saved stderr logs record abnormal subprocess exits at cycle, blank, and
trim-mode specs. The initial `err.log` also contains many uncaught Python
filter-arity and integer-conversion exceptions. These failures motivated server
hardening but the runner logs did not preserve enough protocol context to
diagnose them independently.

