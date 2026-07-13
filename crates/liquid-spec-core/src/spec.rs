use anyhow::{Context, Result, bail};
use liquid_spec_protocol::{CompileOptions, Fixture, RenderOptions, TemplateBundle, WireValue};
use serde::Deserialize;
use serde_json::Value as JsonValue;
use std::collections::{BTreeMap, BTreeSet};
use std::fs;
use std::path::{Path, PathBuf};

#[derive(Clone, Debug)]
pub struct Namespace {
    pub id: String,
    pub name: String,
    pub description: String,
    pub path: PathBuf,
    pub default: bool,
    pub timings: bool,
    pub features: BTreeSet<String>,
    pub minimum_complexity: u16,
    pub default_iteration_seconds: f64,
    pub defaults: NamespaceDefaults,
}

#[derive(Clone, Debug, Default, Deserialize)]
pub struct NamespaceDefaults {
    #[serde(default)]
    pub render_errors: bool,
    #[serde(default)]
    pub error_mode: Option<String>,
    #[serde(default)]
    pub expected: Option<String>,
}

#[derive(Deserialize)]
struct RawNamespace {
    #[serde(default)]
    name: String,
    #[serde(default)]
    description: String,
    #[serde(default)]
    default: bool,
    #[serde(default)]
    timings: bool,
    #[serde(default)]
    features: Vec<String>,
    #[serde(default = "default_complexity")]
    minimum_complexity: u16,
    #[serde(default = "default_iteration_seconds")]
    default_iteration_seconds: f64,
    #[serde(default)]
    defaults: NamespaceDefaults,
}

fn default_complexity() -> u16 {
    1000
}
fn default_iteration_seconds() -> f64 {
    5.0
}

#[derive(Clone, Debug)]
pub struct Spec {
    pub name: String,
    pub bundle: TemplateBundle,
    pub environment: BTreeMap<String, WireValue>,
    pub expected: Expected,
    pub complexity: u16,
    pub hint: Option<String>,
    pub doc: Option<String>,
    pub features: BTreeSet<String>,
    /// Parse modes explicitly declared by the source spec. An empty list means
    /// the adapter's highest supported mode should be selected at execution.
    pub error_modes: Vec<String>,
    pub compile_options: CompileOptions,
    pub render_options: RenderOptions,
    pub source_file: PathBuf,
}

impl Spec {
    /// Create an isolated execution variant for one concrete parse mode.
    /// Multi-mode declarations are expanded by the runner in strictness order.
    pub fn with_error_mode(&self, mode: &str, label: bool) -> Self {
        let mut variant = self.clone();
        variant.error_modes = vec![mode.to_owned()];
        variant.compile_options.parse_mode = Some(mode.to_owned());
        let parse_features = ["strict2_parsing", "strict_parsing", "lax_parsing"];
        variant
            .features
            .retain(|feature| !parse_features.contains(&feature.as_str()));
        variant.features.insert(format!("{mode}_parsing"));
        if label {
            variant.name = format!("{} [error_mode={mode}]", self.name);
        }
        variant
    }
}

#[derive(Clone, Debug)]
pub enum Expected {
    Output(Vec<u8>),
    Pattern(String),
    Error {
        phase: String,
        patterns: Vec<ErrorPattern>,
    },
}

#[derive(Clone, Debug)]
pub enum ErrorPattern {
    Literal(String),
    Regex(String),
}

#[derive(Default, Deserialize)]
struct Metadata {
    #[serde(default)]
    hint: Option<String>,
    #[serde(default)]
    doc: Option<String>,
    #[serde(default)]
    required_options: BTreeMap<String, serde_yaml::Value>,
    #[serde(default)]
    render_errors: Option<bool>,
    #[serde(default)]
    minimum_complexity: Option<u16>,
    #[serde(default)]
    complexity: Option<u16>,
    #[serde(default)]
    features: Vec<String>,
    #[serde(default)]
    data_files: Vec<String>,
}

pub fn discover_namespaces(root: &Path) -> Result<Vec<Namespace>> {
    let mut namespaces = Vec::new();
    for entry in
        fs::read_dir(root).with_context(|| format!("read namespaces from {}", root.display()))?
    {
        let path = entry?.path();
        if !path.is_dir() {
            continue;
        }
        let metadata_file = path.join("suite.yml");
        let mut raw: RawNamespace = if metadata_file.is_file() {
            serde_yaml::from_str(&fs::read_to_string(&metadata_file)?)
                .with_context(|| format!("parse {}", metadata_file.display()))?
        } else {
            RawNamespace {
                name: String::new(),
                description: String::new(),
                default: false,
                timings: false,
                features: Vec::new(),
                minimum_complexity: default_complexity(),
                default_iteration_seconds: default_iteration_seconds(),
                defaults: NamespaceDefaults::default(),
            }
        };
        if raw.name.trim().is_empty() {
            raw.name = path
                .file_name()
                .map(|name| name.to_string_lossy().into_owned())
                .unwrap_or_else(|| "namespace".into());
        }
        namespaces.push(Namespace {
            id: path.file_name().unwrap().to_string_lossy().into_owned(),
            name: raw.name,
            description: raw.description,
            path,
            default: raw.default,
            timings: raw.timings,
            features: raw.features.into_iter().collect(),
            minimum_complexity: raw.minimum_complexity,
            default_iteration_seconds: raw.default_iteration_seconds,
            defaults: NamespaceDefaults {
                render_errors: raw.defaults.render_errors,
                error_mode: raw.defaults.error_mode.as_deref().map(normalize_mode),
                expected: raw.defaults.expected,
            },
        });
    }
    namespaces.sort_by(|a, b| a.id.cmp(&b.id));
    Ok(namespaces)
}

pub fn load_namespace(namespace: &Namespace) -> Result<Vec<Spec>> {
    let mut specs = Vec::new();
    for entry in fs::read_dir(&namespace.path)? {
        let path = entry?.path();
        if path.file_name().is_some_and(|name| name == "suite.yml") {
            continue;
        }
        if path.extension().is_some_and(|ext| ext == "yml") {
            specs.extend(load_spec_file(&path, namespace)?);
        } else if path.is_dir() && path.join("template.liquid").is_file() {
            specs.push(load_directory_spec(&path, namespace)?);
        }
    }
    specs.sort_by(|a, b| {
        a.complexity
            .cmp(&b.complexity)
            .then_with(|| a.name.cmp(&b.name))
    });
    Ok(specs)
}

pub fn load_spec_file(path: &Path, namespace: &Namespace) -> Result<Vec<Spec>> {
    let content = fs::read_to_string(path)?;
    load_specs_yaml(&content, path, namespace)
}

/// Load one or more specs from YAML text using the same normalization and
/// metadata rules as a committed spec file. `source` is used only for error
/// locations and resolving `_metadata.data_files`; callers reading stdin can
/// pass a descriptive path such as `<stdin>`.
pub fn load_specs_yaml(content: &str, source: &Path, namespace: &Namespace) -> Result<Vec<Spec>> {
    // serde_yaml intentionally rejects Ruby object construction. The one legacy
    // tag retained by the corpus is normalized into an explicit regexp marker.
    let normalized = normalize_yaml(content);
    let mut specs = Vec::new();
    let documents = parse_yaml_documents(&normalized, source)?;
    for file in documents {
        let (metadata, values) = split_spec_document(file)?;
        let base = source.parent().unwrap_or_else(|| Path::new("."));
        let shared = load_shared_data(base, &metadata.data_files)?;
        specs.extend(
            values
                .into_iter()
                .map(|value| build_spec(value, &metadata, &shared, source, namespace))
                .collect::<Result<Vec<_>>>()?,
        );
    }
    Ok(specs)
}

fn parse_yaml_documents(content: &str, path: &Path) -> Result<Vec<serde_yaml::Value>> {
    let parse = |input: &str| {
        serde_yaml::Deserializer::from_str(input)
            .map(serde_yaml::Value::deserialize)
            .collect::<std::result::Result<Vec<_>, _>>()
    };
    match parse(content) {
        Ok(documents) => Ok(documents),
        Err(error) if error.to_string().contains("recursion limit") => {
            // Recursive YAML aliases are only used by Ruby-object compatibility
            // fixtures. Preserve the spec metadata and make the recursive value
            // inert so portable adapters can skip it by feature.
            let decycled = regex::Regex::new(r"\*[0-9]+")
                .expect("valid alias regexp")
                .replace_all(content, "{}");
            parse(&decycled).with_context(|| format!("parse {}", path.display()))
        }
        Err(error) => Err(error).with_context(|| format!("parse {}", path.display())),
    }
}

fn split_spec_document(file: serde_yaml::Value) -> Result<(Metadata, Vec<serde_yaml::Value>)> {
    match file {
        serde_yaml::Value::Null => Ok((Metadata::default(), Vec::new())),
        serde_yaml::Value::Sequence(values) => Ok((Metadata::default(), values)),
        serde_yaml::Value::Mapping(mut mapping) => {
            // Ad-hoc evaluation accepts a single spec mapping directly (the
            // ergonomic form shown in the CLI docs).  Committed files use the
            // extended `{_metadata, specs}` wrapper, but treating a mapping
            // with a `name` field as one spec keeps both forms on the same
            // loader path.
            if mapping.contains_key(serde_yaml::Value::String("name".into())) {
                return Ok((
                    Metadata::default(),
                    vec![serde_yaml::Value::Mapping(mapping)],
                ));
            }
            let metadata = mapping
                .remove(serde_yaml::Value::String("_metadata".into()))
                .map(serde_yaml::from_value)
                .transpose()?
                .unwrap_or_default();
            let values = mapping
                .remove(serde_yaml::Value::String("specs".into()))
                .and_then(|value| value.as_sequence().cloned())
                .context("extended spec file requires a specs array")?;
            Ok((metadata, values))
        }
        _ => bail!("spec document must be an array or an extended mapping"),
    }
}

fn normalize_yaml(input: &str) -> String {
    let large_integer = regex::Regex::new(
        r"^(?P<prefix>\s*(?:[^:#\n]+:|-)\s*)(?P<value>-?[0-9]{20,})(?P<suffix>\s*(?:#.*)?)$",
    )
    .expect("valid integer normalization regexp");
    input
        .lines()
        .map(|line| {
            if let Some(index) = line.find("!ruby/regexp ") {
                let prefix = &line[..index];
                let pattern = &line[index + "!ruby/regexp ".len()..];
                format!("{prefix}{{ __liquid_spec_regex: {:?} }}", pattern.trim())
            } else if line == "..." {
                "---".to_owned()
            } else if let Some(captures) = large_integer.captures(line) {
                format!(
                    "{}!liquid-spec/integer {:?}{}",
                    &captures["prefix"], &captures["value"], &captures["suffix"]
                )
            } else {
                line.to_owned()
            }
        })
        .collect::<Vec<_>>()
        .join("\n")
}

fn load_shared_data(base: &Path, files: &[String]) -> Result<serde_yaml::Mapping> {
    let mut merged = serde_yaml::Mapping::new();
    for file in files {
        let value: serde_yaml::Value = serde_yaml::from_str(&fs::read_to_string(base.join(file))?)?;
        let mapping = value
            .as_mapping()
            .context("shared data file must contain a mapping")?;
        for (key, value) in mapping {
            merged.insert(key.clone(), value.clone());
        }
    }
    Ok(merged)
}

fn build_spec(
    value: serde_yaml::Value,
    metadata: &Metadata,
    shared: &serde_yaml::Mapping,
    path: &Path,
    namespace: &Namespace,
) -> Result<Spec> {
    let map = value.as_mapping().context("spec entry must be a mapping")?;
    let get = |name: &str| map.get(serde_yaml::Value::String(name.into()));
    let name = get("name")
        .and_then(|v| v.as_str())
        .context("spec requires name")?
        .to_owned();
    let template = get("template")
        .and_then(|v| v.as_str())
        .with_context(|| format!("spec {name} requires template"))?
        .to_owned();
    let template_name = get("template_name")
        .and_then(|v| v.as_str())
        .unwrap_or("main")
        .to_owned();
    let mut sources = BTreeMap::from([(template_name.clone(), template)]);
    if let Some(filesystem) = get("filesystem").and_then(|v| v.as_mapping()) {
        for (key, value) in filesystem {
            if let (Some(key), Some(value)) = (key.as_str(), value.as_str()) {
                sources.insert(key.into(), value.into());
            }
        }
    }
    let mut env = shared.clone();
    if let Some(environment) = get("environment").and_then(|v| v.as_mapping()) {
        for (key, value) in environment {
            env.insert(key.clone(), value.clone());
        }
    }
    let environment: BTreeMap<String, WireValue> = env
        .into_iter()
        .map(|(key, value)| {
            let key = key
                .as_str()
                .context("environment keys must be strings")?
                .to_owned();
            Ok((key, yaml_to_wire(value)?))
        })
        .collect::<Result<_>>()?;
    let expected = parse_expected(map)?;
    let complexity = get("complexity")
        .and_then(|v| v.as_u64())
        .map(|v| v as u16)
        .or(metadata.minimum_complexity)
        .or(metadata.complexity)
        .unwrap_or(namespace.minimum_complexity);
    if complexity > 1000 {
        bail!("spec {name}: complexity exceeds 1000");
    }
    let mut features: BTreeSet<String> = namespace.features.iter().cloned().collect();
    features.extend(metadata.features.iter().cloned());
    if let Some(values) = get("features").and_then(|v| v.as_sequence()) {
        features.extend(
            values
                .iter()
                .filter_map(|v| v.as_str().map(ToOwned::to_owned)),
        );
    }
    if environment.values().any(contains_fixture) {
        features.insert("drops".into());
    }
    if environment.values().any(contains_ruby_fixture) {
        features.insert("ruby_compat".into());
    }
    if environment.values().any(contains_binary_data) {
        features.insert("binary_data".into());
    }
    let error_modes = get("error_mode")
        .map(mode_strings)
        .filter(|modes| !modes.is_empty())
        .or_else(|| {
            metadata
                .required_options
                .get("error_mode")
                .map(mode_strings)
                .filter(|modes| !modes.is_empty())
        })
        .or_else(|| namespace.defaults.error_mode.clone().map(|mode| vec![mode]))
        .unwrap_or_default();
    let error_mode = error_modes.first().cloned();
    if let Some(mode) = &error_mode {
        features.insert(format!("{mode}_parsing"));
    }
    let render_errors = get("render_errors")
        .and_then(|v| v.as_bool())
        .or(metadata.render_errors)
        .unwrap_or(namespace.defaults.render_errors);
    if render_errors {
        features.insert("inline_errors".into());
    }
    Ok(Spec {
        name,
        bundle: TemplateBundle {
            entry: template_name,
            sources,
        },
        environment,
        expected,
        complexity,
        hint: get("hint")
            .and_then(|v| v.as_str())
            .map(ToOwned::to_owned)
            .or_else(|| metadata.hint.clone()),
        doc: get("doc")
            .and_then(|v| v.as_str())
            .map(ToOwned::to_owned)
            .or_else(|| metadata.doc.clone()),
        features,
        error_modes,
        compile_options: CompileOptions {
            parse_mode: error_mode,
            line_numbers: true,
        },
        render_options: RenderOptions {
            error_policy: if render_errors { "inline" } else { "raise" }.into(),
            now: Some("2024-01-01T00:01:58Z".into()),
            resource_limits: get("resource_limits").map(yaml_to_json).transpose()?,
        },
        source_file: path.to_owned(),
    })
}

fn primary_string(value: &serde_yaml::Value) -> Option<String> {
    value
        .as_str()
        .map(normalize_mode)
        .or_else(|| value.as_sequence()?.first()?.as_str().map(normalize_mode))
}

fn mode_strings(value: &serde_yaml::Value) -> Vec<String> {
    match value {
        serde_yaml::Value::Sequence(values) => values
            .iter()
            .filter_map(|value| value.as_str().map(normalize_mode))
            .collect(),
        _ => primary_string(value).into_iter().collect(),
    }
}

fn normalize_mode(value: &str) -> String {
    value.strip_prefix(':').unwrap_or(value).to_owned()
}

#[allow(clippy::collapsible_if, clippy::cmp_owned)]
fn parse_expected(map: &serde_yaml::Mapping) -> Result<Expected> {
    let key = |name: &str| serde_yaml::Value::String(name.into());
    if let Some(value) = map.get(key("expected")).and_then(|v| v.as_str()) {
        return Ok(Expected::Output(value.as_bytes().to_vec()));
    }
    if let Some(serde_yaml::Value::Tagged(tagged)) = map.get(key("expected")) {
        if tagged.tag.to_string() == "!binary" {
            use base64::Engine;
            let encoded = tagged
                .value
                .as_str()
                .context("!binary expected value must be text")?;
            return base64::engine::general_purpose::STANDARD
                .decode(encoded.split_whitespace().collect::<String>())
                .map(Expected::Output)
                .context("decode !binary expected value");
        }
    }
    if let Some(value) = map.get(key("expected_pattern")).and_then(|v| v.as_str()) {
        return Ok(Expected::Pattern(value.into()));
    }
    if let Some(errors) = map.get(key("errors")).and_then(|v| v.as_mapping()) {
        for phase in ["parse_error", "render_error", "output"] {
            if let Some(patterns) = errors.get(key(phase)).and_then(|v| v.as_sequence()) {
                let patterns = patterns
                    .iter()
                    .map(|value| {
                        if let Some(value) = value.as_str() {
                            Ok(ErrorPattern::Literal(value.into()))
                        } else if let Some(pattern) = value
                            .as_mapping()
                            .and_then(|m| m.get(key("__liquid_spec_regex")))
                            .and_then(|v| v.as_str())
                        {
                            Ok(ErrorPattern::Regex(pattern.into()))
                        } else {
                            bail!("error pattern must be a string or regexp")
                        }
                    })
                    .collect::<Result<_>>()?;
                return Ok(Expected::Error {
                    phase: phase.into(),
                    patterns,
                });
            }
        }
    }
    bail!("spec requires expected, expected_pattern, or errors")
}

#[allow(clippy::cmp_owned)]
fn yaml_to_wire(value: serde_yaml::Value) -> Result<WireValue> {
    if let serde_yaml::Value::Tagged(tagged) = &value {
        if tagged.tag.to_string() == "!binary" {
            use base64::Engine;
            let encoded = tagged
                .value
                .as_str()
                .context("!binary value must be text")?;
            return base64::engine::general_purpose::STANDARD
                .decode(encoded.split_whitespace().collect::<String>())
                .map(WireValue::Bytes)
                .context("decode !binary value");
        }
        if tagged.tag.to_string() == "!liquid-spec/integer" {
            return Ok(WireValue::BigInteger(
                tagged
                    .value
                    .as_str()
                    .context("tagged integer must be text")?
                    .into(),
            ));
        }
    }
    if let Some(map) = value.as_mapping() {
        if map.len() == 1 {
            let (key, params) = map.iter().next().unwrap();
            if let Some(name) = key
                .as_str()
                .and_then(|key| key.strip_prefix("instantiate:"))
                .map(|name| name.trim_end_matches(':'))
            {
                return Ok(WireValue::Fixture(Fixture {
                    set: fixture_set(name).into(),
                    version: 1,
                    name: name.into(),
                    params: yaml_to_json(params)?,
                }));
            }
        }
        if map.keys().all(|key| key.as_str().is_some()) {
            return map
                .iter()
                .map(|(key, value)| {
                    Ok((
                        key.as_str().expect("checked string key").to_owned(),
                        yaml_to_wire(value.clone())?,
                    ))
                })
                .collect::<Result<_>>()
                .map(WireValue::Object);
        }
        return map
            .iter()
            .map(|(key, value)| Ok((yaml_to_wire(key.clone())?, yaml_to_wire(value.clone())?)))
            .collect::<Result<_>>()
            .map(WireValue::Map);
    }
    match value {
        serde_yaml::Value::Null => Ok(WireValue::Null),
        serde_yaml::Value::Bool(value) => Ok(WireValue::Bool(value)),
        serde_yaml::Value::Number(value) => yaml_number_to_wire(value),
        serde_yaml::Value::String(value) => Ok(WireValue::String(value)),
        serde_yaml::Value::Sequence(values) => values
            .into_iter()
            .map(yaml_to_wire)
            .collect::<Result<_>>()
            .map(WireValue::Array),
        serde_yaml::Value::Tagged(tagged) => yaml_to_wire(tagged.value),
        serde_yaml::Value::Mapping(_) => unreachable!("mappings returned above"),
    }
}

#[allow(clippy::collapsible_if)]
fn yaml_number_to_wire(value: serde_yaml::Number) -> Result<WireValue> {
    if let Some(value) = value.as_i64() {
        return Ok(WireValue::Number(value.into()));
    }
    if let Some(value) = value.as_u64() {
        return Ok(WireValue::Number(value.into()));
    }
    if let Some(value) = value.as_f64() {
        if let Some(number) = serde_json::Number::from_f64(value) {
            return Ok(WireValue::Number(number));
        }
    }
    Ok(WireValue::BigInteger(value.to_string()))
}

fn fixture_set(name: &str) -> &'static str {
    match name {
        "BooleanDrop" | "NumberDrop" | "StringDrop" | "MethodDrop" | "IndexDrop"
        | "SequenceDrop" | "NilDrop" | "OpaqueDrop" | "ErrorDrop" | "NestedDrop" => {
            "standard-drops"
        }
        _ => "ruby-compat",
    }
}

fn contains_ruby_fixture(value: &WireValue) -> bool {
    match value {
        WireValue::Fixture(fixture) => fixture.set == "ruby-compat",
        WireValue::Array(values) => values.iter().any(contains_ruby_fixture),
        WireValue::Object(values) => values.values().any(contains_ruby_fixture),
        WireValue::Map(values) => values
            .iter()
            .any(|(key, value)| contains_ruby_fixture(key) || contains_ruby_fixture(value)),
        WireValue::Range { start, end, .. } => {
            contains_ruby_fixture(start) || contains_ruby_fixture(end)
        }
        _ => false,
    }
}

fn contains_fixture(value: &WireValue) -> bool {
    match value {
        WireValue::Fixture(_) => true,
        WireValue::Array(values) => values.iter().any(contains_fixture),
        WireValue::Object(values) => values.values().any(contains_fixture),
        WireValue::Map(values) => values
            .iter()
            .any(|(key, value)| contains_fixture(key) || contains_fixture(value)),
        WireValue::Range { start, end, .. } => contains_fixture(start) || contains_fixture(end),
        _ => false,
    }
}

fn contains_binary_data(value: &WireValue) -> bool {
    match value {
        WireValue::Bytes(_) => true,
        WireValue::Array(values) => values.iter().any(contains_binary_data),
        WireValue::Object(values) => values.values().any(contains_binary_data),
        WireValue::Map(values) => values
            .iter()
            .any(|(key, value)| contains_binary_data(key) || contains_binary_data(value)),
        WireValue::Range { start, end, .. } => {
            contains_binary_data(start) || contains_binary_data(end)
        }
        _ => false,
    }
}

fn yaml_to_json(value: &serde_yaml::Value) -> Result<JsonValue> {
    Ok(match value {
        serde_yaml::Value::Null => JsonValue::Null,
        serde_yaml::Value::Bool(v) => (*v).into(),
        serde_yaml::Value::Number(v) => serde_json::to_value(v)?,
        serde_yaml::Value::String(v) => v.clone().into(),
        serde_yaml::Value::Sequence(v) => {
            JsonValue::Array(v.iter().map(yaml_to_json).collect::<Result<_>>()?)
        }
        serde_yaml::Value::Mapping(v) => {
            let mut object = serde_json::Map::new();
            for (key, value) in v {
                object.insert(
                    key.as_str()
                        .context("JSON object keys must be strings")?
                        .into(),
                    yaml_to_json(value)?,
                );
            }
            JsonValue::Object(object)
        }
        serde_yaml::Value::Tagged(tagged) => yaml_to_json(&tagged.value)?,
    })
}

fn load_directory_spec(path: &Path, namespace: &Namespace) -> Result<Spec> {
    let name = path.file_name().unwrap().to_string_lossy().into_owned();
    let template = fs::read_to_string(path.join("template.liquid"))?;
    let expected = fs::read_to_string(path.join("expected.html"))?;
    let environment = if path.join("environment.yml").is_file() {
        let raw: serde_yaml::Mapping =
            serde_yaml::from_str(&fs::read_to_string(path.join("environment.yml"))?)?;
        raw.into_iter()
            .map(|(key, value)| {
                Ok((
                    key.as_str()
                        .context("environment key must be a string")?
                        .into(),
                    yaml_to_wire(value)?,
                ))
            })
            .collect::<Result<_>>()?
    } else {
        BTreeMap::new()
    };
    Ok(Spec {
        name,
        bundle: TemplateBundle {
            entry: "main".into(),
            sources: BTreeMap::from([("main".into(), template)]),
        },
        environment,
        expected: Expected::Output(expected.into_bytes()),
        complexity: namespace.minimum_complexity,
        hint: None,
        doc: None,
        features: namespace.features.clone(),
        error_modes: namespace.defaults.error_mode.clone().into_iter().collect(),
        compile_options: CompileOptions {
            parse_mode: namespace.defaults.error_mode.clone(),
            line_numbers: true,
        },
        render_options: RenderOptions {
            error_policy: if namespace.defaults.render_errors {
                "inline"
            } else {
                "raise"
            }
            .into(),
            now: Some("2024-01-01T00:01:58Z".into()),
            resource_limits: None,
        },
        source_file: path.join("template.liquid"),
    })
}
