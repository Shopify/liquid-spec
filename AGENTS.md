# liquid-spec (Rust)

This tree is the Rust rewrite of liquid-spec. There is no Ruby gem surface here.

## Layout

- `crates/liquid-spec-cli` — CLI binary (`liquid-spec`) and test server
- `crates/liquid-spec-core` — YAML corpus loading and namespace discovery
- `crates/liquid-spec-protocol` — JSON-RPC v2 types and conformance vectors
- `specs/` — acceptance corpus (YAML)
- `docs/` — implementer guides (embedded into the CLI)

## Commands

```bash
cargo test --workspace --locked
cargo run -p liquid-spec-cli -- tools check
cargo run -p liquid-spec-cli -- protocol -- target/debug/liquid-spec-test-server
make install   # binary + ~/.local/share/liquid-spec/specs
```

## Specs at runtime

Installed binaries find the corpus under `$XDG_DATA_HOME/liquid-spec/specs`
(or `~/.local/share/liquid-spec/specs`). From a checkout, `specs/` next to the
workspace root is used automatically. Override with `LIQUID_SPEC_ROOT`.

## Adapter boundary

Adapters are external newline-delimited JSON-RPC v2 processes. See
`liquid-spec docs protocol` and `docs/json-rpc-protocol-v2.md`.
