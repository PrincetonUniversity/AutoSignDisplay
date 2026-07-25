# Managed App Configuration

AutoSignDisplay is designed to be provisioned by MDM. Everything a user can set
on the device can be set centrally instead, and locked.

| File | Use |
|---|---|
| [`jamf-app-config-kiosk.xml`](jamf-app-config-kiosk.xml) | Typical unattended display — one channel, locked settings. Start here. |
| [`jamf-app-config.xml`](jamf-app-config.xml) | Every supported key, commented. |

Both are also mirrored by
[`../AutoSignDisplay/ManagedAppConfig.example.plist`](../AutoSignDisplay/ManagedAppConfig.example.plist),
which is the copy that ships alongside the source.

## Applying it

**Jamf Pro:** Devices → Mobile Device Apps → AutoSignDisplay → **App
Configuration**, then paste the file's contents (including the `<dict>`).

Other MDMs use the same mechanism under different names — "Managed App Config",
"App Configuration", "Managed Preferences". The payload format is identical
because it is defined by Apple, not by the MDM.

Bundle identifier: `edu.princeton.autosigndisplay`

Do **not** wrap the dictionary in a `com.apple.configuration.managed` key. The
platform supplies that wrapper; the app reads it from `UserDefaults`. Your payload
is the inner dictionary only.

## Keys

Every key is optional. Omit one and the app keeps whatever value it already has —
a partial payload manages only what it names.

| Key | Type | Notes |
|---|---|---|
| `DisplayTitle` | String | Heading at the top of the main screen. Must be non-empty. Omit for the app's own name. |
| `ViewOnlyMode` | Boolean | Reduce the main screen to the preset list. |
| `SettingsPIN` | String | Require this PIN to open Settings. Must be non-empty. |
| `PlayOnAppOpen` | Boolean | Begin playback at launch. |
| `AutoResume` | Boolean | Rebuild the player when a stream stalls or the network drops. |
| `SettingsDisabled` | Boolean | Lock the on-device Settings screen. |
| `RetryTimeout` | Real | Seconds before retrying a stalled stream. Must be positive; non-positive values are rejected. |
| `StreamURL` | String | Stream to load. Must be non-empty. Takes precedence over `DefaultChannel`. |
| `DefaultChannel` | String | Preset to select at launch. Match a `ChannelPresets` URL exactly. |
| `ChannelPresets` | Array | Up to 20 entries; extras are dropped. |

### ChannelPresets

Each entry is a dictionary with a required `URL` and an optional `Name`. When a
name is present the app shows it in place of the URL, which makes the on-screen
list readable:

```xml
<dict>
  <key>Name</key>
  <string>Lobby</string>
  <key>URL</key>
  <string>https://stream.example.edu/lobby/index.m3u8</string>
</dict>
```

A flat array of `<string>` URLs is still accepted, so payloads written before
names existed keep working — each becomes a name-less preset. Entries missing a
URL, or with a blank one, are discarded.

When `ChannelPresets` is present the app marks its preset list read-only: the
on-device Manage Stream Presets screen shows the entries but allows no edits,
additions, or deletions.

## Locking a display down

Three keys restrict what a local user can do, and they are independent — pick the
combination that matches how much control the site should have.

| Key | Removes |
|---|---|
| `ViewOnlyMode` | Stream URL entry, Play/Clear, and the Manage Stream Presets button. The preset list stays, and pressing a preset plays it. |
| `SettingsDisabled` | Access to Settings entirely. |
| `SettingsPIN` | Nothing, but demands a PIN before Settings opens. |

A common pairing is `ViewOnlyMode` with `SettingsPIN`: a local user can switch
between the channels you provisioned but cannot add streams, edit presets, or
change playback behavior without the PIN.

`ViewOnlyMode` alone still leaves Settings reachable — deliberately, since
otherwise a device configured this way could not be taken out of the mode from the
couch. Combine it with `SettingsDisabled` or `SettingsPIN` if that matters.

### About `SettingsPIN`

**This is a deterrent, not a security control.** The PIN is kept in the app's
preferences, not the keychain, and it is compared as plain text. It stops a
passer-by from changing the channel list; it does not stop anyone with device
access or MDM read access. Do not reuse a PIN that protects anything else.

When the PIN arrives by MDM, the on-device PIN field becomes read-only, so a local
user cannot change or clear an administrator's PIN. Removing the payload clears the
PIN along with it — otherwise pulling the configuration would strand Settings behind
a PIN nobody on site knows.

The prompt appears on each visit to Settings; unlocking is not remembered between
visits.

## Booleans must be `<true/>` or `<false/>`

This is the one type rule worth stating outright, because the failure is silent.

```xml
<!-- Correct -->
<key>PlayOnAppOpen</key>
<true/>

<!-- Rejected: the value is ignored and the app keeps its local setting -->
<key>PlayOnAppOpen</key>
<integer>1</integer>
```

Swift will happily cast an `NSNumber` holding `1` to `true`, so a payload using
integers would appear to work while actually being malformed. AutoSignDisplay
guards against that by inspecting the underlying type and accepting only a real
CFBoolean. If a Boolean setting seems to be ignored, check that your MDM emitted
`<true/>` rather than `<integer>1</integer>` — some editors substitute one for the
other.

This applies to `PlayOnAppOpen`, `AutoResume`, `SettingsDisabled`, and
`ViewOnlyMode`.

## Behavior notes

- **`DisplayTitle` is useful for telling displays apart.** Pushing the location a
  screen serves — `Engineering Quad — Lobby` — means a technician can identify a
  display without cross-referencing its serial number. Blank or whitespace-only
  values are rejected, so a mistake leaves the default heading rather than an empty
  one. Users can also set it on-device under Settings → Appearance unless
  `SettingsDisabled` is true.
- **`RetryTimeout` is not restricted to the values in the UI.** The Settings
  screen cycles through 3/5/10/15/30/60 seconds because typing digits on a remote
  is slow, but any positive number you push is honored and displayed. A managed
  value of `7` shows as `7s`.
- **`DefaultChannel` must match a preset URL exactly** for the app to highlight
  that row. A mismatch still plays the stream; it just won't mark a preset.
- **Managed presets are sticky until the payload is removed.** When the
  configuration disappears, the app restores its default presets and clears the
  managed flag, along with the playback preferences the payload had set.
- **Removing the payload does not reset local-only preferences** such as Confirm
  Before Deleting, which has no managed key: preset editing is unavailable under
  MDM, so there is nothing for an administrator to configure.

## Verifying on a device or simulator

`scripts/check-managed-status.sh` and `scripts/verify-unmanaged.sh` report whether
the app currently sees a managed payload. To exercise the managed path against a
simulator:

```bash
./scripts/run-tests.sh --managed     # inject a sample payload, then run tests
./scripts/run-tests.sh --unmanaged   # clear it first
```

Managed state persists in a simulator between runs. To force a genuinely unmanaged
launch:

```bash
xcrun simctl spawn <UDID> defaults delete edu.princeton.autosigndisplay \
  com.apple.configuration.managed
```
