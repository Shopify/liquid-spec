use std::io::Write;
use std::process::{Command, Stdio};
use std::time::{SystemTime, UNIX_EPOCH};

fn binary() -> &'static str {
    env!("CARGO_BIN_EXE_liquid-spec")
}

fn server() -> &'static str {
    env!("CARGO_BIN_EXE_liquid-spec-test-server")
}

#[test]
fn init_generates_manifest_agents_and_executable_typescript_demo() {
    let directory =
        std::env::temp_dir().join(format!("liquid-spec-init-test-{}", std::process::id()));
    std::fs::create_dir_all(&directory).expect("create init directory");
    let output = Command::new(binary())
        .args(["init", directory.to_str().unwrap()])
        .output()
        .expect("run init");
    assert!(
        output.status.success(),
        "{}",
        String::from_utf8_lossy(&output.stderr)
    );
    let manifest =
        std::fs::read_to_string(directory.join("liquid-spec.toml")).expect("read starter manifest");
    assert!(manifest.contains("default = \"check\""));
    assert!(manifest.contains("command = [\"./adapter.ts\"]"));
    assert!(directory.join("AGENTS.md").is_file());
    let adapter =
        std::fs::read_to_string(directory.join("adapter.ts")).expect("read TypeScript demo");
    assert!(adapter.starts_with("#!/usr/bin/env -S node --experimental-strip-types\n"));
    let _ = std::fs::remove_dir_all(directory);
}

#[test]
fn protocol_gate_runs_before_acceptance_specs() {
    let output = Command::new(binary())
        .args(["protocol", "--", server()])
        .output()
        .expect("run protocol gate");
    assert!(
        output.status.success(),
        "{}",
        String::from_utf8_lossy(&output.stderr)
    );
    assert!(String::from_utf8_lossy(&output.stdout).contains("Protocol v2: OK"));
}

#[test]
fn docs_list_reports_absolute_root_and_markdown_files() {
    let output = Command::new(binary())
        .args(["docs", "list"])
        .output()
        .expect("list docs");
    assert!(output.status.success());
    let stdout = String::from_utf8_lossy(&output.stdout);
    let root =
        std::fs::canonicalize(std::path::Path::new(env!("CARGO_MANIFEST_DIR")).join("../../docs"))
            .expect("canonical docs root");
    assert!(stdout.contains("Docs directory: "));
    assert!(stdout.contains(&root.display().to_string()));
    assert!(stdout.contains("implementers/curriculum.md"));
}

#[test]
fn docs_accept_case_insensitive_filename_substrings() {
    let output = Command::new(binary())
        .args(["docs", "CURRICULUM.MD"])
        .output()
        .expect("read curriculum docs");
    assert!(output.status.success());
    assert!(String::from_utf8_lossy(&output.stdout).contains("# Liquid Implementation Curriculum"));
}

#[test]
fn docs_reports_ambiguous_substrings_with_candidates() {
    let output = Command::new(binary())
        .args(["docs", "filter"])
        .output()
        .expect("resolve ambiguous docs topic");
    assert!(!output.status.success());
    let stderr = String::from_utf8_lossy(&output.stderr);
    assert!(stderr.contains("ambiguous"));
    assert!(stderr.contains("implementers/filters.md"));
    assert!(stderr.contains("filter_matrix_quirks.md"));
}

#[test]
fn run_executes_a_focused_spec_through_json_rpc() {
    let output = Command::new(binary())
        .args([
            "run",
            "-s",
            "basics",
            "-n",
            "literal_passthrough",
            "--",
            server(),
        ])
        .output()
        .expect("run focused spec");
    assert!(
        output.status.success(),
        "{}",
        String::from_utf8_lossy(&output.stderr)
    );
    assert!(String::from_utf8_lossy(&output.stdout).contains("1 passes"));
}

#[test]
fn check_fails_semantic_mismatches_and_writes_all_results_report() {
    let directory =
        std::env::temp_dir().join(format!("liquid-spec-check-test-{}", std::process::id()));
    std::fs::create_dir_all(&directory).expect("create check working directory");
    let output = Command::new(binary())
        .args([
            "check",
            "-s",
            "basics",
            "-n",
            "object_string_literal",
            "--",
            server(),
        ])
        .current_dir(&directory)
        .output()
        .expect("run check");
    assert!(
        !output.status.success(),
        "check should fail on spec mismatches"
    );
    let stdout = String::from_utf8_lossy(&output.stdout);
    let marker = "[all failures in ";
    let start = stdout.find(marker).expect("report marker");
    let path = stdout[start + marker.len()..]
        .lines()
        .next()
        .expect("report path")
        .trim_end_matches(']');
    let report = std::fs::read_to_string(path).expect("read check report");
    assert!(report.contains("FAIL [c="));
    assert!(report.contains("object_string_literal"));
    let _ = std::fs::remove_dir_all(directory);
}

#[test]
fn check_and_features_are_available_as_tool_commands() {
    let check = Command::new(binary())
        .args(["tools", "check"])
        .output()
        .unwrap();
    assert!(check.status.success());
    let check_stdout = String::from_utf8_lossy(&check.stdout);
    assert!(check_stdout.contains("7905 specs"));
    assert!(check_stdout.contains("Running 12 Ruby verifier(s)"));
    assert!(check_stdout.contains("PASS scripts/verifiers/spec_schema.rb"));

    let features = Command::new(binary())
        .args(["tools", "features"])
        .output()
        .unwrap();
    assert!(features.status.success());
    assert!(String::from_utf8_lossy(&features.stdout).contains("core"));
}

#[test]
fn bench_uses_server_owned_batches_and_precompiled_render() {
    let output = Command::new(binary())
        .args([
            "bench",
            "-n",
            "bench_dynamic_partials",
            "--iterations",
            "2",
            "--",
            server(),
        ])
        .output()
        .expect("run benchmark");
    assert!(
        output.status.success(),
        "{}",
        String::from_utf8_lossy(&output.stderr)
    );
    let stdout = String::from_utf8_lossy(&output.stdout);
    assert!(stdout.contains("compile"));
    assert!(stdout.contains("render"));
}

#[test]
fn eval_reads_yaml_from_stdin() {
    let mut child = Command::new(binary())
        .args(["tools", "eval", "--json", "--", server()])
        .stdin(Stdio::piped())
        .stdout(Stdio::piped())
        .spawn()
        .expect("start eval");
    child
        .stdin
        .take()
        .expect("eval stdin")
        .write_all(b"- name: eval_literal\n  template: hello\n  expected: hello\n  complexity: 1\n")
        .expect("write eval YAML");
    let output = child.wait_with_output().expect("wait for eval");
    assert!(
        output.status.success(),
        "{}",
        String::from_utf8_lossy(&output.stderr)
    );
    let stdout = String::from_utf8_lossy(&output.stdout);
    assert!(stdout.contains("\"passed\":1"));
    assert!(stdout.contains("\"equivalent\":true"));
}

#[test]
fn eval_compare_uses_the_configured_reference_adapter() {
    let suffix = SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .unwrap()
        .as_nanos();
    let config_path = std::env::temp_dir().join(format!("liquid-spec-eval-{suffix}.toml"));
    let config = format!(
        "reference_adapter = \"reference\"\n\n[adapters.reference]\ncommand = [\"{}\"]\n",
        server().replace('\\', "\\\\").replace('"', "\\\"")
    );
    std::fs::write(&config_path, config).expect("write eval config");
    let mut child = Command::new(binary())
        .args([
            "--config",
            config_path.to_str().unwrap(),
            "tools",
            "eval",
            "--compare",
            "--json",
            "--",
            server(),
        ])
        .stdin(Stdio::piped())
        .stdout(Stdio::piped())
        .spawn()
        .expect("start eval comparison");
    child
        .stdin
        .take()
        .expect("comparison stdin")
        .write_all(b"- name: eval_compare\n  template: hello\n  expected: hello\n  complexity: 1\n")
        .expect("write comparison YAML");
    let output = child.wait_with_output().expect("wait for eval comparison");
    let _ = std::fs::remove_file(&config_path);
    assert!(
        output.status.success(),
        "{}",
        String::from_utf8_lossy(&output.stderr)
    );
    let stdout = String::from_utf8_lossy(&output.stdout);
    assert!(stdout.contains("\"reference\""));
    assert!(stdout.contains("\"equivalent\":true"));
}
