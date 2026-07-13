use anyhow::{Context, Result, bail};
use liquid_spec_core::{ErrorPattern, Expected, Spec};
use liquid_spec_protocol::*;
use regex::Regex;
use serde::{Deserialize, Serialize};
use serde_json::{Value, json};
use std::error::Error as StdError;
use std::fmt::{Display, Formatter};
use std::io::{BufRead, BufReader, Write};
use std::process::{Child, ChildStdin, ChildStdout, Command, Stdio};
use std::sync::mpsc;
use std::thread;
use std::time::Duration;

pub struct Session {
    child: Child,
    input: ChildStdin,
    responses: mpsc::Receiver<Result<String, String>>,
    next_id: u64,
    timeout: Duration,
}

/// Marks a request/transport failure while evaluating a spec.  Semantic
/// mismatches are recorded in the run summary (and intentionally do not make
/// `check` fail), but an adapter that stops speaking JSON-RPC is a protocol
/// failure and must still propagate to the command boundary.
#[derive(Debug)]
struct ProtocolFailure(anyhow::Error);

impl Display for ProtocolFailure {
    fn fmt(&self, formatter: &mut Formatter<'_>) -> std::fmt::Result {
        self.0.fmt(formatter)
    }
}

impl StdError for ProtocolFailure {
    fn source(&self) -> Option<&(dyn StdError + 'static)> {
        self.0.source()
    }
}

impl Session {
    pub fn spawn(command: &[String], timeout: Duration) -> Result<Self> {
        let (program, args) = command.split_first().context("adapter command is empty")?;
        let mut child = Command::new(program)
            .args(args)
            .stdin(Stdio::piped())
            .stdout(Stdio::piped())
            .stderr(Stdio::inherit())
            .spawn()
            .with_context(|| format!("start adapter {program:?}"))?;
        let input = child.stdin.take().unwrap();
        let output = child.stdout.take().unwrap();
        let (sender, responses) = mpsc::channel();
        thread::spawn(move || read_responses(output, sender));
        Ok(Self {
            child,
            input,
            responses,
            next_id: 0,
            timeout,
        })
    }

    fn response<P: Serialize>(&mut self, method: &str, params: P) -> Result<Response> {
        self.next_id += 1;
        let request = Request::new(self.next_id, method, params)?;
        writeln!(self.input, "{}", serde_json::to_string(&request)?)?;
        self.input.flush()?;
        let line = self
            .responses
            .recv_timeout(self.timeout)
            .with_context(|| {
                format!(
                    "adapter did not respond to {method:?} within {:?}",
                    self.timeout
                )
            })?
            .map_err(anyhow::Error::msg)?;
        let response: Response = serde_json::from_str(&line)
            .with_context(|| format!("invalid JSON-RPC response: {line}"))?;
        if response.jsonrpc != JSONRPC_VERSION {
            bail!("response uses JSON-RPC {:?}", response.jsonrpc);
        }
        if response.id != self.next_id {
            bail!(
                "response id {} does not match request id {}",
                response.id,
                self.next_id
            );
        }
        if response.result.is_some() == response.error.is_some() {
            bail!("response must contain exactly one of result or error");
        }
        Ok(response)
    }

    fn request<P: Serialize, T: for<'de> Deserialize<'de>>(
        &mut self,
        method: &str,
        params: P,
    ) -> Result<T> {
        let response = self.response(method, params)?;
        if let Some(error) = response.error {
            bail!("JSON-RPC error {}: {}", error.code, error.message);
        }
        serde_json::from_value(
            response
                .result
                .context("response has neither result nor error")?,
        )
        .context("decode response result")
    }

    fn expect_rpc_error<P: Serialize>(&mut self, method: &str, params: P, code: i64) -> Result<()> {
        let response = self.response(method, params)?;
        let error = response
            .error
            .with_context(|| format!("{method} unexpectedly succeeded"))?;
        if error.code != code {
            bail!("{method} returned error {}, expected {code}", error.code);
        }
        Ok(())
    }

    /// Compile a bundle outside a benchmark timer and return its handle.
    pub fn compile_template(
        &mut self,
        bundle: TemplateBundle,
        options: CompileOptions,
    ) -> Result<String> {
        let result: Outcome<CompileSuccess> =
            self.request("template.compile", CompileParams { bundle, options })?;
        match result {
            Outcome::Ok { ok } => Ok(ok.template_id),
            Outcome::Error { error } => {
                bail!("compile error [{}]: {}", error.code, error.message)
            }
        }
    }

    pub fn release_template(&mut self, template_id: impl Into<String>) -> Result<()> {
        let _: Value = self.request(
            "template.release",
            json!({"template_id": template_id.into()}),
        )?;
        Ok(())
    }

    pub fn conformance(&mut self) -> Result<InitializeResult> {
        let result: InitializeResult = self.request(
            "initialize",
            InitializeParams {
                protocol_versions: vec![PROTOCOL_VERSION.into()],
                client: Implementation {
                    name: "liquid-spec".into(),
                    version: env!("CARGO_PKG_VERSION").into(),
                    language: Some("rust".into()),
                },
            },
        )?;
        if result.protocol_version != PROTOCOL_VERSION {
            bail!(
                "server selected unsupported protocol {:?}",
                result.protocol_version
            );
        }
        if result.implementation.name.trim().is_empty()
            || result.implementation.version.trim().is_empty()
        {
            bail!("implementation name and version are required");
        }
        self.expect_rpc_error("liquid-spec.unknown", json!({}), -32601)?;
        self.expect_rpc_error("template.compile", json!({"invalid": true}), -32602)?;
        let echo = json!({
            "values": [
                WireValue::BigInteger("9007199254740993".into()),
                WireValue::Bytes(vec![0, 255]),
                WireValue::Symbol("protocol".into()),
            ]
        });
        let echoed: Value = self.request("protocol.echo", echo.clone())?;
        if echoed != echo {
            bail!("protocol.echo did not preserve typed values");
        }
        let bundle = TemplateBundle {
            entry: "main".into(),
            sources: [("main".into(), "protocol sentinel".into())]
                .into_iter()
                .collect(),
        };
        let compile: Outcome<CompileSuccess> = self.request(
            "template.compile",
            CompileParams {
                bundle,
                options: CompileOptions {
                    // The protocol sentinel exercises lifecycle and typed
                    // output only.  Parse-mode support is a Liquid capability
                    // advertised by initialize, not a JSON-RPC requirement.
                    parse_mode: None,
                    line_numbers: true,
                },
            },
        )?;
        let template_id = match compile {
            Outcome::Ok { ok } => ok.template_id,
            Outcome::Error { error } => {
                bail!("protocol sentinel compile failed: {}", error.message)
            }
        };
        let render: Outcome<RenderSuccess> = self.request(
            "template.render",
            RenderParams {
                template_id: template_id.clone(),
                environment: Default::default(),
                options: Default::default(),
            },
        )?;
        match render {
            Outcome::Ok { ok } if ok.output == WireValue::String("protocol sentinel".into()) => {}
            Outcome::Ok { ok } => bail!("protocol sentinel rendered {:?}", ok.output),
            Outcome::Error { error } => bail!("protocol sentinel render failed: {}", error.message),
        }
        let repeated: Outcome<RenderSuccess> = self.request(
            "template.render",
            RenderParams {
                template_id: template_id.clone(),
                environment: Default::default(),
                options: Default::default(),
            },
        )?;
        if !matches!(repeated, Outcome::Ok { ok } if ok.output == WireValue::String("protocol sentinel".into()))
        {
            bail!("compiled templates must support repeated isolated renders");
        }
        let _: Value = self.request("template.release", json!({"template_id": template_id}))?;
        self.expect_rpc_error(
            "template.render",
            RenderParams {
                template_id: "released-template".into(),
                environment: Default::default(),
                options: Default::default(),
            },
            -32602,
        )?;
        if result.capabilities.benchmark {
            self.benchmark_smoke()?;
        }
        Ok(result)
    }

    /// Run one server-side benchmark batch.  The adapter owns the monotonic
    /// clock and reports raw integer nanoseconds; the client never times the
    /// JSON-RPC round trip.  Render requests must refer to a handle compiled
    /// before this call, so parsing cannot leak into render timings.
    pub fn benchmark_run(&mut self, request: BenchmarkRequest) -> Result<BenchmarkResult> {
        request
            .validate()
            .map_err(|error| anyhow::anyhow!("invalid benchmark request: {error}"))?;
        let operation = request.operation;
        let result: BenchmarkResult = self.request("benchmark.run", request)?;
        result
            .validate(operation)
            .map_err(|error| anyhow::anyhow!("invalid benchmark result: {error}"))?;
        Ok(result)
    }

    pub fn benchmark_compile(
        &mut self,
        bundle: TemplateBundle,
        options: CompileOptions,
        iterations: u32,
    ) -> Result<BenchmarkResult> {
        self.benchmark_run(BenchmarkRequest::compile(bundle, options, iterations))
    }

    pub fn benchmark_render(
        &mut self,
        template_id: impl Into<String>,
        environment: std::collections::BTreeMap<String, WireValue>,
        options: RenderOptions,
        iterations: u32,
    ) -> Result<BenchmarkResult> {
        self.benchmark_run(BenchmarkRequest::render(
            template_id,
            environment,
            options,
            iterations,
        ))
    }

    pub fn benchmark_artifact(
        &mut self,
        artifact: WireValue,
        iterations: u32,
    ) -> Result<BenchmarkResult> {
        self.benchmark_run(BenchmarkRequest::artifact(artifact, iterations))
    }

    fn benchmark_smoke(&mut self) -> Result<()> {
        let bundle = TemplateBundle {
            entry: "benchmark-smoke".into(),
            sources: [("benchmark-smoke".into(), "benchmark sentinel".into())]
                .into_iter()
                .collect(),
        };
        let result = self.benchmark_compile(bundle.clone(), CompileOptions::default(), 1)?;
        if result.digest == WireValue::Null {
            bail!("benchmark compile returned an empty digest");
        }
        // Compile outside the timed render request.  This is deliberately a
        // normal compile call, making it impossible for a conforming server to
        // hide parsing in its render benchmark implementation.
        let compile: Outcome<CompileSuccess> = self.request(
            "template.compile",
            CompileParams {
                bundle,
                options: CompileOptions::default(),
            },
        )?;
        let template_id = match compile {
            Outcome::Ok { ok } => ok.template_id,
            Outcome::Error { error } => {
                bail!("benchmark render smoke compile failed: {}", error.message)
            }
        };
        let render = self.benchmark_render(
            template_id.clone(),
            Default::default(),
            RenderOptions::default(),
            1,
        )?;
        if render.digest == WireValue::Null {
            bail!("benchmark render returned an empty digest");
        }
        let _: Value = self.request("template.release", json!({"template_id": template_id}))?;
        Ok(())
    }

    pub fn run_specs(
        &mut self,
        mut specs: Vec<Spec>,
        capabilities: &Capabilities,
    ) -> Result<RunSummary> {
        // Keep the curriculum deterministic even when callers combine several
        // namespaces or append ad-hoc specs.  This also makes the first
        // reported failures the genuinely lowest-complexity lessons.
        specs.sort_by(|left, right| {
            left.complexity
                .cmp(&right.complexity)
                .then_with(|| left.name.cmp(&right.name))
        });
        let supported: std::collections::BTreeSet<_> =
            capabilities.features.iter().map(String::as_str).collect();
        let mut summary = RunSummary::default();
        for spec in specs {
            if spec.features.iter().any(|feature| {
                feature != "core" && !feature_supported(feature, &supported, capabilities)
            }) {
                summary.skipped += 1;
                continue;
            }
            match self.run_spec(&spec) {
                Ok(()) => {
                    summary.passed += 1;
                    summary.passed_complexities.push(spec.complexity);
                    summary.passed_names.push(spec.name.clone());
                    summary.passed_entries.push((spec.name, spec.complexity));
                }
                Err(error) if error.downcast_ref::<ProtocolFailure>().is_some() => {
                    return Err(error);
                }
                Err(error) => summary.failures.push(Failure {
                    name: spec.name,
                    complexity: spec.complexity,
                    source: spec.source_file,
                    message: error.to_string(),
                    hint: spec.hint,
                }),
            }
        }
        // Namespace discovery is deterministic, but concatenating several
        // namespaces does not guarantee a global complexity order. Keep the
        // concise "next best" diagnostics focused on the actual lowest
        // complexity failures regardless of namespace selection.
        summary.failures.sort_by(|left, right| {
            left.complexity
                .cmp(&right.complexity)
                .then_with(|| left.name.cmp(&right.name))
        });
        summary.failed = summary.failures.len();
        summary.max_complexity_reached = summary.complexity_level();
        Ok(summary)
    }

    fn run_spec(&mut self, spec: &Spec) -> Result<()> {
        let compile: Outcome<CompileSuccess> = self
            .request(
                "template.compile",
                CompileParams {
                    bundle: spec.bundle.clone(),
                    options: spec.compile_options.clone(),
                },
            )
            .map_err(|error| anyhow::Error::new(ProtocolFailure(error)))?;
        let template_id = match compile {
            Outcome::Ok { ok } => ok.template_id,
            Outcome::Error { error } => {
                return match &spec.expected {
                    Expected::Error { phase, patterns } if phase == "parse_error" => {
                        match_error(&error, patterns)
                    }
                    _ => bail!("compile error [{}]: {}", error.code, error.message),
                };
            }
        };
        let result: Outcome<RenderSuccess> = self
            .request(
                "template.render",
                RenderParams {
                    template_id: template_id.clone(),
                    environment: spec.environment.clone(),
                    options: spec.render_options.clone(),
                },
            )
            .map_err(|error| anyhow::Error::new(ProtocolFailure(error)))?;
        let _: Value = self
            .request("template.release", json!({"template_id": template_id}))
            .map_err(|error| anyhow::Error::new(ProtocolFailure(error)))?;
        match (result, &spec.expected) {
            (Outcome::Ok { ok }, Expected::Output(expected))
                if output_bytes(&ok.output)? == *expected =>
            {
                Ok(())
            }
            (Outcome::Ok { ok }, Expected::Pattern(pattern))
                if Regex::new(pattern)?.is_match(output_text(&ok.output)?) =>
            {
                Ok(())
            }
            (Outcome::Ok { ok }, Expected::Error { phase, patterns }) if phase == "output" => {
                match_text(output_text(&ok.output)?, patterns)
            }
            (Outcome::Error { error }, Expected::Error { phase, patterns })
                if phase == "render_error" =>
            {
                match_error(&error, patterns)
            }
            (Outcome::Ok { ok }, Expected::Output(expected)) => {
                bail!(
                    "expected {} output bytes, got {:?}",
                    expected.len(),
                    ok.output
                )
            }
            (Outcome::Ok { ok }, _) => bail!("unexpected output {:?}", ok.output),
            (Outcome::Error { error }, _) => {
                bail!("render error [{}]: {}", error.code, error.message)
            }
        }
    }

    pub fn shutdown(&mut self) -> Result<()> {
        let notification = Notification {
            jsonrpc: JSONRPC_VERSION.into(),
            method: "shutdown".into(),
            params: json!({}),
        };
        writeln!(self.input, "{}", serde_json::to_string(&notification)?)?;
        self.input.flush()?;
        // A shutdown notification has no response. Give a well-behaved server
        // a brief window to flush an accidental response so protocol mistakes
        // are reported at the boundary rather than contaminating a later
        // request; normal process teardown is handled by Drop.
        if let Ok(Ok(message)) = self.responses.recv_timeout(Duration::from_millis(20)) {
            bail!("adapter emitted a response to shutdown: {message}");
        }
        Ok(())
    }
}

fn feature_supported(
    feature: &str,
    advertised: &std::collections::BTreeSet<&str>,
    capabilities: &Capabilities,
) -> bool {
    if advertised.contains(feature) {
        return true;
    }
    match feature {
        "drops" => capabilities
            .fixture_sets
            .get("standard-drops")
            .is_some_and(|version| *version >= 1),
        "strict2_parsing" => capabilities
            .parse_modes
            .iter()
            .any(|mode| mode == "strict2"),
        "strict_parsing" => capabilities.parse_modes.iter().any(|mode| mode == "strict"),
        "lax_parsing" => capabilities.parse_modes.iter().any(|mode| mode == "lax"),
        _ => false,
    }
}

impl Drop for Session {
    fn drop(&mut self) {
        let _ = self.child.kill();
        let _ = self.child.wait();
    }
}

fn read_responses(output: ChildStdout, sender: mpsc::Sender<Result<String, String>>) {
    for line in BufReader::new(output).lines() {
        if sender.send(line.map_err(|e| e.to_string())).is_err() {
            return;
        }
    }
    let _ = sender.send(Err("adapter closed stdout".into()));
}

fn match_error(error: &LiquidError, patterns: &[ErrorPattern]) -> Result<()> {
    let mut text = format!("{} {}", error.code, error.message);
    if let Some(location) = &error.location {
        text.push_str(&format!(
            " {} {:?} {:?}",
            location.template, location.line, location.column
        ));
    }
    match_text(&text, patterns)
}

fn output_bytes(output: &WireValue) -> Result<Vec<u8>> {
    match output {
        WireValue::String(value) => Ok(value.as_bytes().to_vec()),
        WireValue::Bytes(value) => Ok(value.clone()),
        other => bail!("render output must be a string or bytes, got {other:?}"),
    }
}

fn output_text(output: &WireValue) -> Result<&str> {
    match output {
        WireValue::String(value) => Ok(value),
        WireValue::Bytes(value) => {
            std::str::from_utf8(value).context("pattern matching requires UTF-8 output")
        }
        other => bail!("render output must be a string or bytes, got {other:?}"),
    }
}

fn match_text(text: &str, patterns: &[ErrorPattern]) -> Result<()> {
    for pattern in patterns {
        let matches = match pattern {
            ErrorPattern::Literal(value) => text.to_lowercase().contains(&value.to_lowercase()),
            ErrorPattern::Regex(value) => parse_ruby_regex(value)?.is_match(text),
        };
        if !matches {
            bail!("{text:?} does not match {pattern:?}");
        }
    }
    Ok(())
}

fn parse_ruby_regex(value: &str) -> Result<Regex> {
    let value = value.strip_prefix('/').unwrap_or(value);
    let (pattern, flags) = value.rsplit_once('/').unwrap_or((value, ""));
    regex::RegexBuilder::new(pattern)
        .case_insensitive(flags.contains('i'))
        .build()
        .map_err(Into::into)
}

#[derive(Default, Serialize)]
pub struct RunSummary {
    pub passed: usize,
    pub failed: usize,
    pub skipped: usize,
    pub failures: Vec<Failure>,
    #[serde(skip)]
    passed_complexities: Vec<u16>,
    #[serde(rename = "passed_specs")]
    pub passed_names: Vec<String>,
    #[serde(skip)]
    pub passed_entries: Vec<(String, u16)>,
    pub max_complexity_reached: u16,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub all_failures_path: Option<std::path::PathBuf>,
}

impl RunSummary {
    pub fn print(&self) {
        self.print_with(false);
    }

    /// Print a concise ramp report. The complete ordered result list is written
    /// to the deterministic report path by the check command.
    pub fn print_with(&self, list_passed: bool) {
        if !self.failures.is_empty() {
            println!("Next best specs to work on:\n");
            let failures = self.failures.iter().take(5).collect::<Vec<_>>();
            for (index, failure) in failures.iter().enumerate() {
                println!(
                    "{}) [c={}] {}\n   {}",
                    index + 1,
                    failure.complexity,
                    failure.name,
                    failure.message
                );
                println!("   Source: {}", failure.source.display());
                if let Some(hint) = &failure.hint {
                    println!("   Hint: {}", hint.trim().replace('\n', " "));
                }
                println!();
            }
            if self.failures.len() > failures.len() {
                println!(
                    "(... {} more failures are listed in the check report)\n",
                    self.failures.len() - failures.len()
                );
            }
        }
        if list_passed {
            println!("Passed specs:");
            for name in &self.passed_names {
                println!("  {name}");
            }
            println!();
        }
        let level = self.complexity_level();
        println!(
            "Complexity level cleared: {level} of 1000, {} passes, {} failures, {} skipped.",
            self.passed, self.failed, self.skipped
        );
    }

    fn complexity_level(&self) -> u16 {
        if self.failed == 0 {
            self.passed_complexities.iter().copied().max().unwrap_or(0)
        } else {
            let first_failure = self.failures.iter().map(|f| f.complexity).min().unwrap();
            self.passed_complexities
                .iter()
                .copied()
                .filter(|c| *c < first_failure)
                .max()
                .unwrap_or(0)
        }
    }
}

#[derive(Serialize)]
pub struct Failure {
    pub name: String,
    pub complexity: u16,
    pub source: std::path::PathBuf,
    pub message: String,
    pub hint: Option<String>,
}
