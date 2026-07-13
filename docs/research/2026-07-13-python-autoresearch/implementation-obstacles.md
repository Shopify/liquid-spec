# Implementation obstacle inventory

This is the complete family-level inventory reconstructed from the event log,
commit history, and process logs. It intentionally groups repeated individual
test failures by the missing rule they exposed; listing thousands of repeated
per-spec failures would be less actionable.

## Protocol and lifecycle

- JSON-RPC server robustness, restart/EOF behavior, and abnormal exits.
- Compile versus render error envelopes and inline versus raised errors.
- Loss of `strict_errors: false` during option serialization.
- Parse mode propagation from adapter through engine, parser, nested partials,
  and expression parsing.
- Filesystem key normalization and `.liquid` fallback.
- Frozen time and render-register propagation.
- RPC/test drops, iteration, property access, and unsupported Ruby values.

## Tokenization and parsing

- Competing/nested `{{` and `{%` delimiters and malformed close delimiters.
- Left/right whitespace control, especially inside raw/comment/block bodies.
- Nested raw/comment/doc tags and termination of malformed blocks.
- `{% liquid %}` line splitting, inline comments, multiword tags, and nested
  block structures.
- Orphaned `else`/`elsif`/end tags and unclosed output tags.
- Filter colon/comma parsing, trailing separators, and missing arguments.
- Range syntax, exclusive ranges, variable bounds, and invalid bounds.
- Bare bracket access and its strict2 versus strict/lax meaning.
- Dynamic bracket keys, nested brackets, quoted keys, and `self[...]`.
- Hyphenated identifiers and special keywords used as property names.
- Include/render/tablerow modifier parsing with optional commas and spaces.

## Expressions and values

- Liquid truthiness: only nil and false are falsy.
- `empty` and `blank` sentinels and their output/equality behavior.
- Strict type equality and ordering errors across strings/numbers/nil.
- `contains` behavior for nil, false, strings, arrays, and type conversion.
- Equal-precedence, left-to-right boolean chains and whole-chain
  short-circuiting.
- Variable lookup precedence across locals, base/static environments,
  counters, render scopes, and SelfDrop.
- Array/hash/range/string property shortcuts (`first`, `last`, `size`).
- Python/Ruby type differences, especially bool-as-int.
- Liquid output conversion versus Ruby `to_s`/`inspect` compatibility.
- Integer/float formatting, scientific notation, big integers, and NaN.

## Scope and control flow

- Assign/capture persistence through loop scopes.
- Independent increment/decrement counters.
- Cycle identity, naming, state isolation, and render boundaries.
- `offset:continue` state.
- Nested `forloop.parentloop` and complete forloop/tablerowloop properties.
- Break/continue propagation with partial output through nested conditionals,
  include boundaries, render isolation, and use outside loops.
- `ifchanged` state.
- Case/when `or`, multiple matching clauses, and unusual else ordering.
- Unless plus elsif semantics.

## Iteration and tablerow

- String, hash, range, nil, false, empty, and non-iterable collections.
- Limit/offset/reversed parsing, slicing, variable modifiers, and coercion.
- Different include/render behavior for `with` and `for` collections.
- Tablerow HTML/newline formatting and default column count.
- `col`, `col0`, `row`, `col_first`, and mode/default-sensitive `col_last`.
- Nil/boolean/string integer coercion varying by parse mode.
- Explicit versus omitted `cols` behavior—the major 240 plateau blocker.

## Includes and renders

- Dynamic template names and validation.
- `with`/`for` aliases, hash/non-iterable handling, and iteration context.
- Named argument parsing and source-order evaluation.
- Include's shared scope versus render's isolated scope.
- Static environment visibility inside render.
- Cycle and interrupt isolation across render boundaries.
- Missing template errors, template names/line locations, and nesting depth.
- Include-inside-render rejection.

## Filters and conversions

- Numeric coercion for nil, bool, strings, floats, and drops.
- Integer validation versus Ruby `to_i` behavior.
- Division by zero, float division, rounding, and precision.
- Slice negative indexes/lengths and out-of-range behavior.
- Date parsing, timezone formats, `%s/%e/%l/%c`, `now`/`today`, and frozen time.
- ASCII versus Unicode whitespace in `truncatewords` and split behavior.
- HTML escape/escape_once/strip_html edge cases.
- Ruby-compatible stringification for arrays/hashes in many string filters.
- `map`, `where`, `find`, `find_index`, `has`, `reject`, `compact`, `sort`,
  `sort_natural`, `sum`, `flatten`, and range/drop inputs.
- Base64 binary/encoding behavior.
- Ruby gsub replacement escapes and empty-pattern replacement.
- Filter arity and whether errors propagate, render inline, or are swallowed by
  assign.

## Drops and portability

- Boolean, Number, String, Method, Index, Sequence, Nil, Opaque, and Error drop
  behavior.
- SelfDrop lookup, iteration, comparison, stringification, and shadowing.
- Ruby-specific hash/class output and binary values over JSON-RPC.
- Optional feature enablement causing score regressions.

## Corpus/ramp defects revealed by those obstacles

- Missing focused prerequisites before wide generated matrices.
- Hints that omitted the discriminating mode or explicit/default distinction.
- Conflicting-looking generated/manual cases separated by large complexity
  gaps.
- Production recordings without explicit parse mode.
- Ruby implementation quirks insufficiently separated from portable Liquid.
- A contiguous metric with no useful intermediate levels from 240 to 800.

