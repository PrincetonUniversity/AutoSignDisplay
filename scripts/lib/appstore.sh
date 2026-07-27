#!/usr/bin/env bash
# Shared helpers for the AutoSignDisplay App Store scripts.
#
# Source this, don't execute it:
#   source "$(dirname "${BASH_SOURCE[0]}")/lib/appstore.sh"
#
# Sets REPO_ROOT and cds into it, so callers can use repo-relative paths no matter
# where they were invoked from. Matches lib/simulator.sh, which the simulator
# scripts share — bash rather than zsh so both are sourceable from either shell.
#
# Nothing here touches the network or the keychain at source time. The functions
# that parse tool output take stdin so they can be tested against fixtures; see
# scripts/tests/appstore.bats.

# These are read by the scripts that source this file, not here.
# shellcheck disable=SC2034
PROJECT_NAME="AutoSignDisplay"
SCHEME_NAME="AutoSignDisplay"
BUNDLE_ID="edu.princeton.autosigndisplay"
# The App Store Connect record this repo publishes to. Uploads associate by bundle
# id; this is here for altool's --apple-id and for error messages that name the
# record a human can go look at.
ASC_APPLE_ID="6757710459"
# tvOS. altool spells this "appletvos", not "tvos" — the latter is silently wrong.
ASC_PLATFORM="appletvos"

# shellcheck disable=SC2034  # consumed by sourcing scripts
LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$LIB_DIR/../.." && pwd)"
cd "$REPO_ROOT" || exit 1

# shellcheck disable=SC2034
XCODEPROJ="$REPO_ROOT/$PROJECT_NAME.xcodeproj"
RELEASE_DIR="$REPO_ROOT/build/release"
# Credentials and local overrides. Gitignored — see scripts/appstore.env.example.
ENV_FILE="$REPO_ROOT/scripts/appstore.env"
# Where altool discovers App Store Connect API keys. Not configurable: altool
# searches this path (and ./private_keys, ~/private_keys) and nowhere else.
ASC_KEY_DIR="$HOME/.appstoreconnect/private_keys"

DRY_RUN=0

# ---------- output ----------

log()  { echo "[asc] $*"; }
warn() { echo "[asc] warning: $*" >&2; }
die()  { echo "[asc] error: $*" >&2; exit 1; }

# Section heading, so a long bootstrap run stays readable.
section() { echo; echo "=== $* ==="; }

# Runs a command, or prints it under --dry-run. Use for anything with side effects.
#
# Named run_cmd, not run: bats defines its own `run` helper, and a lib function of
# that name shadows it inside tests — which silently turns every assertion on a
# script's exit status into a no-op.
run_cmd() {
  if [[ "$DRY_RUN" -eq 1 ]]; then
    echo "DRY: $*"
    return 0
  fi
  "$@"
}

require_cmd() {
  command -v "$1" >/dev/null 2>&1 || die "$1 not found on PATH."
}

# ---------- local configuration ----------

# Sources scripts/appstore.env when present. Everything it sets is also settable
# as a plain environment variable, so CI can supply the same values later without
# a file on disk.
load_release_config() {
  if [[ -f "$ENV_FILE" ]]; then
    log "reading local config from scripts/appstore.env"
    # shellcheck disable=SC1090  # path is a computed constant, not user input
    source "$ENV_FILE"
  fi
}

# ---------- teams and signing identities ----------

# The team the project is configured to build for. Read from the project rather
# than hardcoded, so changing it in Xcode changes it here too.
project_team_id() {
  xcodebuild -project "$XCODEPROJ" -target "$PROJECT_NAME" \
    -configuration Release -showBuildSettings 2>/dev/null \
    | awk -F' = ' '/^[[:space:]]+DEVELOPMENT_TEAM = /{print $2; exit}'
}

# Parses `security find-identity -v -p codesigning` on stdin into lines of
#   <team-id>\t<certificate-type>\t<organisation>
# Example input line:
#   1) ABC123 "Apple Distribution: Princeton University (Y3TW367T4G)"
# Split out from the `security` call so it is testable against fixtures.
parse_signing_identities() {
  sed -n 's/^[[:space:]]*[0-9][0-9]*)[[:space:]]*[0-9A-F]*[[:space:]]*"\(.*\)"[[:space:]]*$/\1/p' \
    | while IFS= read -r subject; do
        # "Apple Distribution: Princeton University (Y3TW367T4G)"
        local type org team
        type="${subject%%: *}"
        org="${subject#*: }"
        # Trailing "(TEAMID)" — the team is the last parenthesised group.
        team="${org##*(}"
        team="${team%)}"
        org="${org% (*}"
        [[ "$team" == "$subject" ]] && continue   # no parenthesised team; skip
        printf '%s\t%s\t%s\n' "$team" "$type" "$org"
      done
}

installed_identities() {
  security find-identity -v -p codesigning 2>/dev/null | parse_signing_identities
}

# Every distinct team id that has a signing identity installed, with its name.
list_signing_teams() {
  installed_identities | awk -F'\t' '{print $1"\t"$3}' | sort -u
}

# True when the team has an "Apple Distribution" identity — the one App Store
# submission requires. An "Apple Development" cert for the same team is not enough.
team_has_distribution_identity() {
  local team="$1"
  installed_identities | awk -F'\t' -v t="$team" \
    '$1 == t && $2 == "Apple Distribution" { found = 1 } END { exit !found }'
}

# Organisation name for a team id, or empty when no identity is installed for it.
# This is the only local source of a team's *name*: Xcode's account list is not
# exposed to the CLI, but a downloaded certificate carries the organisation.
team_display_name() {
  local team="$1"
  installed_identities | awk -F'\t' -v t="$team" '$1 == t { print $3; exit }'
}

# Picks a team id by organisation name from parse_signing_identities-format lines on
# stdin. Prints the id, or prints nothing and returns non-zero when the name does not
# resolve to exactly one team.
#
# Preferring distribution-capable teams is the whole point. One person can belong to
# several teams sharing a display name — three "Michael Bino" teams here — and only
# some will have an Apple Distribution certificate. Taking the first sorted match
# picked a development-only team and produced a signing error that named a team the
# user never asked for.
match_team_by_name() {
  local want="$1" identities candidates distribution
  identities="$(cat)"

  # tolower() on both sides rather than awk's IGNORECASE, which is a GNU extension
  # that macOS's awk accepts and silently ignores.
  candidates="$(printf '%s\n' "$identities" | awk -F'\t' -v want="$want" \
    'tolower($3) ~ tolower(want) { print $1 }' | sort -u)"
  [[ -n "$candidates" ]] || return 1

  distribution="$(printf '%s\n' "$identities" | awk -F'\t' -v want="$want" \
    'tolower($3) ~ tolower(want) && $2 == "Apple Distribution" { print $1 }' | sort -u)"

  # A team that can sign for distribution is unambiguously the one meant.
  if [[ "$(printf '%s\n' "$distribution" | grep -c .)" -eq 1 ]]; then
    printf '%s' "$distribution"
    return 0
  fi

  # Otherwise only a single overall match is safe to assume.
  if [[ "$(printf '%s\n' "$candidates" | grep -c .)" -eq 1 ]]; then
    printf '%s' "$candidates"
    return 0
  fi
  return 1
}

# Resolves a --team argument to a team id.
#   (empty) | project        -> whatever the project is configured for
#   <10-char id>             -> used as-is
# Anything else is matched, case-insensitively, against the organisation names of
# installed identities, so `--team princeton` works once a cert exists.
resolve_team() {
  local requested="${1:-}"

  if [[ -z "$requested" || "$requested" == "project" ]]; then
    local team
    team="$(project_team_id)"
    [[ -n "$team" ]] || die "could not read DEVELOPMENT_TEAM from the project."
    printf '%s' "$team"
    return
  fi

  if [[ "$requested" =~ ^[A-Z0-9]{10}$ ]]; then
    printf '%s' "$requested"
    return
  fi

  local match
  if match="$(installed_identities | match_team_by_name "$requested")" \
     && [[ -n "$match" ]]; then
    printf '%s' "$match"
    return
  fi

  {
    echo "[asc] error: team '$requested' does not resolve to exactly one signing team."
    echo "       Teams with certificates installed:"
    installed_identities \
      | awk -F'\t' '{ printf "         %s  %-20s %s\n", $1, $3, $2 }' \
      | sort -u
    echo "       Names are not unique — several teams can share one. Pass the"
    echo "       10-character team id, or --team project to use the project's."
  } >&2
  exit 1
}

# ---------- version and build number ----------

# Marketing version from the project, e.g. 1.0. Must match the version of the App
# Store Connect record the build is going to.
project_marketing_version() {
  xcodebuild -project "$XCODEPROJ" -target "$PROJECT_NAME" \
    -configuration Release -showBuildSettings 2>/dev/null \
    | awk -F' = ' '/^[[:space:]]+MARKETING_VERSION = /{print $2; exit}'
}

# Default build number: the commit count. Monotonic, reproducible from a checkout,
# and needs no state outside git — which matters because App Store Connect rejects
# a build number it has already seen for the same version.
default_build_number() {
  git -C "$REPO_ROOT" rev-list --count HEAD 2>/dev/null || echo "1"
}

# App Store Connect wants two or three dot-separated integers.
validate_version_string() {
  local version="$1"
  [[ "$version" =~ ^[0-9]+\.[0-9]+(\.[0-9]+)?$ ]] \
    || die "version '$version' is not of the form X.Y or X.Y.Z."
}

validate_build_number() {
  local build="$1"
  [[ "$build" =~ ^[0-9]+$ ]] || die "build '$build' is not a positive integer."
}

# ---------- App Store Connect credentials ----------

# Which credentials are available, as one of: api-key, keychain, none.
#
# API key is preferred: it is not tied to a personal Apple ID, survives the holder
# leaving the team, and needs no 2FA. The keychain path exists because an App
# Manager can always mint an app-specific password, whereas team API keys need
# Admin — see docs/RELEASING.md.
asc_credential_mode() {
  if [[ -n "${ASC_KEY_ID:-}" && -n "${ASC_ISSUER_ID:-}" ]] \
     && [[ -f "$ASC_KEY_DIR/AuthKey_${ASC_KEY_ID}.p8" ]]; then
    echo "api-key"
  elif [[ -n "${ASC_KEYCHAIN_ITEM:-}" && -n "${ASC_USERNAME:-}" ]]; then
    echo "keychain"
  else
    echo "none"
  fi
}

# Emits the altool authentication arguments for the available credentials.
asc_auth_args() {
  case "$(asc_credential_mode)" in
    api-key)
      printf '%s\n%s\n%s\n%s\n' --apiKey "$ASC_KEY_ID" --apiIssuer "$ASC_ISSUER_ID"
      ;;
    keychain)
      printf '%s\n%s\n%s\n%s\n' \
        --username "$ASC_USERNAME" --password "@keychain:$ASC_KEYCHAIN_ITEM"
      ;;
    *)
      die "no App Store Connect credentials configured. Run scripts/appstore-bootstrap.sh."
      ;;
  esac
}

# ---------- export options ----------

# Writes an ExportOptions.plist for an App Store Connect export.
#
# `method` is app-store-connect; the older `app-store` is deprecated in Xcode 26.
# `destination` stays `export` so the .ipa lands on disk and can be validated
# before anything is sent — uploading straight from the export step would skip
# that and give worse errors.
# `manageAppVersionAndBuildNumber` must be false or Xcode overrides the version and
# build this script deliberately pinned.
write_export_options() {
  local path="$1" team="$2"
  cat > "$path" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN"
 "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
  <dict>
    <key>method</key>
    <string>app-store-connect</string>
    <key>destination</key>
    <string>export</string>
    <key>teamID</key>
    <string>$team</string>
    <key>uploadSymbols</key>
    <true/>
    <key>manageAppVersionAndBuildNumber</key>
    <false/>
  </dict>
</plist>
PLIST
}
