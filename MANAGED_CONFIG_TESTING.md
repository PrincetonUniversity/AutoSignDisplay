# Managed App Configuration Testing Guide

## Current Status

✅ **The app is now running UNMANAGED in the simulator** (the correct default state)

The previous simulator instance had managed config data persisted from test runs. This has been cleared.

## What's Different Now

### Before (Managed State - INCORRECT)
- `com.apple.configuration.managed` key existed in UserDefaults
- `channelPresetsManaged` flag was `true`
- App displayed "Managed" UI indicators

### After (Unmanaged State - CORRECT) 
- ❌ No `com.apple.configuration.managed` key in UserDefaults
- ✅ No `channelPresetsManaged` flag (defaults to `false`)
- ✅ App uses default test presets
- ✅ All settings are editable by the user

## How We Fixed It

1. **Shut down simulator**: `xcrun simctl shutdown all`
2. **Erased all simulator state**: `xcrun simctl erase all`
3. **Built fresh app**: `xcodebuild -project AutoSignDisplay.xcodeproj -scheme AutoSignDisplay -sdk appletvsimulator build`
4. **Installed to clean simulator**: Clean install onto reset simulator

## Building Without Managed Config

To build and install a version that is NOT managed (the default):

```bash
# Build the app
xcodebuild -project AutoSignDisplay.xcodeproj -scheme AutoSignDisplay -sdk appletvsimulator build

# Erase simulator state (if needed)
xcrun simctl shutdown all
xcrun simctl erase all

# Boot simulator
xcrun simctl boot <device-id>

# Install app
xcrun simctl install <device-id> <path-to-build>/AutoSignDisplay.app

# Launch app
xcrun simctl launch <device-id> edu.princeton.autosigndisplay
```

## Testing Managed vs Unmanaged

### Unmanaged (Default)
```bash
./scripts/verify-unmanaged.sh
```

### Managed (With Config)
To test managed mode, inject a config plist:
```bash
xcrun simctl spawn <device-id> defaults write \
  edu.princeton.autosigndisplay \
  com.apple.configuration.managed \
  -dict-add ChannelPresets \
  -array-add-string "https://example.com/channel.m3u8"
```

Then relaunch the app to apply managed configuration.

## Key Behavioral Differences

| Aspect | Unmanaged | Managed |
|--------|-----------|---------|
| Channel Presets | User can add/remove/edit | Preset by MDM administrator |
| Settings | User can modify | May be locked/hidden |
| Stream URL | User selects from presets | Set by DefaultChannel config |
| PlayOnOpen | User preference | Can be enforced by config |
| Auto-Resume | User preference | Can be enforced by config |

## Current Running Instance

Device ID: `22EE280A-72F6-46C5-BA67-357D68316385`  
App Bundle ID: `edu.princeton.autosigndisplay`  
Status: ✅ **Unmanaged** (correct)
