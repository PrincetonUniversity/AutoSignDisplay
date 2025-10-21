 # Autostream
 
 tvOS app for playing HLS streams, configurable via AppConfig.
 
 ## Build & run (local macOS / Xcode)
 
This project contains an Xcode project (`Autostream.xcodeproj`) that builds the Autostream tvOS app. To open and run locally:

 1. Open `Autostream.xcodeproj` in Xcode.
2. Select the `Autostream` scheme (product name will be `Autostream` at runtime) and choose an Apple TV simulator (e.g., "Apple TV 4K (2nd generation)").
 3. Build and Run (⌘R) to install and launch the app in the tvOS simulator.
 
 Notes:
 - The app entrypoint (`Autostream`) applies managed configuration at `init()` by calling `AppConfig.applyConfiguration()`; to test managed settings locally, add the `com.apple.configuration.managed` dictionary to the simulator's `UserDefaults` or use `Autostream/ManagedAppConfig.example.plist` as a reference.
 
 ## Build & test from the command line
 
 You can run tests using `xcodebuild`. Example (macOS Terminal):
 
 ```bash
 xcodebuild -project Autostream.xcodeproj -scheme Autostream -sdk appletvsimulator test
 ```
 
 This will build and run the unit and UI tests in the tvOS simulator. Tests in `AutostreamTests` prepare `UserDefaults` directly before instantiating `StreamViewModel`.

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
xcodebuild -project Autostream.xcodeproj -scheme Autostream -sdk appletvsimulator -destination 'id=<UDID>' test
```

Notes & troubleshooting:
- If `simctl boot` reports data migration on first boot, wait for it to finish (bootstatus will wait until the device is ready).
- If you see warnings about main-actor-isolated properties in tests, ensure tests update `UserDefaults` from the main actor (examples in `AutostreamTests/*`).
- If xcodebuild can't find a simulator runtime, install the matching simulator runtime via Xcode's Components preferences.
 
 ## Project structure (key files)
 
 - `Autostream/AutostreamApp.swift` — App entrypoint (struct `Autostream`); applies managed configuration.
 - `Autostream/ContentView.swift` — main SwiftUI view and `UserDefaults` key constants.
 - `Autostream/StreamViewModel.swift` — AVPlayer lifecycle, retry timer, and persisted settings.
 - `Autostream/AppConfig.swift` — maps managed keys into `UserDefaults`.
 - `Autostream/SettingsView.swift` — settings UI bound to `StreamViewModel`.
 - `Autostream/OnChangeOld.swift` — helper providing old+new value for change handlers.
 

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

