#!/usr/bin/env bats
# Tests for the App Store release scripts.
#
#   bats scripts/tests/appstore.bats
#
# These exercise the parsing and argument handling, plus the --dry-run plan, and
# never touch the network, the keychain, or App Store Connect. The functions that
# read tool output take stdin precisely so they can be driven from fixtures here —
# `security find-identity` output cannot otherwise be reproduced on a machine that
# lacks the certificates.

setup() {
  REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
  export REPO_ROOT
  # shellcheck source=../lib/appstore.sh
  source "$REPO_ROOT/scripts/lib/appstore.sh"
}

# Two teams with a distribution cert each, plus development-only certs, which is
# the shape of a machine signed in to both a personal and an organisation team.
fixture_identities() {
  cat <<'EOF'
  1) 273475FF24FE9BDE37878FB68EE312B49156F907 "Apple Distribution: Michael Bino (W7EJE9LZ23)"
  2) DA60E7B212999B7B7E206C24A5FAD397FE2DF0E4 "Developer ID Application: Michael Bino (W7EJE9LZ23)"
  3) 87222E3565DF4F62E6B74476BDCF080903B96B23 "Apple Development: Michael Bino (3WM5YE6V3K)"
  4) 1111111111111111111111111111111111111111 "Apple Distribution: Princeton University (Y3TW367T4G)"
     4 valid identities found
EOF
}

# ---------- identity parsing ----------

@test "parses team, type and organisation from security output" {
  run bash -c "$(declare -f fixture_identities parse_signing_identities); fixture_identities | parse_signing_identities"
  [ "$status" -eq 0 ]
  [[ "$output" == *"W7EJE9LZ23	Apple Distribution	Michael Bino"* ]]
  [[ "$output" == *"Y3TW367T4G	Apple Distribution	Princeton University"* ]]
  [[ "$output" == *"3WM5YE6V3K	Apple Development	Michael Bino"* ]]
}

@test "ignores the trailing identity count line" {
  run bash -c "$(declare -f fixture_identities parse_signing_identities); fixture_identities | parse_signing_identities"
  [[ "$output" != *"valid identities found"* ]]
}

@test "handles an organisation name containing spaces" {
  run bash -c "$(declare -f fixture_identities parse_signing_identities); fixture_identities | parse_signing_identities"
  [[ "$output" == *"Princeton University"* ]]
}

@test "produces no output when no identities are installed" {
  run bash -c "$(declare -f parse_signing_identities); printf '     0 valid identities found\n' | parse_signing_identities"
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

# ---------- version and build validation ----------

@test "accepts two- and three-component versions" {
  run validate_version_string "1.0"
  [ "$status" -eq 0 ]
  run validate_version_string "1.2.3"
  [ "$status" -eq 0 ]
}

@test "rejects a version App Store Connect would not accept" {
  for bad in "1" "1.0.0.0" "v1.0" "1.0-beta" ""; do
    run validate_version_string "$bad"
    [ "$status" -ne 0 ]
  done
}

@test "rejects a non-numeric build number" {
  run validate_build_number "42"
  [ "$status" -eq 0 ]
  for bad in "1.0" "abc" "-1" ""; do
    run validate_build_number "$bad"
    [ "$status" -ne 0 ]
  done
}

@test "default build number is the commit count, so it always increases" {
  run default_build_number
  [ "$status" -eq 0 ]
  [[ "$output" =~ ^[0-9]+$ ]]
  [ "$output" -gt 0 ]
}

# ---------- credential resolution ----------

@test "reports no credentials when nothing is configured" {
  unset ASC_KEY_ID ASC_ISSUER_ID ASC_USERNAME ASC_KEYCHAIN_ITEM
  run asc_credential_mode
  [ "$output" = "none" ]
}

@test "an API key without its private key on disk does not count as configured" {
  export ASC_KEY_ID="NOSUCHKEY1" ASC_ISSUER_ID="00000000-0000-0000-0000-000000000000"
  unset ASC_USERNAME ASC_KEYCHAIN_ITEM
  run asc_credential_mode
  # The .p8 is what altool actually needs; having the ids alone would fail at upload.
  [ "$output" = "none" ]
}

@test "falls back to keychain credentials when both are set" {
  unset ASC_KEY_ID ASC_ISSUER_ID
  export ASC_USERNAME="you@princeton.edu" ASC_KEYCHAIN_ITEM="AutoSignDisplay-ASC"
  run asc_credential_mode
  [ "$output" = "keychain" ]
}

@test "keychain auth args reference the keychain, never a literal password" {
  unset ASC_KEY_ID ASC_ISSUER_ID
  export ASC_USERNAME="you@princeton.edu" ASC_KEYCHAIN_ITEM="AutoSignDisplay-ASC"
  run asc_auth_args
  [[ "$output" == *"@keychain:AutoSignDisplay-ASC"* ]]
  [[ "$output" == *"--username"* ]]
}

@test "asking for auth args with no credentials fails loudly" {
  unset ASC_KEY_ID ASC_ISSUER_ID ASC_USERNAME ASC_KEYCHAIN_ITEM
  run asc_auth_args
  [ "$status" -ne 0 ]
  [[ "$output" == *"bootstrap"* ]]
}

# ---------- export options ----------

@test "export options request App Store Connect and pin our version numbers" {
  local plist="$BATS_TEST_TMPDIR/ExportOptions.plist"
  write_export_options "$plist" "Y3TW367T4G"

  run /usr/libexec/PlistBuddy -c "Print :method" "$plist"
  [ "$output" = "app-store-connect" ]

  run /usr/libexec/PlistBuddy -c "Print :teamID" "$plist"
  [ "$output" = "Y3TW367T4G" ]

  # If Xcode manages these, it overrides the version and build the script pinned.
  run /usr/libexec/PlistBuddy -c "Print :manageAppVersionAndBuildNumber" "$plist"
  [ "$output" = "false" ]

  # Export to disk so the .ipa can be validated before anything is submitted.
  run /usr/libexec/PlistBuddy -c "Print :destination" "$plist"
  [ "$output" = "export" ]
}

@test "export options are valid plist" {
  local plist="$BATS_TEST_TMPDIR/ExportOptions.plist"
  write_export_options "$plist" "Y3TW367T4G"
  run plutil -lint "$plist"
  [ "$status" -eq 0 ]
}

# ---------- team resolution ----------

@test "an explicit ten-character team id is used verbatim" {
  run resolve_team "Y3TW367T4G"
  [ "$output" = "Y3TW367T4G" ]
}

@test "a name shared by several teams picks the distribution-capable one" {
  # Three teams are called "Michael Bino" in the fixture; only W7EJE9LZ23 can sign
  # for distribution. Taking the first sorted match would pick 3WM5YE6V3K and fail
  # later with a signing error naming a team nobody asked for.
  run bash -c "$(declare -f fixture_identities parse_signing_identities match_team_by_name); \
    fixture_identities | parse_signing_identities | match_team_by_name 'michael bino'"
  [ "$status" -eq 0 ]
  [ "$output" = "W7EJE9LZ23" ]
}

@test "an ambiguous name with several distribution teams is refused, not guessed" {
  ambiguous() {
    cat <<'EOF'
  1) AAAA "Apple Distribution: Princeton University (AAAAAAAAAA)"
  2) BBBB "Apple Distribution: Princeton University Press (BBBBBBBBBB)"
EOF
  }
  run bash -c "$(declare -f ambiguous parse_signing_identities match_team_by_name); \
    ambiguous | parse_signing_identities | match_team_by_name 'princeton'"
  [ "$status" -ne 0 ]
  [ -z "$output" ]
}

@test "a name matching one development-only team still resolves" {
  # No distribution cert, but unambiguous — let it through so the caller can raise
  # the specific 'no distribution identity' error instead of a confusing name error.
  run bash -c "$(declare -f parse_signing_identities match_team_by_name); \
    printf '  1) AA \"Apple Development: Solo Team (CCCCCCCCCC)\"\n' \
    | parse_signing_identities | match_team_by_name 'solo'"
  [ "$status" -eq 0 ]
  [ "$output" = "CCCCCCCCCC" ]
}

@test "an unknown team name fails and lists what is available" {
  run resolve_team "Definitely Not A Team"
  [ "$status" -ne 0 ]
  [[ "$output" == *"does not resolve to exactly one signing team"* ]]
}

@test "empty or 'project' resolves to the project's configured team" {
  run resolve_team ""
  [ "$status" -eq 0 ]
  [[ "$output" =~ ^[A-Z0-9]{10}$ ]]
  local from_empty="$output"
  run resolve_team "project"
  [ "$output" = "$from_empty" ]
}

@test "the project's team matches what the project file declares" {
  run project_team_id
  [ "$status" -eq 0 ]
  [[ "$output" =~ ^[A-Z0-9]{10}$ ]]
  grep -q "DEVELOPMENT_TEAM = $output;" "$REPO_ROOT/AutoSignDisplay.xcodeproj/project.pbxproj"
}

# ---------- platform constant ----------

@test "the upload platform is appletvos" {
  # altool accepts "tvos" as a word but means something else by it; the tvOS value
  # is "appletvos" and getting it wrong fails only at upload time.
  [ "$ASC_PLATFORM" = "appletvos" ]
}

# ---------- scripts as a whole ----------

@test "both scripts are executable and offer --help" {
  for s in appstore-bootstrap.sh release.sh; do
    [ -x "$REPO_ROOT/scripts/$s" ]
    run "$REPO_ROOT/scripts/$s" --help
    [ "$status" -eq 0 ]
    [[ -n "$output" ]]
  done
}

@test "both scripts reject an unknown option instead of ignoring it" {
  for s in appstore-bootstrap.sh release.sh; do
    run "$REPO_ROOT/scripts/$s" --not-a-real-flag
    [ "$status" -ne 0 ]
    [[ "$output" == *"unknown option"* ]]
  done
}

@test "release --dry-run prints a plan and runs no build" {
  run "$REPO_ROOT/scripts/release.sh" --dry-run --team Y3TW367T4G --version 1.0 --build 7
  # Fails before planning if no distribution identity exists for the team, which is
  # itself the correct behaviour — assert on whichever of the two happened.
  if [ "$status" -eq 0 ]; then
    [[ "$output" == *"DRY: xcodebuild archive"* ]]
    [[ "$output" == *"1.0"* ]]
    [[ "$output" == *"CURRENT_PROJECT_VERSION=7"* ]]
  else
    [[ "$output" == *"no Apple Distribution identity"* ]]
  fi
}

@test "release refuses a malformed version before doing any work" {
  run "$REPO_ROOT/scripts/release.sh" --dry-run --version "v1.0"
  [ "$status" -ne 0 ]
  [[ "$output" == *"not of the form"* ]]
}

@test "bootstrap --list-teams succeeds and names the project team" {
  run "$REPO_ROOT/scripts/appstore-bootstrap.sh" --list-teams
  [ "$status" -eq 0 ]
  [[ "$output" == *"The project builds for team:"* ]]
}
