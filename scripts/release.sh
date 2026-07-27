#!/usr/bin/env bash
# Archive, export, validate and upload an AutoSignDisplay build to App Store Connect.
#
#   ./scripts/release.sh --validate-only          # build + check against ASC, submit nothing
#   ./scripts/release.sh                          # build + upload
#   ./scripts/release.sh --version 1.0 --build 42 # pin both explicitly
#   ./scripts/release.sh --skip-upload            # just produce the .ipa
#   ./scripts/release.sh --dry-run                # print the commands only
#
# The version and build number are passed to xcodebuild rather than written into
# project.pbxproj, so a release never dirties the working tree and the same command
# is reproducible from CI later.
#
# This uploads a build. It does not submit for review: once the build finishes
# processing, select it on the App Store Connect version page and submit there.
# See docs/RELEASING.md.

set -euo pipefail

# shellcheck source=scripts/lib/appstore.sh
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib/appstore.sh"

TEAM_ARG=""
VERSION=""
BUILD=""
VALIDATE_ONLY=0
SKIP_UPLOAD=0
KEEP_ARCHIVE=0

usage() {
  cat <<'USAGE'
release.sh — archive, export, validate and upload a build to App Store Connect.

  ./scripts/release.sh --validate-only    Build and run App Store Connect's checks,
                                          submit nothing. Start here.
  ./scripts/release.sh                    Build and upload.
  ./scripts/release.sh --skip-upload      Produce an .ipa only.

Options:
  --version <X.Y[.Z]>   Marketing version. Defaults to the project's MARKETING_VERSION.
                        Must match the App Store Connect version record.
  --build <n>           Build number. Defaults to the commit count, which is monotonic.
                        Must be one App Store Connect has not seen for this version.
  --team <name|id>      Signing team. Defaults to the project's DEVELOPMENT_TEAM.
  --keep-archive        Keep the .xcarchive after a successful upload.
  --dry-run             Print the commands without running them.
  -h, --help            This text.

Version and build are passed to xcodebuild, never written into project.pbxproj, so a
release leaves the working tree clean.

This uploads a build; it does not submit for review. Once the build finishes
processing, select it on the App Store Connect version page and submit there.
USAGE
  exit 0
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --team)          TEAM_ARG="${2:?--team needs a value}"; shift 2 ;;
    --version)       VERSION="${2:?--version needs a value}"; shift 2 ;;
    --build)         BUILD="${2:?--build needs a value}"; shift 2 ;;
    --validate-only) VALIDATE_ONLY=1; shift ;;
    --skip-upload)   SKIP_UPLOAD=1; shift ;;
    --keep-archive)  KEEP_ARCHIVE=1; shift ;;
    --dry-run)       DRY_RUN=1; shift ;;
    -h|--help)       usage ;;
    *)               die "unknown option: $1 (try --help)" ;;
  esac
done

load_release_config
require_cmd xcodebuild
require_cmd git

# ---------- resolve inputs ----------

TEAM="$(resolve_team "$TEAM_ARG")"
[[ -n "$VERSION" ]] || VERSION="$(project_marketing_version)"
[[ -n "$BUILD" ]]   || BUILD="$(default_build_number)"
validate_version_string "$VERSION"
validate_build_number "$BUILD"

# Signing is the failure that costs the most time to discover late: it surfaces at
# the end of a full Release archive. Check it before building anything.
if ! team_has_distribution_identity "$TEAM"; then
  die "no Apple Distribution identity for team $TEAM. Run scripts/appstore-bootstrap.sh."
fi

# Likewise credentials: needed only at the upload step, but worth failing on now
# rather than after a ten-minute archive.
if [[ "$SKIP_UPLOAD" -eq 0 ]]; then
  [[ "$(asc_credential_mode)" != "none" ]] \
    || die "no App Store Connect credentials. Run scripts/appstore-bootstrap.sh."
fi

# A release built from uncommitted work cannot be reproduced from the tag later.
# Warn rather than block: --validate-only and --skip-upload are legitimate on a
# dirty tree while iterating.
if [[ -n "$(git -C "$REPO_ROOT" status --porcelain --untracked-files=no)" ]]; then
  if [[ "$VALIDATE_ONLY" -eq 1 || "$SKIP_UPLOAD" -eq 1 || "$DRY_RUN" -eq 1 ]]; then
    warn "working tree has uncommitted changes."
  else
    warn "working tree has uncommitted changes — this build will not be reproducible"
    warn "from git. Commit first, or accept that build $BUILD maps to no commit."
  fi
fi

OUT_DIR="$RELEASE_DIR/$VERSION-$BUILD"
ARCHIVE="$OUT_DIR/$PROJECT_NAME.xcarchive"
EXPORT_DIR="$OUT_DIR/export"
EXPORT_OPTIONS="$OUT_DIR/ExportOptions.plist"
IPA="$EXPORT_DIR/$PROJECT_NAME.ipa"

team_name="$(team_display_name "$TEAM")"
section "Release plan"
echo "  app          $PROJECT_NAME ($BUNDLE_ID)"
echo "  record       App Store Connect Apple ID $ASC_APPLE_ID"
echo "  team         $TEAM${team_name:+ ($team_name)}"
echo "  version      $VERSION"
echo "  build        $BUILD"
echo "  commit       $(git -C "$REPO_ROOT" rev-parse --short HEAD 2>/dev/null || echo unknown)"
echo "  credentials  $(asc_credential_mode)"
echo "  output       ${OUT_DIR#"$REPO_ROOT"/}"
if [[ "$VALIDATE_ONLY" -eq 1 ]]; then
  echo "  action       validate against App Store Connect, upload nothing"
elif [[ "$SKIP_UPLOAD" -eq 1 ]]; then
  echo "  action       export an .ipa only"
else
  echo "  action       upload to App Store Connect"
fi

# ---------- archive ----------

section "Archiving"
run_cmd mkdir -p "$OUT_DIR"
run_cmd rm -rf "$ARCHIVE"

# -allowProvisioningUpdates lets Xcode fetch or renew the distribution profile using
# the account already signed in, which is what makes this work without checking a
# .mobileprovision into the repo.
run_cmd xcodebuild archive \
  -project "$XCODEPROJ" \
  -scheme "$SCHEME_NAME" \
  -configuration Release \
  -destination 'generic/platform=tvOS' \
  -archivePath "$ARCHIVE" \
  -allowProvisioningUpdates \
  DEVELOPMENT_TEAM="$TEAM" \
  MARKETING_VERSION="$VERSION" \
  CURRENT_PROJECT_VERSION="$BUILD"

# ---------- export ----------

section "Exporting"
run_cmd rm -rf "$EXPORT_DIR"
if [[ "$DRY_RUN" -eq 1 ]]; then
  echo "DRY: write $EXPORT_OPTIONS (method app-store-connect, team $TEAM)"
else
  write_export_options "$EXPORT_OPTIONS" "$TEAM"
fi

run_cmd xcodebuild -exportArchive \
  -archivePath "$ARCHIVE" \
  -exportPath "$EXPORT_DIR" \
  -exportOptionsPlist "$EXPORT_OPTIONS" \
  -allowProvisioningUpdates

if [[ "$DRY_RUN" -eq 0 ]]; then
  [[ -f "$IPA" ]] || die "export produced no .ipa at $IPA"
  log "exported $(du -h "$IPA" | cut -f1) → ${IPA#"$REPO_ROOT"/}"

  # Confirm the binary carries the version and build we asked for. Cheap, and it
  # catches manageAppVersionAndBuildNumber having been flipped back on.
  plist="$ARCHIVE/Products/Applications/$PROJECT_NAME.app/Info.plist"
  if [[ -f "$plist" ]]; then
    got_version="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$plist" 2>/dev/null || echo '?')"
    got_build="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$plist" 2>/dev/null || echo '?')"
    if [[ "$got_version" != "$VERSION" || "$got_build" != "$BUILD" ]]; then
      die "built bundle is $got_version ($got_build), expected $VERSION ($BUILD)."
    fi
    log "bundle reports $got_version ($got_build)"
  fi
fi

if [[ "$SKIP_UPLOAD" -eq 1 ]]; then
  section "Done"
  log "skipped upload. .ipa is at ${IPA#"$REPO_ROOT"/}"
  exit 0
fi

# ---------- validate ----------

# altool --validate-app runs App Store Connect's own acceptance checks without
# submitting, which catches version/record mismatches, missing icons and bad
# entitlements before a build is spent.
#
# Read into an array line by line rather than with mapfile: macOS ships bash 3.2,
# where mapfile does not exist.
AUTH_ARGS=()
while IFS= read -r auth_arg; do
  AUTH_ARGS+=("$auth_arg")
done < <(asc_auth_args)

section "Validating against App Store Connect"
run_cmd xcrun altool --validate-app \
  -f "$IPA" \
  -t "$ASC_PLATFORM" \
  --apple-id "$ASC_APPLE_ID" \
  "${AUTH_ARGS[@]}"

if [[ "$VALIDATE_ONLY" -eq 1 ]]; then
  section "Done"
  log "validation passed. Re-run without --validate-only to upload."
  exit 0
fi

# ---------- upload ----------

section "Uploading"
run_cmd xcrun altool --upload-app \
  -f "$IPA" \
  -t "$ASC_PLATFORM" \
  --apple-id "$ASC_APPLE_ID" \
  "${AUTH_ARGS[@]}"

if [[ "$KEEP_ARCHIVE" -eq 0 && "$DRY_RUN" -eq 0 ]]; then
  # The .xcarchive is large and the .ipa plus dSYMs are what matter afterwards.
  run_cmd rm -rf "$ARCHIVE"
fi

section "Done"
log "uploaded $VERSION ($BUILD)."
log "App Store Connect processes the build before it can be selected — usually"
log "minutes, occasionally an hour. You will get an email when it is ready."
log
log "This script does not submit for review. To finish:"
log "  1. https://appstoreconnect.apple.com > My Apps > $PROJECT_NAME"
log "  2. On the version page, Build > select $VERSION ($BUILD)"
log "  3. Add for Review / Submit"
