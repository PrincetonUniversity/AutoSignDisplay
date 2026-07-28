# Managed App Configuration

AutoSignDisplay is designed to be provisioned by MDM. Everything a user can set
on the device can be set centrally instead, and locked.

| File | Use |
|---|---|
| [`jamf-app-config-verify.xml`](jamf-app-config-verify.xml) | First install on a managed device — proves the payload is arriving, locks nothing. Start here. |
| [`jamf-app-config-kiosk.xml`](jamf-app-config-kiosk.xml) | Typical unattended display — one channel, locked settings. |
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
| `SettingsPIN` | String | Require this PIN to open Settings. At least 6 characters. |
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

Must be at least 6 characters. Shorter values are rejected: a short PIN locks a
fleet out as effectively as a long one while being trivial to guess, and a
half-typed one locks out the very screen needed to correct it. Managed PINs need
not be numeric — a passphrase is fine — though the on-device field accepts digits
only, since that is what a remote can enter comfortably.

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

### Recovering from a forgotten PIN

There is no back door, and there does not need to be: the app stores only its own
configuration — presets, playback preferences, the title — and nothing a site would
miss. **Reinstalling the app is a legitimate first resort.** It discards the
preferences, PIN included, and the device picks the managed payload back up on next
launch.

For a managed fleet, two routes avoid touching the device:

| Situation | Recovery |
|---|---|
| The PIN came from MDM | Push a payload with a known `SettingsPIN`, or one that **omits** `SettingsPIN` — omitting it clears the PIN on next launch. |
| A user set the PIN on-device | Push a payload with a known `SettingsPIN`. It overrides the local value. |
| Either | Delete and reinstall the app. |

Note the asymmetry: a payload that omits `SettingsPIN` clears a *managed* PIN, but
leaves a *user-set* one alone. The app only knows a PIN was administrator-owned
because it recorded that when applying it, so there is no managed flag to act on for
a PIN it never managed. Pushing a known PIN works in both cases, which makes it the
reliable move if you are unsure which kind you are dealing with.

When testing this against a simulator, be aware that `defaults import` plus a
running app is a poor imitation of MDM: the app's own preference write-back can
clobber the `com.apple.configuration.managed` key you just imported, and reads taken
immediately after a write may catch cfprefsd mid-flush and show stale or mixed
state. Terminate the app and re-read the container plist before trusting what you
see:

```bash
xcrun simctl terminate <UDID> edu.princeton.autosigndisplay
plutil -p "$(xcrun simctl get_app_container <UDID> edu.princeton.autosigndisplay data)"/Library/Preferences/edu.princeton.autosigndisplay.plist
```

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

## Applying a changed payload

**The app reads managed configuration once, at launch.** `applyConfiguration()` runs
in the app's `init()`, so a payload you change in Jamf does not take effect until the
app's process restarts. Backgrounding is not enough on tvOS — force-quit it
(double-press TV, swipe up) or reboot the device.

This matters operationally, not just while testing: changing the channel list for a
wall-mounted display currently needs the app restarted. Until that changes, a
Jamf-scheduled nightly restart is the practical way to make configuration changes
land without visiting the device.

Treating the payload as declarative — the app noticing a changed payload and
reconciling to it live, including switching the playing channel — is planned for 1.1.
It needs the configuration re-applied when the managed dictionary changes and the
view model reloaded from defaults, and it has to avoid reacting to the app's *own*
writes to `UserDefaults`, which would otherwise loop.

## TestFlight cannot test any of this

A build installed from TestFlight is not an MDM-managed app, so no managed
configuration is delivered to it. TestFlight is the right way to check playback,
auto-resume and the remote-control UI on real hardware; it tells you nothing about
the managed path.

To exercise managed configuration before the app is publicly available, distribute it
as a **Custom App** through Apple Business Manager so Jamf installs it as a managed
app. Only then does the App Configuration payload reach it.

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
