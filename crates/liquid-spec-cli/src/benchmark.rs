use anyhow::{Context, Result, bail};
use liquid_spec_core::{discover_namespaces, load_namespace};
use liquid_spec_protocol::{BenchmarkResult, Capabilities};
use regex::RegexBuilder;
use serde::Serialize;
use std::path::Path;

use crate::config::Config;
use crate::session::Session;

/// Execute a benchmark namespace through the adapter-owned benchmark-v1
/// extension.  Parsing/compilation happens in a separate request; render
/// measurements always use a precompiled handle.
#[allow(clippy::too_many_arguments)]
pub fn run(
    config: &Config,
    adapter: Option<&str>,
    direct: Vec<String>,
    root: &Path,
    namespace: &str,
    name: Option<&str>,
    iterations: u32,
    json: bool,
) -> Result<()> {
    let namespaces = discover_namespaces(root)?;
    let namespace = namespaces
        .iter()
        .find(|candidate| candidate.id == namespace)
        .with_context(|| format!("unknown benchmark namespace {namespace:?}"))?;
    if !namespace.timings {
        bail!("namespace {namespace:?} is not marked timings: true");
    }
    let matcher = name
        .map(RegexBuilder::new)
        .map(|mut builder| builder.case_insensitive(true).build())
        .transpose()?;
    let specs = load_namespace(namespace)?
        .into_iter()
        .filter(|spec| matcher.as_ref().is_none_or(|m| m.is_match(&spec.name)))
        .collect::<Vec<_>>();
    if specs.is_empty() {
        bail!("no benchmark specs matched");
    }

    let command = if !direct.is_empty() {
        direct
    } else {
        config
            .command(adapter)
            .map(ToOwned::to_owned)
            .context("no adapter command: configure liquid-spec.toml or pass it after --")?
    };
    let mut session = Session::spawn(&command, config.timeout(adapter))?;
    let info = session.conformance()?;
    require_benchmark_capability(&info.capabilities)?;
    let mut report = BenchmarkSummary::default();

    for spec in specs {
        let case = (|| -> Result<BenchmarkCase> {
            let compile = session.benchmark_compile(
                spec.bundle.clone(),
                spec.compile_options.clone(),
                iterations,
            )?;
            let template_id =
                session.compile_template(spec.bundle.clone(), spec.compile_options.clone())?;
            let render = session.benchmark_render(
                template_id.clone(),
                spec.environment.clone(),
                spec.render_options.clone(),
                iterations,
            )?;
            session.release_template(template_id)?;
            let artifact = compile
                .artifact
                .clone()
                .map(|artifact| session.benchmark_artifact(artifact, iterations))
                .transpose()?;
            Ok(BenchmarkCase {
                name: spec.name.clone(),
                complexity: spec.complexity,
                compile,
                render,
                artifact,
            })
        })();
        match case {
            Ok(case) => {
                report.passed += 1;
                report.cases.push(case);
            }
            Err(error) => {
                report.failed += 1;
                report.failures.push(BenchmarkFailure {
                    name: spec.name,
                    complexity: spec.complexity,
                    message: error.to_string(),
                });
            }
        }
    }
    session.shutdown()?;

    if json {
        println!("{}", serde_json::to_string_pretty(&report)?);
    } else {
        report.print();
    }
    if report.failed > 0 {
        bail!("{} benchmark(s) failed", report.failed);
    }
    Ok(())
}

fn require_benchmark_capability(capabilities: &Capabilities) -> Result<()> {
    if !capabilities.benchmark {
        bail!("adapter does not advertise benchmark-v1 capability");
    }
    Ok(())
}

#[derive(Default, Serialize)]
pub struct BenchmarkSummary {
    pub passed: usize,
    pub failed: usize,
    pub cases: Vec<BenchmarkCase>,
    pub failures: Vec<BenchmarkFailure>,
}

#[derive(Serialize)]
pub struct BenchmarkCase {
    pub name: String,
    pub complexity: u16,
    pub compile: BenchmarkResult,
    pub render: BenchmarkResult,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub artifact: Option<BenchmarkResult>,
}

#[derive(Serialize)]
pub struct BenchmarkFailure {
    pub name: String,
    pub complexity: u16,
    pub message: String,
}

impl BenchmarkSummary {
    fn print(&self) {
        println!("Benchmark-v1 results:\n");
        for case in &self.cases {
            println!(
                "[c={}] {} — compile {} ns/op, render {} ns/op",
                case.complexity,
                case.name,
                ns_per_op(&case.compile),
                ns_per_op(&case.render),
            );
            if let Some(artifact) = &case.artifact {
                println!("          artifact load {} ns/op", ns_per_op(artifact));
            }
        }
        for failure in &self.failures {
            println!(
                "[c={}] {} — FAILED: {}",
                failure.complexity, failure.name, failure.message
            );
        }
        println!("\n{} passed, {} failed.", self.passed, self.failed);
    }
}

fn ns_per_op(result: &BenchmarkResult) -> u64 {
    let iterations = result.iterations.max(1) as u128;
    (result.total_elapsed_ns() / iterations).min(u128::from(u64::MAX)) as u64
}
