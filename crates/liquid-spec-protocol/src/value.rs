use serde::{Deserialize, Serialize};
use serde_json::{Map, Number, Value as JsonValue};
use std::collections::BTreeMap;
use thiserror::Error;

const ENVELOPE: &str = "$liquid-spec";

/// Values accepted by a v2 adapter. Common JSON values stay compact; values
/// JSON cannot preserve use a collision-safe tagged envelope.
#[derive(Clone, Debug, PartialEq)]
pub enum WireValue {
    Null,
    Bool(bool),
    Number(Number),
    String(String),
    Array(Vec<WireValue>),
    Object(BTreeMap<String, WireValue>),
    BigInteger(String),
    SpecialFloat(SpecialFloat),
    Bytes(Vec<u8>),
    Symbol(String),
    Date(String),
    Time(String),
    DateTime(String),
    Range {
        start: Box<WireValue>,
        end: Box<WireValue>,
        exclusive: bool,
    },
    Map(Vec<(WireValue, WireValue)>),
    Fixture(Fixture),
}

#[derive(Clone, Copy, Debug, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum SpecialFloat {
    Nan,
    PositiveInfinity,
    NegativeInfinity,
}

#[derive(Clone, Debug, PartialEq, Serialize, Deserialize)]
pub struct Fixture {
    pub set: String,
    pub version: u32,
    pub name: String,
    #[serde(default)]
    pub params: JsonValue,
}

#[derive(Debug, Error)]
pub enum ValueError {
    #[error("invalid liquid-spec value envelope: {0}")]
    InvalidEnvelope(String),
    #[error("invalid base64 bytes: {0}")]
    InvalidBytes(String),
    #[error("map entry must contain key and value")]
    InvalidMapEntry,
}

impl WireValue {
    pub fn to_json(&self) -> JsonValue {
        match self {
            Self::Null => JsonValue::Null,
            Self::Bool(value) => JsonValue::Bool(*value),
            Self::Number(value) => JsonValue::Number(value.clone()),
            Self::String(value) => JsonValue::String(value.clone()),
            Self::Array(values) => JsonValue::Array(values.iter().map(Self::to_json).collect()),
            Self::Object(values) if !values.contains_key(ENVELOPE) => JsonValue::Object(
                values.iter().map(|(key, value)| (key.clone(), value.to_json())).collect(),
            ),
            Self::Object(values) => tagged("object", [("value", JsonValue::Object(
                values.iter().map(|(key, value)| (key.clone(), value.to_json())).collect(),
            ))]),
            Self::BigInteger(value) => tagged("integer", [("value", value.clone().into())]),
            Self::SpecialFloat(value) => tagged("float", [("value", serde_json::to_value(value).unwrap())]),
            Self::Bytes(value) => {
                use base64::Engine;
                tagged("bytes", [("base64", base64::engine::general_purpose::STANDARD.encode(value).into())])
            }
            Self::Symbol(value) => tagged("symbol", [("value", value.clone().into())]),
            Self::Date(value) => tagged("date", [("value", value.clone().into())]),
            Self::Time(value) => tagged("time", [("value", value.clone().into())]),
            Self::DateTime(value) => tagged("datetime", [("value", value.clone().into())]),
            Self::Range { start, end, exclusive } => tagged("range", [
                ("start", start.to_json()),
                ("end", end.to_json()),
                ("exclusive", (*exclusive).into()),
            ]),
            Self::Map(entries) => tagged("map", [("entries", JsonValue::Array(entries.iter().map(|(key, value)| {
                serde_json::json!({"key": key.to_json(), "value": value.to_json()})
            }).collect()))]),
            Self::Fixture(fixture) => tagged("fixture", [
                ("set", fixture.set.clone().into()),
                ("version", fixture.version.into()),
                ("name", fixture.name.clone().into()),
                ("params", fixture.params.clone()),
            ]),
        }
    }

    pub fn from_json(value: JsonValue) -> Result<Self, ValueError> {
        match value {
            JsonValue::Null => Ok(Self::Null),
            JsonValue::Bool(value) => Ok(Self::Bool(value)),
            JsonValue::Number(value) => Ok(Self::Number(value)),
            JsonValue::String(value) => Ok(Self::String(value)),
            JsonValue::Array(values) => values
                .into_iter()
                .map(Self::from_json)
                .collect::<Result<_, _>>()
                .map(Self::Array),
            JsonValue::Object(mut values) if values.len() == 1 && values.contains_key(ENVELOPE) => {
                let payload = values
                    .remove(ENVELOPE)
                    .and_then(|v| v.as_object().cloned())
                    .ok_or_else(|| {
                        ValueError::InvalidEnvelope("payload must be an object".into())
                    })?;
                decode_tag(payload)
            }
            JsonValue::Object(values) => values
                .into_iter()
                .map(|(key, value)| Ok((key, Self::from_json(value)?)))
                .collect::<Result<_, _>>()
                .map(Self::Object),
        }
    }
}

fn tagged<const N: usize>(kind: &str, fields: [(&str, JsonValue); N]) -> JsonValue {
    let mut payload = Map::new();
    payload.insert("type".into(), kind.into());
    payload.extend(fields.into_iter().map(|(key, value)| (key.into(), value)));
    JsonValue::Object(
        [(ENVELOPE.into(), JsonValue::Object(payload))]
            .into_iter()
            .collect(),
    )
}

fn decode_tag(mut payload: Map<String, JsonValue>) -> Result<WireValue, ValueError> {
    let kind = take_string(&mut payload, "type")?;
    match kind.as_str() {
        "object" => match payload.remove("value") {
            Some(JsonValue::Object(values)) => values
                .into_iter()
                .map(|(key, value)| Ok((key, WireValue::from_json(value)?)))
                .collect::<Result<_, _>>()
                .map(WireValue::Object),
            _ => Err(ValueError::InvalidEnvelope(
                "object.value must be an object".into(),
            )),
        },
        "integer" => Ok(WireValue::BigInteger(take_string(&mut payload, "value")?)),
        "float" => {
            let value = payload
                .remove("value")
                .ok_or_else(|| ValueError::InvalidEnvelope("missing float.value".into()))?;
            serde_json::from_value(value)
                .map(WireValue::SpecialFloat)
                .map_err(|e| ValueError::InvalidEnvelope(e.to_string()))
        }
        "bytes" => {
            use base64::Engine;
            let value = take_string(&mut payload, "base64")?;
            base64::engine::general_purpose::STANDARD
                .decode(value)
                .map(WireValue::Bytes)
                .map_err(|e| ValueError::InvalidBytes(e.to_string()))
        }
        "symbol" => Ok(WireValue::Symbol(take_string(&mut payload, "value")?)),
        "date" => Ok(WireValue::Date(take_string(&mut payload, "value")?)),
        "time" => Ok(WireValue::Time(take_string(&mut payload, "value")?)),
        "datetime" => Ok(WireValue::DateTime(take_string(&mut payload, "value")?)),
        "range" => Ok(WireValue::Range {
            start: Box::new(WireValue::from_json(payload.remove("start").ok_or_else(
                || ValueError::InvalidEnvelope("missing range.start".into()),
            )?)?),
            end: Box::new(WireValue::from_json(payload.remove("end").ok_or_else(
                || ValueError::InvalidEnvelope("missing range.end".into()),
            )?)?),
            exclusive: payload
                .remove("exclusive")
                .and_then(|v| v.as_bool())
                .unwrap_or(false),
        }),
        "map" => {
            let entries = payload
                .remove("entries")
                .and_then(|v| v.as_array().cloned())
                .ok_or_else(|| {
                    ValueError::InvalidEnvelope("map.entries must be an array".into())
                })?;
            entries
                .into_iter()
                .map(|entry| {
                    let mut entry = entry
                        .as_object()
                        .cloned()
                        .ok_or(ValueError::InvalidMapEntry)?;
                    let key = WireValue::from_json(
                        entry.remove("key").ok_or(ValueError::InvalidMapEntry)?,
                    )?;
                    let value = WireValue::from_json(
                        entry.remove("value").ok_or(ValueError::InvalidMapEntry)?,
                    )?;
                    Ok((key, value))
                })
                .collect::<Result<_, _>>()
                .map(WireValue::Map)
        }
        "fixture" => Ok(WireValue::Fixture(Fixture {
            set: take_string(&mut payload, "set")?,
            version: payload
                .remove("version")
                .and_then(|v| v.as_u64())
                .ok_or_else(|| {
                    ValueError::InvalidEnvelope("fixture.version must be an integer".into())
                })? as u32,
            name: take_string(&mut payload, "name")?,
            params: payload
                .remove("params")
                .unwrap_or(JsonValue::Object(Map::new())),
        })),
        other => Err(ValueError::InvalidEnvelope(format!(
            "unknown type {other:?}"
        ))),
    }
}

fn take_string(payload: &mut Map<String, JsonValue>, field: &str) -> Result<String, ValueError> {
    payload
        .remove(field)
        .and_then(|v| v.as_str().map(ToOwned::to_owned))
        .ok_or_else(|| ValueError::InvalidEnvelope(format!("{field} must be a string")))
}

impl Serialize for WireValue {
    fn serialize<S>(&self, serializer: S) -> Result<S::Ok, S::Error>
    where
        S: serde::Serializer,
    {
        self.to_json().serialize(serializer)
    }
}

impl<'de> Deserialize<'de> for WireValue {
    fn deserialize<D>(deserializer: D) -> Result<Self, D::Error>
    where
        D: serde::Deserializer<'de>,
    {
        let value = JsonValue::deserialize(deserializer)?;
        Self::from_json(value).map_err(serde::de::Error::custom)
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn reserved_key_objects_round_trip_without_collision() {
        let value = WireValue::Object(
            [(ENVELOPE.into(), WireValue::String("ordinary".into()))]
                .into_iter()
                .collect(),
        );
        let json = serde_json::to_value(&value).unwrap();
        assert_eq!(serde_json::from_value::<WireValue>(json).unwrap(), value);
    }

    #[test]
    fn extended_values_round_trip() {
        let values = vec![
            WireValue::BigInteger("999999999999999999999999".into()),
            WireValue::Bytes(vec![0, 255, 42]),
            WireValue::Symbol("foo".into()),
            WireValue::Range {
                start: Box::new(WireValue::Number(1.into())),
                end: Box::new(WireValue::Number(4.into())),
                exclusive: true,
            },
            WireValue::Fixture(Fixture {
                set: "standard-drops".into(),
                version: 1,
                name: "BooleanDrop".into(),
                params: serde_json::json!({"value": false}),
            }),
        ];
        for value in values {
            let json = serde_json::to_value(&value).unwrap();
            assert_eq!(serde_json::from_value::<WireValue>(json).unwrap(), value);
        }
    }
}
