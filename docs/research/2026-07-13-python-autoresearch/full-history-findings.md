# Full measured-history review

This review covers all 1,133 measured events in `.auto/log.jsonl`, not only the
commits labelled `BREAKTHROUGH`. Events were divided into:

- 243 meaningful attempts that changed code, capability selection, results, or
  the working hypothesis;
- 890 repeated confirmations with no new implementation or diagnostic result.

The repeated events remain important as plateau evidence, but they do not each
represent a separate Liquid lesson. The meaningful events are indexed below by
run number. Together the ranges cover every meaningful event extracted from the
history.

## Runs 1-8: the first ramp was far too coarse

The implementation moved 5 → 35 → 55 → 80 → 85 → 95 → 105. These jumps hid
the following separately implementable lessons:

- JSON-RPC lifecycle and a non-crashing compile/render loop (run 1);
- dynamic bracket lookup and array `first`/`last`/`size` (run 1);
- truthiness, comparisons, `empty`, `blank`, and boolean output (run 2);
- filter-call argument syntax (run 3);
- loop modifiers, variable range bounds, and negative slicing (run 4);
- `case/when or`, numeric filters, dates, and nil arithmetic (run 5);
- loop scope, parent loops, range values, cycle names, and default blankness
  (run 6);
- block whitespace and invalid/undefined range bounds (runs 7-8).

Action: the 0-105 spine needs consecutive first-contact lessons. A model should
never need one patch containing truthiness, six comparison operators, three
sentinels, boolean serialization, and a logic parser merely to move from 5 to
35.

## Runs 9-20: tokenizer architecture was discovered through edge cases

Twelve runs remained at 105 while independently discovering:

- `strip_newlines` (run 9);
- nested comment and raw behavior (runs 10-11, 14, 17-18);
- first `{% liquid %}` and `echo` behavior (runs 12-13);
- competing and nested Liquid delimiters (runs 15-16, 19-20);
- decrement initialization (runs 19-20).

Action: add a tokenizer curriculum before malformed-delimiter matrices: one
text token, one output token, one tag token, delimiter priority, raw capture,
comment capture, then malformed termination. Raw/comment/liquid interactions
must come later. These are parser prerequisites, not one complexity-105 lesson.

## Runs 21-43: core evaluation and state were interleaved

The history separately exposed:

- numeric coercion, nil `contains`, and output formatting (run 21);
- string/empty iteration and array rendering (runs 22-23);
- counter state independent from assignments (run 24);
- floating arithmetic and partial numeric parsing (run 25);
- first `ifchanged` (run 26);
- nil truncation and standalone echo (run 27);
- reusable parsing of `{% liquid %}` bodies (runs 28-29, 32, 34-35);
- loop modifier syntax (run 30);
- the base/local/counter scope architecture (run 31);
- `offset:continue` state (run 33);
- strict equality, nil ordering, and blank/empty case values (runs 36, 38, 40);
- recursively recognizing output-producing nodes for whitespace (runs 36-38);
- bracket semantics and Ruby hash output (run 39);
- output tokenizer correctness (run 41);
- date `%s` and timezone parsing (run 42);
- cycle identity and sharing rules (run 43).

Action: make scope and state explicit curriculum tracks. Counter namespaces,
loop-local scope, outer assignment, render isolation, include sharing, and
register state should each occupy their own level before interaction specs.

## Runs 44-74: thirty-one filter lessons were trapped at 155

Runs 44-74 cover independent behavior for include/render parsing plus compact,
sort_natural, numeric bool handling, hyphenated assignment, abs/min/max type
preservation, base64 conversion, capitalization, ceil/floor/round nil input,
default blankness and `allow_false`, complex-value stringification,
escape_once, `h`, xml_escape, hash `first`, `has`, string stripping, integer and
boolean `size`, negative slice bounds, sort, squish, strip_html, sum,
truncatewords, URL encoding, string `where`, and keyword property access.

Action: generated standard-filter breadth must not sit at one score. Each filter
gets a tiny ordinary-input lesson; conversion behavior gets a separate shared
coercion lesson; Ruby `inspect` compatibility and bizarre inputs move to a
later compatibility track. The run spent 31 attempts at 155 because these
three kinds of test were mixed.

## Runs 75-97: tablerow was learned one property at a time

The implementation encountered render/include clauses, tablerow HTML and
newlines, find/find_index/has/reject/map, empty and nil collections, `cols:nil`,
nil limit/offset, modifier tokenization, loop interrupts, integer validation,
exclusive ranges, JSON-RPC false-option loss, and the `col0`/`row` properties.

Action implemented: `specs/basics/tablerow.yml` now uses consecutive levels
241-265. The exact explicit-`cols` `col_last` discriminator is its own lesson at
248 instead of being hidden inside a score-250 group.

## Runs 98-119: partial semantics were a seventeen-run pileup

These runs separately fixed:

- date padding flags (run 98);
- dynamic include names and filesystem normalization (runs 99, 102);
- loop/partial whitespace and scope (runs 100-101);
- include `for`, `with`, aliases, hash behavior, and validation (runs 103-108);
- render interrupt isolation and include prohibition (runs 109-110);
- render named args, iteration, aliases, hash behavior, and forloop data
  (runs 111-116);
- parameter evaluation order and cycle isolation (run 117);
- interrupts outside loops and across render (run 118);
- render static-environment visibility and tablerow defaults (run 119).

Action implemented: the first 52 partial lessons now occupy consecutive levels
189-240. Eight later interactions occupy 266-273. Six recursion lessons occupy
600-605. Previously all 66 specs were collapsed onto 100, 200, 210, 220, and
300, including recursion beside ordinary parameter passing.

## Runs 120-180: compatibility breadth obscured the next lesson

This section added or corrected:

- split trailing empties, date keywords/casing/frozen time, apostrophe escaping,
  and include interrupt propagation (runs 120-123, 133-135);
- missing-template errors and false tablerow collections (runs 124-125);
- hash/range properties and unusual case flow-through (runs 126-128, 137);
- non-iterable render/include behavior and dynamic `with` names (runs 131-132);
- SelfDrop lookup, nesting, iteration, and stringification (runs 138-141);
- capture outer-scope writes and render alias precedence (runs 143-147);
- doc parsing and malformed comment/raw fallback (runs 149-150);
- filter punctuation, sentinel output, range filters, scalar property size,
  date formats, round, flatten, filter arity, and assign error swallowing
  (runs 151-163);
- liquid-block word boundaries and elsif (runs 164-165);
- mixed-type comparison errors and partial nesting limits (runs 166-168);
- capability experiments for SelfDrop, strict2 blank bodies, standard drops,
  Ruby types, and Ruby drops (runs 170-180).

Discarded runs 136, 148, 169, 172-174, 177, and 181-184 are especially useful:
they identify apparent contradictions and non-monotonic feature opt-ins. They
must be represented as paired specs with the discriminating mode/option, not as
instructions to keep whichever lower score currently wins.

## Runs 181-920: the controller repeated a known impasse

The meaningful attempts in this interval are capability/regression probes at
181-188 and the retained tablerow coercion change at run 734. The remaining
events overwhelmingly repeated the same complexity-240 result. By run 183 the
controller had already named all three blockers: `col_last`, boolean-chain
evaluation, and tablerow coercion.

Action: after repeated identical result fingerprints, the tool must compare
blocking specs' full metadata and stop or change strategy. Hundreds of reruns
are not curriculum research.

## Runs 921-955: useful work was invisible to complexity

While complexity stayed at 240, the implementation fixed error formatting,
date behavior, float serialization, big integers, filter integer validation,
range types, capture interrupts, orphan structural tags, unless/elsif, string
collections, strict2 bare brackets, protocol error envelopes, map conversion,
float division by zero, nil filters, loop slicing, reversed punctuation,
comparison formatting, range conversion, contains edge cases, forloop naming,
base64 bytes, render assignment scope, and finally boolean chains.

Notable bulk unlocks were +86 passes from loop slicing (run 941), +20 from one
parser punctuation rule (run 942), +19 from comparison semantics (run 943), and
+186 from the correct boolean-chain model (run 955).

Action: each bulk unlock needs one earlier curated semantic spec. The generated
matrix remains later breadth. Complexity reporting should also expose failures
remaining at the first blocked level so this progress is visible.

## Runs 956-974: tail compatibility contained distinct maturity levels

The remaining work included include-range behavior, float scientific notation,
unclosed outputs in partials, include-with-array iteration, ASCII whitespace,
huge integer handling, Ruby replacement escapes, underscore validation,
tablerow offset, mode-sensitive boolean coercion, and empty-string collection
handling (runs 956-973).

Run 974 discovered explicit versus default `cols` and jumped 240 → 800 after
only four additional passes. That jump is the clearest proof that scores were
acting as buckets rather than lessons.

## Runs 975-993: the last blocker was a mode-selection defect

Runs 976-981 fixed or reverted Ruby gsub replacement parsing. Runs 989-990
repeated the remaining strict2 bare-bracket conflict. Run 992 propagated mode
through the parser and changed the adapter default to strict; the suite reached
1000 immediately. Run 993 was the only useful confirmation.

Action: adapters must explicitly declare supported modes. The runner tests the
highest compatible strict mode (strict2, then strict) and runs lax separately
only when it is explicitly declared. Mode-sensitive recordings must declare
compatible modes; an adapter default must never choose their semantics.

## Runs 994-1133: success was already established

These 140 events added no Liquid knowledge. They repeatedly committed the same
1000/1000 result.

Action: terminate after a small configurable confirmation count and never make
Git commits for unchanged evaluations.

## Cross-cutting migrations still required

The complete history supports these remaining workstreams:

1. spread the 0-188 curated core over consecutive levels;
2. split the standard-filter matrices into first contact, shared conversion,
   portable edge case, and Ruby-compatibility tracks;
3. add focused boolean-chain lessons before generated truth tables;
4. add focused tokenizer lessons before malformed syntax matrices;
5. explicitly model supported parse modes and expand specs per supported mode;
6. separate core complexity from optional capability progress;
7. fix false-valued JSON-RPC option serialization;
8. add first-blocking-level progress and spec-metadata comparison diagnostics;
9. rotate/deduplicate result logs and stop repeated evaluations;
10. improve abnormal-exit protocol context.
