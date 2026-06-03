# Testing Patterns

**Analysis Date:** 2026-06-03

## Test Framework

**Swift (iOS app layer):**
- No XCTest targets exist in the Xcode project (`GooseSwift.xcodeproj/project.pbxproj` contains only `com.apple.product-type.application` and `com.apple.product-type.app-extension`)
- No `XCTestCase`, `@testable import`, or Swift Testing (`import Testing`) files found anywhere in `GooseSwift/`
- **The Swift layer has zero automated test coverage.**

**Rust (core logic layer):**
- Runner: `cargo test` via the standard Rust test harness
- Framework: Built-in `#[test]` attribute — no external test framework
- Config: `Rust/core/Cargo.toml` — `[dev-dependencies]` includes `tempfile = "3.13"` for temp directory fixtures
- Integration tests live in `Rust/core/tests/` (41 test files, 681 `#[test]` functions)

**Run Commands:**
```bash
cd Rust/core
cargo test                            # Run all tests
cargo test -- --nocapture             # Run tests with stdout output visible
cargo test bridge_                    # Run tests matching a name prefix
cargo test --release                  # Run in release mode (used for perf budget tests)
```

## Test File Organization

**Location:**
- All Rust tests are in `Rust/core/tests/` as integration tests (not unit tests in `src/`)
- Each file corresponds to a domain or module: `protocol_tests.rs`, `store_tests.rs`, `bridge_tests.rs`
- No co-located unit tests (`#[cfg(test)] mod tests { ... }` blocks) detected in the survey

**Naming:**
- Files: `<module>_tests.rs` — e.g., `bridge_tests.rs`, `metric_features_tests.rs`, `sleep_validation_tests.rs`
- Functions: snake_case, descriptive of the scenario being verified — e.g., `parses_hand_derived_goose_v5_get_hello_frame`, `bridge_returns_core_version_payload`, `perf_budget_reports_failed_budget_without_hiding_workload_context`

**Structure:**
```
Rust/core/tests/
├── bridge_tests.rs           # FFI bridge round-trips (8,719 lines, largest)
├── protocol_tests.rs         # BLE frame parsing and building
├── store_tests.rs            # SQLite store CRUD and migration
├── fixture_tests.rs          # Fixture index validation
├── property_tests.rs         # Property-based tests (deterministic seed)
├── perf_budget_tests.rs      # Performance budget assertions
├── sleep_validation_tests.rs # Sleep algorithm validation (6,633 lines)
├── export_tests.rs           # Export bundle validation
├── metric_features_tests.rs  # Health metric feature computation
├── history_sync_tests.rs     # Historical BLE sync state machine
├── health_sync_tests.rs      # HealthKit sync dry-run
└── ... (29 more domain files)
```

## Test Structure

**Suite Organization:**
```rust
// Each test is a standalone function — no setup/teardown structs
#[test]
fn bridge_returns_core_version_payload() {
    let response = request(serde_json::json!({
        "schema": "goose.bridge.request.v1",
        "request_id": "version-1",
        "method": "core.version",
        "args": {}
    }));

    assert!(response.ok, "{:?}", response.error);
    assert_eq!(response.result.unwrap()["bridge_request_schema"], "goose.bridge.request.v1");
}
```

**Patterns:**
- No `before_each` or `after_each` — shared setup is provided by private helper functions at the bottom of each test file
- Helper functions are `fn` (not `#[test]`) and are called inline from test bodies
- Test data (constant hex frames, UUIDs, service UUIDs) is defined as `const` at the top of the file, shared across tests in that file

## Mocking

**Framework:** None — no mock libraries used. The Rust layer avoids mocking by using pure functions and in-memory state.

**Patterns:**
- In-memory SQLite databases are used for storage tests: `Connection::open_in_memory()` or `tempfile::tempdir()` with `rusqlite::Connection::open(db_path)`
- FFI bridge is tested directly through the C ABI using real `CString`/`CStr` round-trips — no mocking of the bridge layer
- `tempfile::TempDir` is used to create isolated filesystem fixtures for tests that need file I/O (export tests, fixture index tests)

**What to mock:**
- File system: use `tempfile::tempdir()` to get an isolated working directory
- SQLite: use in-memory connections (`Connection::open_in_memory()`) or temp file paths

**What NOT to mock:**
- The Rust bridge FFI — tests exercise it directly to catch ABI regressions
- Algorithm implementations — property tests and fixture tests run real implementations

## Fixtures and Factories

**Test Data:**
```rust
// Shared constants at file top
const GET_HELLO_FRAME: &str = "aa0108000001e67123019101363e5c8d";
const GET_HELLO_RESPONSE_FRAME: &str = "aa010c000001e7412409910100000000401adc66";
const COMMAND_SERVICE_UUID: &str = "61080001-0000-1000-8000-00805f9b34fb";

// Helper builders for parameterized test data
fn historical_k18_frame_hex(marker_value: u8) -> String {
    let mut payload = vec![PACKET_TYPE_HISTORICAL_DATA, 18, 1, ...];
    hex::encode(build_v5_payload_frame(&payload))
}
```

**Location:**
- Physical fixture files (real captured data) live in `Rust/core/fixtures/` with `owned/` and `synthetic/` subdirectories
- Fixture metadata includes checksums (SHA-256) and schema tags — validated by `fixture_tests.rs`
- Helper builder functions are defined at the bottom of each test file (private to that module)

**Bridge request helper:**
All bridge tests use a shared `request()` helper defined at the bottom of `bridge_tests.rs`:
```rust
fn request(payload: serde_json::Value) -> BridgeResponse {
    let json = payload.to_string();
    let c_str = CString::new(json).unwrap();
    let response_ptr = unsafe { goose_bridge_handle_json(c_str.as_ptr()) };
    // parse and return BridgeResponse
}
```

## Coverage

**Requirements:** Not enforced — no `cargo-tarpaulin` or coverage gating in the project

**View Coverage:**
```bash
# No coverage tooling configured; run manually if needed:
cargo install cargo-tarpaulin
cargo tarpaulin --out Html
```

## Test Types

**Unit Tests (Rust inline `#[cfg(test)]`):**
- Not observed in sampled source files; all tests are integration-style in `tests/`

**Integration Tests (Rust `tests/` directory):**
- Full module-level tests exercising real implementations end-to-end
- Bridge tests verify the complete JSON-over-FFI request/response cycle
- Store tests exercise SQLite migration paths and full CRUD operations
- 41 test files, 681 test functions as of this analysis

**Property Tests:**
- `property_tests.rs` uses a seeded random suite (`seed: 42`, `cases_per_group: 32`) implemented inside the `goose_core` library itself (`goose_core::property_tests`)
- Properties verified: parser frame invariants, deframer stream invariants, algorithm bounds, algorithm metamorphic invariants

**Performance Budget Tests:**
- `perf_budget_tests.rs` runs a workload at a configurable `scale` and asserts against time and memory budgets
- Workloads: `parser_frame_batch`, `deframer_split_stream`, `goose_score_batch`, `raw_export_bundle`
- Failed budgets produce structured `next_actions` with `scope` and `reason` fields

**UI Coverage Tests (Rust):**
- `ui_coverage_tests.rs` audits Android navigation graph / layout / source class inventories against a coverage map
- Uses `tempfile::TempDir` to write CSV inventory files and runs `run_ui_coverage_audit()`
- These are architectural guard tests, not functional tests of the iOS UI

## Common Patterns

**Assertion style:**
```rust
// Always include the debug value in the message on boolean asserts
assert!(response.ok, "{:?}", response.error);
assert!(report.pass, "{:#?}", report.issues);
assert!(index.pass, "{:?}", index.issues);

// Direct equality
assert_eq!(parsed.packet_type_name.as_deref(), Some("COMMAND"));
assert_eq!(report.seed, 42);
```

**Error case testing:**
```rust
fn perf_budget_requires_non_zero_scale() {
    let error = run_perf_budget(PerfBudgetOptions { scale: 0, .. }).unwrap_err();
    assert!(error.to_string().contains("scale"));
}
```

**Async Testing:**
- Not applicable to the Rust test layer (synchronous tests only)
- Swift layer has no tests

**Negative path testing:**
- Tests for `!report.pass` explicitly verify individual failure fields and `issues`/`next_actions` contents
- Assertions on `next_actions` include both `scope` and `reason` and `action` content checks

## Notes for New Tests

**Swift / iOS:**
- No test infrastructure exists. To add XCTest coverage, create a new test target in `GooseSwift.xcodeproj` and add `@testable import GooseSwift` files under a `Tests/` directory
- The main testable logic (algorithm utilities, formatting, data parsing helpers) lives in `GooseSwift/HealthDataStore+Utilities.swift`, `GooseSwift/FitnessFormatting.swift`, `GooseSwift/ActivityModels.swift`

**Rust:**
- Add new test files to `Rust/core/tests/` following the `<domain>_tests.rs` naming pattern
- Place shared constants at the top of the file, private builder helpers at the bottom
- Use `tempfile::tempdir()` for any filesystem I/O
- Use `serde_json::json!({...})` macro for JSON payloads in bridge tests

---

*Testing analysis: 2026-06-03*
