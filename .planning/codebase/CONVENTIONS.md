# Coding Conventions

**Analysis Date:** 2026-06-03

## Naming Patterns

**Files:**
- Swift source files use PascalCase matching the primary type they contain: `GooseBLEClient.swift`, `ActivityModels.swift`, `HealthDataStore.swift`
- Extensions that add a functional area to a class use `+` suffix notation: `GooseBLEClient+Commands.swift`, `GooseAppModel+OvernightRun.swift`, `HealthDataStore+Utilities.swift`
- Views use a `Views` suffix for files containing multiple related views: `HealthDashboardViews.swift`, `SleepV2BevelTrendViews.swift`
- Type definition files use a `Types` suffix: `GooseBLETypes.swift`, `CoachChatTypes.swift`, `HealthPacketCaptureTypes.swift`
- Models use a `Models` suffix: `ActivityModels.swift`, `HealthModels.swift`, `OnboardingModels.swift`

**Types (classes, structs, enums):**
- PascalCase throughout: `GooseAppModel`, `GooseBLEClient`, `OvernightSQLiteMirrorQueue`
- Prefix with the subsystem or domain name for disambiguation: `GooseMessage`, `GooseSyncToast`, `GooseHistoricalSyncProgress`
- Enum cases use camelCase: `case debug`, `case poweredOn`, `case healthMonitor`
- Error types use PascalCase with an `Error` suffix: `GooseRustBridgeError`, `OpenAIResponsesError`

**Functions and methods:**
- camelCase: `handleNotification`, `startOvernightGuard`, `refreshActivityTimeline`
- Verbs for actions: `begin`, `start`, `stop`, `handle`, `refresh`, `resume`, `persist`, `publish`
- Booleans prefixed with `is`, `can`, `has`, `should`: `isScanning`, `canSend`, `isStreaming`
- Factory static methods prefixed with `make` or descriptive verbs: `makeRequest`, `build`

**Properties:**
- camelCase for all stored and computed properties: `bluetoothState`, `connectionState`, `liveHeartRateBPM`
- UserDefaults keys use dot-namespaced reverse-DNS strings stored as `static let` on the relevant type: `"goose.swift.liveHRVRMSSD"`, `"goose.coach.modelPreset"`
- DispatchQueue labels use reverse-DNS format: `"com.goose.swift.corebluetooth"`, `"com.goose.swift.notification-ingest"`

**Constants:**
- `static let` on the enclosing type; naming is camelCase: `static let bleUIStatePublishInterval: TimeInterval = 0.2`, `static let maximumDisplayedMessages = 300`
- Enum cases used as namespaced constants: `OnboardingStorage.onboardingComplete`, `FitnessColor.workoutYellow`

## Code Style

**Formatting:**
- No formatter config file detected (no `.swiftformat`, `.swiftlint.yml`, or similar)
- 2-space indentation used consistently throughout all Swift files
- Opening braces on the same line as the declaration (Allman-adjacent, K&R style)
- Trailing commas in multi-line array/dict literals

**Blank lines:**
- One blank line between methods within a type
- Two blank lines between top-level declarations in an extension file (import block + two blank lines + extension body)
- No blank lines between `import` statements

**Line length:**
- Long method signatures split with each parameter on its own indented line, closing `)` on its own line:
  ```swift
  func beginActivityRecording(
    activity: ActivityKind,
    startedAt: Date,
    source: String = "ios.live_activity",
    detectionMethod: String = "user_assigned"
  ) {
  ```

**Access control:**
- `private` used heavily for internal state in `final class` types (~1281 occurrences)
- `private(set)` used for read-only public properties in `ObservableObject`: `@Published private(set) var messages`
- `nonisolated` used on static utility methods that can safely run off the main actor: `nonisolated static func writeRawValidationSidecars(...)`
- `@unchecked Sendable` on queue-protected types: `final class CaptureFrameWriteQueue: @unchecked Sendable`

## Import Organization

**Order (observed pattern):**
1. Apple system frameworks (Foundation, UIKit, SwiftUI, CoreBluetooth, OSLog, etc.)
2. No third-party imports (no external SPM dependencies in `GooseSwift/`)

**Style:**
- Each framework on its own `import` line
- No blank lines between imports
- Alphabetical ordering within each import group is not strictly enforced

## Error Handling

**Primary pattern — `Result<T, Error>` with background queue and main-thread dispatch:**
```swift
let result: Result<OutputType, Error>
do {
  let value = try someThrowingCall()
  result = .success(value)
} catch {
  result = .failure(error)
}

DispatchQueue.main.async { [weak self] in
  guard let self else { return }
  switch result {
  case .success(let output):
    // update @Published properties
  case .failure(let error):
    // update status string, record error log
  }
}
```
Files: `GooseAppModel+ActivityRecording.swift`, `GooseAppModel+HealthCapture.swift`, `GooseAppModel+ActivityTimeline.swift`

**Typed error enums:** Custom `Error` enums list specific failure cases with associated values where needed:
```swift
enum GooseRustBridgeError: Error {
  case encodingFailed
  case nullResponse
  case malformedResponse
  case methodFailed(String)
}
```
Files: `GooseRustBridge.swift`, `OpenAICoachResponsesClient.swift`

**`LocalizedError` conformance:** Error types exposed to the UI also conform to `LocalizedError` with `var errorDescription: String?`:
```swift
enum OpenAIResponsesError: Error, LocalizedError {
  case httpStatus(Int, String)
  var errorDescription: String? { ... }
}
```
File: `OpenAICoachResponsesClient.swift`

**`do/try` without `Result` wrapping:** Used for short synchronous operations where the error is caught inline:
```swift
do {
  try fileManager.createDirectory(at: sidecarDirectory, withIntermediateDirectories: true)
} catch { ... }
```

**`guard` for early exit:** Preconditions and nil checks at function entry:
```swift
guard !overnightGuardActive else { return }
guard ble.connectionState == "ready" else { ... return }
```

**`@discardableResult`:** Annotated on methods whose `Bool` return indicates success but callers may not need it: `AppRouter.swift`, `GooseBLEClient+UserActions.swift`, `OnboardingPersistence.swift`

## Logging

**Framework:** OSLog `Logger` (subsystem `com.goose.swift`) used in BLE layer:
```swift
let logger = Logger(subsystem: "com.goose.swift", category: "ble")
```
File: `GooseBLEClient.swift`

**Primary logging API:** `ble.record(level:source:title:body:)` — an in-app message log displayed in the device view. Structured key-value style used in `body`:
```swift
ble.record(level: .warn, source: "overnight.guard", title: "start.blocked", body: overnightGuardStatus)
ble.record(source: "rust", title: "core.version", body: output.coreVersion)
```

**Log levels:** `GooseLogLevel` enum with `.debug`, `.info`, `.warn`, `.error`. Default level (omitted parameter) is `.info`.

**Source naming:** dot-separated domain identifiers: `"overnight.guard"`, `"ble"`, `"rust"`, `"activity.timeline"`, `"ui"`, `"whoop.data"`

**Title naming:** dot-separated event names: `"start.requested"`, `"start.ok"`, `"start.failed"`, `"notification.frame.reassembled"`

## Comments

**When to comment:**
- Inline documentation comments (`///`) are not used on public API — this codebase has no `///` doc comments
- Inline `//` comments explain non-obvious logic or configuration constants
- No TODO, FIXME, HACK, or XXX markers found in the codebase

**Comment style:**
- Explanatory comments use natural sentence case
- Parameter names and type context are omitted in comments; they are considered self-documenting from the code

## Function Design

**Size:** Functions are medium-to-large; major `GooseAppModel` extension methods run 50–150 lines, reflecting the complexity of the data pipeline. No arbitrary line-limit enforced.

**Parameters:** Named parameters are always used (Swift label convention). Default parameter values are used extensively to provide common-case shortcuts:
```swift
func startHealthPacketCapture(duration: TimeInterval = 30 * 60, source: String = "ui.debug")
func beginActivityRecording(activity: ..., source: String = "ios.live_activity", detectionMethod: String = "user_assigned")
```

**Return values:** Methods that return `Bool` indicating success are annotated `@discardableResult` when callers may legitimately ignore the result.

**Closures:** `@escaping` closure parameters used for callbacks. `@MainActor @escaping` is used when the closure must run on the main actor:
```swift
completion: @escaping @MainActor (CaptureFrameWriteResult) -> Void
onEvent: @MainActor @escaping (OpenAIResponseStreamEvent) throws -> Void
```

## Module / Type Design

**ObservableObject pattern:** Classes that own app state conform to `ObservableObject` with `@Published` properties. All such classes are `@MainActor final class`: `GooseAppModel`, `GooseBLEClient`, `HealthDataStore`, `AppRouter`, `OpenAICoachChatModel`.

**Extensions for subsystem grouping:** Large classes are split across multiple files using extensions with the `+SubsystemName` naming pattern. Each extension file begins with a new `extension ClassName {` block. All logic for a subsystem lives in its extension file: `GooseAppModel+OvernightRun.swift`, `GooseAppModel+PacketPublishing.swift`.

**Structs for data types:** Value types (`struct`) are used for all data-carrying types: `GooseMessage`, `GooseNotificationEvent`, `GooseHistoricalSyncProgress`, `OvernightSQLiteMirrorSnapshot`.

**Enums for namespacing constants:** Caseless enums used as namespaces for `static let` constants and `static func` factory methods: `GooseTheme`, `FitnessColor`, `OnboardingStorage`, `CoachLocalToolContext`.

**Callback properties for loose coupling:** Classes expose optional closure properties for event callbacks rather than delegate protocols:
```swift
var onNotification: ((GooseNotificationEvent) -> Void)?
var onLiveHeartRate: ((Int, String, Date) -> Void)?
```
File: `GooseBLEClient.swift`

**Memory management:** `[weak self]` is used in all closures that capture `self` across async boundaries. `guard let self else { return }` is the canonical guard pattern (Swift 5.7+ shorthand used throughout).

**`@unknown default`:** All `switch` statements on Apple SDK enums include `@unknown default` to handle future cases safely: `CBManager.authorization`, `UIUserInterfaceStyle`, `ScenePhase`.

**SwiftUI `View` structs:** All SwiftUI views are `struct` with a `var body: some View`. Private sub-views within a file are defined as `private struct`. `PreferenceKey` types for geometry tracking are `private struct` defined at the bottom of the relevant file.

---

*Convention analysis: 2026-06-03*
