mod adversarial;
mod benchmark;
mod config;
mod docs;
mod eval;
mod report;
mod session;

use anyhow::{Context, Result};
use clap::{CommandFactory, Parser, Subcommand};
use config::Config;
use liquid_spec_core::{
    Namespace, NamespaceDefaults, discover_namespaces, load_namespace, load_specs_yaml,
};
use session::Session;
use std::ffi::OsString;
use std::path::PathBuf;

#[derive(Parser)]
#[command(
    name = "liquid-spec",
    version,
    about = "Build and verify Liquid implementations",
    disable_help_subcommand = true,
    after_help = "Without a subcommand, liquid-spec follows `default` in liquid-spec.toml (normally check against the default adapter). Check flags may be supplied directly."
)]
struct Cli {
    #[arg(long, global = true, default_value = "liquid-spec.toml")]
    config: PathBuf,
    #[command(subcommand)]
    command: Option<Command>,
}

#[derive(Subcommand)]
enum Command {
    /// Show the top-level command list.
    Help,
    /// Create a JSON-RPC adapter manifest and implementation guide.
    Init {
        /// Directory in which to create liquid-spec.toml and AGENTS.md.
        #[arg(value_name = "DIRECTORY", default_value = ".")]
        directory: PathBuf,
        /// Replace files that already exist.
        #[arg(long)]
        force: bool,
    },
    /// Print implementation guides bundled with liquid-spec.
    Docs {
        /// Topic name (omit, or use `list`, to list topics).
        topic: Option<String>,
    },
    /// Run protocol checks (kept as a short top-level alias).
    #[command(hide = true)]
    Protocol {
        #[arg(long)]
        adapter: Option<String>,
        #[arg(last = true)]
        command: Vec<String>,
    },
    /// Inspection and contributor tools.
    Tools {
        #[command(subcommand)]
        command: ToolCommand,
    },
    /// Check an implementation against the acceptance ramp.
    #[command(name = "check", visible_alias = "run")]
    Check {
        #[arg(long)]
        adapter: Option<String>,
        #[arg(short = 's', long = "namespace", default_value = "all")]
        namespace: String,
        #[arg(short = 'n', long)]
        name: Option<String>,
        #[arg(short = 'l', long)]
        list: bool,
        #[arg(long)]
        list_namespaces: bool,
        #[arg(long)]
        json: bool,
        /// Emit one JSON event per spec and a final summary event.
        #[arg(long)]
        jsonl: bool,
        /// Print the names of specs that passed.
        #[arg(long)]
        list_passed: bool,
        /// File containing known failure names, one per line.
        #[arg(long)]
        known_failures: Option<PathBuf>,
        /// Add standalone YAML specs (repeat the flag for multiple files).
        #[arg(long = "spec", visible_alias = "add-specs")]
        additional_specs: Vec<PathBuf>,
        #[arg(short = 'c', long)]
        compare: bool,
        #[arg(last = true)]
        command: Vec<String>,
    },
    /// Run server-side benchmark-v1 measurements.
    Bench {
        #[arg(long)]
        adapter: Option<String>,
        #[arg(short = 's', long = "namespace", default_value = "benchmarks")]
        namespace: String,
        #[arg(short = 'n', long)]
        name: Option<String>,
        #[arg(long, default_value_t = 100)]
        iterations: u32,
        #[arg(long)]
        json: bool,
        #[arg(last = true)]
        command: Vec<String>,
    },
}

#[derive(Subcommand)]
#[command(disable_help_subcommand = true)]
enum ToolCommand {
    /// Show the tools command list.
    Help,
    /// Test adapter protocol conformance.
    Protocol {
        #[arg(long)]
        adapter: Option<String>,
        #[arg(last = true)]
        command: Vec<String>,
    },
    /// List or print built-in implementation documentation.
    Docs { topic: Option<String> },
    /// List feature tags present in the built-in corpus.
    Features,
    /// Validate that every built-in namespace and spec can be loaded.
    Check,
    /// Run selected specs and show their detailed failure context.
    Inspect {
        #[arg(long)]
        adapter: Option<String>,
        #[arg(short = 's', long = "namespace", default_value = "basics")]
        namespace: String,
        #[arg(short = 'n', long)]
        name: String,
        #[arg(last = true)]
        command: Vec<String>,
    },
    /// Run the same selected specs against multiple configured adapters.
    Matrix {
        /// Adapter names to include (repeat the flag for multiple adapters).
        #[arg(
            short = 'a',
            long = "adapter",
            visible_alias = "adapters",
            value_delimiter = ',',
            value_name = "NAME"
        )]
        adapters: Vec<String>,
        /// Include every adapter in liquid-spec.toml.
        #[arg(long)]
        all: bool,
        #[arg(short = 's', long = "namespace", default_value = "basics")]
        namespace: String,
        #[arg(short = 'n', long)]
        name: Option<String>,
        #[arg(long)]
        json: bool,
    },
    /// Evaluate a YAML spec from a file or stdin.
    Eval {
        #[arg(long, value_name = "FILE")]
        spec: Option<PathBuf>,
        #[arg(long)]
        adapter: Option<String>,
        #[arg(short = 'c', long)]
        compare: bool,
        #[arg(long)]
        json: bool,
        #[arg(last = true)]
        command: Vec<String>,
    },
    /// Summarize the JSONL result log from prior runs.
    Report {
        #[arg(long, value_name = "FILE")]
        input: Option<PathBuf>,
        #[arg(long)]
        json: bool,
    },
    /// Run every configured adapter (an alias for `matrix --all`).
    Test {
        #[arg(short = 's', long = "namespace", default_value = "basics")]
        namespace: String,
        #[arg(short = 'n', long)]
        name: Option<String>,
        #[arg(long)]
        json: bool,
    },
    /// Deterministically mutate selected corpus specs.
    Mutate {
        #[arg(long)]
        adapter: Option<String>,
        #[arg(long = "namespace", default_value = "basics")]
        namespace: String,
        #[arg(long)]
        around: Option<String>,
        #[arg(long, default_value_t = 100)]
        limit: usize,
        #[arg(long)]
        json: bool,
        #[arg(last = true)]
        command: Vec<String>,
    },
    /// Run seeded, bounded generated probes.
    Fuzz {
        #[arg(long)]
        adapter: Option<String>,
        #[arg(long, default_value_t = 1)]
        seed: u64,
        #[arg(long, default_value_t = 100)]
        rounds: usize,
        #[arg(long)]
        json: bool,
        #[arg(last = true)]
        command: Vec<String>,
    },
    /// Run bounded nesting/repetition stress probes.
    Stress {
        #[arg(long)]
        adapter: Option<String>,
        #[arg(long, default_value_t = 64)]
        depth: usize,
        #[arg(long, default_value_t = 1)]
        repetitions: usize,
        #[arg(long)]
        json: bool,
        #[arg(last = true)]
        command: Vec<String>,
    },
}

fn main() {
    if let Err(error) = execute() {
        eprintln!("Error: {error:#}");
        std::process::exit(2);
    }
}

fn execute() -> Result<()> {
    let cli = Cli::parse_from(normalize_default_invocation());
    let config = if matches!(
        cli.command.as_ref(),
        Some(Command::Init { .. } | Command::Docs { .. })
    ) {
        Config::default()
    } else if cli.config.is_file() {
        Config::load(&cli.config)?
    } else {
        Config::default()
    };
    let command = match cli.command {
        Some(command) => command,
        None if cli.config.is_file() => default_command(&config)?,
        None => Command::Help,
    };
    match command {
        Command::Help => {
            println!("{}", Cli::command().render_help());
        }
        Command::Init { directory, force } => init(&directory, force)?,
        Command::Docs { topic } => docs::print(topic.as_deref())?,
        Command::Protocol { adapter, command } => {
            run_protocol(&config, adapter, command)?;
        }
        Command::Tools { command } => match command {
            ToolCommand::Help => print_tools_help(),
            ToolCommand::Protocol { adapter, command } => {
                run_protocol(&config, adapter, command)?;
            }
            ToolCommand::Docs { topic } => docs::print(topic.as_deref())?,
            ToolCommand::Features => print_features()?,
            ToolCommand::Check => check_corpus()?,
            ToolCommand::Inspect {
                adapter,
                namespace,
                name,
                command,
            } => {
                let specs = load_selected_specs(&builtin_spec_root(), &namespace, Some(&name))?;
                if specs.is_empty() {
                    anyhow::bail!("no specs matched {name:?}");
                }
                let command = resolve_command(&config, adapter.as_deref(), command)?;
                let mut session = Session::spawn(&command, config.timeout(adapter.as_deref()))?;
                let info = session.conformance()?;
                let summary = session.run_specs(specs, &info.capabilities)?;
                summary.print();
                session.shutdown()?;
                if summary.failed > 0 {
                    std::process::exit(1);
                }
            }
            ToolCommand::Matrix {
                adapters,
                all,
                namespace,
                name,
                json,
            } => run_matrix(&config, adapters, all, &namespace, name.as_deref(), json)?,
            ToolCommand::Eval {
                spec,
                adapter,
                compare,
                json,
                command,
            } => {
                let success = eval::run(
                    &config,
                    adapter.as_deref(),
                    command,
                    spec.as_deref(),
                    compare,
                    json,
                )?;
                if !success {
                    std::process::exit(1);
                }
            }
            ToolCommand::Report { input, json } => report::run(input.as_deref(), json)?,
            ToolCommand::Test {
                namespace,
                name,
                json,
            } => {
                run_matrix(&config, Vec::new(), true, &namespace, name.as_deref(), json)?;
            }
            ToolCommand::Mutate {
                adapter,
                namespace,
                around,
                limit,
                json,
                command,
            } => adversarial::run(
                adversarial::Mode::Mutate,
                &config,
                adapter.as_deref(),
                command,
                &builtin_spec_root(),
                &namespace,
                around.as_deref(),
                limit,
                1,
                1,
                1,
                1,
                json,
            )?,
            ToolCommand::Fuzz {
                adapter,
                seed,
                rounds,
                json,
                command,
            } => adversarial::run(
                adversarial::Mode::Fuzz,
                &config,
                adapter.as_deref(),
                command,
                &builtin_spec_root(),
                "basics",
                None,
                rounds,
                seed,
                rounds,
                1,
                1,
                json,
            )?,
            ToolCommand::Stress {
                adapter,
                depth,
                repetitions,
                json,
                command,
            } => adversarial::run(
                adversarial::Mode::Stress,
                &config,
                adapter.as_deref(),
                command,
                &builtin_spec_root(),
                "basics",
                None,
                repetitions,
                1,
                1,
                depth,
                repetitions,
                json,
            )?,
        },
        Command::Check {
            adapter,
            namespace,
            name,
            list,
            list_namespaces,
            json,
            jsonl,
            list_passed,
            known_failures,
            additional_specs,
            compare,
            command,
        } => {
            let root = builtin_spec_root();
            let namespaces = discover_available_namespaces(&root)?;
            if list_namespaces {
                for item in &namespaces {
                    println!(
                        "{}{} — {}",
                        item.id,
                        if item.default { " (default)" } else { "" },
                        item.description
                    );
                }
                return Ok(());
            }
            let selected: Vec<_> = if namespace == "all" {
                namespaces.iter().filter(|s| s.default).collect()
            } else {
                vec![
                    namespaces
                        .iter()
                        .find(|s| s.id == namespace)
                        .with_context(|| format!("unknown namespace {namespace:?}"))?,
                ]
            };
            let matcher = name
                .as_deref()
                .map(regex::RegexBuilder::new)
                .map(|mut builder| builder.case_insensitive(true).build())
                .transpose()?;
            let mut specs = Vec::new();
            for selected_namespace in selected {
                specs.extend(
                    load_namespace(selected_namespace)?
                        .into_iter()
                        .filter(|spec| matcher.as_ref().is_none_or(|m| m.is_match(&spec.name))),
                );
            }
            specs.extend(
                load_additional_specs(&additional_specs)?
                    .into_iter()
                    .filter(|spec| matcher.as_ref().is_none_or(|m| m.is_match(&spec.name))),
            );
            if list {
                for spec in specs {
                    println!("[c={}] {}", spec.complexity, spec.name);
                }
                return Ok(());
            }
            let command = resolve_command(&config, adapter.as_deref(), command)?;
            let mut session = Session::spawn(&command, config.timeout(adapter.as_deref()))?;
            let info = session.conformance()?;
            let compare_specs = specs.clone();
            let mut summary = session.run_specs(specs, &info.capabilities)?;
            let report_path = write_check_report(&summary)?;
            summary.all_failures_path = Some(report_path.clone());
            let candidate_failures: std::collections::BTreeMap<_, _> = summary
                .failures
                .iter()
                .map(|failure| (failure.name.clone(), failure.message.clone()))
                .collect();
            if jsonl {
                for failure in &summary.failures {
                    println!(
                        "{}",
                        serde_json::to_string(&serde_json::json!({
                            "name": failure.name,
                            "complexity": failure.complexity,
                            "status": "fail",
                            "message": failure.message,
                        }))?
                    );
                }
                for name in &summary.passed_names {
                    println!(
                        "{}",
                        serde_json::to_string(&serde_json::json!({
                            "name": name,
                            "status": "success",
                        }))?
                    );
                }
                println!("{}", serde_json::to_string(&summary)?);
            } else if json {
                println!("{}", serde_json::to_string(&summary)?);
            } else {
                summary.print_with(list_passed);
                println!("[all failures in {}]", report_path.display());
            }
            let known = load_known_failures(known_failures.as_deref())?;
            let known_failed = summary
                .failures
                .iter()
                .filter(|failure| known.contains(&failure.name))
                .count();
            let known_fixed = known
                .iter()
                .filter(|name| {
                    !summary
                        .failures
                        .iter()
                        .any(|failure| &failure.name == *name)
                })
                .count();
            if !known.is_empty() && !json && !jsonl {
                println!("Known failures: {known_failed}, fixed: {known_fixed}");
            }
            session.shutdown()?;
            if compare {
                let reference = config
                    .reference_adapter
                    .as_deref()
                    .context("--compare requires reference_adapter in liquid-spec.toml")?;
                let reference_command =
                    config.command(Some(reference)).cloned().with_context(|| {
                        format!("reference adapter {:?} is not configured", reference)
                    })?;
                let mut reference_session =
                    Session::spawn(&reference_command, config.timeout(Some(reference)))?;
                let reference_info = reference_session.conformance()?;
                let reference_summary =
                    reference_session.run_specs(compare_specs, &reference_info.capabilities)?;
                let reference_failures: std::collections::BTreeMap<_, _> = reference_summary
                    .failures
                    .iter()
                    .map(|failure| (failure.name.clone(), failure.message.clone()))
                    .collect();
                reference_session.shutdown()?;
                if candidate_failures != reference_failures
                    || summary.skipped != reference_summary.skipped
                {
                    println!("Comparison differences:");
                    for name in candidate_failures
                        .keys()
                        .filter(|name| !reference_failures.contains_key(*name))
                    {
                        println!("  candidate differs: {name}");
                    }
                    for name in reference_failures
                        .keys()
                        .filter(|name| !candidate_failures.contains_key(*name))
                    {
                        println!("  reference differs: {name}");
                    }
                    for name in candidate_failures
                        .keys()
                        .filter(|name| {
                            reference_failures.get(*name) != candidate_failures.get(*name)
                        })
                        .filter(|name| reference_failures.contains_key(*name))
                    {
                        println!("  error differs: {name}");
                    }
                    if summary.skipped != reference_summary.skipped {
                        println!(
                            "  skipped differs: candidate {}, reference {}",
                            summary.skipped, reference_summary.skipped
                        );
                    }
                }
            }
        }
        Command::Bench {
            adapter,
            namespace,
            name,
            iterations,
            json,
            command,
        } => {
            benchmark::run(
                &config,
                adapter.as_deref(),
                command,
                &builtin_spec_root(),
                &namespace,
                name.as_deref(),
                iterations,
                json,
            )?;
        }
    }
    Ok(())
}

/// Let a manifest-backed directory accept check options without repeating the
/// subcommand: `liquid-spec -n assign` is equivalent to
/// `liquid-spec check -n assign`. Explicit subcommands and top-level help/version
/// remain untouched.
fn normalize_default_invocation() -> Vec<OsString> {
    let args: Vec<OsString> = std::env::args_os().collect();
    let rest = &args[1..];
    if rest.is_empty() || has_explicit_command(rest) || requests_top_level_help(rest) {
        return args;
    }
    if rest
        .iter()
        .any(|arg| arg.to_string_lossy().starts_with('-'))
    {
        let mut normalized = Vec::with_capacity(args.len() + 1);
        normalized.push(args[0].clone());
        normalized.push(OsString::from("check"));
        normalized.extend_from_slice(rest);
        normalized
    } else {
        args
    }
}

fn has_explicit_command(args: &[OsString]) -> bool {
    let commands = [
        "help", "init", "docs", "protocol", "tools", "check", "run", "bench",
    ];
    let mut skip_next = false;
    for arg in args {
        let value = arg.to_string_lossy();
        if skip_next {
            skip_next = false;
            continue;
        }
        if value == "--config" {
            skip_next = true;
            continue;
        }
        if value.starts_with("--config=") || value.starts_with('-') {
            continue;
        }
        return commands.contains(&value.as_ref());
    }
    false
}

fn requests_top_level_help(args: &[OsString]) -> bool {
    args.iter().any(|arg| {
        matches!(
            arg.to_string_lossy().as_ref(),
            "-h" | "--help" | "-V" | "--version"
        )
    })
}

fn load_selected_specs(
    root: &std::path::Path,
    namespace: &str,
    name: Option<&str>,
) -> Result<Vec<liquid_spec_core::Spec>> {
    let namespaces = discover_available_namespaces(root)?;
    let selected: Vec<_> = if namespace == "all" {
        namespaces
            .iter()
            .filter(|candidate| candidate.default)
            .collect()
    } else {
        vec![
            namespaces
                .iter()
                .find(|candidate| candidate.id == namespace)
                .with_context(|| format!("unknown namespace {:?}", namespace))?,
        ]
    };
    let matcher = name
        .map(regex::RegexBuilder::new)
        .map(|mut builder| builder.case_insensitive(true).build())
        .transpose()?;
    let mut specs = Vec::new();
    for selected_namespace in selected {
        specs.extend(
            load_namespace(selected_namespace)?
                .into_iter()
                .filter(|spec| matcher.as_ref().is_none_or(|m| m.is_match(&spec.name))),
        );
    }
    Ok(specs)
}

fn default_command(config: &Config) -> Result<Command> {
    match config.default_action().trim().to_ascii_lowercase().as_str() {
        "check" | "run" => Ok(Command::Check {
            adapter: None,
            namespace: "all".into(),
            name: None,
            list: false,
            list_namespaces: false,
            json: false,
            jsonl: false,
            list_passed: false,
            known_failures: None,
            additional_specs: Vec::new(),
            compare: false,
            command: Vec::new(),
        }),
        "protocol" => Ok(Command::Protocol {
            adapter: None,
            command: Vec::new(),
        }),
        "bench" => Ok(Command::Bench {
            adapter: None,
            namespace: "benchmarks".into(),
            name: None,
            iterations: 100,
            json: false,
            command: Vec::new(),
        }),
        "help" => Ok(Command::Help),
        action => anyhow::bail!(
            "unknown default action {action:?}; use default = \"check\", \"protocol\", \"bench\", or \"help\""
        ),
    }
}

fn print_features() -> Result<()> {
    let mut counts = std::collections::BTreeMap::<String, usize>::new();
    for namespace in discover_available_namespaces(&builtin_spec_root())? {
        for spec in load_namespace(&namespace)? {
            for feature in spec.features {
                *counts.entry(feature).or_default() += 1;
            }
        }
    }
    println!("Feature inventory:\n");
    for (feature, count) in counts {
        println!("  {feature:<32} {count}");
    }
    Ok(())
}

fn check_corpus() -> Result<()> {
    let mut namespaces_count = 0;
    let mut specs_count = 0;
    for namespace in discover_available_namespaces(&builtin_spec_root())? {
        namespaces_count += 1;
        let specs = load_namespace(&namespace)?;
        for spec in &specs {
            if spec.complexity > 1000 {
                anyhow::bail!("{} exceeds complexity 1000", spec.name);
            }
            if spec.name.trim().is_empty() {
                anyhow::bail!("spec with empty name in {}", spec.source_file.display());
            }
        }
        specs_count += specs.len();
    }
    println!("OK: loaded {specs_count} specs across {namespaces_count} namespaces");
    Ok(())
}

fn run_protocol(config: &Config, adapter: Option<String>, direct: Vec<String>) -> Result<()> {
    let command = resolve_command(config, adapter.as_deref(), direct)?;
    let mut session = Session::spawn(&command, config.timeout(adapter.as_deref()))?;
    let report = session.conformance()?;
    println!(
        "Protocol v2: OK — {} {}",
        report.implementation.name, report.implementation.version
    );
    session.shutdown()?;
    Ok(())
}

#[derive(serde::Serialize)]
struct MatrixRow {
    adapter: String,
    status: &'static str,
    passed: usize,
    failed: usize,
    skipped: usize,
    #[serde(skip_serializing_if = "Option::is_none")]
    error: Option<String>,
}

fn run_matrix(
    config: &Config,
    requested: Vec<String>,
    all: bool,
    namespace: &str,
    name: Option<&str>,
    json: bool,
) -> Result<()> {
    let adapter_names = matrix_adapter_names(config, requested, all)?;
    let specs = load_selected_specs(&builtin_spec_root(), namespace, name)?;
    if specs.is_empty() {
        anyhow::bail!("no specs matched the selected namespace/name")
    }

    let mut rows = Vec::with_capacity(adapter_names.len());
    for adapter in adapter_names {
        let row = match config.command(Some(&adapter)) {
            None => MatrixRow {
                adapter,
                status: "error",
                passed: 0,
                failed: 0,
                skipped: 0,
                error: Some("adapter is not configured".into()),
            },
            Some(command) => {
                match run_matrix_adapter(command, config.timeout(Some(&adapter)), specs.clone()) {
                    Ok(summary) => MatrixRow {
                        adapter,
                        status: if summary.failed == 0 { "pass" } else { "fail" },
                        passed: summary.passed,
                        failed: summary.failed,
                        skipped: summary.skipped,
                        error: None,
                    },
                    Err(error) => MatrixRow {
                        adapter,
                        status: "error",
                        passed: 0,
                        failed: 0,
                        skipped: 0,
                        error: Some(error.to_string()),
                    },
                }
            }
        };
        rows.push(row);
    }

    if json {
        println!("{}", serde_json::to_string_pretty(&rows)?);
    } else {
        println!("Adapter matrix ({})", namespace);
        println!(
            "{:<24} {:<7} {:>7} {:>7} {:>7}",
            "adapter", "status", "passed", "failed", "skipped"
        );
        for row in &rows {
            println!(
                "{:<24} {:<7} {:>7} {:>7} {:>7}",
                row.adapter, row.status, row.passed, row.failed, row.skipped
            );
            if let Some(error) = &row.error {
                println!("  error: {error}");
            }
        }
    }
    if rows.iter().any(|row| row.status != "pass") {
        std::process::exit(1);
    }
    Ok(())
}

fn matrix_adapter_names(config: &Config, requested: Vec<String>, all: bool) -> Result<Vec<String>> {
    let adapter_names = if all {
        config.adapters.keys().cloned().collect::<Vec<_>>()
    } else {
        requested
    };
    if adapter_names.is_empty() {
        anyhow::bail!("tools matrix requires at least one adapter; use --adapter NAME or --all")
    }
    Ok(adapter_names)
}

fn run_matrix_adapter(
    command: &[String],
    timeout: std::time::Duration,
    specs: Vec<liquid_spec_core::Spec>,
) -> Result<session::RunSummary> {
    let mut session = Session::spawn(command, timeout)?;
    let info = session.conformance()?;
    let summary = session.run_specs(specs, &info.capabilities)?;
    session.shutdown()?;
    Ok(summary)
}

fn init(directory: &std::path::Path, force: bool) -> Result<()> {
    std::fs::create_dir_all(directory)
        .with_context(|| format!("create init directory {}", directory.display()))?;
    let config_path = directory.join("liquid-spec.toml");
    let agents_path = directory.join("AGENTS.md");
    let adapter_path = directory.join("adapter.ts");
    let config_written = Config::write_starter(&config_path, force)?;
    let agents_written = write_agents(&agents_path, force)?;
    let adapter_written = write_adapter(&adapter_path, force)?;
    if config_written {
        println!("created {}", config_path.display());
    } else {
        println!("kept {} (use --force to replace)", config_path.display());
    }
    if agents_written {
        println!("created {}", agents_path.display());
    } else {
        println!("kept {} (use --force to replace)", agents_path.display());
    }
    if adapter_written {
        println!("created {}", adapter_path.display());
    } else {
        println!("kept {} (use --force to replace)", adapter_path.display());
    }
    Ok(())
}

fn print_tools_help() {
    let mut command = Cli::command();
    if let Some(tools) = command.find_subcommand_mut("tools") {
        println!("{}", tools.render_help());
    }
}

fn write_agents(path: &std::path::Path, force: bool) -> Result<bool> {
    if path.exists() && !force {
        return Ok(false);
    }
    std::fs::write(path, STARTER_AGENTS).with_context(|| format!("write {}", path.display()))?;
    Ok(true)
}

fn write_adapter(path: &std::path::Path, force: bool) -> Result<bool> {
    if path.exists() && !force {
        return Ok(false);
    }
    std::fs::write(path, STARTER_ADAPTER_TS)
        .with_context(|| format!("write {}", path.display()))?;
    #[cfg(unix)]
    {
        use std::os::unix::fs::PermissionsExt;
        let mut permissions = std::fs::metadata(path)?.permissions();
        permissions.set_mode(0o755);
        std::fs::set_permissions(path, permissions)
            .with_context(|| format!("make {} executable", path.display()))?;
    }
    Ok(true)
}

const STARTER_AGENTS: &str = r#"# Implementing Liquid with liquid-spec

This project uses the Rust `liquid-spec` runner. Every implementation is an external
newline-delimited JSON-RPC adapter (protocol v2); there is no in-process adapter API.

## Loop

1. Run `liquid-spec` (the manifest's `default = "check"` points at candidate), or
   use `liquid-spec check --adapter candidate` explicitly.
2. Read the lowest-complexity failure and its hint.
3. Implement the general Liquid behavior in your library, then rerun earlier specs.
4. Run `liquid-spec tools protocol --adapter candidate` after changing the adapter.
5. Compare configured implementations with `liquid-spec tools matrix --all -n assign`.

`check` evaluates the full selected corpus. Once the protocol gate succeeds, Liquid
spec mismatches are observational and the command exits 0; protocol or adapter-process
failures still exit nonzero. Every check overwrites a deterministic report in `/tmp`
containing all PASS and FAIL entries ordered by complexity; human output prints its
location as `[all failures in ...]`. `run` is retained only as a compatibility alias.
Use `--namespace NAME` (or `-s NAME`) for a directory under `specs/`; there is no
separate grouping concept in the Rust runner.

Read a guide with `liquid-spec docs curriculum` or `liquid-spec docs json-rpc-protocol-v2`.
The manifest in `liquid-spec.toml` names the candidate and optional Shopify/liquid
reference adapters. Add a command as an array so arguments are never shell-parsed.

The adapter must complete `initialize`, `protocol.echo`, `template.compile`,
`template.render`, and `template.release`; send diagnostics to stderr and JSON-RPC
responses only to stdout. Advertise only capabilities that are actually implemented.
Standard fixture drops are language-neutral and selected through typed fixture values;
Ruby callback drops are intentionally not part of protocol v2.

`init` also creates `adapter.ts`, a fully documented source-echo server that is
deliberately useful as a protocol smoke test but not a Liquid implementation. Replace
its compile/render store with your parser and renderer while preserving the wire
contract. The starter manifest runs its executable shebang: `./adapter.ts`, which
invokes Node with `--experimental-strip-types`. If your Node version predates that
flag, replace the command with `npx tsx adapter.ts`.
"#;

const STARTER_ADAPTER_TS: &str = r##"#!/usr/bin/env -S node --experimental-strip-types
/**
 * liquid-spec JSON-RPC v2 demo adapter.
 *
 * This file is intentionally a complete, dependency-light protocol server rather
 * than a fake Liquid implementation. It echoes the source supplied to
 * template.compile from template.render, which gives a new implementation a useful
 * first milestone: `liquid-spec protocol --adapter candidate` passes while the
 * acceptance check reports the first semantic failures. Replace the compile/render
 * store with your parser, AST, bytecode, or VM without changing the JSON-RPC shell.
 *
 * Run it directly on Node versions with built-in type stripping:
 *
 *   ./adapter.ts
 *
 * Node versions without built-in type stripping can use:
 *
 *   npx tsx adapter.ts
 *
 * stdout is reserved for one JSON-RPC response per request. Put diagnostics on
 * stderr. The runner starts a fresh process for each check, so this example keeps
 * handles in memory and does not need persistence.
 *
 * Required lifecycle methods:
 *   initialize       negotiate protocol and advertise capabilities
 *   protocol.echo    prove typed JSON values survive the transport
 *   template.compile parse all sources and return an opaque handle
 *   template.render  render an existing handle (never parse here)
 *   template.release release an opaque handle
 *   shutdown         notification; no response is allowed
 *
 * Liquid parse/render failures belong in a successful JSON-RPC result as
 * { error: LiquidError }. JSON-RPC errors are reserved for malformed requests,
 * unknown methods, and invalid handles. The source-echo behavior below has no
 * semantic errors yet, so it only returns successful Liquid outcomes.
 */

import * as readline from "node:readline";

const JSON_RPC = "2.0";
const PROTOCOL_VERSION = "2";

type JsonObject = Record<string, unknown>;

type JsonRpcRequest = {
  jsonrpc: string;
  id?: number;
  method: string;
  params?: unknown;
};

type JsonRpcResponse = {
  jsonrpc: string;
  id: number;
  result?: unknown;
  error?: { code: number; message: string; data?: unknown };
};

type CompiledTemplate = {
  entry: string;
  sources: Record<string, string>;
};

const templates = new Map<string, CompiledTemplate>();
let nextTemplateId = 0;

function isObject(value: unknown): value is JsonObject {
  return typeof value === "object" && value !== null && !Array.isArray(value);
}

function response(id: number, result: unknown): JsonRpcResponse {
  return { jsonrpc: JSON_RPC, id, result };
}

function rpcError(id: number, code: number, message: string): JsonRpcResponse {
  return { jsonrpc: JSON_RPC, id, error: { code, message } };
}

function write(message: JsonRpcResponse): void {
  process.stdout.write(`${JSON.stringify(message)}\n`);
}

function invalidParams(id: number, message: string): JsonRpcResponse {
  return rpcError(id, -32602, message);
}

function initialize(id: number): JsonRpcResponse {
  return response(id, {
    protocol_version: PROTOCOL_VERSION,
    implementation: {
      name: "liquid-spec-typescript-demo",
      version: "0.1.0",
      language: "typescript",
    },
    capabilities: {
      // Add parse modes only after your parser implements their semantics.
      parse_modes: ["strict2"],
      features: ["core"],
      fixture_sets: {},
      artifacts: false,
      benchmark: false,
    },
  });
}

function compile(id: number, params: unknown): JsonRpcResponse {
  if (!isObject(params)) return invalidParams(id, "compile params must be an object");
  const bundle = params.bundle;
  if (!isObject(bundle)) return invalidParams(id, "compile requires bundle");
  const entry = bundle.entry;
  const sources = bundle.sources;
  if (typeof entry !== "string" || !isObject(sources)) {
    return invalidParams(id, "compile requires bundle.entry and bundle.sources");
  }
  const sourceMap: Record<string, string> = {};
  for (const [name, source] of Object.entries(sources)) {
    if (typeof source !== "string") return invalidParams(id, `source ${name} must be a string`);
    sourceMap[name] = source;
  }
  if (!(entry in sourceMap)) return invalidParams(id, `unknown entry template ${entry}`);

  // Replace this source copy with parsing/compilation. Parse every source here,
  // including partials, so render and benchmark requests never parse source.
  const templateId = `template-${++nextTemplateId}`;
  templates.set(templateId, { entry, sources: sourceMap });
  return response(id, { ok: { template_id: templateId } });
}

function render(id: number, params: unknown): JsonRpcResponse {
  if (!isObject(params)) return invalidParams(id, "render params must be an object");
  const templateId = params.template_id;
  if (typeof templateId !== "string") return invalidParams(id, "render requires template_id");
  const compiled = templates.get(templateId);
  if (!compiled) return invalidParams(id, `unknown template_id ${templateId}`);

  // Replace this lookup with evaluation of the precompiled representation. The
  // render request intentionally receives only a handle and runtime environment.
  const output = compiled.sources[compiled.entry];
  return response(id, { ok: { output, diagnostics: [] } });
}

function release(id: number, params: unknown): JsonRpcResponse {
  if (!isObject(params) || typeof params.template_id !== "string") {
    return invalidParams(id, "release requires template_id");
  }
  if (!templates.delete(params.template_id)) {
    return invalidParams(id, `unknown template_id ${params.template_id}`);
  }
  return response(id, { ok: {} });
}

function dispatch(request: JsonRpcRequest): JsonRpcResponse | null {
  // shutdown is a notification. Do not emit a response for it.
  if (request.method === "shutdown" && request.id === undefined) {
    process.exit(0);
  }
  if (typeof request.id !== "number") return null;
  if (request.jsonrpc !== JSON_RPC || typeof request.method !== "string") {
    return rpcError(request.id, -32600, "invalid JSON-RPC request");
  }

  switch (request.method) {
    case "initialize":
      return initialize(request.id);
    case "protocol.echo":
      // Returning params unchanged is the transport conformance test.
      return response(request.id, request.params ?? {});
    case "template.compile":
      return compile(request.id, request.params);
    case "template.render":
      return render(request.id, request.params);
    case "template.release":
      return release(request.id, request.params);
    default:
      return rpcError(request.id, -32601, `method not found: ${request.method}`);
  }
}

const input = readline.createInterface({ input: process.stdin, crlfDelay: Infinity });
for await (const line of input) {
  if (line.trim() === "") continue;
  try {
    const request = JSON.parse(line) as JsonRpcRequest;
    const result = dispatch(request);
    if (result !== null) write(result);
  } catch (error) {
    // A malformed JSON line has no reliable request id. JSON-RPC uses null for
    // this parse-error response; the Rust runner treats it as a protocol error.
    process.stdout.write(
      `${JSON.stringify({ jsonrpc: JSON_RPC, id: null, error: { code: -32700, message: String(error) } })}\n`,
    );
  }
}
"##;

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
        .map(ToOwned::to_owned)
        .context("no adapter command: configure liquid-spec.toml or pass it after --")
}

fn load_known_failures(
    path: Option<&std::path::Path>,
) -> Result<std::collections::BTreeSet<String>> {
    let Some(path) = path else {
        return Ok(std::collections::BTreeSet::new());
    };
    let content = std::fs::read_to_string(path)
        .with_context(|| format!("read known failures {}", path.display()))?;
    Ok(content
        .lines()
        .map(str::trim)
        .filter(|line| !line.is_empty() && !line.starts_with('#'))
        .map(ToOwned::to_owned)
        .collect())
}

fn load_additional_specs(paths: &[PathBuf]) -> Result<Vec<liquid_spec_core::Spec>> {
    let namespace = Namespace {
        id: "additional".into(),
        name: "Additional specs".into(),
        description: "Standalone YAML specs supplied on the command line".into(),
        path: PathBuf::from("."),
        default: false,
        timings: false,
        features: Default::default(),
        minimum_complexity: 1000,
        default_iteration_seconds: 5.0,
        defaults: NamespaceDefaults::default(),
    };
    let mut specs = Vec::new();
    for path in paths {
        let content = std::fs::read_to_string(path)
            .with_context(|| format!("read additional spec {}", path.display()))?;
        specs.extend(load_specs_yaml(&content, path, &namespace)?);
    }
    Ok(specs)
}

fn write_check_report(summary: &session::RunSummary) -> Result<PathBuf> {
    use std::fmt::Write;
    let cwd = std::env::current_dir().unwrap_or_else(|_| PathBuf::from("."));
    let hash = stable_path_hash(cwd.to_string_lossy().as_bytes());
    let path = std::env::temp_dir().join(format!("liquid-spec-check-{hash:016x}.txt"));
    let mut records = Vec::with_capacity(summary.passed_entries.len() + summary.failures.len());
    for (name, complexity) in &summary.passed_entries {
        records.push((
            *complexity,
            name.clone(),
            "PASS",
            String::new(),
            String::new(),
        ));
    }
    for failure in &summary.failures {
        records.push((
            failure.complexity,
            failure.name.clone(),
            "FAIL",
            failure.source.display().to_string(),
            failure.message.clone(),
        ));
    }
    records.sort_by(|left, right| {
        left.0
            .cmp(&right.0)
            .then_with(|| left.1.cmp(&right.1))
            .then_with(|| left.2.cmp(right.2))
    });
    let mut contents = String::new();
    writeln!(contents, "# liquid-spec check report").unwrap();
    writeln!(contents, "# working_directory: {}", cwd.display()).unwrap();
    for (complexity, name, status, source, message) in records {
        if status == "PASS" {
            writeln!(contents, "PASS [c={complexity}] {name}").unwrap();
        } else {
            writeln!(contents, "FAIL [c={complexity}] {name}").unwrap();
            writeln!(contents, "  source: {source}").unwrap();
            writeln!(contents, "  error: {message}").unwrap();
        }
    }
    std::fs::write(&path, contents)
        .with_context(|| format!("write check report {}", path.display()))?;
    Ok(path)
}

fn stable_path_hash(bytes: &[u8]) -> u64 {
    // FNV-1a is tiny, deterministic across platforms, and avoids adding a
    // cryptographic dependency merely to derive a report filename.
    let mut hash = 0xcbf29ce484222325_u64;
    for byte in bytes {
        hash ^= u64::from(*byte);
        hash = hash.wrapping_mul(0x100000001b3);
    }
    hash
}

fn builtin_spec_root() -> PathBuf {
    if let Some(root) = std::env::var_os("LIQUID_SPEC_ROOT") {
        return PathBuf::from(root);
    }
    let candidates = [
        PathBuf::from(env!("CARGO_MANIFEST_DIR")).join("../../specs"),
        std::env::current_dir()
            .unwrap_or_else(|_| PathBuf::from("."))
            .join("specs"),
        std::env::current_exe()
            .ok()
            .and_then(|path| path.parent().map(|parent| parent.join("specs")))
            .unwrap_or_else(|| PathBuf::from("specs")),
    ];
    candidates
        .into_iter()
        .find(|candidate| candidate.is_dir())
        .unwrap_or_else(|| PathBuf::from("specs"))
}

/// Built-in namespaces remain the default corpus, while a project-local
/// `./specs` directory can add namespaces without copying built-ins.
fn discover_available_namespaces(
    root: &std::path::Path,
) -> Result<Vec<liquid_spec_core::Namespace>> {
    let mut namespaces = discover_namespaces(root)?;
    let local = PathBuf::from("specs");
    if local.is_dir() && local != root {
        let existing: std::collections::BTreeSet<_> = namespaces
            .iter()
            .map(|namespace| namespace.id.clone())
            .collect();
        namespaces.extend(
            discover_namespaces(&local)?
                .into_iter()
                .filter(|namespace| !existing.contains(&namespace.id)),
        );
        namespaces.sort_by(|left, right| left.id.cmp(&right.id));
    }
    Ok(namespaces)
}

#[cfg(test)]
mod tests {
    use super::*;
    use config::Adapter;

    fn config_with_adapters() -> Config {
        Config {
            default_action: Some("check".into()),
            default_adapter: Some("candidate".into()),
            reference_adapter: None,
            adapters: [
                (
                    "candidate".into(),
                    Adapter {
                        command: vec!["candidate".into()],
                        timeout_ms: 100,
                    },
                ),
                (
                    "reference".into(),
                    Adapter {
                        command: vec!["reference".into()],
                        timeout_ms: 100,
                    },
                ),
            ]
            .into_iter()
            .collect(),
        }
    }

    #[test]
    fn matrix_requires_explicit_selection() {
        let error = matrix_adapter_names(&config_with_adapters(), Vec::new(), false)
            .expect_err("matrix should require --adapter or --all");
        assert!(error.to_string().contains("--adapter NAME or --all"));
    }

    #[test]
    fn matrix_all_is_deterministic_and_explicit_names_are_preserved() {
        let config = config_with_adapters();
        assert_eq!(
            matrix_adapter_names(&config, Vec::new(), true).unwrap(),
            vec!["candidate", "reference"]
        );
        assert_eq!(
            matrix_adapter_names(&config, vec!["reference".into()], false).unwrap(),
            vec!["reference"]
        );
    }

    #[test]
    fn check_report_orders_every_result_by_complexity() {
        let mut summary = session::RunSummary::default();
        summary.passed_entries = vec![("late_pass".into(), 30), ("early_pass".into(), 1)];
        summary.failures = vec![session::Failure {
            name: "middle_failure".into(),
            complexity: 10,
            source: "specs/example.yml".into(),
            message: "expected output".into(),
            hint: None,
        }];

        let path = write_check_report(&summary).expect("write check report");
        let report = std::fs::read_to_string(&path).expect("read check report");
        let results: Vec<_> = report
            .lines()
            .filter(|line| line.starts_with("PASS ") || line.starts_with("FAIL "))
            .collect();
        assert_eq!(
            results,
            vec![
                "PASS [c=1] early_pass",
                "FAIL [c=10] middle_failure",
                "PASS [c=30] late_pass",
            ]
        );
        std::fs::remove_file(path).expect("remove check report");
    }
}
