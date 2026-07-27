#!/usr/bin/env bash
# One-time (and re-runnable) setup for App Store Connect submission.
#
# Checks every prerequisite for signing and uploading, reports exactly what is
# missing and how to fix it, and can install the two credentials the release script
# needs. Read-only unless you pass --api-key or --store-password.
#
#   ./scripts/appstore-bootstrap.sh                      # check everything, change nothing
#   ./scripts/appstore-bootstrap.sh --list-teams         # show signing teams found locally
#   ./scripts/appstore-bootstrap.sh --api-key ~/AuthKey_ABC123.p8 \
#       --key-id ABC123 --issuer-id <uuid>               # install API key credentials
#   ./scripts/appstore-bootstrap.sh --store-password     # store an app-specific password
#   ./scripts/appstore-bootstrap.sh --provision          # let Xcode create cert + profile
#
# Exits non-zero when a required check fails, so it doubles as a preflight.

set -euo pipefail

# shellcheck source=scripts/lib/appstore.sh
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib/appstore.sh"

TEAM_ARG=""
API_KEY_PATH=""
KEY_ID=""
ISSUER_ID=""
STORE_PASSWORD=0
LIST_TEAMS=0
PROVISION=0

usage() {
  cat <<'USAGE'
appstore-bootstrap.sh — check and set up everything needed to submit to App Store Connect.

  ./scripts/appstore-bootstrap.sh                  Check all prerequisites, change nothing.
  ./scripts/appstore-bootstrap.sh --list-teams     List signing teams found locally.
  ./scripts/appstore-bootstrap.sh --provision      Archive once so Xcode creates the
                                                   distribution certificate and profile.

Installing credentials (pick one):
  --api-key <path.p8> --key-id <id> --issuer-id <uuid>
                                                   App Store Connect API key. Preferred:
                                                   not tied to a personal Apple ID.
  --store-password                                 Apple ID + app-specific password,
                                                   stored in the login keychain.

Other options:
  --team <name|id|project>                         Team to check. Defaults to the project's.
  --dry-run                                        Print actions without taking them.
  -h, --help                                       This text.

Exits non-zero if a required check fails, so it doubles as a preflight.
USAGE
  exit 0
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --team)            TEAM_ARG="${2:?--team needs a value}"; shift 2 ;;
    --api-key)         API_KEY_PATH="${2:?--api-key needs a path}"; shift 2 ;;
    --key-id)          KEY_ID="${2:?--key-id needs a value}"; shift 2 ;;
    --issuer-id)       ISSUER_ID="${2:?--issuer-id needs a value}"; shift 2 ;;
    --store-password)  STORE_PASSWORD=1; shift ;;
    --list-teams)      LIST_TEAMS=1; shift ;;
    --provision)       PROVISION=1; shift ;;
    --dry-run)         DRY_RUN=1; shift ;;
    -h|--help)         usage ;;
    *)                 die "unknown option: $1 (try --help)" ;;
  esac
done

load_release_config

FAILURES=0
pass() { echo "  ok    $*"; }
fail() { echo "  FAIL  $*"; FAILURES=$((FAILURES + 1)); }
note() { echo "        $*"; }

# ---------- --list-teams ----------

if [[ "$LIST_TEAMS" -eq 1 ]]; then
  section "Signing teams with certificates installed locally"
  if [[ -z "$(list_signing_teams)" ]]; then
    echo "  (none)"
  else
    printf '  %-12s %s\n' "TEAM ID" "ORGANISATION"
    list_signing_teams | while IFS=$'\t' read -r team org; do
      printf '  %-12s %s\n' "$team" "$org"
    done
  fi
  section "Distribution identities (required for App Store submission)"
  if installed_identities | awk -F'\t' '$2 == "Apple Distribution"' | grep -q .; then
    installed_identities | awk -F'\t' '$2 == "Apple Distribution" { printf "  %-12s %s\n", $1, $3 }'
  else
    echo "  (none — see 'Distribution certificate' below when you run without --list-teams)"
  fi
  echo
  echo "The project builds for team: $(project_team_id)"
  exit 0
fi

# ---------- credential installation ----------

if [[ -n "$API_KEY_PATH" ]]; then
  section "Installing App Store Connect API key"
  [[ -f "$API_KEY_PATH" ]] || die "no such file: $API_KEY_PATH"
  [[ -n "$KEY_ID" ]]    || die "--api-key also needs --key-id (the 10-character Key ID)."
  [[ -n "$ISSUER_ID" ]] || die "--api-key also needs --issuer-id (the UUID from ASC > Integrations)."

  # altool only looks in these directories; the filename must be AuthKey_<KEYID>.p8.
  run_cmd mkdir -p "$ASC_KEY_DIR"
  run_cmd chmod 700 "$ASC_KEY_DIR"
  run_cmd cp "$API_KEY_PATH" "$ASC_KEY_DIR/AuthKey_${KEY_ID}.p8"
  run_cmd chmod 600 "$ASC_KEY_DIR/AuthKey_${KEY_ID}.p8"
  log "installed $ASC_KEY_DIR/AuthKey_${KEY_ID}.p8"

  # Record the non-secret halves so release.sh can find them. The .p8 itself stays
  # outside the repo.
  if [[ "$DRY_RUN" -eq 0 ]]; then
    umask 077
    cat > "$ENV_FILE" <<ENV
# App Store Connect credentials for scripts/release.sh.
# Written by scripts/appstore-bootstrap.sh. Gitignored — do not commit.
# The private key lives at $ASC_KEY_DIR/AuthKey_${KEY_ID}.p8, not here.
ASC_KEY_ID="$KEY_ID"
ASC_ISSUER_ID="$ISSUER_ID"
ENV
    log "wrote scripts/appstore.env (gitignored)"
  else
    echo "DRY: write scripts/appstore.env with ASC_KEY_ID / ASC_ISSUER_ID"
  fi
  load_release_config
fi

if [[ "$STORE_PASSWORD" -eq 1 ]]; then
  section "Storing an app-specific password in the keychain"
  local_user="${ASC_USERNAME:-}"
  if [[ -z "$local_user" ]]; then
    read -r -p "  Apple ID email: " local_user
  fi
  [[ -n "$local_user" ]] || die "an Apple ID is required."
  echo "  Create an app-specific password at https://appleid.apple.com > Sign-In and Security."
  read -r -s -p "  App-specific password: " app_password
  echo
  [[ -n "$app_password" ]] || die "no password entered."

  item="AutoSignDisplay-ASC"
  run_cmd xcrun altool --store-password-in-keychain-item "$item" \
    -u "$local_user" -p "$app_password"
  log "stored keychain item '$item'"

  if [[ "$DRY_RUN" -eq 0 ]]; then
    umask 077
    cat > "$ENV_FILE" <<ENV
# App Store Connect credentials for scripts/release.sh.
# Written by scripts/appstore-bootstrap.sh. Gitignored — do not commit.
# The password itself is in the login keychain under ASC_KEYCHAIN_ITEM.
ASC_USERNAME="$local_user"
ASC_KEYCHAIN_ITEM="$item"
ENV
    log "wrote scripts/appstore.env (gitignored)"
  fi
  unset app_password
  load_release_config
fi

# ---------- checks ----------

section "Toolchain"
for cmd in xcodebuild xcrun git security python3; do
  if command -v "$cmd" >/dev/null 2>&1; then pass "$cmd"; else fail "$cmd not on PATH"; fi
done
if xcrun --find altool >/dev/null 2>&1; then
  pass "altool ($(xcodebuild -version | head -1))"
else
  fail "altool not found — install the full Xcode, not just Command Line Tools"
fi

section "Project"
TEAM="$(resolve_team "$TEAM_ARG")"
PROJECT_TEAM="$(project_team_id)"
VERSION="$(project_marketing_version)"
BUILD="$(default_build_number)"

pass "bundle identifier: $BUNDLE_ID"
pass "App Store Connect record: Apple ID $ASC_APPLE_ID"
pass "build number would be: $BUILD (commit count)"

if [[ "$TEAM" == "$PROJECT_TEAM" ]]; then
  pass "team: $TEAM (from the project)"
else
  pass "team: $TEAM (overriding the project's $PROJECT_TEAM)"
  note "release.sh must be given the same --team, or it will build for $PROJECT_TEAM."
fi

team_name="$(team_display_name "$TEAM")"
if [[ -n "$team_name" ]]; then
  pass "team $TEAM is '$team_name'"
else
  note "team $TEAM has no certificate installed yet, so its name cannot be confirmed"
  note "locally — Xcode's account list is not exposed to the CLI. It will be shown"
  note "once a certificate exists."
fi

# A version of 0.x almost certainly does not match a hand-filled ASC record, and
# the mismatch surfaces only after a full archive and upload.
if [[ "$VERSION" =~ ^0\. ]]; then
  fail "MARKETING_VERSION is $VERSION"
  note "App Store Connect rejects a build whose version has no matching record."
  note "If the record you filled out says 1.0, set MARKETING_VERSION to 1.0 in Xcode"
  note "(or pass --version 1.0 to release.sh, which overrides without editing the project)."
else
  pass "marketing version: $VERSION"
fi

section "Distribution certificate"
if team_has_distribution_identity "$TEAM"; then
  pass "Apple Distribution identity present for team $TEAM"
else
  fail "no Apple Distribution identity for team $TEAM"
  note "An Apple Development certificate is not sufficient for App Store submission."
  note "Two ways to fix it:"
  note "  1. Xcode > Settings > Accounts > select the team > Manage Certificates >"
  note "     + > Apple Distribution."
  note "  2. Re-run this script with --provision, which archives once with"
  note "     -allowProvisioningUpdates and lets Xcode create the certificate and"
  note "     profile for you. Note this consumes one of the team's two distribution"
  note "     certificate slots, which matters on a shared team."
  if [[ -n "$(list_signing_teams)" ]]; then
    note "Installed identities are for these teams:"
    list_signing_teams | while IFS=$'\t' read -r t o; do note "  $t  $o"; done
  fi
fi

section "App Store Connect credentials"
case "$(asc_credential_mode)" in
  api-key)
    pass "API key: Key ID ${ASC_KEY_ID}, issuer ${ASC_ISSUER_ID}"
    pass "private key at $ASC_KEY_DIR/AuthKey_${ASC_KEY_ID}.p8"
    ;;
  keychain)
    pass "app-specific password for ${ASC_USERNAME} in keychain item ${ASC_KEYCHAIN_ITEM}"
    note "An API key is preferable: not tied to a personal Apple ID, and survives you"
    note "leaving the team. Re-run with --api-key once you have one."
    ;;
  none)
    fail "no credentials configured"
    note "Preferred — App Store Connect API key (App Manager can create an individual"
    note "key: ASC > Integrations > App Store Connect API > Individual Keys):"
    note "  ./scripts/appstore-bootstrap.sh --api-key ~/Downloads/AuthKey_XXXX.p8 \\"
    note "      --key-id XXXX --issuer-id <uuid>"
    note "Fallback — app-specific password tied to your Apple ID:"
    note "  ./scripts/appstore-bootstrap.sh --store-password"
    ;;
esac

# ---------- optional: materialise signing assets ----------

if [[ "$PROVISION" -eq 1 ]]; then
  section "Provisioning (archiving once so Xcode creates signing assets)"
  archive="$RELEASE_DIR/provision-probe.xcarchive"
  run_cmd mkdir -p "$RELEASE_DIR"
  run_cmd rm -rf "$archive"
  log "archiving for team $TEAM — Xcode will create a certificate and profile if needed"
  run_cmd xcodebuild archive \
    -project "$XCODEPROJ" \
    -scheme "$SCHEME_NAME" \
    -configuration Release \
    -destination 'generic/platform=tvOS' \
    -archivePath "$archive" \
    -allowProvisioningUpdates \
    DEVELOPMENT_TEAM="$TEAM"
  if [[ "$DRY_RUN" -eq 0 ]]; then
    if team_has_distribution_identity "$TEAM"; then
      log "distribution identity for $TEAM is now present ($(team_display_name "$TEAM"))"
    else
      warn "archive succeeded but no Apple Distribution identity appeared for $TEAM."
      warn "Create one via Xcode > Settings > Accounts > Manage Certificates."
    fi
    run_cmd rm -rf "$archive"
  fi
fi

# ---------- verdict ----------

section "Result"
if [[ "$FAILURES" -eq 0 ]]; then
  log "ready. Next: ./scripts/release.sh --validate-only"
  exit 0
fi
log "$FAILURES check(s) failed — see the notes above."
exit 1
