# Curriculum issues

Each item is written as a potential liquid-spec issue. Commit identifiers refer
to the Python implementation repository described in the directory README.

## CUR-01: Complexity 240 is a cliff, not a ramp

The run spent 841 measured attempts at complexity 240. During that plateau the
pass count rose from roughly 3,656 to 4,246, but the curriculum score stayed
fixed. Commit `017267d` fixed four remaining cases and jumped directly from 240
to 800.

The metric correctly describes a contiguous ramp, but the ramp itself provides
almost no intermediate feedback across a large body of behavior. Complexity
levels are now treated as ordinal lesson positions rather than round-number
buckets: the advanced tablerow specs occupy consecutive levels 241 onward.
Continue this migration across other clustered feature families. A useful
quality gate would flag any adjacent cleared levels where one fix can jump more
than a configured threshold.

## CUR-02: `tablerowloop.col_last` hides two different rules

Early generated specs appeared to require `col_last` on the final collection
item. A later manual spec appeared to require it only at the configured column
boundary. The model repeatedly toggled the behavior and regressed complexity
from 240 to 175.

The reconciling rule, found in `017267d`, is:

- with explicit `cols:`, `col_last` means the configured final column;
- with default columns, it is also true for the final collection item.

The current implementer guide says only that `col_last` is based on the column
position and explicitly says it is false for an incomplete final row. That is
insufficient for the default-cols behavior encountered by the run. Add two
adjacent, tiny specs contrasting explicit and omitted `cols`, update the guide,
and make both hints state why the results differ.

## CUR-03: Boolean `tablerow` coercion looked contradictory across modes

Lower-complexity cases expected `limit:true` to raise an invalid-integer error,
while a later case expected no error. The model treated this as an impossible
semantic conflict. Commit `bc6f8bc` discovered the missing dimension: strict2
silently coerces/ignores the boolean while warn/strict/lax raise.

Put the mode in the spec name and hint, and introduce a paired strict2 versus
strict lesson before broader coercion matrices. The first failure should tell
the implementer to branch coercion by parse mode rather than change global
integer conversion.

## CUR-04: Boolean-chain semantics were taught as conflicting precedence

Generated cases around complexity 140 led the implementation to conventional
`and`-before-`or` precedence. A manual case around complexity 300 required
Liquid's chain behavior. The implementation oscillated until `d8cd01e`
implemented left-to-right short-circuiting of the entire remaining chain,
which converted 186 failures to passes at once.

Add focused prerequisites for:

1. equal precedence / left-to-right grouping;
2. `and` short-circuit of the remaining chain;
3. `or` short-circuit of the remaining chain;
4. interaction with an invalid expression that proves it was not evaluated.

The rule is too foundational to first emerge from a wide generated matrix.

## CUR-05: The final production recording silently selected the wrong mode

`RecordedTest#test_indirect_variable_lookup` uses bare `[var]` access. It was
recorded from production behavior where the syntax is accepted, but had no
mode annotation and therefore ran using the adapter's strict2 default. Strict2
correctly rejects bare bracket access. The run spent 17 measured attempts at
complexity 800 and repeatedly declared the last failure unresolvable. Commit
`3afef1c` changed the adapter default to strict and immediately reached 1000.

Annotate the recording as lax/strict-compatible, or place it in a suite whose
mode is explicit. More generally, every recording whose parse result differs
by mode must carry an `error_mode`; adapter defaults must not define recorded
semantics.

## CUR-06: Specs should run only in modes the adapter declares

The generated adapter says to implement only strict2 and skip strict/lax/raise,
but unannotated specs still run in whichever default the adapter supplies. This
mixes two concepts: a spec's compatible modes and the implementation's
supported modes.

Add an explicit ordered adapter capability such as:

```ruby
config.error_modes = [:strict2]
```

or:

```ruby
config.error_modes = [:strict2, :strict, :lax]
```

The runner should intersect this list with each spec's compatible modes and
test the intersection in canonical order `strict2`, `strict`, `lax`. A spec
with no annotation should run in each declared supported mode only if its
expected behavior is mode-independent. Mode-dependent specs must be annotated.

## CUR-07: Feature opt-ins create non-monotonic curriculum changes

Enabling drops temporarily moved complexity from 240 to 190, enabling
`ruby_types` moved it to 135, and enabling `ruby_drops` moved it to 125. The
model reasonably explored capabilities but the single headline level made a
more capable implementation look less advanced.

Report a core curriculum level separately from optional-feature coverage. When
a feature is newly enabled, show its own first failing level and do not replace
the already-earned core level with the optional track's score.

## CUR-08: Generated breadth obscured semantic prerequisites

At several plateaus, dozens or hundreds of compatibility cases passed after a
single structural fix: for slicing added 86 passes (`608a1d8`), trailing comma
handling added 20 (`11ae321`), comparison semantics added 19 (`4255712`), and
boolean-chain evaluation added 186 (`d8cd01e`). This is evidence that broad
matrices existed without a small lesson that named the shared abstraction.

For each large generated family, require at least one earlier curated spec with
an actionable hint and `doc:` link explaining the general rule.

## CUR-09: Some hints led to symptom patching

The history contains repeated local fixes to tokenizer delimiters, raw/comment
nesting, whitespace stripping, render/include scope, numeric validation, and
Ruby string conversion. Many were correct but narrowly inferred from one next
failure. Hints should identify whether the rule belongs in tokenization,
parsing, evaluation, scope, conversion, or output serialization. This would
reduce special cases in implementations built by weak agents.

## CUR-10: Reference quirks need portability labels

The run implemented Ruby-specific behaviors such as Integer byte size, Ruby
hash inspection, gsub replacement escapes, bignum/null-byte parsing, float
formatting, and ASCII-only splitting. Some were exercised despite a Python
implementation, while related Ruby features were skipped.

Audit whether each behavior is portable Liquid, liquid-ruby compatibility, or
Shopify production behavior. Tag and document it consistently so an
implementer can deliberately choose conformance rather than infer it from the
next failure.
