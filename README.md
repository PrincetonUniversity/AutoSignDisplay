 # Autostream
 
 tvOS app for playing HLS streams, configurable via AppConfig.
 
 ## Build & run (local macOS / Xcode)
 
This project contains an Xcode project (`Autostream.xcodeproj`) that builds the Autostream tvOS app. To open and run locally:

 1. Open `Autostream.xcodeproj` in Xcode.
2. Select the `Autostream` scheme (product name will be `Autostream` at runtime) and choose an Apple TV simulator (e.g., "Apple TV 4K (2nd generation)").
 3. Build and Run (⌘R) to install and launch the app in the tvOS simulator.
 
 Notes:
- The app entrypoint (`Autostream`) applies managed configuration at `init()` by calling `AppConfig.applyConfiguration()`; to test managed settings locally, add the `com.apple.configuration.managed` dictionary to the simulator's `UserDefaults` or use `Streamosphere/ManagedAppConfig.example.plist` as a reference.
 
 ## Build & test from the command line
 
 You can run tests using `xcodebuild`. Example (macOS Terminal):
 
 ```bash
 xcodebuild -project Autostream.xcodeproj -scheme Autostream -sdk appletvsimulator test
 ```
 
This will build and run the unit and UI tests in the tvOS simulator. Tests in `AutostreamTests` prepare `UserDefaults` directly before instantiating `StreamViewModel`.
 
 ## Project structure (key files)
 
 - `Autostream/AutostreamApp.swift` — App entrypoint (struct `Autostream`); applies managed configuration.
 - `Autostream/ContentView.swift` — main SwiftUI view and `UserDefaults` key constants.
 - `Autostream/StreamViewModel.swift` — AVPlayer lifecycle, retry timer, and persisted settings.
 - `Autostream/AppConfig.swift` — maps managed keys into `UserDefaults`.
 - `Autostream/SettingsView.swift` — settings UI bound to `StreamViewModel`.
 - `Autostream/OnChangeOld.swift` — helper providing old+new value for change handlers.
 
 If you'd like, I can add a short troubleshooting section for common simulator issues (signing, missing simulator runtimes) or a script for automated test runs.
