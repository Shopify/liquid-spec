use anyhow::{Context, Result, bail};
use serde::Serialize;
use serde_json::Value;
use std::collections::BTreeMap;
use std::fs::File;
use std::io::{BufRead, BufReader};
use std::path::Path;

/// Summarize the append-only result log produced by the runner.  The log is
/// deliberately plain JSONL so CI and other tools can consume it without
/// depending on Rust types.
pub fn run(path: Option<&Path>, json: bool) -> Result<()> {
    let path = path.unwrap_or_else(|| Path::new("/tmp/liquid-spec-results.jsonl"));
    let mut report = Report::default();
    let file = File::open(path).with_context(|| format!("read result log {}", path.display()))?;
    // Keep report responsive on the multi-gigabyte logs produced by long-lived
    // CI workspaces. Callers needing a complete historical roll-up can point
    // the command at a rotated log file.
    const MAX_LINES: usize = 10_000;
    for (line_no, line) in BufReader::new(file).lines().take(MAX_LINES).enumerate() {
        let line = line.with_context(|| format!("read result log line {}", line_no + 1))?;
        if line.trim().is_empty() {
            continue;
        }
        // Older Ruby runners occasionally appended two arrays without a
        // newline. Normalize that boundary before parsing this line.
        let normalized = line.replace("][", "]\n[");
        for value_text in normalized.lines() {
            let value: Value = serde_json::from_str(value_text)
                .with_context(|| format!("parse result log line {}", line_no + 1))?;
            let Some(items) = value.as_array() else {
                // Permit benchmark summaries and future object-shaped events, but
                // do not silently count them as acceptance results.
                continue;
            };
            if items.len() < 6 {
                continue;
            }
            let status = items[5].as_str().unwrap_or("unknown").to_owned();
            *report.statuses.entry(status).or_default() += 1;
            report
                .runs
                .insert(items[0].as_str().unwrap_or("unknown").into());
            if let Some(complexity) = items[4].as_u64() {
                report.max_complexity = report.max_complexity.max(complexity as u16);
            }
        }
    }
    if report.statuses.is_empty() {
        bail!("result log contained no acceptance entries");
    }
    if json {
        println!("{}", serde_json::to_string_pretty(&report)?);
    } else {
        println!(
            "Result report: {} run(s) (first {MAX_LINES} log lines)",
            report.runs.len()
        );
        for (status, count) in &report.statuses {
            println!("  {status:<8} {count}");
        }
        println!("  max complexity observed: {}", report.max_complexity);
    }
    Ok(())
}

#[derive(Default, Serialize)]
struct Report {
    runs: std::collections::BTreeSet<String>,
    statuses: BTreeMap<String, usize>,
    max_complexity: u16,
}
