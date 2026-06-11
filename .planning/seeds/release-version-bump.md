---
name: release-version-bump
description: RESOLVED — version bump is now fully automated in release.yml; no manual step needed before tagging
metadata:
  type: seed
  trigger_condition: n/a — automated
  planted_date: 2026-06-11
  resolved_date: 2026-06-11
---

## Resolved

The manual bump was automated in commit `9ac4884` (ci: auto-bump MARKETING_VERSION, build number, and Cargo.toml from release tag).

## How it works now

The `release.yml` CI step "Bump versions from tag" runs before `xcodebuild`:

```bash
TAG="v9.0"
VERSION="9.0"          # → MARKETING_VERSION
MAJOR="9"              # → CURRENT_PROJECT_VERSION
CARGO_VERSION="9.0.0"  # → Rust/core/Cargo.toml
```

All three fields are patched inline on the runner before the build — no commit required. The IPA is built with the correct version embedded. The About screen will show `9.0 (9)` and Rust core `9.0.0` automatically.

## Release flow (current)

```
git tag v9.0 && git push origin v9.0
# CI does everything: bump → build → publish → AltStore update
```
