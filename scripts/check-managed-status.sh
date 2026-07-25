#!/usr/bin/env bash
set -euo pipefail

# Report whether AutoSignDisplay currently sees a managed configuration.
#
# Usage (runnable from any directory):
#   ./scripts/check-managed-status.sh [--udid <UDID>]
#
# Without --udid, targets a booted tvOS simulator if there is one.

source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib/simulator.sh"

UDID=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --udid) UDID="$2"; shift 2 ;;
    -h|--help) sed -n '4,9p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'; exit 0 ;;
    *) echo "Unknown arg: $1" >&2; exit 2 ;;
  esac
done

UDID="$(resolve_udid "$UDID")"

echo "=========================================="
echo "AutoSignDisplay managed-configuration status"
echo "device: $UDID ($(device_state "$UDID"))"
echo "=========================================="
echo

read_default() {
  xcrun simctl spawn "$UDID" defaults read "$BUNDLE_ID" "$1" 2>&1 || true
}

echo "1. com.apple.configuration.managed:"
MANAGED_CONFIG="$(read_default com.apple.configuration.managed)"
if echo "$MANAGED_CONFIG" | grep -q "does not exist"; then
  echo "   not present — the app is unmanaged"
else
  echo "$MANAGED_CONFIG" | sed 's/^/   /'
fi

echo
echo "2. channelPresetsManaged flag:"
MANAGED_FLAG="$(read_default channelPresetsManaged)"
if echo "$MANAGED_FLAG" | grep -q "does not exist"; then
  echo "   not set — presets are user-editable"
elif [[ "$MANAGED_FLAG" == "0" ]]; then
  echo "   false — presets are user-editable"
else
  echo "   true — presets are locked to the managed list"
fi

echo
# The app's own writes sit in cfprefsd's cache and may not appear above while it is
# running. The container plist on disk is authoritative once the app has quit.
CONTAINER="$(xcrun simctl get_app_container "$UDID" "$BUNDLE_ID" data 2>/dev/null || true)"
PREFS="$CONTAINER/Library/Preferences/$BUNDLE_ID.plist"
if [[ -n "$CONTAINER" && -f "$PREFS" ]]; then
  echo "3. On-disk preferences (authoritative once the app has quit):"
  plutil -p "$PREFS" | sed 's/^/   /'
else
  echo "3. App is not installed on this device, or has never written preferences."
fi
