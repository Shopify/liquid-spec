use anyhow::{Context, Result};
use serde::{Deserialize, Serialize};
use std::collections::BTreeMap;
use std::fs;
use std::path::Path;
use std::time::Duration;

#[derive(Clone, Debug, Default, Deserialize, Serialize)]
pub struct Config {
    /// Action used when `liquid-spec` is invoked without a subcommand.
    /// The starter manifest sets this to `check`; explicit CLI subcommands
    /// always take precedence.
    #[serde(default, rename = "default", skip_serializing_if = "Option::is_none")]
    pub default_action: Option<String>,
    pub default_adapter: Option<String>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub reference_adapter: Option<String>,
    #[serde(default)]
    pub adapters: BTreeMap<String, Adapter>,
}

#[derive(Clone, Debug, Deserialize, Serialize)]
pub struct Adapter {
    pub command: Vec<String>,
    #[serde(default = "default_timeout")]
    pub timeout_ms: u64,
}

fn default_timeout() -> u64 {
    2_000
}

impl Config {
    pub fn load(path: &Path) -> Result<Self> {
        toml::from_str(&fs::read_to_string(path)?)
            .with_context(|| format!("parse {}", path.display()))
    }

    pub fn command(&self, name: Option<&str>) -> Option<&Vec<String>> {
        let name = name.or(self.default_adapter.as_deref())?;
        self.adapters.get(name).map(|adapter| &adapter.command)
    }

    pub fn default_action(&self) -> &str {
        self.default_action.as_deref().unwrap_or("check")
    }

    pub fn timeout(&self, name: Option<&str>) -> Duration {
        let name = name.or(self.default_adapter.as_deref());
        Duration::from_millis(
            name.and_then(|name| self.adapters.get(name))
                .map_or(default_timeout(), |a| a.timeout_ms),
        )
    }

    /// The smallest useful manifest for a new JSON-RPC adapter. Keeping this
    /// in Rust (rather than shelling out to a generator) makes `init` work for
    /// a downloaded binary and gives callers a stable, editable file.
    pub fn starter_manifest() -> &'static str {
        r#"# liquid-spec v2 adapter manifest
# All adapters speak newline-delimited JSON-RPC 2.0 (protocol version 2).
# With no subcommand, `liquid-spec` follows this action link.
default = "check"
default_adapter = "candidate"
reference_adapter = "liquid-ruby"

[adapters.candidate]
command = ["./adapter.ts"]
timeout_ms = 2000

# Optional Shopify/liquid reference adapter. It is only started by --compare.
[adapters.liquid-ruby]
command = ["bundle", "exec", "ruby", "examples/liquid_ruby_jsonrpc_v2.rb"]
timeout_ms = 5000
"#
    }

    pub fn write_starter(path: &Path, force: bool) -> Result<bool> {
        if path.exists() && !force {
            return Ok(false);
        }
        fs::write(path, Self::starter_manifest())
            .with_context(|| format!("write {}", path.display()))?;
        Ok(true)
    }
}

#[cfg(test)]
mod tests {
    use super::Config;

    #[test]
    fn starter_manifest_links_bare_invocation_to_candidate_check() {
        let config: Config = toml::from_str(Config::starter_manifest()).unwrap();
        assert_eq!(config.default_action(), "check");
        assert_eq!(config.default_adapter.as_deref(), Some("candidate"));
        assert_eq!(config.adapters["candidate"].command, vec!["./adapter.ts"]);
    }
}
