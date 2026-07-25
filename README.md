 # AutoSignDisplay
 
 tvOS app for playing HLS streams, configurable via AppConfig.
 
 ## Build & run (local macOS / Xcode)
 
This project contains an Xcode project (`AutoSignDisplay.xcodeproj`) that builds the AutoSignDisplay tvOS app. To open and run locally:

 1. Open `AutoSignDisplay.xcodeproj` in Xcode.
2. Select the `AutoSignDisplay` scheme (product name will be `AutoSignDisplay` at runtime) and choose an Apple TV simulator (e.g., "Apple TV 4K (2nd generation)").
 3. Build and Run (⌘R) to install and launch the app in the tvOS simulator.
 
 Notes:
 - The app entrypoint (`AutoSignDisplay`) applies managed configuration at `init()` by calling `AppConfig.applyConfiguration()`; to test managed settings locally, add the `com.apple.configuration.managed` dictionary to the simulator's `UserDefaults` or use `AutoSignDisplay/ManagedAppConfig.example.plist` as a reference.
 
 ## Build & test from the command line
 
 You can run tests using `xcodebuild`. Example (macOS Terminal):
 
 ```bash
 xcodebuild -project AutoSignDisplay.xcodeproj -scheme AutoSignDisplay -sdk appletvsimulator test
 ```
 
 This will build and run the unit and UI tests in the tvOS simulator. Tests in `AutoSignDisplayTests` prepare `UserDefaults` directly before instantiating `StreamViewModel`.

Tip: if xcodebuild appears to hang at the tvOS home screen, explicitly boot a simulator and run tests against its UDID. Example step-by-step:

1. List available tvOS simulators and find a suitable UDID:

```bash
xcrun simctl list devices --json | jq '.devices["com.apple.CoreSimulator.SimRuntime.tvOS-26-0"][] | {name, udid, state}'
```

2. Boot the simulator (replace <UDID> with the chosen device UDID):

```bash
xcrun simctl boot <UDID>
xcrun simctl bootstatus <UDID> -b
```

3. Run tests targeting that UDID so xcodebuild uses the booted simulator:

```bash
xcodebuild -project AutoSignDisplay.xcodeproj -scheme AutoSignDisplay -sdk appletvsimulator -destination 'id=<UDID>' test
```

Notes & troubleshooting:
- If `simctl boot` reports data migration on first boot, wait for it to finish (bootstatus will wait until the device is ready).
- If you see warnings about main-actor-isolated properties in tests, ensure tests update `UserDefaults` from the main actor (examples in `AutoSignDisplayTests/*`).
- If xcodebuild can't find a simulator runtime, install the matching simulator runtime via Xcode's Components preferences.
 
 ## Project structure (key files)
 
 - `AutoSignDisplay/AutoSignDisplayApp.swift` — App entrypoint (struct `AutoSignDisplay`); applies managed configuration.
 - `AutoSignDisplay/ContentView.swift` — main SwiftUI view and `UserDefaults` key constants.
 - `AutoSignDisplay/StreamViewModel.swift` — AVPlayer lifecycle, retry timer, and persisted settings.
 - `AutoSignDisplay/AppConfig.swift` — maps managed keys into `UserDefaults`.
 - `AutoSignDisplay/SettingsView.swift` — settings UI bound to `StreamViewModel`.
 - `AutoSignDisplay/OnChangeOld.swift` — helper providing old+new value for change handlers.
 

## Features

The app implements a small set of focused features for playing and managing HLS streams:

- Enter an HLS stream URL and click "Play Stream" to start playback.
- Channel presets: manage up to 20 saved streams, each with an optional name and a required URL. When a name is set it shows in the Stream Presets list instead of the raw URL. Presets can be locked down via managed configuration.
- Play-on-open: enable or disable "Play on App Open" so the app will automatically play the last-used URL on launch.
- Auto-resume: enable and display an "Auto Resume on Network Interrupt" option so the player will attempt to resume playback after transient network interruptions.
- Retry timeout: how long to wait before retrying a stalled stream.
- Managed App Config: all user-facing options are also configurable via MDM/managed app configuration (see `AutoSignDisplay/ManagedAppConfig.example.plist` and `AppConfig.applyConfiguration()`).

These features are intentionally small and testable; they are exercised by the unit tests in `AutoSignDisplayTests` and the small UI tests in `AutoSignDisplayUITests`.

### Retry Timeout and MDM values

The Settings screen presents Retry Timeout as a row that cycles through a fixed
set of intervals — 3, 5, 10, 15, 30, and 60 seconds — rather than a free-text
field. Typing digits with the on-screen keyboard is slow on a remote, and this
value is normally set once by an administrator.

**A value pushed via MDM is always honored, even if it is not one of those six
intervals.** The list only governs what pressing the row cycles to; it does not
clamp or validate what `RetryTimeout` may contain:

- `AppConfig` accepts any positive `RetryTimeout` (a `<real>` in the managed
  plist) and writes it straight through to `UserDefaults`. Non-positive and
  wrong-typed values are rejected, as before.
- The Settings row displays whatever the current value is. A managed value of
  `7` renders as `7s`.
- Pressing the row advances to the first listed interval **greater than** the
  current value, so `7s` steps to `10s` rather than snapping backwards to a
  listed value. Past `60s` it wraps to `3s`.
- When `SettingsDisabled` is true the row is disabled outright, so a managed
  value cannot be changed on the device at all.

To offer a different set of intervals, edit `SettingsView.retryTimeoutOptions`.
That constant affects only the on-device UI — it places no constraint on MDM.

## Tests and regression protection

Core behaviors are covered by unit and small integration tests to prevent regressions:

- Playback creation: tests assert a player is created when a valid stream URL exists and "Play on App Open" is enabled.
- Channel presets seeding and managed overrides: tests confirm default presets are seeded, respect the 20-item limit, and that managed configuration enforces a read-only list with a default channel selection.
- Auto-resume logging/behavior: tests inject a test `Logger` implementation to verify the auto-resume behavior emits expected logs (see `AutoSignDisplayTests/LoggerTests.swift`).
- Settings persistence: tests set `UserDefaults` values (on the main actor) before creating the `StreamViewModel` and assert persistence and behavior are correct.

How to run tests:

1. Use the helper script (recommended). It discovers or boots a simulator, sets the
   managed/unmanaged state, and pins the run to one device. Runnable from any directory:

```bash
./scripts/run-tests.sh                  # auto-pick a simulator, unmanaged
./scripts/run-tests.sh --udid <UDID>    # pin a specific device
./scripts/run-tests.sh --managed        # apply the sample managed payload first
```

2. Or run directly with xcodebuild and a pinned UDID to avoid cloned simulators:

```bash
xcodebuild -project AutoSignDisplay.xcodeproj -scheme AutoSignDisplay -sdk appletvsimulator -destination 'id=<UDID>' -parallel-testing-enabled NO test
```

To build and launch the app on a simulator:

```bash
./scripts/run.sh                        # build, install, launch
./scripts/run.sh --managed              # launch with a managed payload applied
./scripts/run.sh --clean --release      # wipe app data, build Release
./scripts/run.sh --dry-run              # print the plan without doing it
```

Test guidance:

- When tests need to change `UserDefaults` values that are main-actor-isolated (for example keys defined in `ContentView`), update `UserDefaults` from the main actor using `await MainActor.run { ... }` to avoid main-actor warnings and Sendable capture issues.
- Pin a UDID and disable parallel testing for consistent, single-device test runs (this avoids xcodebuild creating cloned simulator devices).
- If you add features that change persistence or playback lifecycle, add or update unit tests in `AutoSignDisplayTests` that set up `UserDefaults`, create a `StreamViewModel`, and assert the expected `player` state and retry behavior.

### The shared scheme

`AutoSignDisplay.xcodeproj/xcshareddata/xcschemes/AutoSignDisplay.xcscheme` is
checked in, and needs to stay that way. Without it xcodebuild falls back to an
auto-generated scheme whose buildables resolve no eligible destinations, so any
`-scheme … build` invocation fails with:

```
error: Supported platforms for the buildables in the current scheme is empty.
```

The *test* action tolerates the auto-generated scheme, which makes this confusing
to diagnose — tests pass while builds fail. If you recreate the project or add a
target, confirm the scheme is still marked **Shared** in Product → Scheme → Manage
Schemes.

## Helper script: scripts/run-tests.sh

For convenience there's a small helper script that will discover or accept a tvOS simulator UDID, boot it if necessary, wait for readiness, and run the tests:

```bash
# Dry-run to preview actions:
./scripts/run-tests.sh --dry-run

# Let the script pick an available tvOS simulator and run tests:
./scripts/run-tests.sh

# Use a specific UDID (replace with the UDID from simctl list):
./scripts/run-tests.sh --udid 2414D6A2-3663-4DFF-9EED-DACA32FB64B5
```

The script is executable by default in the repository (mode 100755). If you ever need to restore exec permission locally:

```bash
chmod +x scripts/run-tests.sh
```

