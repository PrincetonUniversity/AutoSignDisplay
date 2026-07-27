# Releasing AutoSignDisplay

Two scripts, both in `scripts/`:

| Script | Use |
|---|---|
| `appstore-bootstrap.sh` | Check prerequisites and install credentials. Run once, re-run any time — it changes nothing unless you ask it to. |
| `release.sh` | Archive, export, validate, upload. Run for every build. |

The App Store Connect record already exists (bundle id `edu.princeton.autosigndisplay`,
Apple ID `6757710459`). Uploads attach to it automatically by bundle id — there is no
"associate" step.

## What these scripts do and do not do

They get a **validated build into the App Store Connect record**. They do **not**
submit for review.

That boundary is deliberate. Submitting for review means writing to the version
record — release notes, screenshots, export compliance, the review submission itself
— and you have already filled that in through the web forms. Uploading a build is
idempotent and safe to retry; submitting for review is neither. So the last two
clicks stay manual:

1. <https://appstoreconnect.apple.com> → My Apps → AutoSignDisplay
2. On the version page, **Build** → select the build you just uploaded
3. **Add for Review** / **Submit**

If you later want that automated too, it is App Store Connect API calls against
`appStoreVersions` and `appStoreVersionSubmissions`, and it belongs behind an explicit
flag.

## First run

```bash
./scripts/appstore-bootstrap.sh
```

It prints an `ok` / `FAIL` line per prerequisite with remediation for each failure.
Expect two failures on a fresh machine — a missing distribution certificate and
missing credentials. Both are covered below.

### Distribution certificate

App Store submission needs an **Apple Distribution** certificate for the signing
team. An *Apple Development* certificate for the same team is not enough, which is a
common way to lose an hour: the archive succeeds and the export fails at the end.

To see what you have:

```bash
./scripts/appstore-bootstrap.sh --list-teams
```

**A certificate someone else created is not usable here.** Xcode's Manage
Certificates list shows every distribution certificate on the team, including ones
created by colleagues, marked **Not in Keychain**. Those cannot sign on this machine:
the private key stays on the Mac that generated it, and a certificate without its
private key is inert. Only an entry that is *in* your keychain counts, which is
exactly what `--list-teams` reports.

Two ways to get one:

- **Xcode** → Settings → Accounts → select the team → Manage Certificates → **+** →
  Apple Distribution. This creates a new certificate with its private key locally.
- **`./scripts/appstore-bootstrap.sh --provision`**, which archives once with
  `-allowProvisioningUpdates` and lets Xcode create the certificate and profile.

Prefer the Xcode route on a shared team, and check the existing list first. Apple caps
the number of active distribution certificates per team; if the team is already at the
cap, creating another means revoking someone else's, which breaks whatever they sign
with it. Coordinate before revoking anything. The alternative is asking a colleague to
export their certificate and private key as a `.p12` and importing that instead.

A note on team names: Xcode's account list is not exposed to any command-line tool,
so these scripts can only learn a team's *name* from an installed certificate. Until
one exists, `--list-teams` shows the team id and nothing else.

### Credentials

**Preferred — App Store Connect API key.** Not tied to a personal Apple ID, survives
the holder leaving the team, no 2FA prompts, and revocable on its own.

App Store Connect → Integrations → App Store Connect API. An **App Manager** can
create an *Individual Key*; *Team Keys* require Admin. Either works. Download the
`.p8` — Apple lets you download it exactly once.

```bash
./scripts/appstore-bootstrap.sh \
    --api-key ~/Downloads/AuthKey_ABCD123456.p8 \
    --key-id ABCD123456 \
    --issuer-id 00000000-0000-0000-0000-000000000000
```

This copies the key to `~/.appstoreconnect/private_keys/`, which is the only place
`altool` looks for it, and records the two non-secret ids in `scripts/appstore.env`.
That file is gitignored; the key never enters the repo.

**Fallback — Apple ID and app-specific password.** Works when you cannot get an API
key, but ties releases to one person's Apple ID.

```bash
./scripts/appstore-bootstrap.sh --store-password
```

The password goes into the login keychain. `release.sh` passes
`@keychain:AutoSignDisplay-ASC` to `altool` and never handles the secret itself.

## Version and build numbers

Both are passed to `xcodebuild` on the command line, never written into
`project.pbxproj`. A release therefore leaves the working tree clean and the same
command is reproducible later from CI.

- **Version** defaults to the project's `MARKETING_VERSION`. It **must match** the
  version of the App Store Connect record, or the upload is rejected. Override with
  `--version 1.0` without touching the project.
- **Build** defaults to `git rev-list --count HEAD` — the commit count. Monotonic,
  reproducible from a checkout, and needs no state outside git. App Store Connect
  rejects a build number it has already accepted for the same version, so this has to
  increase; a commit count does, a timestamp is noisier, and a hand-maintained
  counter drifts.

`release.sh` reads the built `Info.plist` back and fails if the version or build in
the binary is not what you asked for. That catches
`manageAppVersionAndBuildNumber` being turned back on in the export options, which
would otherwise silently let Xcode pick its own numbers.

## Releasing

Always start with a validation pass. It runs App Store Connect's own acceptance
checks — version/record mismatches, missing icons, bad entitlements — without
spending a build number:

```bash
./scripts/release.sh --validate-only
```

Then upload:

```bash
./scripts/release.sh
```

Useful variations:

```bash
./scripts/release.sh --dry-run                 # print every command, run none
./scripts/release.sh --skip-upload             # .ipa only, no network
./scripts/release.sh --version 1.0 --build 42  # pin both
./scripts/release.sh --team "Princeton"        # match a team by organisation name
./scripts/release.sh --keep-archive            # keep the .xcarchive
```

Output lands in `build/release/<version>-<build>/` — gitignored.

After a successful upload, App Store Connect processes the build before it can be
selected. Usually minutes; occasionally an hour. You get an email.

## Tests

The scripts have their own tests, which never touch the network, the keychain, or
App Store Connect:

```bash
bats scripts/tests/appstore.bats
shellcheck -x scripts/lib/appstore.sh scripts/appstore-bootstrap.sh scripts/release.sh
```

The functions that parse tool output take stdin specifically so they can be driven
from fixtures — `security find-identity` output cannot otherwise be reproduced on a
machine that lacks the certificates.

## CI/CD

Not wired up yet, deliberately. Two things to know when it is:

- **tvOS archiving cannot run in a container.** It needs macOS and a full Xcode, so
  this pipeline cannot follow the containerized-CI pattern the rest of the test suite
  uses. It needs a macOS runner, hosted or self-hosted.
- **The scripts are already CI-shaped.** Every value in `scripts/appstore.env` is
  also read from the environment, so a runner supplies the same configuration through
  secrets with no file on disk. What CI additionally needs is the signing certificate
  in its keychain — export the distribution cert and key as a `.p12`, store it as a
  secret, and import it into a temporary keychain per run rather than letting Xcode
  mint new certificates against the team's two-certificate cap.
