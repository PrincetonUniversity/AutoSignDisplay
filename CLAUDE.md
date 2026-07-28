# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Product purpose

AutoSignDisplay is an Apple TV kiosk player. In priority order:

1. Display an MDM-configured channel list (HLS stream URLs).
2. Auto-play / auto-resume a specific MDM-configured channel.
3. Fall back to manual channel and auto-play configuration when the app is *not* MDM-managed.

The MDM-managed path is the golden path — the `NSNumber` `objCType` guards, sticky-managed-state handling, and `channelPresetsManaged` / `settingsDisabled` UI locks all exist to protect it. When designing a new setting, ask "does this need an MDM key?" first, then "does it need a manual UI?" Regressions in the managed path are higher-priority than regressions in the manual/unmanaged path.

## Project

tvOS SwiftUI app that plays HLS streams. Single Xcode target `AutoSignDisplay` (bundle id `edu.princeton.autosigndisplay`, tvOS 18.4, Swift 5.0). Test targets: `AutoSignDisplayTests` (unit) and `AutoSignDisplayUITests` (UI).

## Build, run, test

Open `AutoSignDisplay.xcodeproj` in Xcode and run the `AutoSignDisplay` scheme against a tvOS simulator.

From the command line, prefer the helper — it discovers or accepts a UDID, boots the simulator, applies managed/unmanaged defaults, and runs tests pinned to that UDID:

```bash
./scripts/run-tests.sh                     # auto-pick simulator, unmanaged
./scripts/run-tests.sh --udid <UDID>       # pin a specific device
./scripts/run-tests.sh --managed           # inject the sample managed plist first
./scripts/run-tests.sh --dry-run           # print actions without running
```

Direct `xcodebuild` — always pin a UDID and disable parallel testing, otherwise xcodebuild spawns cloned simulators and can hang at the tvOS home screen:

```bash
xcodebuild -project AutoSignDisplay.xcodeproj -scheme AutoSignDisplay \
  -sdk appletvsimulator -destination 'id=<UDID>' \
  -parallel-testing-enabled NO test
```

Find or boot a tvOS simulator with `xcrun simctl list devices --json` and `xcrun simctl boot <UDID> && xcrun simctl bootstatus <UDID> -b`. Test output is often truncated in xcodebuild — tee to a file (`2>&1 | tee /tmp/test_output.log`) then grep.

## Architecture

State flows one way: managed plist → `UserDefaults` → `StreamViewModel` (`@Published`) → SwiftUI views.

- **`AutoSignDisplayApp.swift`** — app entrypoint. Calls `AppConfig.applyConfiguration()` in `init()` before any view is created.
- **`AppConfig.swift`** — reads `com.apple.configuration.managed` from `UserDefaults`, validates each key, and mirrors valid values into the app's own `UserDefaults` keys. When the managed dict disappears after a previous managed session, it resets presets to defaults and clears the managed flag.
- **`StreamViewModel.swift`** — owns the `AVPlayer`, the retry timer, and every persisted setting. Reads `UserDefaults` at `init()`; writes back on every mutation. `startStreamIfNeeded()` creates a player and starts the retry timer; `startRetryTimer()` self-heals the player when `autoResume` is on and `currentItem` has gone nil.
- **`ContentView.swift`** — main view. Defines the `UserDefaults` key constants (`playOnOpenKey`, `lastStreamURLKey`, `channelPresetsKey`, `channelPresetsManagedKey`, …) as static let. `scheduleAutoPlayPresentation()` intentionally defers `showPlayer = true` through `DispatchQueue.main.async` and retries once after 1 s — preserve this to avoid tvOS presentation races.
- **`SettingsView.swift` / `ChannelPresetsView.swift`** — bind directly to `StreamViewModel` and call back into it on change; they honor `settingsDisabled` and `channelPresetsManaged` to lock UI when MDM is in charge.

Two parallel key namespaces exist and must be kept in sync when adding settings:

- App-side `UserDefaults` keys — camelCase constants on `ContentView` (e.g. `"playOnAppOpen"`, `"lastStreamURL"`).
- Managed plist keys — PascalCase constants on `AppConfigKeys` (e.g. `"PlayOnAppOpen"`, `"StreamURL"`).

`AppConfig.applyValidatedConfiguration()` is the bridge. Adding a new managed setting means: constant in `AppConfigKeys`, validation + `defaults.set(...)` in `applyValidatedConfiguration`, entry in `ManagedAppConfig.example.plist`, and (if user-facing) a `@Published` property in `StreamViewModel` initialized from `UserDefaults`.

### Preset schema

Presets are `ChannelPreset` (`name: String`, `url: String`) and persist as `[[String: String]]` under `channelPresets`, with the keys `Name` and `URL`. The same keys are used in the managed plist's `ChannelPresets` array — one decoder (`ChannelPreset.fromDictionary`) handles both sources. `AppConfig` and `StreamViewModel.loadPresets` also accept the legacy `[String]` form (each entry becomes a name-less preset) so pre-migration installs and older MDM payloads keep working. Read defaults through `object(forKey:) as? [Any]` — `array(forKey:)` returns nil for dict-of-string arrays imported via `defaults import`.

### Screen presentation and text fields

**Any screen containing a `TextField` must be reached by a navigation push, never by `.sheet` or `.fullScreenCover`.**

Inside a presented modal, tvOS does not tear down a text field's editing presentation when the user backs out of the keyboard without committing: the field is left stuck as a near-white bar with small, faint text, and only an unrelated re-render clears it. The same field reached by `NavigationLink` behaves correctly. `ContentView` pushes both `SettingsView` and `ChannelPresetsView` for this reason; the only `fullScreenCover` in the app is the video player, which holds no text fields.

Consequences worth preserving:

- **Leave text fields unstyled.** No `@FocusState`, no `.focused()`, no `.foregroundColor` on the field, and no `Group` wrapping it — see `LabeledTextField`. tvOS owns the focused background and the text contrast. Every attempt to manage them by hand reintroduced the bug in a new form.
- **Button labels are the opposite case.** They *do* need explicit colors, because a focused button card is near-white and `.primary` resolves to white in dark mode. That is what `RowLabel`, `CenteredRowLabel`, `DestructiveRowLabel`, and `PresetListRow` are for — they read ambient `\.isFocused`. Do not extend that pattern to text fields.
- **Keep `fieldSpacing` at 12pt or more.** A focused tvOS control scales up and casts a shadow; at 6pt the halo bled onto the neighbouring field and lit both.

`FieldEditingPatternTests.swift` enforces these rules by reading the source, since the failure is a rendering state that no unit test can observe and tvOS focus automation is too flaky to assert on in a UI test. The tests are deliberately text-based and comment-stripped; if you rename these types, update the guards.

## Critical gotchas

- **NSNumber vs Bool for managed Boolean keys.** `NSNumber` cast to `Bool` in Swift silently accepts `<integer>1</integer>`. `AppConfig` guards against this by checking `NSNumber` **first**, reading `objCType`, and only accepting `"c"` (CFBoolean). Any new Boolean managed key must follow the same pattern used for `PlayOnAppOpen` / `AutoResume` / `SettingsDisabled` — do not simplify to a plain `as? Bool`.
- **`onChangeOld`, not `.onChange`.** The project uses the custom `OnChangeOldModifier` (in `OnChangeOld.swift`) to get (old, new) across Xcode versions. Do not migrate call sites to newer platform overloads.
- **Main-actor `UserDefaults` in tests.** `ContentView.*Key` constants are main-actor-isolated. Tests must mutate `UserDefaults` inside `await MainActor.run { ... }` before constructing `StreamViewModel` (see the `resetDefaults()` helper in `AutoSignDisplayTests.swift`).
- **Preset count is capped.** `StreamViewModel.maxChannelPresets = 20`; both `addChannelPreset()` and managed-plist loading enforce this. When `channelPresetsManaged` is true, the UI must not allow edits.
- **Managed state is sticky in the simulator.** A previous `--managed` test run leaves `com.apple.configuration.managed` in the app's defaults. To force truly unmanaged state, `xcrun simctl spawn <UDID> defaults delete edu.princeton.autosigndisplay com.apple.configuration.managed` (or `xcrun simctl erase all`). `./scripts/verify-unmanaged.sh` and `./scripts/check-managed-status.sh` inspect the current state.

## Managed-config test fixtures

`AutoSignDisplayTests/*.plist` — `ValidManagedConfig`, `InvalidManagedConfig` (type-rejection cases), `EmptyManagedConfig`, `NegativeRetryTimeoutConfig`. `AppConfig.loadConfigurationFromFile(_:)` locates them across the test bundle and app bundle before injecting into `UserDefaults` and calling `applyConfiguration()`. `PropertyListSerialization` options must be `[]` — `.mutabilityOptions` is invalid and won't compile.

## Repo hygiene

Do not commit `CLAUDE.md`, `.claude/`, or agent authoring messages (per the user's global instructions).
