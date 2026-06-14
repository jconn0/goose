# Feature Backlog

## BL-001: Apple Intelligence Coach Provider

**Status**: Research complete — ready for implementation

**Summary**: Replace the ChatGPT login requirement with an on-device Apple Intelligence LLM as the default Coach provider, keeping cloud providers as opt-in upgrades.

### Motivation

The current Coach requires OAuth device-code login (ChatGPT) or API keys (Claude, Gemini, Custom Endpoint). Apple Intelligence on iOS 26 provides an on-device LLM with zero config, no network, and no third-party account — aligning with the project's local-first privacy stance.

### Feasibility

- **Framework**: `FoundationModels` (iOS 26, WWDC25)
- **Key types**: `SystemLanguageModel.default`, `LanguageModelSession`, `streamResponse(to:)`, `Tool` protocol, `@Generable` constrained output
- **Availability**: iOS 26+ on Apple Intelligence devices (A17 Pro+ / M1+). No special entitlements — any third-party app can use it.
- **Streaming**: `streamResponse(to: generating: String.self)` returns an `AsyncSequence` of partial snapshots — maps directly to the existing `AsyncStream<String>` delta pattern
- **Tool calling**: Swift-native `Tool` protocol with `@Generable Arguments` — no JSON tool-call parsing needed (unlike ChatGPT provider's HTTP tool flow)
- **Privacy**: Fully on-device. No tokens, no Keychain, no network calls. Private Cloud Compute is NOT available to third-party apps.

### Limitations

| Limitation | Impact | Mitigation |
|---|---|---|
| 3B model quality | Cannot match cloud LLMs for complex reasoning | Default to Apple Intelligence; let users opt into cloud for depth |
| Limited context window | Full Coach context JSON + multi-turn may exceed limits | Trim context; use tool calls instead of prompt stuffing |
| No world knowledge | Cannot answer general wellness/nutrition questions | Inject verified knowledge into system prompt or tools |
| Device availability | Only Apple Intelligence devices (iPhone 15 Pro+, iPhone 16+, M1+ iPads/Macs) | Fall back to cloud providers on unsupported devices |
| Guardrails | Apple safety layer may block some health topics | Aligned with existing "do not diagnose" instruction |
| Model tied to OS | Behavior changes across iOS updates | Pin prompt patterns; test across versions |

### Implementation Sketch

Add `AppleIntelligenceCoachProvider` as a fifth `CoachProvider`:

```swift
import FoundationModels

@MainActor @Observable
final class AppleIntelligenceCoachProvider: CoachProvider {
  let id = "apple-intelligence"
  let displayName = "Apple Intelligence"
  let availablePresets: [CoachModelPreset] = [.onDeviceDefault]
  let isAuthenticated: Bool  // always true when available

  private let model = SystemLanguageModel.default
  private var session: LanguageModelSession?

  func send(messages:systemPrompt:preset:) async throws -> AsyncStream<String> {
    // Check model.availability, create session with tools + instructions,
    // stream response, yield deltas by diffing consecutive partial snapshots
  }

  func signOut() { /* no-op */ }
}
```

`CoachProviderRegistry` should pick Apple Intelligence by default when `model.availability == .available`, falling back to whichever cloud provider the user configured.

### Dependencies

- iOS 26 SDK with FoundationModels framework
- Xcode 26 beta (initially)
- New `CoachModelPreset.onDeviceDefault` case

---

## BL-002: Food Intake Tracking & Metric Correlation

**Status**: Research complete — ready for Phase 1 implementation

**Summary**: Enable correlation between food intake and biometric metrics (HRV, recovery, sleep, strain) by reading dietary data from HealthKit, with optional FatSecret integration for richer per-meal data.

### Motivation

Users want to understand how nutrition affects their recovery and performance. Goose already has WHOOP biometric data and a Coach that consumes health context; adding food data completes the feedback loop.

### Feasibility

**Cronometer**: No public API. CSV export only. Not feasible for direct integration.

**MyFitnessPal**: API shut down in 2018. Not feasible.

**FatSecret**: Best third-party option. 3-legged OAuth 2.0, `food_entries.get.v2` and `food_entries.get_month` endpoints, per-meal macro/micro data (16+ micronutrients). Free tier: 5K calls/day, US-only data on basic tier. Requires API key (embedded or proxied).

**HealthKit (recommended Phase 1)**: Zero dependencies. Cronometer, Lose It, Yazio, and MyFitnessPal all write dietary data to HealthKit. Goose already uses HealthKit for sleep import and workout write. Just needs to READ additional dietary types.

### HealthKit Dietary Types

| Identifier | Unit | Written by Cronometer |
|---|---|---|
| `.dietaryEnergyConsumed` | kcal | Yes |
| `.dietaryFatTotal` | g | Yes |
| `.dietaryProtein` | g | Yes |
| `.dietaryCarbohydrates` | g | Yes |
| `.dietaryFiber` | g | Yes |
| `.dietarySugar` | g | Yes |
| `.dietarySodium` | mg | Yes |
| `.dietaryCaffeine` | mg | Yes |
| `.dietaryVitaminC` | mg | Yes |
| `.dietaryCalcium` | mg | Partial |
| `.dietaryIron` | mg | Partial |
| `HKCorrelationTypeIdentifier.food` | Named items | Yes (per-item) |

### Phased Plan

#### Phase 1: HealthKit Dietary Read (1-2 days)

- Add dietary `HKQuantityTypeIdentifier` values to `HealthKitFullImporter.readTypes()`
- Add `queryTodaySum` calls for calories, protein, fat, carbs (same pattern as steps/active energy in `HealthKitFullImporter.swift:246-258`)
- Add `queryQuantityHistory` for 30-day macro trends (same pattern as HRV history at `HealthKitFullImporter.swift:311-329`)
- New `@Published` properties on `HealthDataStore`: `hkDietaryCalories`, `hkDietaryProtein`, `hkDietaryFat`, `hkDietaryCarbs`, `hkDietaryCaloriesHistory`
- Feed into `CoachLocalToolContext.build()` as a new `"nutrition"` key
- No server changes needed

#### Phase 2: FatSecret Integration (5-7 days, optional)

- 3-legged OAuth 2.0 flow via `ASWebAuthenticationSession`
- Token storage in Keychain (reuse `Security` framework pattern from `CodexEmbeddedAuth`)
- FatSecret API client: `food_entries.get.v2`, `food_entries.get_month`
- Per-meal breakdowns (breakfast, lunch, dinner, snacks) + 16 micronutrients
- Attribution UI required on free tier

#### Phase 3: Server-Side Correlation Dashboard (future)

- Add `daily_nutrition` hypertable to TimescaleDB alongside `daily_metrics`
- `/v1/nutrition` ingestion endpoint on FastAPI server
- iOS upload client extension for nutrition data (store-and-forward batching, same as biometric streams)
- Correlation API: Pearson r and Spearman rho between macro intake and recovery/HRV/strain over configurable rolling windows (7-day default)
- Coach integration: inject correlation coefficients into system prompt

### Correlation Approach

- **Day-over-day join**: Daily macro totals aligned with `daily_metrics` on `(device_id, day)` — identical to existing server-side pattern
- **7-day rolling window** for smoothing (already used in cardio load computation at `HealthDataStore+Cardio.swift:209-240`)
- **Pearson r** for linear relationships (calories vs. recovery score)
- **Spearman rho** for monotonic-but-nonlinear relationships (protein vs. strain capacity)
- **Delta correlation** (change in macros vs. change in HRV) most actionable for Coach

### Dependencies

- Phase 1: None (HealthKit already integrated)
- Phase 2: FatSecret API key
- Phase 3: Server deployment, FastAPI schema migration