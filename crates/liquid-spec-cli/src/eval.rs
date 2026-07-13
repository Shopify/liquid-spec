use anyhow::{Context, Result, bail};
use liquid_spec_core::{Namespace, NamespaceDefaults, load_specs_yaml};
use serde::Serialize;
use std::collections::BTreeSet;
use std::fs;
use std::io::{self, Read};
use std::path::{Path, PathBuf};

use crate::config::Config;
use crate::session::{RunSummary, Session};

/// Evaluate ad-hoc YAML specs against one JSON-RPC adapter and, optionally,
/// the configured reference adapter. Returns whether the candidate and
/// comparison both matched; callers map a mismatch to the normal test exit
/// status instead of treating it as a CLI/configuration error.
pub fn run(
    config: &Config,
    adapter: Option<&str>,
    direct: Vec<String>,
    spec_path: Option<&Path>,
    compare: bool,
    json: bool,
) -> Result<bool> {
    let (content, source) = read_source(spec_path)?;
    let namespace = eval_namespace(&source);
    let specs = load_specs_yaml(&content, &source, &namespace)?;
    if specs.is_empty() {
        bail!("spec input did not contain any specs");
    }

    let command = resolve_command(config, adapter, direct)?;
    let mut candidate = Session::spawn(&command, config.timeout(adapter))?;
    let candidate_info = candidate.conformance()?;
    let candidate_summary = candidate.run_specs(specs.clone(), &candidate_info.capabilities)?;
    candidate.shutdown()?;

    let reference_summary = if compare {
        let reference_name = config
            .reference_adapter
            .as_deref()
            .context("--compare requires reference_adapter in liquid-spec.toml")?;
        let reference_command = config
            .command(Some(reference_name))
            .cloned()
            .with_context(|| format!("reference adapter {reference_name:?} is not configured"))?;
        let mut reference =
            Session::spawn(&reference_command, config.timeout(Some(reference_name)))?;
        let reference_info = reference.conformance()?;
        let summary = reference.run_specs(specs, &reference_info.capabilities)?;
        reference.shutdown()?;
        Some(summary)
    } else {
        None
    };

    let equivalent = reference_summary
        .as_ref()
        .is_none_or(|reference| summaries_match(&candidate_summary, reference));
    let result = EvalResult {
        candidate: candidate_summary,
        reference: reference_summary,
        equivalent,
    };
    if json {
        println!("{}", serde_json::to_string(&result)?);
    } else {
        result.print(compare);
    }
    Ok(result.equivalent && result.candidate.failed == 0)
}

fn read_source(path: Option<&Path>) -> Result<(String, PathBuf)> {
    match path {
        Some(path) => Ok((
            fs::read_to_string(path).with_context(|| format!("read spec {}", path.display()))?,
            path.to_path_buf(),
        )),
        None => {
            let mut content = String::new();
            io::stdin()
                .read_to_string(&mut content)
                .context("read spec YAML from stdin")?;
            Ok((content, PathBuf::from("<stdin>")))
        }
    }
}

fn eval_namespace(source: &Path) -> Namespace {
    Namespace {
        id: "eval".into(),
        name: "Ad-hoc evaluation".into(),
        description: "A YAML spec supplied to tools eval".into(),
        path: source
            .parent()
            .unwrap_or_else(|| Path::new("."))
            .to_path_buf(),
        default: false,
        timings: false,
        features: BTreeSet::new(),
        minimum_complexity: 1000,
        default_iteration_seconds: 5.0,
        defaults: NamespaceDefaults::default(),
    }
}

fn resolve_command(
    config: &Config,
    adapter: Option<&str>,
    direct: Vec<String>,
) -> Result<Vec<String>> {
    if !direct.is_empty() {
        return Ok(direct);
    }
    config
        .command(adapter)
        .cloned()
        .context("no adapter command: configure liquid-spec.toml or pass it after --")
}

fn summaries_match(candidate: &RunSummary, reference: &RunSummary) -> bool {
    let candidate_failures: std::collections::BTreeMap<_, _> = candidate
        .failures
        .iter()
        .map(|failure| (failure.name.as_str(), failure.message.as_str()))
        .collect();
    let reference_failures: std::collections::BTreeMap<_, _> = reference
        .failures
        .iter()
        .map(|failure| (failure.name.as_str(), failure.message.as_str()))
        .collect();
    candidate_failures == reference_failures && candidate.skipped == reference.skipped
}

#[derive(Serialize)]
struct EvalResult {
    candidate: RunSummary,
    #[serde(skip_serializing_if = "Option::is_none")]
    reference: Option<RunSummary>,
    equivalent: bool,
}

impl EvalResult {
    fn print(&self, compare: bool) {
        println!("Candidate:");
        self.candidate.print();
        if let Some(reference) = &self.reference {
            println!("\nReference:");
            reference.print();
            if !self.equivalent {
                println!("\nComparison differences:");
                let candidate: std::collections::BTreeMap<_, _> = self
                    .candidate
                    .failures
                    .iter()
                    .map(|failure| (failure.name.as_str(), failure.message.as_str()))
                    .collect();
                let reference_failures: std::collections::BTreeMap<_, _> = reference
                    .failures
                    .iter()
                    .map(|failure| (failure.name.as_str(), failure.message.as_str()))
                    .collect();
                for name in candidate
                    .keys()
                    .filter(|name| !reference_failures.contains_key(*name))
                {
                    println!("  candidate differs: {name}");
                }
                for name in reference_failures
                    .keys()
                    .filter(|name| !candidate.contains_key(*name))
                {
                    println!("  reference differs: {name}");
                }
                for name in candidate
                    .keys()
                    .filter(|name| reference_failures.get(*name) != candidate.get(*name))
                    .filter(|name| reference_failures.contains_key(*name))
                {
                    println!("  error differs: {name}");
                }
                if self.candidate.skipped != reference.skipped {
                    // The exact skipped counts are printed by each summary;
                    // avoid duplicating a potentially confusing failure list.
                    println!(
                        "  skipped differs: candidate {}, reference {}",
                        self.candidate.skipped, reference.skipped
                    );
                }
            }
        } else if compare {
            println!("Comparison was requested but no reference result was produced.");
        }
    }
}
