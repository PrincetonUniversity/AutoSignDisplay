#!/usr/bin/env bash
set -euo pipefail

# Run Autostream unit + UI tests on a tvOS simulator, booting a simulator if needed.
# Usage:
#   ./scripts/run-tests.sh [--udid <UDID>] [--dry-run]

DRY_RUN=0
UDID=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --dry-run) DRY_RUN=1; shift ;;
    --udid) UDID="$2"; shift 2 ;;
    -h|--help) echo "Usage: $0 [--udid <UDID>] [--dry-run]"; exit 0 ;;
    *) echo "Unknown arg: $1" >&2; echo "Usage: $0 [--udid <UDID>] [--dry-run]"; exit 2 ;;
  esac
done

echo "[run-tests] dry-run=${DRY_RUN} udid=${UDID:-<auto>}"

if [[ -z "$UDID" ]]; then
  echo "[run-tests] discovering a suitable tvOS simulator UDID..."
  UDID=$(python3 - <<'PY'
import json,subprocess,sys
out = subprocess.check_output(["xcrun","simctl","list","devices","--json"]).decode()
data = json.loads(out)
devices = data.get('devices', {})
# prefer a booted tvOS device, otherwise pick the first available tvOS device
for runtime in sorted(devices.keys(), reverse=True):
    if 'tvOS' not in runtime:
        continue
    arr = devices[runtime]
    for d in arr:
        if d.get('isAvailable') and d.get('state') == 'Booted':
            print(d['udid']); sys.exit(0)
    for d in arr:
        if d.get('isAvailable'):
            print(d['udid']); sys.exit(0)
print('')
PY
)
  if [[ -z "$UDID" ]]; then
    echo "[run-tests] error: no available tvOS simulator found" >&2
    exit 3
  fi
  echo "[run-tests] selected UDID: $UDID"
fi

# If the device is not Booted, boot it and wait for readiness
STATE=$(xcrun simctl getenv "$UDID" state 2>/dev/null || true)
if [[ "$STATE" != "Booted" ]]; then
  echo "[run-tests] simulator $UDID is not Booted (state="$STATE"). Booting..."
  if [[ $DRY_RUN -eq 1 ]]; then
    echo "DRY: xcrun simctl boot $UDID"
    echo "DRY: xcrun simctl bootstatus $UDID -b"
  else
    xcrun simctl boot "$UDID"
    xcrun simctl bootstatus "$UDID" -b
  fi
else
  echo "[run-tests] simulator $UDID is already Booted"
fi

CMD=(xcodebuild -project Autostream.xcodeproj -scheme Autostream -sdk appletvsimulator -destination "id=$UDID" test)

echo "[run-tests] running: ${CMD[*]}"
if [[ $DRY_RUN -eq 1 ]]; then
  echo "DRY: ${CMD[*]}"
  exit 0
fi

"${CMD[@]}"
