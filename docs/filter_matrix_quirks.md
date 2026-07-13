# Generated filter-matrix behavior

`specs/liquid_ruby/standard_filters.yml` is a broad compatibility matrix. Each filter is
exercised across many input types (strings, integers, floats, booleans, nil, arrays,
hashes, fixtures, and dates). The matrix is intentionally later than the curated beginner
namespace because failures are often caused by shared value/coercion rules rather than by
the named filter itself.

The YAML is generated from the pinned reference corpus in this repository. Treat the
checked-in YAML and its hints as the source of truth for an adapter run; contributors who
regenerate it should use the repository's generation task and review the resulting diff.
The Rust runner does not require Ruby or a generation task at runtime.

## 1. Date / Time rendering

Filters that receive a `Date` or `Time` (e.g. `escape`, `capitalize`, `append`) must first
render the date to its Liquid string form before applying. Liquid renders `Date` as
`YYYY-MM-DD` (e.g. `2001-02-03`) and `Time` as `YYYY-MM-DD HH:MM:SS %z` (UTC under the
frozen test time `2024-01-01 00:01:58 UTC`).

- `{{ d | escape }}` with `d = 2001-02-03` → `2001-02-03` (escape of a date string is a
  no-op; the work is in the date→string step).
- A filter that stringifies its input (e.g. `append`) must use the date string, not the
  raw object.

**Check:** does your implementation render `Date`/`Time` to the correct string *before*
the filter sees it?

## 2. Float formatting and precision

The reference outputs floats using a shortest round-trip representation with its recorded
integer/decimal distinction. Match the expected representation for the selected feature
set rather than delegating blindly to a host language formatter.

- `0.0` renders as `0.0` (not `0` and not `0.00`).
- `0.1 + 0.5` (e.g. via `plus`) renders as `0.6`.
- Integer-valued float results keep the `.0` (`4.0` → `4.0`, not `4`).

**Check:** does your number rendering preserve the float/integer distinction and match
the expected output in the neighboring specs?

## 3. Type coercion of inputs

Generated inputs deliberately mix types. A filter's behavior depends on the *coerced*
input type, not the surface type:

- `abs` of `true` → `0` (booleans coerce to 0/1, then abs).
- `first` / `last` on a coerced string or array.
- `contains` / `has` with type-mismatched operands → `false` (no implicit conversion).

**Check:** are you coercing operands the way Liquid does (boolean→0/1, string→chars for
`first`/`last`, strict `contains` equality) before applying the filter?

## 4. nil / empty handling

- Most filters pass `nil` through as `""` (empty string), not `"nil"`.
- `nil | size` → `0`. `nil | first` → `""`.
- Empty array/string inputs produce empty or zero outputs, not errors.

**Check:** does every filter treat `nil` as empty-string (or the filter-specific empty
value) rather than erroring or stringifying `nil`?

## 5. Drops and Ruby objects (ruby_drops / ruby_types)

Inputs may be standard fixtures or Ruby-compatibility values. These specs are tagged
`drops`, `ruby_drops`, or `ruby_types` according to the value they exercise. JSON-RPC
adapters can advertise only the feature sets they support; skipped compatibility tracks
must not change the semantics of portable filters.

- A drop input must have `to_liquid` / `to_s` called before the filter applies.
- Hash-inspect outputs (`{"k"=>"v"}`) are Ruby-compatibility behavior — see
  [`ruby_hash_inspect_format.md`](ruby_hash_inspect_format.md).

## When to add a spec-level hint

The file-level `_metadata.hint` (above) points here. A *spec-level* `hint:` is useful when
a case exercises a rule not covered by the categories above. Keep the hint with the
checked-in spec or the generator's source data, depending on how that corpus is maintained;
the runner displays it but does not infer implementation strategy from it.
