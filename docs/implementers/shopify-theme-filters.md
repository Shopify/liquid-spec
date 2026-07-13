---
title: "Shopify Theme Filters"
position: 40
description: "Read when targeting Shopify themes. Describes the extension boundary, observable filter contracts, and pagination state without prescribing a language or class layout."
optional: true
---

# Shopify Theme Filters

Shopify theme behavior is an optional extension of Liquid. The core corpus and the
default benchmark do not require it. Enable the Shopify namespaces only after the
core parser, value model, scopes, filters, and partials are reliable.

This page is a contract guide, not a drop-in implementation. The JSON-RPC adapter
may expose filters through a registry, a compiler table, a VM instruction, or any
other design. What matters is the behavior recorded by the tagged specs and the
way your implementation handles values at the extension boundary.

## Find the contract first

The Shopify examples are recordings rather than a general Shopify API. Before
implementing a filter:

1. Locate the specs tagged `shopify_filters`, `shopify_tags`, or the relevant
   Shopify feature.
2. Read the complete fixture: template, environment, filesystem, expected output,
   and error mode. Several filters depend on the shape of the supplied object.
3. Implement the smallest general rule that explains all nearby examples.
4. Run the focused namespace and then a matrix comparison against the configured
   reference adapter. Keep the reference process outside your adapter; protocol v2
   has no callbacks for asking the runner to resolve Ruby objects.

Do not infer a production URL, currency, shop identifier, or HTML policy from an
isolated example. If the recording contains a placeholder or fixture-specific value,
preserve it as data and avoid hard-coding it into filter dispatch.

## Filter families

The current recordings cover several families. They exercise coercion and output
formatting as much as the filter names themselves:

| Family | Questions to settle in the value model |
| --- | --- |
| Money and weight | Which numeric units are accepted? How are nil, fractions, rounding, and signs represented? |
| Image and asset URLs | Which input shapes expose a source URL? How are size variants, missing values, and path components handled? |
| HTML helpers | Which attributes are escaped, and is the output intentionally marked as HTML or just a string? |
| Handles and pluralization | What normalization is applied to Unicode, punctuation, and count values? |
| Pagination helpers | Which fields are optional, how are links and current pages represented, and how is HTML escaped? |

Treat each family as ordinary filter semantics layered on top of your existing
argument evaluation and stringification rules. In particular:

- Evaluate arguments before dispatching the filter, including property lookups and
  drops/fixtures.
- Apply the same nil, boolean, numeric, and string coercion rules used by core
  filters unless the spec explicitly records an extension-specific difference.
- Escape untrusted values at the point where the extension creates HTML. Do not
  escape a value twice merely because it passed through another filter.
- Keep URL construction deterministic. A test process must not depend on a live
  Shopify endpoint, wall clock, random number, or machine-specific path.
- Return a normal Liquid error for invalid arguments when the fixture expects an
  error; do not turn a malformed value into a plausible URL or empty page silently.

## Pagination is state, not only formatting

The `{% paginate ... by N %}` tag combines collection slicing with a scoped
`paginate` value. An implementation needs to define these observable steps:

1. Resolve the collection using normal Liquid lookup and determine its size.
2. Read the current page from the render context (or the recorded default).
3. Compute the offset and the page slice without mutating the caller's collection.
4. Expose the page metadata only inside the block's scope.
5. Render the block with the sliced collection, then restore the previous scope.
6. Build `previous`, `next`, and page parts according to the recorded fixtures,
   including gaps and the current-page marker.

The `default_pagination` filter consumes that metadata and produces HTML. Keep the
metadata model separate from the HTML formatter so a theme can provide another
formatter without changing pagination arithmetic. Verify boundary cases explicitly:
empty collections, one page, first/middle/last pages, a page beyond the end, and
missing optional URLs.

## Capability and rollout

Advertise Shopify capabilities only when the adapter implements their semantics.
An adapter can advertise core protocol support while omitting `shopify_filters` and
`shopify_tags`; the runner will skip those specs and still provide useful progress.
When adding a new extension, add a focused first-contact spec, a useful hint, and a
feature tag before adding broad recordings. This keeps the implementation ramp
diagnostic rather than rewarding a special case for one theme.

See also:

- [Filters](filters.md) for shared coercion and dispatch rules.
- [Partials](partials.md) for scope and filesystem behavior used by themes.
- [JSON-RPC protocol v2](../json-rpc-protocol-v2.md) for adapter capabilities.
