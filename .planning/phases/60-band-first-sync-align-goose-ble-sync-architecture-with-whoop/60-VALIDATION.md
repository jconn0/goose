---
phase: 60
slug: band-first-sync-align-goose-ble-sync-architecture-with-whoop
status: draft
nyquist_compliant: false
wave_0_complete: false
created: 2026-06-11
---

# Phase 60 — Validation Strategy

> Per-phase validation contract for feedback sampling during execution.

---

## Test Infrastructure

| Property | Value |
|----------|-------|
| **Framework** | Xcode build (Swift compiler) — no Swift test target detected |
| **Config file** | GooseSwift.xcodeproj |
| **Quick run command** | `xcodebuild build -project GooseSwift.xcodeproj -scheme GooseSwift -destination "generic/platform=iOS Simulator" 2>&1 | tail -5` |
| **Full suite command** | `xcodebuild build -project GooseSwift.xcodeproj -scheme GooseSwift -destination "generic/platform=iOS Simulator" 2>&1 | grep -E "error:|warning:|BUILD"` |
| **Estimated runtime** | ~60 seconds |

---

## Sampling Rate

- **After every task commit:** Run quick build command
- **After every plan wave:** Run full build + simulator boot check
- **Before `/gsd-verify-work`:** Full build must be green with zero errors
- **Max feedback latency:** 90 seconds

---

## Per-Task Verification Map

| Task ID | Plan | Wave | Requirement | Threat Ref | Secure Behavior | Test Type | Automated Command | File Exists | Status |
|---------|------|------|-------------|------------|-----------------|-----------|-------------------|-------------|--------|
| 60-01-01 | 01 | 1 | overnight-removal | — | No overnightGuard* symbols remain | build | `xcodebuild build ... 2>&1 | grep error:` | ✅ | ⬜ pending |
| 60-01-02 | 01 | 1 | overnight-removal | — | GooseAppModel+OvernightRun.swift deleted | manual | `ls GooseSwift/GooseAppModel+OvernightRun.swift 2>&1` | N/A | ⬜ pending |
| 60-02-01 | 02 | 1 | foreground-sync | — | triggerForegroundBLESync() compiles | build | `xcodebuild build ... 2>&1 | grep error:` | ✅ W0 | ⬜ pending |
| 60-03-01 | 03 | 2 | bg-task | — | BGAppRefreshTask handler compiles, entitlements present | build | `xcodebuild build ... 2>&1 | grep error:` | ✅ W0 | ⬜ pending |

*Status: ⬜ pending · ✅ green · ❌ red · ⚠️ flaky*

---

## Wave 0 Requirements

- No test framework installation needed — build-only validation via Xcode
- Existing infrastructure covers all phase requirements (build-time checks sufficient for removal + new file creation)

*All validation is build-compilation and manual simulator verification.*

---

## Manual-Only Verifications

| Behavior | Requirement | Why Manual | Test Instructions |
|----------|-------------|------------|-------------------|
| Foreground sync fires on app foreground | D-06, D-08 | Requires live WHOOP BLE connection | Boot simulator, navigate to app, background and foreground it, check OSLog for "foreground sync" message |
| 30-min cooldown prevents redundant sync | D-09 | Time-dependent behavior | Trigger foreground sync, immediately background+foreground again, verify "skipped — last sync within 30 min" in OSLog |
| BGAppRefreshTask registers without crash | D-11 | Requires OS scheduling | Run on device or simulator, check Console for BGTaskScheduler registration success |
| Overnight guard UI card absent from More tab | D-02 | Visual inspection | Boot simulator, navigate to More tab, confirm no overnight guard section visible |

---

## Validation Sign-Off

- [ ] All tasks have `<automated>` verify or Wave 0 dependencies
- [ ] Sampling continuity: no 3 consecutive tasks without automated verify
- [ ] Wave 0 covers all MISSING references
- [ ] No watch-mode flags
- [ ] Feedback latency < 90s
- [ ] `nyquist_compliant: true` set in frontmatter

**Approval:** pending
