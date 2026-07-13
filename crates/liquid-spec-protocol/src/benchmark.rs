//! Server-side benchmark-v1 messages.
//!
//! Benchmarking is intentionally a separate protocol surface from ordinary
//! compile/render requests.  An adapter owns the monotonic clock and reports
//! raw nanosecond batches.  This keeps transport and parsing costs out of
//! render measurements and makes results comparable across clients.

use crate::{CompileOptions, RenderOptions, TemplateBundle, WireValue};
use serde::{Deserialize, Serialize};
use std::collections::BTreeMap;

/// Version of the server-side benchmark extension.
pub const BENCHMARK_PROTOCOL_VERSION: &str = "1";

/// The operation whose body is measured by the adapter.
///
/// `Render` always receives a previously compiled `template_id`; it must not
/// parse source while the timer is running.  `Compile` parses the supplied
/// bundle and `ArtifactLoad` deserializes an implementation-owned artifact.
#[derive(Clone, Copy, Debug, Serialize, Deserialize, PartialEq, Eq)]
#[serde(rename_all = "snake_case")]
pub enum BenchmarkOperation {
    Compile,
    Render,
    ArtifactLoad,
}

#[derive(Clone, Debug, Serialize, Deserialize)]
pub struct BenchmarkRequest {
    /// Must equal [`BENCHMARK_PROTOCOL_VERSION`].
    #[serde(default = "default_version")]
    pub version: String,
    pub operation: BenchmarkOperation,
    /// Required for `compile`.
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub bundle: Option<TemplateBundle>,
    /// Required for `render`; this handle is created by `template.compile`
    /// outside the timed region.
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub template_id: Option<String>,
    /// Required for `artifact_load`.  Artifact bytes are represented as a
    /// typed value so implementations can choose their own serialization.
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub artifact: Option<WireValue>,
    #[serde(default)]
    pub environment: BTreeMap<String, WireValue>,
    #[serde(default)]
    pub compile_options: CompileOptions,
    #[serde(default)]
    pub render_options: RenderOptions,
    /// Number of operations per reported batch.  If omitted, the server picks
    /// a stable size based on a short probe.
    #[serde(default)]
    pub batch_size: Option<u32>,
    /// Maximum operation count.  The server may stop earlier at its duration
    /// budget, but must report the actual count in `BenchmarkResult`.
    #[serde(default = "default_iterations")]
    pub iterations: u32,
    /// Optional warm-up count, never included in reported timings.
    #[serde(default)]
    pub warmup_iterations: u32,
    /// Duration budget in milliseconds.  `None` means one batch only; this is
    /// useful for deterministic protocol tests and smoke checks.
    #[serde(default)]
    pub duration_ms: Option<u64>,
}

impl BenchmarkRequest {
    pub fn compile(bundle: TemplateBundle, options: CompileOptions, iterations: u32) -> Self {
        Self {
            version: BENCHMARK_PROTOCOL_VERSION.into(),
            operation: BenchmarkOperation::Compile,
            bundle: Some(bundle),
            template_id: None,
            artifact: None,
            environment: BTreeMap::new(),
            compile_options: options,
            render_options: RenderOptions::default(),
            batch_size: None,
            iterations,
            warmup_iterations: 0,
            duration_ms: None,
        }
    }

    pub fn render(
        template_id: impl Into<String>,
        environment: BTreeMap<String, WireValue>,
        options: RenderOptions,
        iterations: u32,
    ) -> Self {
        Self {
            version: BENCHMARK_PROTOCOL_VERSION.into(),
            operation: BenchmarkOperation::Render,
            bundle: None,
            template_id: Some(template_id.into()),
            artifact: None,
            environment,
            compile_options: CompileOptions::default(),
            render_options: options,
            batch_size: None,
            iterations,
            warmup_iterations: 0,
            duration_ms: None,
        }
    }

    pub fn artifact(artifact: WireValue, iterations: u32) -> Self {
        Self {
            version: BENCHMARK_PROTOCOL_VERSION.into(),
            operation: BenchmarkOperation::ArtifactLoad,
            bundle: None,
            template_id: None,
            artifact: Some(artifact),
            environment: BTreeMap::new(),
            compile_options: CompileOptions::default(),
            render_options: RenderOptions::default(),
            batch_size: None,
            iterations,
            warmup_iterations: 0,
            duration_ms: None,
        }
    }

    /// Validate operation-specific fields before a server starts its timer.
    /// Keeping this check in the shared crate prevents a render benchmark from
    /// accidentally carrying source that an implementation might parse.
    pub fn validate(&self) -> Result<(), String> {
        if self.version != BENCHMARK_PROTOCOL_VERSION {
            return Err(format!(
                "benchmark request uses version {:?}, expected {:?}",
                self.version, BENCHMARK_PROTOCOL_VERSION
            ));
        }
        if self.iterations == 0 {
            return Err("benchmark request iterations must be greater than zero".into());
        }
        if self.batch_size == Some(0) {
            return Err("benchmark request batch_size must be greater than zero".into());
        }
        match self.operation {
            BenchmarkOperation::Compile => {
                if self.bundle.is_none() {
                    return Err("compile benchmark requires bundle".into());
                }
                if self.template_id.is_some() || self.artifact.is_some() {
                    return Err("compile benchmark cannot carry template_id or artifact".into());
                }
            }
            BenchmarkOperation::Render => {
                if self.template_id.is_none() {
                    return Err("render benchmark requires template_id".into());
                }
                if self.bundle.is_some() || self.artifact.is_some() {
                    return Err("render benchmark cannot carry bundle or artifact".into());
                }
            }
            BenchmarkOperation::ArtifactLoad => {
                if self.artifact.is_none() {
                    return Err("artifact_load benchmark requires artifact".into());
                }
                if self.bundle.is_some() || self.template_id.is_some() {
                    return Err("artifact_load benchmark cannot carry bundle or template_id".into());
                }
            }
        }
        Ok(())
    }
}

fn default_version() -> String {
    BENCHMARK_PROTOCOL_VERSION.into()
}

fn default_iterations() -> u32 {
    1
}

#[derive(Clone, Debug, Serialize, Deserialize, PartialEq, Eq)]
pub struct BenchmarkBatch {
    /// Number of measured operations represented by `elapsed_ns`.
    pub iterations: u32,
    /// Monotonic elapsed time for the whole batch, in integer nanoseconds.
    pub elapsed_ns: u64,
}

#[derive(Clone, Debug, Serialize, Deserialize)]
pub struct BenchmarkResult {
    #[serde(default = "default_version")]
    pub version: String,
    pub operation: BenchmarkOperation,
    /// The number of measured operations across all batches.
    pub iterations: u64,
    /// Raw batches are retained for downstream statistics and diagnostics.
    #[serde(default)]
    pub batches: Vec<BenchmarkBatch>,
    /// A digest of the operation's observable result.  Clients must verify it
    /// changes when the operation is actually performed; it prevents no-op
    /// benchmark implementations from reporting plausible timings.
    pub digest: WireValue,
    /// Optional artifact returned by compile/load implementations.  It is not
    /// used by render timings and is included only for artifact workflows.
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub artifact: Option<WireValue>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub artifact_bytes: Option<u64>,
}

impl BenchmarkResult {
    pub fn total_elapsed_ns(&self) -> u128 {
        self.batches
            .iter()
            .map(|batch| u128::from(batch.elapsed_ns))
            .sum()
    }

    pub fn validate(&self, expected: BenchmarkOperation) -> Result<(), String> {
        if self.version != BENCHMARK_PROTOCOL_VERSION {
            return Err(format!(
                "benchmark result uses version {:?}, expected {:?}",
                self.version, BENCHMARK_PROTOCOL_VERSION
            ));
        }
        if self.operation != expected {
            return Err(format!(
                "benchmark result operation {:?}, expected {:?}",
                self.operation, expected
            ));
        }
        let measured: u64 = self
            .batches
            .iter()
            .map(|batch| u64::from(batch.iterations))
            .sum();
        if self.batches.iter().any(|batch| batch.iterations == 0) {
            return Err("benchmark result contains an empty batch".into());
        }
        if measured != self.iterations {
            return Err(format!(
                "benchmark result reports {} iterations but batches contain {}",
                self.iterations, measured
            ));
        }
        if self.iterations == 0 || self.batches.is_empty() {
            return Err("benchmark result contains no measured operations".into());
        }
        if self.digest == WireValue::Null {
            return Err("benchmark result is missing an observable digest".into());
        }
        Ok(())
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use serde_json::json;

    #[test]
    fn render_request_does_not_carry_source() {
        let request =
            BenchmarkRequest::render("template-1", BTreeMap::new(), RenderOptions::default(), 4);
        let value = serde_json::to_value(request).unwrap();
        assert_eq!(value["operation"], "render");
        assert!(value.get("bundle").is_none());
        assert_eq!(value["template_id"], "template-1");
    }

    #[test]
    fn result_validation_rejects_mismatched_batch_count() {
        let result = BenchmarkResult {
            version: BENCHMARK_PROTOCOL_VERSION.into(),
            operation: BenchmarkOperation::Render,
            iterations: 2,
            batches: vec![BenchmarkBatch {
                iterations: 1,
                elapsed_ns: 7,
            }],
            digest: WireValue::String("output".into()),
            artifact: None,
            artifact_bytes: None,
        };
        assert!(result.validate(BenchmarkOperation::Render).is_err());
    }

    #[test]
    fn render_validation_rejects_a_source_bundle() {
        let mut request =
            BenchmarkRequest::render("template-1", BTreeMap::new(), RenderOptions::default(), 1);
        request.bundle = Some(TemplateBundle {
            entry: "main".into(),
            sources: [("main".into(), "source".into())].into_iter().collect(),
        });
        assert!(request.validate().is_err());
    }

    #[test]
    fn request_defaults_are_wire_compatible() {
        let request: BenchmarkRequest = serde_json::from_value(json!({
            "operation": "compile",
            "bundle": {"entry": "main", "sources": {"main": "hello"}}
        }))
        .unwrap();
        assert_eq!(request.version, BENCHMARK_PROTOCOL_VERSION);
        assert_eq!(request.iterations, 1);
    }
}
