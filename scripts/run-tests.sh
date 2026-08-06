#!/usr/bin/env bash
set -euo pipefail

# Run AutoSignDisplay unit + UI tests on a tvOS simulator, booting a simulator if needed.
# Usage (runnable from any directory):
#   ./scripts/run-tests.sh [--udid <UDID>] [--dry-run] [--managed | --unmanaged]

# shellcheck source=scripts/lib/simulator.sh
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib/simulator.sh"

DRY_RUN=0
UDID=""
MANAGED_MODE="unmanaged"

APP=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --app)     APP="${2:?--app needs a scheme name}"; shift 2 ;;
    --dry-run) DRY_RUN=1; shift ;;
    --udid) UDID="$2"; shift 2 ;;
    --managed) MANAGED_MODE="managed"; shift ;;
    --unmanaged) MANAGED_MODE="unmanaged"; shift ;;
    -h|--help) echo "Usage: $0 [--udid <UDID>] [--dry-run] [--managed | --unmanaged]"; exit 0 ;;
    *) echo "Unknown arg: $1" >&2; echo "Usage: $0 [--udid <UDID>] [--dry-run] [--managed | --unmanaged]"; exit 2 ;;
  esac
done

select_app "$APP"

echo "[run-tests] dry-run=${DRY_RUN} udid=${UDID:-<auto>}"

UDID="$(resolve_udid "$UDID")"
echo "[run-tests] device: $UDID"

ensure_booted "$UDID" "$DRY_RUN"
apply_managed_state "$UDID" "$MANAGED_MODE" "$DRY_RUN"

# Same checks Xcode Cloud runs via ci_scripts/ci_post_clone.sh. Cheap, and they
# catch the classes of defect that otherwise surface only after an upload.
if [[ "$DRY_RUN" -eq 0 ]]; then
  python3 "$REPO_ROOT/scripts/check-source-patterns.py"
fi

CMD=(xcodebuild -project "$PROJECT_NAME.xcodeproj" -scheme "$SCHEME_NAME" -sdk appletvsimulator -destination "id=$UDID" -parallel-testing-enabled NO test)

echo "[run-tests] running: ${CMD[*]}"
if [[ $DRY_RUN -eq 1 ]]; then
  echo "DRY: ${CMD[*]}"
  exit 0
fi

"${CMD[@]}"
