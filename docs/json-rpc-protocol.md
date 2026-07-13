# JSON-RPC adapter protocol

The Rust rewrite uses [JSON-RPC protocol v2](json-rpc-protocol-v2.md) exclusively.
This filename is retained as a stable link for existing guides. Protocol v1's
`compile`/`render` callbacks and `_rpc_drop` values are not accepted by v2; use the
versioned standard fixture values described in the v2 document instead.

See the [v2 schema](json-rpc-protocol-v2.schema.json) and
[conformance vectors](json-rpc-protocol-v2-vectors.json) when implementing an
adapter.
