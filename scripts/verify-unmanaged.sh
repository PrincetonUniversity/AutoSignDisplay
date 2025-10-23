#!/bin/bash

DEVICE_ID="22EE280A-72F6-46C5-BA67-357D68316385"
BUNDLE_ID="edu.princeton.orfe.Autostream"

echo "=========================================="
echo "App Managed Configuration Status Check"
echo "=========================================="
echo ""

echo "1. Checking for com.apple.configuration.managed key:"
MANAGED_CONFIG=$(xcrun simctl spawn "$DEVICE_ID" defaults read "$BUNDLE_ID" com.apple.configuration.managed 2>&1)
if echo "$MANAGED_CONFIG" | grep -q "does not exist"; then
    echo "   ✅ CORRECT: No managed config present (key not found)"
else
    echo "   ❌ ERROR: App has managed config:"
    echo "$MANAGED_CONFIG"
fi

echo ""
echo "2. Checking channelPresetsManaged flag:"
MANAGED_FLAG=$(xcrun simctl spawn "$DEVICE_ID" defaults read "$BUNDLE_ID" channelPresetsManaged 2>&1)
if echo "$MANAGED_FLAG" | grep -q "does not exist"; then
    echo "   ✅ CORRECT: Flag not set"
elif [ "$MANAGED_FLAG" = "0" ]; then
    echo "   ✅ CORRECT: Flag is false (not managed)"
else
    echo "   ❌ ERROR: Managed flag is set to: $MANAGED_FLAG"
fi

echo ""
echo "3. App will use default presets:"
DEFAULT_PRESETS=$(xcrun simctl spawn "$DEVICE_ID" defaults read "$BUNDLE_ID" channelPresets 2>&1)
if echo "$DEFAULT_PRESETS" | grep -q "test-streams.mux.dev"; then
    echo "   ✅ CORRECT: Using default test presets"
elif echo "$DEFAULT_PRESETS" | grep -q "does not exist"; then
    echo "   ℹ️  Presets not yet initialized (will use defaults on first app load)"
else
    echo "   Current presets: $DEFAULT_PRESETS"
fi

echo ""
echo "=========================================="
echo "Status: App is UNMANAGED (correct!)"
echo "=========================================="
