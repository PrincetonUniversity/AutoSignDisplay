# Copilot instructions for AutoSignDisplay

This file gives concise, actionable guidance for an AI coding agent working on the AutoSignDisplay tvOS app located in `AutoSignDisplay/`.

Keep edits small and focused. The app is a lightweight tvOS HLS player whose behavior is primarily driven by `UserDefaults` and an optional managed configuration plist.

Key places to look
 - `AutoSignDisplay/ContentView.swift` — main UI, `UserDefaults` keys, presentation and full-screen player flow.
 - `AutoSignDisplay/StreamViewModel.swift` — business logic: AVPlayer lifecycle, retry timer, and persistence of settings.
 - `AutoSignDisplay/AppConfig.swift` and `AutoSignDisplay/ManagedAppConfig.example.plist` — how managed (MDM) configuration is applied at app startup.
 - `AutoSignDisplay/OnChangeOld.swift` — project-provided helper `onChangeOld` used instead of platform overloads.
 - `AutoSignDisplay/SettingsView.swift` — how settings are bound to `UserDefaults` and when `updateSettings` is expected to be called.
 - `AutoSignDisplayTests/AutoSignDisplayTests.swift` — unit-test style and examples for preparing `UserDefaults` before instantiating `StreamViewModel`.

Big-picture architecture and conventions
- Single-target, SwiftUI tvOS app. Entry point: `AutoSignDisplay` calls `AppConfig.applyConfiguration()` during `init()`.
- App state is stored in `UserDefaults` using a small set of keys defined in `ContentView` and `AppConfigKeys`. Changes are propagated via `@Published` properties on `StreamViewModel` and are persisted immediately.
- Playback is handled by `AVPlayer` instances owned by `StreamViewModel`. The view presents a full-screen `AVPlayerViewController` via `FullscreenPlayerView` when `player` is non-nil and `showPlayer` is true.
- Managed configuration (MDM) is supported. `AppConfig.applyConfiguration()` reads `com.apple.configuration.managed` and writes values into `UserDefaults` so code can read them as usual.
- Small utility `onChangeOld` is provided to get old+new values for `onChange` handlers; prefer using it where available to match existing code.

Developer workflows & commands
- Build & run: open the Xcode workspace/project in Xcode and run the `AutoSignDisplay` scheme (tvOS simulator/device). The repository contains `AutoSignDisplay.xcodeproj`.
- Tests: the project uses a simple test file under `AutoSignDisplayTests`. Run tests from Xcode's Test action or with `xcodebuild` if CI is needed. Example (local macOS Terminal):
- xcodebuild -project AutoSignDisplay.xcodeproj -scheme AutoSignDisplay -sdk appletvsimulator test
- When changing persistent keys, update both `ContentView` key constants and `AppConfigKeys` where appropriate.

Patterns and project-specific details to preserve
- UserDefaults keys live as static constants on `ContentView` (e.g., `lastStreamURLKey`, `playOnOpenKey`). Tests and AppConfig rely on these names — do not rename without updating all references.
- `StreamViewModel` expects defaults to be read at init and will call `startRetryTimer()` when appropriate. Keep timer lifecycle methods (`startRetryTimer`, `stopRetryTimer`, `restartRetryTimer`) consistent when modifying behavior.
- `AppConfig.applyConfiguration()` maps managed plist keys to the `ContentView` keys. If you add a new managed key, mirror it in `AppConfigKeys` and add the apply logic here.
- The UI defers presenting the full-screen player until the view hierarchy is ready using `DispatchQueue.main.async` and retries once after a short delay — preserve this logic if changing presentation timing to avoid tvOS presentation races.

Examples to reference when making changes
- To add a new boolean managed setting `ExampleFlag`:
  - Add `static let exampleFlag = "ExampleFlag"` to `AppConfigKeys`.
  - In `AppConfig.applyConfiguration()` read `managedConfig[AppConfigKeys.exampleFlag] as? Bool` and write to a `UserDefaults` key (add constant to `ContentView` if needed).
  - If UI needs to bind, add a `@Published` property to `StreamViewModel`, initialize from `UserDefaults` in `init()`, and expose a binding through `SettingsView`.

⚠️ Critical gotcha: NSNumber type validation for Boolean fields
When validating Boolean fields from managed configuration, be aware that NSNumber values can be implicitly cast to Bool in Swift, causing validation to incorrectly accept invalid integer values. This is particularly problematic when distinguishing between:
- `<true/>` or `<false/>` from plist (CFBoolean, objCType 'c') → VALID
- `<integer>1</integer>` or `<integer>0</integer>` from plist (int64_t, objCType 'q') → INVALID

**The solution**: In `AppConfig.swift`, check for NSNumber BEFORE checking for Bool, and verify the objCType:
```swift
if let numValue = managedConfig[key] as? NSNumber {
    let objCTypeStr = String(cString: numValue.objCType)
    if objCTypeStr == "c" {  // CFBoolean marker
        defaults.set(numValue.boolValue, forKey: userDefaultsKey)
    } else {
        logger.log("Rejected: integer NSNumber, not CFBoolean")
    }
} else if let boolValue = managedConfig[key] as? Bool {
    defaults.set(boolValue, forKey: userDefaultsKey)
}
```

This applies to all Boolean managed settings: `PlayOnAppOpen`, `AutoResume`, and `SettingsDisabled`.

Testing hints
- Tests prepare `UserDefaults` directly (see `AutoSignDisplayTests.swift`) before instantiating `StreamViewModel`. Follow the same pattern when writing new unit tests.
- `StreamViewModel.startStreamIfNeeded()` creates an `AVPlayer` if a valid URL exists and `playOnOpen` is true — tests assert on the `player` being non-nil.
- When testing managed config validation, use the test plist files in `AutoSignDisplayTests/`: `ValidManagedConfig.plist` (should apply), `InvalidManagedConfig.plist` (should reject invalid types), `EmptyManagedConfig.plist`, and `NegativeRetryTimeoutConfig.plist`.

When editing code
- Keep changes localized: modify small functions/classes and run the test in Xcode or via `xcodebuild` to verify behavior.
- Update `ManagedAppConfig.example.plist` with new managed keys and example values when adding managed settings.
- Preserve the `onChangeOld` usage pattern (old + new value) rather than switching to newer SDK-specific `onChange` overloads — the project intentionally avoids those to remain compatible with multiple Xcode versions.

Debugging managed config issues
- Test output is often truncated in xcodebuild. Save to a file: `xcodebuild ... test 2>&1 | tee /tmp/test_output.log` then read specific sections with grep or by copying to workspace.
- When debugging type issues in managed config loading, store debug info in UserDefaults under a debug key and read it in tests: `defaults.set("debugInfo", forKey: "DEBUG_KEY")` then access in test with `defaults.string(forKey: "DEBUG_KEY")`.
- The PropertyListSerialization options must be empty `[]` not `.mutabilityOptions` — the latter is invalid and causes compile failures.
- Remember that NSNumber objCType can change after storing/retrieving from UserDefaults. Store the value in UserDefaults immediately after loading from plist to test the actual behavior.

If something isn't discoverable
- If you need to know CI or code signing details, ask the repo owner — those details are not present in the source tree.

Next steps
- If this looks correct, I'll add the file to the repository (created here). Tell me if you want more detail about CI, signing, or simulator/device run scripts.
