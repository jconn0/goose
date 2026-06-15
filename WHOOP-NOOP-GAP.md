# Noop vs Goose — Feature Gap & Portability Analysis

> Comparing [NoopApp/noop](https://github.com/NoopApp/noop) (v3.0.0, 1.7k stars) against Goose.
> Focus: WHOOP MG features with portability assessment.
> Generated 2026-06-14.

---

## License & Portability Rules

Noop is licensed under **PolyForm Noncommercial 1.0.0**. Critical distinction from their LICENSE:

> "The protocol facts documented in this repository (BLE service/characteristic identifiers,
> frame layouts, CRC parameters, command/event/packet numbers, byte offsets) are uncopyrightable
> factual information about how bytes appear on a wire. They are not claimed as anyone's property
> and may be reused freely."

| What | Portable? | Notes |
|------|-----------|-------|
| Protocol facts (UUIDs, cmd #s, packet layouts, CRC params) | ✅ **Free to use** | Uncopyrightable wire facts |
| `whoop_protocol.json` schema | ✅ **Free to use** | Protocol facts only |
| Source code (Swift, Kotlin) | ⚠️ Noncommercial only | Goose is open-source/non-commercial — likely permitted, but prefer rewriting |
| CRC/checksum algorithms | ✅ **Free to use** | Standard algorithms; params from wire facts |
| UI/design | ❌ Avoid | Build your own SwiftUI |

**Recommendation:** Use Noop's protocol documentation and `whoop_protocol.json` as a **reference** for wire formats. Re-implement in Goose's own style (Rust for protocol parsing, Swift for BLE transport). The protocol facts are explicitly free — so you can read Noop's decode tables and implement the same wire format in Goose without license concern.

---

## Features Noop Has That Goose Lacks

### Tier 1: Protocol / BLE (High Portability)

| Feature | Noop Status | Goose Status | Portability |
|---------|-------------|--------------|-------------|
| **Full Puffin protocol framing** | ✅ Types 37/38/53/54/56 decoded | ⚠️ RAW_ONLY (extracts type only) | **Easy** — protocol facts from `whoop_protocol.json` are free to use |
| **CRC16-Modbus implementation** | ✅ For WHOOP 5.0 header check | ❌ Goose has no 5.0 header CRC | **Easy** — standard algorithm, params documented |
| **WHOOP 5.0/MG GATT topology docs** | ✅ Full UUID table | ✅ Already implemented | Already parity |
| **Bond handshake lifecycle docs** | ✅ Documented step-by-step | ✅ Already implemented | Already parity |
| **Historical offload state machine** | ✅ Safe-trim invariant documented | ✅ Already implemented | Already parity |
| **Safe/destructive command audit** | ✅ Curated safe subset + hazard list | ⚠️ No formal audit | **Easy** — command numbers are protocol facts |
| **Stuck strap detector** | ✅ Detects frozen frontier + recovery | ⚠️ Goose has simpler watchdog | Medium — algorithm is implementable from description |

### Tier 2: MG-Relevant Commands (High Portability — Wire Facts)

All of these are just command numbers + payload formats. Protocol facts are free to use.

| Command | Noop | Goose | Value for MG |
|---------|------|-------|-------------|
| **79** RUN_HAPTICS_PATTERN | ✅ Full implementation | ✅ Buzz primitive (cmd 0x13) | MG has haptic motor — confirmed on MG hardware |
| **80** GET_ALL_HAPTICS_PATTERN | ✅ Enumerate presets | ❌ | Discover available haptic patterns on MG |
| **84** GET_BODY_LOCATION_AND_STATUS | ✅ | ❌ | Determine wrist/body placement |
| **100** CALIBRATE_CAPSENSE | ✅ | ❌ | Calibrate capacitive touch on MG (Phase 66 blocked by unknown GATT UUID) |
| **122** STOP_HAPTICS | ✅ | ❌ | Cancel in-progress haptic |
| **123** SELECT_WRIST | ✅ | ❌ | Set left/right wrist on MG |
| **96/97** ENTER/EXIT_HIGH_FREQ_SYNC | ✅ | ✅ | Already parity |
| **98** GET_EXTENDED_BATTERY_INFO | ✅ | ❌ | Extended battery metrics (mV, etc.) on MG |
| **66-69** Alarm commands | ✅ SET/GET/RUN/DISABLE | ✅ AlarmCommandKind | Already parity |
| **10/11** SET_CLOCK/GET_CLOCK | ✅ | ✅ | Already parity |

### Tier 3: Event Handling (Medium Portability)

| Event | Noop | Goose | Value for MG |
|-------|------|-------|-------------|
| **14** DOUBLE_TAP | ✅ Mapped to callback | ❌ Not handled | MG supports double-tap gesture |
| **9/10** WRIST_ON / WRIST_OFF | ✅ Mapped to callback | ❌ Goose has no wear detection | On-wrist/off-wrist detection |
| **32** CAPTOUCH_AUTOTHRESHOLD_ACTION | ✅ | ❌ | Cap touch auto-calibration event |
| **56** STRAP_DRIVEN_ALARM_SET | ✅ | ❌ | Alarm confirmation |
| **57** STRAP_DRIVEN_ALARM_EXECUTED | ✅ | ❌ RE-gated | Wake-window engine gate |
| **58** APP_DRIVEN_ALARM_EXECUTED | ✅ | ❌ | App-driven alarm confirmation |
| **59** STRAP_DRIVEN_ALARM_DISABLED | ✅ | ❌ | Alarm disable confirmation |
| **60** HAPTICS_FIRED | ✅ | ❌ | Haptic confirmation |
| **63** EXTENDED_BATTERY_INFORMATION | ✅ | ❌ | Extended battery event |
| **100** HAPTICS_TERMINATED | ✅ | ❌ | Haptic completion |

### Tier 4: App Features (Low Portability — Build Own)

| Feature | Noop | Goose | Portability |
|---------|------|-------|-------------|
| **Android + macOS apps** | ✅ Cross-platform | ❌ iOS only | Not portable — different tech stacks |
| **Mind** (daily mood check-in) | ✅ Correlated against recovery/sleep/HRV | ❌ | Build own SwiftUI |
| **Compare** (dual metric plot) | ✅ | ❌ | Build own |
| **Insights** (behavioral correlations) | ✅ | ❌ | Build own; Goose has correlation engine in Rust |
| **Automations** (double-tap → Mac action) | ✅ macOS-only | ❌ | Not relevant for iOS-only Goose |
| **Wear/presence detection** | ✅ Mac auto-lock | ❌ | Build own from WRIST_ON/OFF events |
| **Haptic coaching** (HR-zone + stress nudge) | ✅ | ❌ | Build own from haptic commands |
| **WHOOP CSV import** | ✅ | ❌ | Build own; protocol facts help |
| **Apple Health XML import** | ✅ Streaming SAX | ❌ Goose uses HealthKit API | Different approach |
| **Nutrition CSV import** | ✅ | ❌ | Not MG-relevant |
| **Step calibration** | ✅ Per-user stride tuning | ❌ | Build own |
| **Configurable notifications** | ✅ Per-metric thresholds | ❌ Goose has 3 hardcoded | Build own |
| **YearHeatStrip heatmap** | ✅ | ❌ | Build own SwiftUI |
| **In-app What's New changelog** | ✅ | ❌ | Trivial |
| **Local AI Coach** (Ollama/LM Studio) | ✅ | ❌ Goose: external API only | Medium — modify CoachChatModel |
| **Long-range Trends** (30d/90d/6mo/1yr) | ✅ | ⚠️ Goose: 7-day only | Build own; Goose has metric_series table |

---

## Easiest Ports for MG Focus

Sorted by effort (lowest first):

### 1. Protocol Facts (0 effort — just read)
Noop's `whoop_protocol.json` contains the authoritative command/event/packet enumeration for both WHOOP 4.0 and 5.0/MG. Since protocol facts are explicitly free, you can:
- Cross-reference command numbers you've already implemented
- Find MG-specific commands you haven't implemented yet
- Verify packet layouts match what Goose decodes

### 2. Puffin Protocol Framing (~1 day)
Goose currently extracts only the type from Puffin packets (37/38/53/54/56) but doesn't decode the inner structure. Noop has full framing. The type aliasing (38→COMMAND_RESPONSE, 56→METADATA) is simple and useful. Implement in Rust `protocol.rs`.

### 3. Event Handlers (~2 days)
Add Swift-side callbacks for events Goose ignores:
- `DOUBLE_TAP` (14) — expose as callback, usable for future automations
- `WRIST_ON`/`WRIST_OFF` (9/10) — on-wrist detection without cap sense hardware
- `HAPTICS_FIRED` (60), `HAPTICS_TERMINATED` (100) — confirm haptic commands worked
- `STRAP_DRIVEN_ALARM_EXECUTED` (57) — **unblocks HAP-04 wake-window engine**

### 4. MG-Specific Commands (~1 week)
Commands MG supports that Goose doesn't send:
- `SELECT_WRIST` (123) — left/right wrist config
- `GET_BODY_LOCATION_AND_STATUS` (84) — body placement
- `GET_EXTENDED_BATTERY_INFO` (98) — richer battery data
- `GET_ALL_HAPTICS_PATTERN` (80) — discover haptic presets on MG

### 5. CRC16-Modbus for WHOOP 5.0 (~2 hours)
Noop implements CRC16-Modbus (poly 0xA001, init 0xFFFF, reflected) for WHOOP 5.0 header validation. Goose currently doesn't validate WHOOP 5.0 headers. Standard algorithm — add to Rust `protocol.rs`.

---

## What NOT to Port

| Item | Why Not |
|------|---------|
| Noop's Swift BLE code | Goose uses Objective-C CoreBluetooth patterns + Rust bridge — different architecture |
| Noop's GRDB/SQLite layer | Goose uses Rust `rusqlite` — different storage engine |
| Noop's UI (StrandDesign) | Goose has its own SwiftUI design system |
| Noop's analytics (StrandAnalytics) | Goose has its own Rust metric algorithms |
| Cross-platform (Android/Kotlin) | Goose is iOS-only |
| macOS-specific automations | Goose is iOS-only |

---

## Actionable Next Steps (MG Focus)

1. **Read Noop's `whoop_protocol.json`** — cross-reference every command/event/packet against Goose's implementation. Flag gaps.
2. **Implement Puffin framing** in Rust — unblocks proper decode of types 37/38/53/54/56.
3. **Wire up MG events** — DOUBLE_TAP, WRIST_ON/OFF, alarm events. The STRAP_DRIVEN_ALARM_EXECUTED event is the HAP-04 gate.
4. **Send missing MG commands** — SELECT_WRIST, GET_BODY_LOCATION, GET_EXTENDED_BATTERY.
5. **CRC16-Modbus** — add WHOOP 5.0 header validation in Rust.

---

## Sources

- NoopApp/noop README + LICENSE + PROTOCOL.md — https://github.com/NoopApp/noop
- Goose codebase: `GooseSwift/`, `Rust/core/src/`
- Goose feature gap: `WHOOP-FEATURE-GAP.md`
- MG feature status: `WHOOP-MG-FEATURE-STATUS.md`
