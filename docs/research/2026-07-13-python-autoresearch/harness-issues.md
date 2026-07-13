# Harness and runner issues

## HAR-01: False JSON-RPC options are dropped

The generated adapter ended with this workaround:

```ruby
if options[:strict_errors] == false
  options["strict_errors"] = false
end
```

Commit `440e047` identifies the cause as serialization using a truthiness
fallback equivalent to `false || nil`, which loses the false value. This can
turn inline-error specs into raised-error specs and makes failures look like
implementation defects. Serialize by key presence, not truthiness, and add a
protocol test for `strict_errors: false`.

## HAR-02: Mode support is represented indirectly by missing features

The adapter had to list `:lax_parsing`, `:strict_parsing`, and `:raise_mode` in
`missing_features`, while strict2 was implied by omission and by a compile
default. This is error-prone and cannot express preference/order cleanly.

Introduce an explicit `error_modes` capability. Validate it, expose it in the
JSON-RPC initialize response, and derive legacy feature tags from it during a
deprecation period.

## HAR-03: Unannotated specs inherit mutable adapter semantics

Changing one line in `adapter-jsonrpc.rb` from strict2 to strict changed the
outcome of a production recording and the global score from 800 to 1000. A
conformance spec's meaning should not depend on an arbitrary adapter default.

Resolve a concrete mode in the runner and send it to compile. For truly
mode-independent specs, run once per supported mode or validate equivalence in
the contributor gate. Never send `nil` and let adapters choose silently.

## HAR-04: Array `error_mode` currently has a primary-only execution model

Project policy says the first array element is primary and is used for testing;
the other modes are checked by separate verifiers against the Ruby reference.
That does not demonstrate that a third-party adapter supports all modes it
claims. The run could pass after changing its default without proving the same
specs under every claimed mode.

At execution time, choose each compatible-mode spec's highest compatible strict
mode (`strict2`, then `strict`) and retain an explicitly declared `lax` variant.
Keep results attributable to `(spec, mode)`.

## HAR-05: Complexity hides large progress within a blocked level

At complexity 240, passing specs rose by nearly 600 while the only headline
number remained unchanged. The runner did print total passes, but automated
optimization treated complexity as the sole objective and could not see that
it was making meaningful progress.

Expose a lexicographic machine metric: cleared level first, then number of
failures at the first failing level, then total failures, then passes. Include
the first-failing-level population so a controller can detect approach to a
breakthrough without weakening the contiguous-level definition.

## HAR-06: Result logging is unbounded and highly repetitive

The shared `/tmp/liquid-spec-results.jsonl` reached 4.3 GB in about thirteen
hours because every run appended thousands of per-spec records, including
hundreds of identical confirmation runs. There is no retention, compaction,
or run summary index.

Add rotation or a configurable destination, write a compact run-summary log,
and optionally deduplicate unchanged `(adapter fingerprint, spec corpus,
result set)` runs. Preserve full records only when requested.

## HAR-07: Abnormal exits provide too little crash context

The process logs contain messages such as:

```
Abnormal exit while running spec: TrimModeTest#test_no_trim_output_72174aa3
```

but no subprocess exit status, signal, last protocol request/response, stderr
tail, or reproduction command. Similar exits occurred for cycle, blank, and
trim-mode specs. Add those details and distinguish timeout, EOF, signal, and
invalid JSON.

## HAR-08: Environment warnings swamp useful diagnostics

Every abnormal-exit log repeated warnings about unbuilt Ruby extensions
(`bigdecimal`, `cgi`, `erb`, `io-console`, `json`). These were unrelated to the
Python adapter failure and consumed the small diagnostic surface. Print
environment warnings once per run or behind verbose output.

## HAR-09: Feature discovery is informational but selection is duplicated

The JSON-RPC server reports features at initialize time, yet the generated Ruby
adapter says those features are informational and requires a second manual
`missing_features` list. The two sources can drift. This happened while the run
experimented with drops and parser modes.

Allow initialize capabilities to drive selection, with an adapter-side override
for policy. Report mismatches explicitly.

## HAR-10: Skipped coverage can make “1000/1000” overstate completion

The final result was 4,248 passes and zero failures, but 1,050 specs were
skipped, primarily Shopify and Ruby-specific features. The achievement is real
for the selected capability set, yet the headline alone reads like universal
Liquid completion.

Include the capability profile in machine and human success summaries and use
phrasing such as “1000/1000 for declared features.”
