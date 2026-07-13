use crate::{JSONRPC_VERSION, WireValue};
use serde::{Deserialize, Serialize};
use serde_json::Value;
use std::collections::BTreeMap;

pub type RequestId = u64;

#[derive(Clone, Debug, Serialize, Deserialize)]
pub struct Request {
    pub jsonrpc: String,
    pub id: RequestId,
    pub method: String,
    #[serde(default)]
    pub params: Value,
}

impl Request {
    pub fn new(
        id: RequestId,
        method: impl Into<String>,
        params: impl Serialize,
    ) -> serde_json::Result<Self> {
        Ok(Self {
            jsonrpc: JSONRPC_VERSION.into(),
            id,
            method: method.into(),
            params: serde_json::to_value(params)?,
        })
    }
}

#[derive(Clone, Debug, Serialize, Deserialize)]
pub struct Notification {
    pub jsonrpc: String,
    pub method: String,
    #[serde(default)]
    pub params: Value,
}

#[derive(Clone, Debug, Serialize, Deserialize)]
pub struct Response {
    pub jsonrpc: String,
    pub id: RequestId,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub result: Option<Value>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub error: Option<RpcError>,
}

#[derive(Clone, Debug, Serialize, Deserialize)]
pub struct RpcError {
    pub code: i64,
    pub message: String,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub data: Option<Value>,
}

#[derive(Clone, Debug, Serialize, Deserialize)]
pub struct InitializeParams {
    pub protocol_versions: Vec<String>,
    pub client: Implementation,
}

#[derive(Clone, Debug, Serialize, Deserialize, PartialEq, Eq)]
pub struct Implementation {
    pub name: String,
    pub version: String,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub language: Option<String>,
}

#[derive(Clone, Debug, Default, Serialize, Deserialize, PartialEq, Eq)]
pub struct Capabilities {
    #[serde(default)]
    pub parse_modes: Vec<String>,
    #[serde(default)]
    pub features: Vec<String>,
    #[serde(default)]
    pub fixture_sets: BTreeMap<String, u32>,
    #[serde(default)]
    pub artifacts: bool,
    #[serde(default)]
    pub benchmark: bool,
}

#[derive(Clone, Debug, Serialize, Deserialize)]
pub struct InitializeResult {
    pub protocol_version: String,
    pub implementation: Implementation,
    pub capabilities: Capabilities,
}

#[derive(Clone, Debug, Serialize, Deserialize)]
pub struct TemplateBundle {
    pub entry: String,
    pub sources: BTreeMap<String, String>,
}

#[derive(Clone, Debug, Default, Serialize, Deserialize)]
pub struct CompileOptions {
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub parse_mode: Option<String>,
    #[serde(default)]
    pub line_numbers: bool,
}

#[derive(Clone, Debug, Serialize, Deserialize)]
pub struct CompileParams {
    pub bundle: TemplateBundle,
    #[serde(default)]
    pub options: CompileOptions,
}

#[derive(Clone, Debug, Default, Serialize, Deserialize)]
pub struct RenderOptions {
    #[serde(default = "default_error_policy")]
    pub error_policy: String,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub now: Option<String>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub resource_limits: Option<Value>,
}

fn default_error_policy() -> String {
    "raise".into()
}

#[derive(Clone, Debug, Serialize, Deserialize)]
pub struct RenderParams {
    pub template_id: String,
    #[serde(default)]
    pub environment: BTreeMap<String, WireValue>,
    #[serde(default)]
    pub options: RenderOptions,
}

#[derive(Clone, Debug, Serialize)]
#[serde(untagged)]
pub enum Outcome<T> {
    Ok { ok: T },
    Error { error: LiquidError },
}

impl<'de, T> Deserialize<'de> for Outcome<T>
where
    T: serde::de::DeserializeOwned,
{
    fn deserialize<D>(deserializer: D) -> Result<Self, D::Error>
    where
        D: serde::Deserializer<'de>,
    {
        let value = Value::deserialize(deserializer)?;
        let object = value
            .as_object()
            .ok_or_else(|| serde::de::Error::custom("outcome must be an object"))?;
        let has_ok = object.contains_key("ok");
        let has_error = object.contains_key("error");
        if has_ok == has_error {
            return Err(serde::de::Error::custom(
                "outcome must contain exactly one of ok or error",
            ));
        }
        if has_ok {
            let ok = serde_json::from_value(object.get("ok").cloned().expect("checked"))
                .map_err(serde::de::Error::custom)?;
            Ok(Self::Ok { ok })
        } else {
            let error = serde_json::from_value(object.get("error").cloned().expect("checked"))
                .map_err(serde::de::Error::custom)?;
            Ok(Self::Error { error })
        }
    }
}

#[derive(Clone, Debug, Serialize, Deserialize)]
pub struct CompileSuccess {
    pub template_id: String,
}

#[derive(Clone, Debug, Serialize, Deserialize)]
pub struct RenderSuccess {
    pub output: WireValue,
    #[serde(default)]
    pub diagnostics: Vec<LiquidError>,
}

#[derive(Clone, Debug, Serialize, Deserialize)]
pub struct LiquidError {
    pub phase: ErrorPhase,
    pub code: String,
    pub message: String,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub location: Option<SourceLocation>,
    #[serde(default)]
    pub causes: Vec<LiquidError>,
}

#[derive(Clone, Copy, Debug, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum ErrorPhase {
    Parse,
    Render,
}

#[derive(Clone, Debug, Serialize, Deserialize)]
pub struct SourceLocation {
    pub template: String,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub line: Option<u32>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub column: Option<u32>,
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn outcome_rejects_both_success_and_error_members() {
        let value = serde_json::json!({
            "ok": {"template_id": "t1"},
            "error": {"phase": "parse", "code": "bad", "message": "bad"}
        });
        assert!(serde_json::from_value::<Outcome<CompileSuccess>>(value).is_err());
    }

    #[test]
    fn outcome_round_trips_success_and_error() {
        let success = Outcome::Ok {
            ok: CompileSuccess {
                template_id: "t1".into(),
            },
        };
        let encoded = serde_json::to_value(&success).unwrap();
        assert!(matches!(
            serde_json::from_value::<Outcome<CompileSuccess>>(encoded).unwrap(),
            Outcome::Ok { .. }
        ));
    }
}
