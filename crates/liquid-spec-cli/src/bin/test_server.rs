//! Deterministic protocol-v2 source-echo server used by integration tests and
//! dumb-adapter curriculum audits. It deliberately implements no Liquid syntax.

use liquid_spec_protocol::*;
use serde_json::{Value, json};
use std::collections::HashMap;
use std::io::{self, BufRead, Write};
use std::time::Instant;

fn main() {
    let stdin = io::stdin();
    let mut stdout = io::stdout().lock();
    let mut templates = HashMap::<String, String>::new();
    let mut next_template = 0_u64;
    for line in stdin.lock().lines() {
        let Ok(line) = line else { break };
        let Ok(message) = serde_json::from_str::<Value>(&line) else {
            write_error(&mut stdout, 0, -32700, "Parse error");
            continue;
        };
        let method = message.get("method").and_then(Value::as_str).unwrap_or("");
        if method == "shutdown" && message.get("id").is_none() {
            break;
        }
        let Some(id) = message.get("id").and_then(Value::as_u64) else {
            continue;
        };
        let params = message.get("params").cloned().unwrap_or(json!({}));
        let result = match method {
            "initialize" => serde_json::to_value(InitializeResult {
                protocol_version: PROTOCOL_VERSION.into(),
                implementation: Implementation {
                    name: "source-echo-v2".into(),
                    version: "1.0.0".into(),
                    language: Some("rust".into()),
                },
                capabilities: Capabilities {
                    parse_modes: vec!["strict2".into()],
                    render_error_modes: vec!["raise".into()],
                    features: vec!["core".into()],
                    benchmark: true,
                    ..Default::default()
                },
            })
            .unwrap(),
            "protocol.echo" => params,
            "template.compile" => {
                let Ok(params) = serde_json::from_value::<CompileParams>(params) else {
                    write_error(&mut stdout, id, -32602, "Invalid params");
                    continue;
                };
                let Some(source) = params.bundle.sources.get(&params.bundle.entry) else {
                    write_error(&mut stdout, id, -32602, "Unknown entry template");
                    continue;
                };
                next_template += 1;
                let template_id = format!("template-{next_template}");
                templates.insert(template_id.clone(), source.clone());
                serde_json::to_value(Outcome::Ok {
                    ok: CompileSuccess { template_id },
                })
                .unwrap()
            }
            "template.render" => {
                let Ok(params) = serde_json::from_value::<RenderParams>(params) else {
                    write_error(&mut stdout, id, -32602, "Invalid params");
                    continue;
                };
                let Some(source) = templates.get(&params.template_id) else {
                    write_error(&mut stdout, id, -32602, "Unknown template_id");
                    continue;
                };
                serde_json::to_value(Outcome::Ok {
                    ok: RenderSuccess {
                        output: WireValue::String(source.clone()),
                        diagnostics: Vec::new(),
                    },
                })
                .unwrap()
            }
            "template.release" => {
                let Some(template_id) = params.get("template_id").and_then(Value::as_str) else {
                    write_error(&mut stdout, id, -32602, "Invalid params");
                    continue;
                };
                if templates.remove(template_id).is_none() {
                    write_error(&mut stdout, id, -32602, "Unknown template_id");
                    continue;
                }
                json!({"ok": {}})
            }
            "benchmark.run" => {
                let Ok(request) = serde_json::from_value::<BenchmarkRequest>(params) else {
                    write_error(&mut stdout, id, -32602, "Invalid benchmark params");
                    continue;
                };
                if request.version != BENCHMARK_PROTOCOL_VERSION {
                    write_error(&mut stdout, id, -32602, "Unsupported benchmark version");
                    continue;
                }
                if request.validate().is_err() {
                    write_error(
                        &mut stdout,
                        id,
                        -32602,
                        "Invalid benchmark operation fields",
                    );
                    continue;
                }
                match request.operation {
                    BenchmarkOperation::Compile => {
                        let bundle = request
                            .bundle
                            .as_ref()
                            .expect("validated compile request has a bundle");
                        if !bundle.sources.contains_key(&bundle.entry) {
                            write_error(&mut stdout, id, -32602, "unknown benchmark entry");
                            continue;
                        }
                    }
                    BenchmarkOperation::Render => {
                        let template_id = request
                            .template_id
                            .as_ref()
                            .expect("validated render request has a template_id");
                        if !templates.contains_key(template_id) {
                            write_error(&mut stdout, id, -32602, "unknown template_id");
                            continue;
                        }
                    }
                    BenchmarkOperation::ArtifactLoad => {}
                }
                let iterations = request.iterations;
                let batch_size = request
                    .batch_size
                    .unwrap_or(iterations)
                    .max(1)
                    .min(iterations);
                let mut batches = Vec::new();
                let mut remaining = iterations;
                let mut digest = WireValue::Null;
                let mut artifact = None;
                while remaining > 0 {
                    let count = remaining.min(batch_size);
                    let started = Instant::now();
                    for _ in 0..count {
                        match request.operation {
                            BenchmarkOperation::Compile => {
                                let Some(bundle) = request.bundle.as_ref() else {
                                    write_error(&mut stdout, id, -32602, "compile requires bundle");
                                    continue;
                                };
                                let Some(source) = bundle.sources.get(&bundle.entry) else {
                                    write_error(&mut stdout, id, -32602, "unknown benchmark entry");
                                    continue;
                                };
                                next_template += 1;
                                // Timed compile handles are ephemeral.  The
                                // benchmark result carries the source digest,
                                // so retaining every iteration would turn a
                                // timing run into an unbounded memory test.
                                let _template_id = format!("benchmark-template-{next_template}");
                                artifact = Some(WireValue::String(source.clone()));
                                digest = WireValue::String(source.clone());
                            }
                            BenchmarkOperation::Render => {
                                let Some(template_id) = request.template_id.as_ref() else {
                                    write_error(
                                        &mut stdout,
                                        id,
                                        -32602,
                                        "render requires template_id",
                                    );
                                    continue;
                                };
                                let Some(source) = templates.get(template_id) else {
                                    write_error(&mut stdout, id, -32602, "unknown template_id");
                                    continue;
                                };
                                digest = WireValue::String(source.clone());
                            }
                            BenchmarkOperation::ArtifactLoad => {
                                let Some(artifact) = request.artifact.as_ref() else {
                                    write_error(
                                        &mut stdout,
                                        id,
                                        -32602,
                                        "artifact_load requires artifact",
                                    );
                                    continue;
                                };
                                digest = artifact.clone();
                            }
                        }
                    }
                    batches.push(BenchmarkBatch {
                        iterations: count,
                        elapsed_ns: started.elapsed().as_nanos().min(u128::from(u64::MAX)) as u64,
                    });
                    remaining -= count;
                }
                let result = BenchmarkResult {
                    version: BENCHMARK_PROTOCOL_VERSION.into(),
                    operation: request.operation,
                    iterations: u64::from(iterations),
                    batches,
                    digest,
                    artifact,
                    artifact_bytes: None,
                };
                serde_json::to_value(result).unwrap()
            }
            _ => {
                write_error(&mut stdout, id, -32601, "Method not found");
                continue;
            }
        };
        let response = Response {
            jsonrpc: JSONRPC_VERSION.into(),
            id,
            result: Some(result),
            error: None,
        };
        writeln!(stdout, "{}", serde_json::to_string(&response).unwrap()).unwrap();
        stdout.flush().unwrap();
    }
}

fn write_error(output: &mut impl Write, id: u64, code: i64, message: &str) {
    let response = Response {
        jsonrpc: JSONRPC_VERSION.into(),
        id,
        result: None,
        error: Some(RpcError {
            code,
            message: message.into(),
            data: None,
        }),
    };
    writeln!(output, "{}", serde_json::to_string(&response).unwrap()).unwrap();
    output.flush().unwrap();
}
