---
title: "Filesystem: include and render template lookup"
position: 9
description: "Read when partial lookup fails. Covers source bundles, name normalization, missing templates, recursion, and path-safety decisions without prescribing a host filesystem API."
optional: false
---

# Filesystem: `include` and `render` template lookup

Partials are supplied to a JSON-RPC v2 adapter as entries in the
`template.compile` bundle. The runner does not call a Ruby filesystem object or
ask the adapter to call back into the runner. Your implementation can keep the
sources in a map, use a virtual filesystem, compile them into an artifact, or
use another representation; the observable lookup and error behavior is the
contract.

## Source names and lookup

Each spec's `filesystem` mapping becomes an additional `bundle.sources` entry.
The entry named by `bundle.entry` is the top-level template. Partial names are
resolved against that source map using the normalization rules exercised by the
selected specs:

- A missing `.liquid` extension may be added when the lookup syntax omits it.
- Subpaths use `/` and remain part of the key.
- Case handling, extension handling, and legacy keys are compatibility behavior;
  follow the focused filesystem specs rather than the behavior of the host disk.
- A lookup must not escape the source bundle merely because the name contains `..`.
  Follow the exact traversal behavior recorded by the focused security fixtures;
  do not delegate this decision to host-disk path normalization.

Normalize names at one boundary (for example, when building the source index) and
use the same function for lookup. Preserve the original requested name for errors
so a user can identify the missing partial.

## Compile/render boundary

`template.compile` receives the complete bundle and parse options and must parse or
prepare every supplied source before returning. It may retain a parse failure for
an unused source, but the failure is already determined during compile. `template.render`
receives only a compiled handle, the environment, and render options; it must not
read source text from the request or re-parse the bundle. This boundary is required
for independent compile/render timing in `liquid-spec bench`.

If a syntax error occurs in an unused partial, report it according to the protocol
and the fixture's expected phase. Do not turn a JSON-RPC transport error into a
Liquid parse error, and do not hide a parse error merely because a partial was not
selected in one render.

## `include` and `render`

The two tags share lookup but differ in context semantics. The exact details are
covered by [Partials](partials.md); the high-level invariants are:

| Feature | `include` | `render` |
| --- | --- | --- |
| Template name | May be dynamic where the syntax allows | Quoted literal in the recorded contract |
| Scope | Can read caller values and uses a local assignment scope | Isolated render context with explicit arguments |
| Counters/register-like state | Shared according to the fixture | Isolated according to the fixture |
| Interrupts | May propagate to the caller's loop | Contained by the render boundary |
| Missing source | Typed Liquid error or inline output according to `error_policy` | Same error contract |

Do not infer a scope rule from the host language's call stack. Model the context
boundary explicitly and test nested includes/renders, argument aliases, loop
variants, and assignments that should or should not escape.

## Missing templates and recursion

A missing source is a normal Liquid outcome. Return a typed `LiquidError` with a
stable code, message substring, and source location when the fixture requests
raised errors (`render.options.error_policy = "raise"`). Inline error output is a
separate advertised render mode; do not silently use it as a fallback.

Track partial nesting or active handles so a recursive include/render terminates
with the recorded error instead of exhausting the process stack. Keep any limit
deterministic and report it through the Liquid error contract.

## Test and rollout checklist

1. Start with one source and one literal include.
2. Add extension and subpath normalization, then missing-source errors.
3. Exercise dynamic include names, render argument isolation, and loop variants.
4. Add traversal and recursion cases only after the basic source index is stable.
5. Run the focused namespace and compare with an external reference adapter. The
   Rust runner itself never embeds a Liquid implementation.

See also:

- [Partials](partials.md) for scope and interrupt propagation.
- [Filesystem-related filters](filters.md) for value coercion at filter boundaries.
- [JSON-RPC protocol v2](../json-rpc-protocol-v2.md) for bundle and render shapes.
