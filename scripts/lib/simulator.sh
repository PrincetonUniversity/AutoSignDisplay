#!/usr/bin/env bash
# Shared helpers for the AutoSignDisplay simulator scripts.
#
# Source this, don't execute it:
#   source "$(dirname "${BASH_SOURCE[0]}")/lib/simulator.sh"
#
# Sets REPO_ROOT and cds into it, so callers can use paths relative to the repo
# regardless of the directory the script was invoked from.

PROJECT_NAME="AutoSignDisplay"
SCHEME_NAME="AutoSignDisplay"
BUNDLE_ID="edu.princeton.autosigndisplay"

# shellcheck disable=SC2034
LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$LIB_DIR/../.." && pwd)"
cd "$REPO_ROOT"

# Prints an available tvOS simulator UDID, preferring one that is already booted.
# Empty output means none was found.
discover_udid() {
  python3 - <<'PY'
import json, subprocess, sys
out = subprocess.check_output(["xcrun", "simctl", "list", "devices", "--json"]).decode()
devices = json.loads(out).get("devices", {})
# Newest runtime first, so a fresh tvOS is picked over an old one.
for runtime in sorted(devices.keys(), reverse=True):
    if "tvOS" not in runtime:
        continue
    for state in ("Booted", None):
        for d in devices[runtime]:
            if not d.get("isAvailable"):
                continue
            if state is None or d.get("state") == state:
                print(d["udid"])
                sys.exit(0)
print("")
PY
}

# Echoes a device's current state (Booted / Shutdown / Unknown).
device_state() {
  python3 - "$1" <<'PY'
import json, subprocess, sys
udid = sys.argv[1]
out = subprocess.check_output(["xcrun", "simctl", "list", "devices", "--json"]).decode()
for devs in json.loads(out).get("devices", {}).values():
    for d in devs:
        if d.get("udid") == udid:
            print(d.get("state", "Unknown"))
            sys.exit(0)
print("Unknown")
PY
}

# Resolves a UDID: uses $1 if non-empty, otherwise discovers one. Exits on failure.
resolve_udid() {
  local requested="${1:-}"
  if [[ -n "$requested" ]]; then
    printf '%s' "$requested"
    return
  fi
  local found
  found="$(discover_udid)"
  if [[ -z "$found" ]]; then
    echo "error: no available tvOS simulator found." >&2
    echo "       Install a tvOS runtime via Xcode > Settings > Components." >&2
    exit 3
  fi
  printf '%s' "$found"
}

# Boots the device if needed and waits for readiness.
ensure_booted() {
  local udid="$1" dry_run="${2:-0}" state
  state="$(device_state "$udid")"
  if [[ "$state" == "Booted" ]]; then
    echo "[sim] $udid already booted"
    return
  fi
  echo "[sim] booting $udid (was $state)"
  if [[ "$dry_run" -eq 1 ]]; then
    echo "DRY: xcrun simctl boot $udid && xcrun simctl bootstatus $udid -b"
    return
  fi
  xcrun simctl boot "$udid"
  xcrun simctl bootstatus "$udid" -b
}

# Writes or clears the managed app configuration for the app on a device.
#   apply_managed_state <udid> <managed|unmanaged> [dry_run]
apply_managed_state() {
  local udid="$1" mode="$2" dry_run="${3:-0}"

  if [[ "$mode" != "managed" ]]; then
    echo "[sim] clearing managed configuration"
    if [[ "$dry_run" -eq 1 ]]; then
      echo "DRY: xcrun simctl spawn $udid defaults delete $BUNDLE_ID com.apple.configuration.managed"
      return
    fi
    xcrun simctl spawn "$udid" defaults delete "$BUNDLE_ID" \
      com.apple.configuration.managed >/dev/null 2>&1 || true
    return
  fi

  echo "[sim] applying managed configuration from mdm/jamf-app-config-kiosk.xml"
  if [[ "$dry_run" -eq 1 ]]; then
    echo "DRY: import mdm/jamf-app-config-kiosk.xml wrapped as com.apple.configuration.managed"
    return
  fi

  # The repo's example payload is the inner dictionary; MDM delivers it wrapped in
  # com.apple.configuration.managed, so wrap it the same way here. Using the shipped
  # example keeps this path honest — if the example breaks, these runs break too.
  local wrapped
  wrapped="$(mktemp -t asd-managed).plist"
  python3 - "$REPO_ROOT/mdm/jamf-app-config-kiosk.xml" "$wrapped" <<'PY'
import plistlib, sys
with open(sys.argv[1], "rb") as f:
    inner = plistlib.load(f)
# Point at a stream that actually resolves, so a managed run can be eyeballed.
url = "https://test-streams.mux.dev/x36xhzz/x36xhzz.m3u8"
inner["ChannelPresets"] = [{"Name": "Test Stream", "URL": url}]
inner["DefaultChannel"] = url
with open(sys.argv[2], "wb") as f:
    plistlib.dump({"com.apple.configuration.managed": inner}, f)
PY
  xcrun simctl spawn "$udid" defaults import "$BUNDLE_ID" "$wrapped"
  rm -f "$wrapped"
}
