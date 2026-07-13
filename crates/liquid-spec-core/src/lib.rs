mod spec;

pub use spec::*;

#[cfg(test)]
mod corpus_tests {
    use super::*;
    use std::path::PathBuf;

    #[test]
    fn every_builtin_namespace_loads_without_ruby_instantiation() {
        let root = PathBuf::from(env!("CARGO_MANIFEST_DIR")).join("../../specs");
        let namespaces = discover_namespaces(&root).expect("discover built-in namespaces");
        assert!(
            namespaces.len() >= 8,
            "expected built-in namespaces, got {}",
            namespaces.len()
        );
        let mut total = 0;
        for namespace in namespaces {
            let specs = load_namespace(&namespace)
                .unwrap_or_else(|error| panic!("{}: {error:#}", namespace.id));
            total += specs.len();
        }
        assert!(
            total > 4_000,
            "expected the full corpus, loaded only {total} specs"
        );
    }

    #[test]
    fn ruby_symbol_style_error_modes_are_normalized_for_v2() {
        let root = PathBuf::from(env!("CARGO_MANIFEST_DIR")).join("../../specs");
        let namespace = discover_namespaces(&root)
            .unwrap()
            .into_iter()
            .find(|namespace| namespace.id == "basics")
            .unwrap();
        let specs = load_namespace(&namespace).unwrap();
        let spec = specs
            .iter()
            .find(|spec| spec.name.contains("division_by_zero_lax"))
            .unwrap();
        assert_eq!(spec.compile_options.parse_mode.as_deref(), Some("lax"));
        assert!(spec.features.contains("lax_parsing"));
    }

    #[test]
    fn ruby_only_fixture_descriptors_are_gated() {
        let root = PathBuf::from(env!("CARGO_MANIFEST_DIR")).join("../../specs");
        let namespace = discover_namespaces(&root)
            .unwrap()
            .into_iter()
            .find(|namespace| namespace.id == "liquid_ruby")
            .unwrap();
        let specs = load_namespace(&namespace).unwrap();
        let spec = specs
            .iter()
            .find(|spec| spec.name == "sec_drop_blocks_class")
            .unwrap();
        assert!(spec.features.contains("ruby_compat"));
    }

    #[test]
    fn standard_fixture_descriptors_require_the_portable_drop_set() {
        let root = PathBuf::from(env!("CARGO_MANIFEST_DIR")).join("../../specs");
        let namespace = discover_namespaces(&root)
            .unwrap()
            .into_iter()
            .find(|namespace| namespace.id == "basics")
            .unwrap();
        let specs = load_namespace(&namespace).unwrap();
        let spec = specs
            .iter()
            .find(|spec| spec.name == "drop_boolean_true_renders")
            .expect("fixture-backed basics spec");
        assert!(spec.features.contains("drops"));
        assert!(!spec.features.contains("ruby_compat"));
    }

    #[test]
    fn ad_hoc_yaml_loader_preserves_spec_metadata() {
        let namespace = Namespace {
            id: "eval".into(),
            name: "eval".into(),
            description: String::new(),
            path: PathBuf::from("."),
            default: false,
            timings: false,
            features: Default::default(),
            minimum_complexity: 1000,
            default_iteration_seconds: 5.0,
            defaults: NamespaceDefaults::default(),
        };
        let specs = load_specs_yaml(
            "_metadata:\n  hint: use passthrough\nspecs:\n- name: one\n  template: hello\n  expected: hello\n  complexity: 3\n",
            PathBuf::from("<stdin>").as_path(),
            &namespace,
        )
        .unwrap();
        assert_eq!(specs.len(), 1);
        assert_eq!(specs[0].name, "one");
        assert_eq!(specs[0].complexity, 3);
        assert_eq!(specs[0].hint.as_deref(), Some("use passthrough"));
    }
}
