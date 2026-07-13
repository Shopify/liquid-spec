//! Built-in implementer documentation exposed by `liquid-spec docs`.
//!
//! A release binary cannot assume that the source checkout is next to it, so
//! the high-signal pages are embedded. During development `LIQUID_SPEC_DOCS`
//! can point at a docs directory to preview edits without rebuilding.

use anyhow::{Context, Result};
use std::fs;
use std::path::{Path, PathBuf};

const TOPICS: &[(&str, &str, &str)] = &[
    (
        "json-rpc-protocol-v2",
        "JSON-RPC adapter protocol v2",
        "json-rpc-protocol-v2.md",
    ),
    (
        "json-rpc-protocol",
        "JSON-RPC protocol compatibility overview",
        "json-rpc-protocol.md",
    ),
    (
        "protocol",
        "JSON-RPC adapter protocol v2 (alias)",
        "json-rpc-protocol-v2.md",
    ),
    (
        "curriculum",
        "Implementer curriculum",
        "implementers/curriculum.md",
    ),
    (
        "core-abstractions",
        "Core implementation abstractions",
        "implementers/core-abstractions.md",
    ),
    (
        "complexity",
        "Complexity and ramp ordering",
        "implementers/complexity.md",
    ),
    ("grammar", "Liquid grammar", "implementers/grammar.md"),
    ("filters", "Filters", "implementers/filters.md"),
    (
        "scopes",
        "Scopes and environments",
        "implementers/scopes.md",
    ),
    (
        "partials",
        "Partials and filesystem access",
        "implementers/partials.md",
    ),
    (
        "parsing",
        "Parsing modes and errors",
        "implementers/parsing.md",
    ),
    (
        "adversarial",
        "Adversarial testing",
        "implementers/adversarial.md",
    ),
    ("cycle", "Cycle tag", "implementers/cycle.md"),
    (
        "filesystem",
        "Filesystem access",
        "implementers/filesystem.md",
    ),
    ("for-loops", "For loops", "implementers/for-loops.md"),
    ("il", "Intermediate language", "implementers/il.md"),
    ("interrupts", "Interrupts", "implementers/interrupts.md"),
    (
        "ruby-quirks",
        "Ruby compatibility quirks",
        "implementers/ruby-quirks.md",
    ),
    (
        "shopify-theme-filters",
        "Shopify theme filters",
        "implementers/shopify-theme-filters.md",
    ),
    ("tablerow", "Tablerow tag", "implementers/tablerow.md"),
    (
        "test-drops",
        "Portable standard fixture drops",
        "test_drops.md",
    ),
    (
        "json-rpc-type-transport",
        "Typed JSON-RPC values",
        "json-rpc-type-transport.md",
    ),
    ("truthiness", "Liquid truthiness", "truthiness.md"),
    (
        "filter-matrix-quirks",
        "Filter matrix quirks",
        "filter_matrix_quirks.md",
    ),
    (
        "ruby-hash-inspect-format",
        "Ruby hash inspect format",
        "ruby_hash_inspect_format.md",
    ),
];

pub fn list() {
    println!("Available documentation topics:\n");
    println!("Docs directory: {}\n", docs_root_display());
    for (topic, description, relative) in TOPICS {
        println!("  {topic:<28} {:<46} {description}", topic_path(relative));
    }
    println!(
        "\nUse `liquid-spec docs TOPIC` to print a topic. TOPIC may be a case-insensitive\nsubstring of the topic name, description, or .md filename."
    );
}

pub fn print(topic: Option<&str>) -> Result<()> {
    let Some(topic) = topic else {
        list();
        return Ok(());
    };
    if matches!(topic, "list" | "help") {
        list();
        return Ok(());
    }
    let relative = resolve_topic(topic)?;
    let content = read_topic(relative)?;
    print!("{content}");
    if !content.ends_with('\n') {
        println!();
    }
    Ok(())
}

/// Resolve an exact topic name first, then accept a case-insensitive substring
/// of a topic name, its description, or its `.md` path. Exact aliases are
/// intentionally retained (`protocol` is a short name for the v2 guide),
/// while ambiguous substrings produce a useful list instead of silently
/// selecting an arbitrary document.
fn resolve_topic(query: &str) -> Result<&'static str> {
    let query = query.trim();
    let exact = TOPICS.iter().find(|(name, _, relative)| {
        name.eq_ignore_ascii_case(query)
            || relative.eq_ignore_ascii_case(query)
            || topic_path(relative).eq_ignore_ascii_case(query)
    });
    if let Some((_, _, relative)) = exact {
        return Ok(relative);
    }

    let needle = normalize(query);
    let mut matches = Vec::new();
    for (name, description, relative) in TOPICS {
        if (normalize(name).contains(&needle)
            || normalize(description).contains(&needle)
            || normalize(relative).contains(&needle)
            || normalize(&topic_path(relative)).contains(&needle))
            && !matches.contains(relative)
        {
            matches.push(relative);
        }
    }
    match matches.as_slice() {
        [relative] => Ok(relative),
        [] => Err(anyhow::anyhow!(
            "unknown docs topic {query:?}; run `liquid-spec docs list`"
        )),
        _ => {
            let choices = matches
                .iter()
                .map(|relative| format!("  {}", topic_path(relative)))
                .collect::<Vec<_>>()
                .join("\n");
            Err(anyhow::anyhow!(
                "docs topic {query:?} is ambiguous; matching files:\n{choices}"
            ))
        }
    }
}

fn normalize(value: &str) -> String {
    value
        .trim()
        .to_ascii_lowercase()
        .replace(['\\', '_', ' '], "-")
}

fn docs_root() -> Option<PathBuf> {
    if let Some(configured) = std::env::var_os("LIQUID_SPEC_DOCS").map(PathBuf::from)
        && configured.is_dir()
    {
        return absolute_path(&configured);
    }
    let source = Path::new(env!("CARGO_MANIFEST_DIR")).join("../../docs");
    source.is_dir().then(|| absolute_path(&source)).flatten()
}

fn absolute_path(path: &Path) -> Option<PathBuf> {
    if let Ok(path) = fs::canonicalize(path) {
        return Some(path);
    }
    if path.is_absolute() {
        Some(path.to_path_buf())
    } else {
        std::env::current_dir().ok().map(|cwd| cwd.join(path))
    }
}

fn docs_root_display() -> String {
    docs_root()
        .map(|path| path.display().to_string())
        .unwrap_or_else(|| "<embedded docs; source directory unavailable>".to_owned())
}

fn topic_path(relative: &str) -> String {
    docs_root()
        .map(|root| root.join(relative).display().to_string())
        .unwrap_or_else(|| format!("<embedded docs>/{relative}"))
}

fn read_topic(relative: &str) -> Result<String> {
    if let Some(root) = std::env::var_os("LIQUID_SPEC_DOCS") {
        let path = PathBuf::from(root).join(relative);
        if path.is_file() {
            return fs::read_to_string(&path)
                .with_context(|| format!("read documentation {}", path.display()));
        }
    }
    let root = Path::new(env!("CARGO_MANIFEST_DIR")).join("../../docs");
    let path = root.join(relative);
    if path.is_file() {
        return fs::read_to_string(&path)
            .with_context(|| format!("read documentation {}", path.display()));
    }
    embedded_topic(relative)
        .map(str::to_owned)
        .ok_or_else(|| anyhow::anyhow!(
            "documentation file {relative:?} is not available; set LIQUID_SPEC_DOCS to a docs directory"
        ))
}

fn embedded_topic(relative: &str) -> Option<&'static str> {
    Some(match relative {
        "json-rpc-protocol-v2.md" => include_str!("../../../docs/json-rpc-protocol-v2.md"),
        "json-rpc-protocol.md" => include_str!("../../../docs/json-rpc-protocol.md"),
        "implementers/curriculum.md" => include_str!("../../../docs/implementers/curriculum.md"),
        "implementers/core-abstractions.md" => {
            include_str!("../../../docs/implementers/core-abstractions.md")
        }
        "implementers/complexity.md" => include_str!("../../../docs/implementers/complexity.md"),
        "implementers/grammar.md" => include_str!("../../../docs/implementers/grammar.md"),
        "implementers/filters.md" => include_str!("../../../docs/implementers/filters.md"),
        "implementers/scopes.md" => include_str!("../../../docs/implementers/scopes.md"),
        "implementers/partials.md" => include_str!("../../../docs/implementers/partials.md"),
        "implementers/parsing.md" => include_str!("../../../docs/implementers/parsing.md"),
        "implementers/adversarial.md" => include_str!("../../../docs/implementers/adversarial.md"),
        "implementers/cycle.md" => include_str!("../../../docs/implementers/cycle.md"),
        "implementers/filesystem.md" => include_str!("../../../docs/implementers/filesystem.md"),
        "implementers/for-loops.md" => include_str!("../../../docs/implementers/for-loops.md"),
        "implementers/il.md" => include_str!("../../../docs/implementers/il.md"),
        "implementers/interrupts.md" => include_str!("../../../docs/implementers/interrupts.md"),
        "implementers/ruby-quirks.md" => include_str!("../../../docs/implementers/ruby-quirks.md"),
        "implementers/shopify-theme-filters.md" => {
            include_str!("../../../docs/implementers/shopify-theme-filters.md")
        }
        "implementers/tablerow.md" => include_str!("../../../docs/implementers/tablerow.md"),
        "test_drops.md" => include_str!("../../../docs/test_drops.md"),
        "json-rpc-type-transport.md" => include_str!("../../../docs/json-rpc-type-transport.md"),
        "truthiness.md" => include_str!("../../../docs/truthiness.md"),
        "filter_matrix_quirks.md" => include_str!("../../../docs/filter_matrix_quirks.md"),
        "ruby_hash_inspect_format.md" => include_str!("../../../docs/ruby_hash_inspect_format.md"),
        _ => return None,
    })
}
