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

# Real subject lines from this machine, which are the shape that matters: the two
# Apple Development certificates carry per-user identifiers in their CN
# (3WM5YE6V3K, KGRKWJN727) while their OU names the actual team. The last one is a
# Princeton identity that looks personal if you read the CN.
fixture_identities() {
  cat <<'EOF'
subject=UID=6S2N758UJ6, CN=Apple Distribution: Michael Bino (W7EJE9LZ23), OU=W7EJE9LZ23, O=Michael Bino, C=US
subject=UID=6S2N758UJ6, CN=Developer ID Application: Michael Bino (W7EJE9LZ23), OU=W7EJE9LZ23, O=Michael Bino, C=US
subject=UID=6S2N758UJ6, CN=Apple Development: Michael Bino (3WM5YE6V3K), OU=W7EJE9LZ23, O=Michael Bino, C=US
subject=UID=6S2N758UJ6, CN=Apple Development: Michael Bino (KGRKWJN727), OU=Y3TW367T4G, O=Princeton University, C=US
EOF
}

# ---------- identity parsing ----------

@test "the team id comes from OU, not the parenthesised value in the CN" {
  # This is the bug: reading the CN reported teams 3WM5YE6V3K and KGRKWJN727, which
  # are per-user identifiers and not teams at all, and reported the Princeton
  # certificate as belonging to "Michael Bino".
  run bash -c "$(declare -f fixture_identities parse_identity_subjects); fixture_identities | parse_identity_subjects"
  [ "$status" -eq 0 ]
  [[ "$output" == *"Y3TW367T4G	Apple Development	Princeton University"* ]]
  [[ "$output" != *"KGRKWJN727	"* ]]
  [[ "$output" != *"3WM5YE6V3K	"* ]]
}

@test "an organisation containing a comma survives field splitting" {
  run bash -c "$(declare -f parse_identity_subjects); printf 'subject=CN=Apple Distribution: X (AAAAAAAAAA), OU=AAAAAAAAAA, O=Princeton University, Inc., C=US\n' | parse_identity_subjects"
  [ "$status" -eq 0 ]
  [[ "$output" == *"Princeton University, Inc."* ]]
}

@test "parses team, type and organisation from security output" {
  run bash -c "$(declare -f fixture_identities parse_identity_subjects); fixture_identities | parse_identity_subjects"
  [ "$status" -eq 0 ]
  [[ "$output" == *"W7EJE9LZ23	Apple Distribution	Michael Bino"* ]]
  [[ "$output" == *"W7EJE9LZ23	Developer ID Application	Michael Bino"* ]]
  [[ "$output" == *"Y3TW367T4G	Apple Development	Princeton University"* ]]
}

@test "ignores blank and malformed lines" {
  run bash -c "$(declare -f parse_identity_subjects); printf '\n     \nnot a subject at all\n' | parse_identity_subjects"
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "handles an organisation name containing spaces" {
  run bash -c "$(declare -f fixture_identities parse_identity_subjects); fixture_identities | parse_identity_subjects"
  [[ "$output" == *"Princeton University"* ]]
}

@test "produces no output when no identities are installed" {
  run bash -c "$(declare -f parse_identity_subjects); printf '' | parse_identity_subjects"
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
  run bash -c "$(declare -f fixture_identities parse_identity_subjects match_team_by_name); \
    fixture_identities | parse_identity_subjects | match_team_by_name 'michael bino'"
  [ "$status" -eq 0 ]
  [ "$output" = "W7EJE9LZ23" ]
}

@test "an ambiguous name with several distribution teams is refused, not guessed" {
  ambiguous() {
    cat <<'EOF'
subject=CN=Apple Distribution: A (AAAAAAAAAA), OU=AAAAAAAAAA, O=Princeton University, C=US
subject=CN=Apple Distribution: B (BBBBBBBBBB), OU=BBBBBBBBBB, O=Princeton University Press, C=US
EOF
  }
  run bash -c "$(declare -f ambiguous parse_identity_subjects match_team_by_name); \
    ambiguous | parse_identity_subjects | match_team_by_name 'princeton'"
  [ "$status" -ne 0 ]
  [ -z "$output" ]
}

@test "a name matching one development-only team still resolves" {
  # No distribution cert, but unambiguous — let it through so the caller can raise
  # the specific 'no distribution identity' error instead of a confusing name error.
  run bash -c "$(declare -f parse_identity_subjects match_team_by_name); \
    printf 'subject=CN=Apple Development: X (ZZZZZZZZZZ), OU=CCCCCCCCCC, O=Solo Team, C=US\n' \
    | parse_identity_subjects | match_team_by_name 'solo'"
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

# ---------- importing a signing identity ----------

# Note on coverage: the import itself is not exercised end to end. macOS will not
# treat a self-signed certificate as a *valid* code-signing identity, so a synthetic
# .p12 never registers and there is nothing to assert against. What is testable is
# the reporting logic that decides whether an import actually produced something
# signable, plus the argument handling — so those are separated out and covered here.

@test "identities_gained reports only what the import added" {
  before="$(printf 'W7EJE9LZ23\tApple Distribution\tMichael Bino')"
  after="$(printf 'W7EJE9LZ23\tApple Distribution\tMichael Bino\nY3TW367T4G\tApple Distribution\tPrinceton University')"
  run identities_gained "$before" "$after"
  [ "$status" -eq 0 ]
  [ "$output" = "$(printf 'Y3TW367T4G\tApple Distribution\tPrinceton University')" ]
}

@test "identities_gained reports nothing for a certificate-only p12" {
  # The failure that matters: a .p12 with no private key imports cleanly and adds no
  # signable identity. Silence here is what triggers the warning.
  same="$(printf 'W7EJE9LZ23\tApple Distribution\tMichael Bino')"
  run identities_gained "$same" "$same"
  [ -z "$output" ]
}

@test "identities_gained copes with an empty starting keychain" {
  run identities_gained "" "$(printf 'Y3TW367T4G\tApple Distribution\tPrinceton University')"
  [[ "$output" == *"Princeton University"* ]]
}

@test "--import-p12 rejects a missing file before touching the keychain" {
  run "$REPO_ROOT/scripts/appstore-bootstrap.sh" --import-p12 /definitely/not/here.p12
  [ "$status" -ne 0 ]
  [[ "$output" == *"no such file"* ]]
}

@test "--import-p12 requires a path" {
  run "$REPO_ROOT/scripts/appstore-bootstrap.sh" --import-p12
  [ "$status" -ne 0 ]
}

@test "the import never passes the passphrase on the command line" {
  # -P would put the .p12 passphrase in the process list, readable by any local
  # user. security itself warns against it; omitting it prompts securely instead.
  run "$REPO_ROOT/scripts/appstore-bootstrap.sh" --import-p12 "$REPO_ROOT/README.md" --dry-run
  [[ "$output" == *"DRY: security import"* ]]
  [[ "$output" != *" -P "* ]]
  # -A would let any process on the machine sign; only codesign and security should.
  [[ "$output" != *" -A"* ]]
  [[ "$output" == *"-T /usr/bin/codesign"* ]]
}

@test "the keychain target is overridable for CI" {
  ASD_KEYCHAIN="/tmp/asd-test.keychain"
  export ASD_KEYCHAIN
  run default_keychain
  [ "$output" = "/tmp/asd-test.keychain" ]
  unset ASD_KEYCHAIN
  run default_keychain
  [[ "$output" == *"login.keychain-db"* ]]
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
