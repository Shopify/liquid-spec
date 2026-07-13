//! Version 2 of the language-neutral liquid-spec adapter protocol.

mod benchmark;
mod rpc;
mod value;

pub use benchmark::*;
pub use rpc::*;
pub use value::*;

pub const PROTOCOL_VERSION: &str = "2";
pub const JSONRPC_VERSION: &str = "2.0";

/// Language-neutral lifecycle vectors shared by adapter implementations.
pub const CONFORMANCE_VECTORS_JSON: &str =
    include_str!("../../../docs/json-rpc-protocol-v2-vectors.json");

#[cfg(test)]
mod vector_tests {
    use super::CONFORMANCE_VECTORS_JSON;

    #[test]
    fn bundled_vectors_have_valid_jsonrpc_framing() {
        let document: serde_json::Value = serde_json::from_str(CONFORMANCE_VECTORS_JSON).unwrap();
        assert_eq!(document["protocol_version"], "2");
        let vectors = document["vectors"].as_array().unwrap();
        assert!(vectors.len() >= 6);
        for vector in vectors {
            let requests = vector
                .get("requests")
                .and_then(|requests| requests.as_array())
                .cloned()
                .or_else(|| vector.get("request").map(|request| vec![request.clone()]))
                .unwrap();
            assert!(!requests.is_empty());
            for request in requests {
                assert_eq!(request["jsonrpc"], "2.0");
                assert!(request["method"].as_str().is_some());
                if request["method"] != "shutdown" {
                    assert!(request["id"].as_u64().is_some());
                }
            }
        }
    }
}
