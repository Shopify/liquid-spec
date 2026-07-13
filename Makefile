.PHONY: install

# Build the CLI in release mode and install it in Cargo's user bin directory
# (usually ~/.cargo/bin, or $CARGO_HOME/bin when CARGO_HOME is set).
install:
	cargo install --locked --path crates/liquid-spec-cli --bin liquid-spec --force
