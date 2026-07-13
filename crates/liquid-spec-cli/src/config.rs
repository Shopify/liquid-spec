use anyhow::{Context, Result};
use serde::{Deserialize, Serialize};
use std::collections::BTreeMap;
use std::fs;
use std::path::{Path, PathBuf};
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
    /// Append-only JSONL result log.  When omitted, the runner uses
    /// `LIQUID_SPEC_RESULTS` when set and `/tmp/liquid-spec-results.jsonl`
    /// otherwise.
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub results_log: Option<PathBuf>,
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

    /// The bundled Shopify/liquid reference is available even when the caller
    /// has no manifest. A manifest may override this command under the same
    /// adapter name.
    pub fn command_with_builtin_reference(&self, name: &str) -> Option<Vec<String>> {
        self.adapters
            .get(name)
            .map(|adapter| adapter.command.clone())
            .or_else(|| {
                (name == "liquid-ruby").then(|| {
                    vec![
                        "ruby".into(),
                        "@liquid-spec/examples/liquid_ruby_jsonrpc_v2.rb".into(),
                    ]
                })
            })
    }

    pub fn reference_adapter_name(&self) -> &str {
        self.reference_adapter.as_deref().unwrap_or("liquid-ruby")
    }

    pub fn default_action(&self) -> &str {
        self.default_action.as_deref().unwrap_or("check")
    }

    pub fn timeout(&self, name: Option<&str>) -> Duration {
        let name = name.or(self.default_adapter.as_deref());
        Duration::from_millis(
            name.and_then(|name| self.adapters.get(name))
                .map(|adapter| adapter.timeout_ms)
                .unwrap_or_else(|| {
                    if name == Some("liquid-ruby") {
                        60_000
                    } else {
                        default_timeout()
                    }
                }),
        )
    }

    pub fn results_log_path(&self) -> PathBuf {
        self.results_log
            .clone()
            .or_else(|| std::env::var_os("LIQUID_SPEC_RESULTS").map(PathBuf::from))
            .unwrap_or_else(|| PathBuf::from("/tmp/liquid-spec-results.jsonl"))
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

# Bundled Shopify/liquid reference (bundler/inline; no Gemfile required).
# `@liquid-spec/...` resolves to the installed data package or checkout.
[adapters.liquid-ruby]
command = ["ruby", "@liquid-spec/examples/liquid_ruby_jsonrpc_v2.rb"]
timeout_ms = 15000
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

/// Expand `@liquid-spec/...` path tokens against the installed data package or
/// the source checkout. Keeps starter manifests portable across machines.
pub fn expand_command_tokens(command: Vec<String>) -> Result<Vec<String>> {
    command
        .into_iter()
        .map(|part| {
            if let Some(relative) = part.strip_prefix("@liquid-spec/") {
                let path = resolve_package_path(relative)?;
                Ok(path.display().to_string())
            } else {
                Ok(part)
            }
        })
        .collect()
}

fn resolve_package_path(relative: &str) -> Result<PathBuf> {
    let mut candidates = Vec::new();
    for data_dir in installed_data_dirs() {
        candidates.push(data_dir.join(relative));
    }
    if let Ok(cwd) = std::env::current_dir() {
        candidates.push(cwd.join(relative));
    }
    // Source checkout during development (`cargo run` / `cargo test`) only.
    #[cfg(debug_assertions)]
    candidates.push(
        PathBuf::from(env!("CARGO_MANIFEST_DIR"))
            .join("../../")
            .join(relative),
    );
    if let Some(path) = candidates
        .into_iter()
        .find(|path| path.is_file() || path.is_dir())
    {
        return Ok(path);
    }
    anyhow::bail!(
        "could not resolve @liquid-spec/{relative}; run `make install` or set XDG_DATA_HOME"
    )
}

fn installed_data_dirs() -> Vec<PathBuf> {
    let mut dirs = Vec::new();
    if let Some(xdg) = std::env::var_os("XDG_DATA_HOME") {
        dirs.push(PathBuf::from(xdg).join("liquid-spec"));
    }
    if let Some(home) = std::env::var_os("HOME") {
        let home = PathBuf::from(home);
        dirs.push(home.join(".local/share/liquid-spec"));
        dirs.push(home.join("Library/Application Support/liquid-spec"));
    }
    dirs.push(PathBuf::from("/usr/local/share/liquid-spec"));
    dirs.push(PathBuf::from("/usr/share/liquid-spec"));
    dirs
}

#[cfg(test)]
mod tests {
    use super::Config;

    #[test]
    fn starter_manifest_links_bare_invocation_to_candidate_check() {
        let config: Config = toml::from_str(Config::starter_manifest()).unwrap();
        assert_eq!(config.default_action(), "check");
        assert_eq!(config.default_adapter.as_deref(), Some("candidate"));
        assert_eq!(config.reference_adapter.as_deref(), Some("liquid-ruby"));
        assert_eq!(config.adapters["candidate"].command, vec!["./adapter.ts"]);
        assert_eq!(
            config.adapters["liquid-ruby"].command,
            vec!["ruby", "@liquid-spec/examples/liquid_ruby_jsonrpc_v2.rb"]
        );
    }
}
