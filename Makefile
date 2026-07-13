.PHONY: install uninstall

# Destination for the acceptance corpus and other runtime data.
# Override with e.g. `make install DATA_HOME=/usr/local/share`.
DATA_HOME ?= $(if $(XDG_DATA_HOME),$(XDG_DATA_HOME),$(HOME)/.local/share)
DATA_DIR  := $(DATA_HOME)/liquid-spec

# Build the CLI in release mode and install it in Cargo's user bin directory
# (usually ~/.cargo/bin, or $CARGO_HOME/bin when CARGO_HOME is set). Also copy
# the YAML corpus and the reference adapter into the XDG data directory so an
# installed binary can find them outside the source checkout.
install:
	cargo install --locked --path crates/liquid-spec-cli --bin liquid-spec --force
	mkdir -p "$(DATA_DIR)"
	rm -rf "$(DATA_DIR)/specs" "$(DATA_DIR)/examples"
	cp -a specs "$(DATA_DIR)/specs"
	cp -a examples "$(DATA_DIR)/examples"
	@echo "Installed liquid-spec binary via cargo install"
	@echo "Installed specs to $(DATA_DIR)/specs"
	@echo "Installed reference adapter to $(DATA_DIR)/examples"
	@echo "Override with LIQUID_SPEC_ROOT or DATA_HOME=/path make install"

uninstall:
	-cargo uninstall liquid-spec
	rm -rf "$(DATA_DIR)"
	@echo "Removed liquid-spec binary (if present) and $(DATA_DIR)"
