#!/bin/bash
set -e

DEVICE_ID="22EE280A-72F6-46C5-BA67-357D68316385"
BUNDLE_ID="edu.princeton.orfe.Autostream"

# Wait a moment for the app to initialize
sleep 2

# Check UserDefaults for the managed flag
echo "Checking if app is marked as managed..."
xcrun simctl spawn "$DEVICE_ID" defaults read "$BUNDLE_ID" com.apple.configuration.managed 2>/dev/null || echo "✅ NOT managed (com.apple.configuration.managed key not found - this is correct)"

echo ""
echo "Checking the channelPresetsManaged flag..."
xcrun simctl spawn "$DEVICE_ID" defaults read "$BUNDLE_ID" channelPresetsManaged 2>/dev/null || echo "✅ Not set as managed (channelPresetsManaged not found or is false)"

echo ""
echo "All UserDefaults keys for the app:"
xcrun simctl spawn "$DEVICE_ID" defaults read "$BUNDLE_ID" 2>/dev/null | head -30 || echo "No defaults found"
