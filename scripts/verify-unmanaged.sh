#!/usr/bin/env bash
set -euo pipefail

# Assert that AutoSignDisplay is in a genuinely unmanaged state, exiting non-zero if
# it is not. Managed state is sticky in a simulator, so a previous --managed run can
# silently poison later unmanaged testing.
#
# Usage (runnable from any directory):
#   ./scripts/verify-unmanaged.sh [--udid <UDID>] [--fix]
#
#   --fix   clear the state instead of only reporting it

# shellcheck source=scripts/lib/simulator.sh
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib/simulator.sh"

UDID=""
FIX=0
APP=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --app)     APP="${2:?--app needs a scheme name}"; shift 2 ;;
    --udid) UDID="$2"; shift 2 ;;
    --fix) FIX=1; shift ;;
    -h|--help) sed -n '4,12p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'; exit 0 ;;
    *) echo "Unknown arg: $1" >&2; exit 2 ;;
  esac
done

select_app "$APP"

UDID="$(resolve_udid "$UDID")"
echo "[verify] device: $UDID ($(device_state "$UDID"))"

read_default() {
  xcrun simctl spawn "$UDID" defaults read "$BUNDLE_ID" "$1" 2>&1 || true
}

FAILURES=0

MANAGED_CONFIG="$(read_default com.apple.configuration.managed)"
if echo "$MANAGED_CONFIG" | grep -q "does not exist"; then
  echo "[verify] ok: no managed configuration present"
else
  echo "[verify] FAIL: managed configuration is present" >&2
  FAILURES=$((FAILURES + 1))
fi

MANAGED_FLAG="$(read_default channelPresetsManaged)"
if echo "$MANAGED_FLAG" | grep -q "does not exist" || [[ "$MANAGED_FLAG" == "0" ]]; then
  echo "[verify] ok: channelPresetsManaged is not set"
else
  echo "[verify] FAIL: channelPresetsManaged is $MANAGED_FLAG" >&2
  FAILURES=$((FAILURES + 1))
fi

if [[ $FAILURES -eq 0 ]]; then
  echo "[verify] app is unmanaged"
  exit 0
fi

if [[ $FIX -eq 1 ]]; then
  echo "[verify] clearing managed state"
  # Remove the whole domain: clearing only com.apple.configuration.managed leaves
  # the mirrored app-side keys behind, which is what makes this state so sticky.
  xcrun simctl spawn "$UDID" defaults delete "$BUNDLE_ID" >/dev/null 2>&1 || true
  echo "[verify] cleared — relaunch the app to re-seed defaults"
  exit 0
fi

cat >&2 <<EOF

[verify] to clear it:
  ./scripts/verify-unmanaged.sh --udid $UDID --fix
EOF
exit 1
