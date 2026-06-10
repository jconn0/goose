---
phase: 50
slug: morning-band-sleep-sync
status: draft
nyquist_compliant: true
wave_0_complete: false
created: 2026-06-10
---

# Phase 50 — Validation Strategy

> Per-phase validation contract for feedback sampling during execution.

---

## Test Infrastructure

| Property | Value |
|----------|-------|
| **Framework** | Rust built-in test runner (cargo test) |
| **Config file** | Rust/core/Cargo.toml |
| **Quick run command** | `cargo test -p goose-core 2>&1 \| tail -20` |
| **Full suite command** | `cargo test -p goose-core` |
| **Estimated runtime** | ~30 seconds |

---

## Sampling Rate

- **After every task commit:** Run `cargo test -p goose-core 2>&1 | tail -20`
- **After every plan wave:** Run `cargo test -p goose-core`
- **Before `/gsd-verify-work`:** Full suite must be green
- **Max feedback latency:** 30 seconds

---

## Per-Task Verification Map

| Task ID | Plan | Wave | Requirement | Automated Command | File Exists | Status |
|---------|------|------|-------------|-------------------|-------------|--------|
| 50-01-01 | 01 | 1 | SLP-SYNC-01 | `cargo check -p goose-core` | ✅ | ⬜ pending |
| 50-01-02 | 01 | 1 | SLP-SYNC-01, SLP-SYNC-02 | `cargo test -p goose-core bridge_v24_gravity_extraction bridge_v24_gravity_insert_roundtrip bridge_band_sleep_external_session_insert bridge_band_sleep_no_duplicate` | ❌ Wave 0 | ⬜ pending |
| 50-02-01 | 02 | 1 | SLP-SYNC-02 | `xcodebuild -project GooseSwift.xcodeproj -scheme GooseSwift -destination 'platform=iOS Simulator,name=iPhone 16' build 2>&1 \| grep -E 'error:\|Build succeeded\|Build failed'` | ❌ Wave 0 | ⬜ pending |
| 50-02-02 | 02 | 1 | SLP-SYNC-03 | `grep -n "A aguardar sincronização" GooseSwift/HealthDataStore.swift` | ✅ | ⬜ pending |
| 50-03-01 | 03 | 2 | SLP-SYNC-01, SLP-SYNC-02 | `cargo test -p goose-core && xcodebuild -project GooseSwift.xcodeproj -scheme GooseSwift -destination 'platform=iOS Simulator,name=iPhone 16' build 2>&1 \| grep -E 'error:\|Build succeeded'` | ✅ | ⬜ pending |
| 50-03-02 | 03 | 2 | SLP-SYNC-03 | manual | N/A | ⬜ pending |

*Status: ⬜ pending · ✅ green · ❌ red · ⚠️ flaky*

---

## Wave 0 Requirements

- [ ] `Rust/core/tests/bridge_tests.rs` — adicionar: `bridge_v24_gravity_extraction`, `bridge_v24_gravity_insert_roundtrip`, `bridge_band_sleep_external_session_insert`, `bridge_band_sleep_no_duplicate`
- [ ] `GooseSwift/GooseAppModel+SleepSync.swift` — ficheiro novo criado em Plan 50-02

*Testes Rust são criados em Plan 50-01 Task 2. GooseAppModel+SleepSync.swift em Plan 50-02 Task 1.*

---

## Manual-Only Verifications

| Behavior | Requirement | Why Manual | Test Instructions |
|----------|-------------|------------|-------------------|
| bandSleepImportStatus = "Sincronizado da pulseira" após sync bem-sucedido | SLP-SYNC-03 | Requer simulação de BLE sync completo — sem testes Swift automatizados no projecto | Build + run simulator, simular BLE connection, verificar label no Sleep V2 BandSyncCard |
| "A aguardar sincronização" em noite sem sync | SLP-SYNC-03 | Estado inicial sem dispositivo conectado | Verificar label inicial no BandSyncCard sem WHOOP conectado |

---

## Validation Sign-Off

- [x] All tasks have `<automated>` verify or Wave 0 dependencies
- [x] Sampling continuity: no 3 consecutive tasks without automated verify
- [x] Wave 0 covers all MISSING (❌) references — Rust tests created in 50-01 Task 2
- [x] No watch-mode flags
- [x] Feedback latency < 30s
- [x] `nyquist_compliant: true` set in frontmatter

**Approval:** pending
