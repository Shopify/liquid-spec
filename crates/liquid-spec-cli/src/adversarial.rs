use anyhow::{Context, Result};
use liquid_spec_core::{Spec, discover_namespaces, load_namespace};
use regex::RegexBuilder;
use std::path::Path;

use crate::config::Config;
use crate::session::Session;

#[derive(Clone, Copy)]
pub enum Mode {
    Mutate,
    Fuzz,
    Stress,
}

/// Run deterministic, bounded generated probes.  These are intentionally
/// corpus-level tools rather than coverage-guided fuzzers: every generated
/// case is a normal JSON-RPC compile/render request and can be promoted to a
/// YAML regression once a difference is found.
#[allow(clippy::too_many_arguments)]
pub fn run(
    mode: Mode,
    config: &Config,
    adapter: Option<&str>,
    direct: Vec<String>,
    root: &Path,
    namespace: &str,
    around: Option<&str>,
    limit: usize,
    seed: u64,
    rounds: usize,
    depth: usize,
    repetitions: usize,
    json: bool,
) -> Result<()> {
    let namespaces = discover_namespaces(root)?;
    let namespace = namespaces
        .iter()
        .find(|candidate| candidate.id == namespace)
        .with_context(|| format!("unknown namespace {namespace:?}"))?;
    let matcher = around
        .map(RegexBuilder::new)
        .map(|mut builder| builder.case_insensitive(true).build())
        .transpose()?;
    let base: Vec<_> = load_namespace(namespace)?
        .into_iter()
        .filter(|spec| matcher.as_ref().is_none_or(|m| m.is_match(&spec.name)))
        .take(limit.max(1))
        .collect();
    let specs = match mode {
        Mode::Mutate => mutate_specs(base),
        Mode::Fuzz => fuzz_specs(seed, rounds.max(1)),
        Mode::Stress => stress_specs(depth.max(1), repetitions.max(1)),
    };
    let command = if direct.is_empty() {
        config
            .command(adapter)
            .cloned()
            .context("no adapter command: configure liquid-spec.toml or pass it after --")?
    } else {
        direct
    };
    let mut session = Session::spawn(&command, config.timeout(adapter))?;
    let info = session.conformance()?;
    let summary = session.run_specs(specs, &info.capabilities)?;
    session.shutdown()?;
    if json {
        println!("{}", serde_json::to_string_pretty(&summary)?);
    } else {
        summary.print_with(false);
    }
    if summary.failed > 0 {
        anyhow::bail!("generated probes found {} failure(s)", summary.failed);
    }
    Ok(())
}

fn mutate_specs(mut specs: Vec<Spec>) -> Vec<Spec> {
    for spec in &mut specs {
        // A comment is semantically inert, so the original expected output
        // remains valid while the parser/block handling is exercised.
        let suffix = "{% comment %}liquid-spec mutation{% endcomment %}";
        if let Some(source) = spec.bundle.sources.get_mut(&spec.bundle.entry) {
            source.push_str(suffix);
        }
        spec.name = format!("{} [mutation: comment]", spec.name);
    }
    specs
}

fn fuzz_specs(seed: u64, rounds: usize) -> Vec<Spec> {
    (0..rounds)
        .map(|round| {
            let value = lcg(seed.wrapping_add(round as u64)) % 1_000_000;
            let text = format!("liquid-spec-fuzz-{value}");
            Spec {
                name: format!("fuzz-{round}"),
                bundle: liquid_spec_protocol::TemplateBundle {
                    entry: "main".into(),
                    sources: [("main".into(), text.clone())].into_iter().collect(),
                },
                environment: Default::default(),
                expected: liquid_spec_core::Expected::Output(text.into_bytes()),
                complexity: 0,
                hint: Some("Generated literal probe; promote interesting cases to a spec.".into()),
                doc: None,
                features: ["core".into()].into_iter().collect(),
                compile_options: Default::default(),
                render_options: Default::default(),
                source_file: "<fuzz>".into(),
            }
        })
        .collect()
}

fn stress_specs(depth: usize, repetitions: usize) -> Vec<Spec> {
    let mut body = String::new();
    for _ in 0..depth.min(256) {
        body.push_str("{% if true %}");
    }
    body.push_str("stress");
    for _ in 0..depth.min(256) {
        body.push_str("{% endif %}");
    }
    (0..repetitions.min(256))
        .map(|index| Spec {
            name: format!("stress-{index}"),
            bundle: liquid_spec_protocol::TemplateBundle {
                entry: "main".into(),
                sources: [("main".into(), body.clone())].into_iter().collect(),
            },
            environment: Default::default(),
            expected: liquid_spec_core::Expected::Output(b"stress".to_vec()),
            complexity: 500,
            hint: Some("Generated bounded nesting probe.".into()),
            doc: None,
            features: ["core".into()].into_iter().collect(),
            compile_options: Default::default(),
            render_options: Default::default(),
            source_file: "<stress>".into(),
        })
        .collect()
}

fn lcg(mut value: u64) -> u64 {
    value = value.wrapping_mul(6364136223846793005).wrapping_add(1);
    value ^ (value >> 33)
}
