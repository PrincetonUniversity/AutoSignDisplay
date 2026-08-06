# Releasing AutoSignDisplay

Releases go through **Xcode Cloud**. Apple builds, signs, and delivers to App Store
Connect; nothing is signed on a developer's machine.

## Why this route

The Princeton team is at Apple's cap for Apple Distribution certificates. All three
belong to other people or to automation, and Apple never releases a private key — the
portal holds only the public certificate, so no role, not even Account Holder, can
hand one over. Freeing a slot needs an Admin.

Xcode Cloud sidesteps that entirely: it signs on Apple's infrastructure with assets
Apple manages. Nobody here needs a distribution certificate.

## Two identities, one source

The app ships under two identities from shared source. They differ only in bundle
identifier, display name, and which default channel list they carry.

| | Scheme | Bundle identifier | Default channels |
|---|---|---|---|
| Private | `AutoSignDisplay` | `edu.princeton.autosigndisplay` | Princeton's four |
| Public | `AutoStreamDisplay` | `edu.princeton.autostreamdisplay` | one neutral sample |

Selected by the `PRIVATE_DISTRIBUTION` compilation condition, set on the private target
only. Both lists are compiled into both builds so each can be asserted in tests.

### This does not need two branches

An Xcode Cloud workflow builds a named **scheme**, and each workflow belongs to one App
Store Connect record. So two app records need **two workflows**, both of which can watch
the same `main`. Build numbers increment per workflow, so each record keeps its own
monotonic counter without coordination.

Where the two releases need to diverge in *timing*, use **tag patterns** — `sign-v*` and
`stream-v*` — not branches. Tags let release schedules differ while the source stays
single. Two long-lived branches would reintroduce exactly the divergence that sharing one
target set is meant to prevent, and every fix would need applying twice.

Branches are only warranted if the *source* has to differ. Today it differs by one
compilation condition.

### Driving either identity locally

The simulator scripts take `--app`, and read the bundle identifier out of the project
rather than keeping their own copy — a second copy would drift, and since the two apps
install side by side a stale value would quietly drive the wrong one.

```bash
./scripts/run.sh                                   # private, the default
./scripts/run.sh --app AutoStreamDisplay           # public
./scripts/run-tests.sh --app AutoStreamDisplay
./scripts/check-managed-status.sh --app AutoStreamDisplay --udid <UDID>
```

### A gap worth knowing

Both test targets pin `TEST_HOST` to `AutoSignDisplay.app`. Running the suite under the
`AutoStreamDisplay` scheme therefore exercises all the shared logic but reports the
*private* identity, so the public target's own default-list selection is not covered by
CI. It is verified by installing both builds side by side and comparing what they show.

Closing that properly means a second test target hosted by `AutoStreamDisplay`, created
in Xcode. Until then, do not read a green public run as proof the public binary carries
the neutral defaults.

## The records

| | Private | Public |
|---|---|---|
| Bundle identifier | `edu.princeton.autosigndisplay` | `edu.princeton.autostreamdisplay` |
| App Store Connect Apple ID | `6757710459` | *(fill in from the new record)* |
| Distribution | Custom App — **blocked**, disabled in this ASM | App Store |
| Status | 1.0 approved, unacquirable | 1.1 pending submission |

Team is `Y3TW367T4G` (Princeton University) for both. Builds attach to a record
automatically by bundle identifier, which is why the two must never share one.

The private record is approved but undeployable: the organisation has Custom Apps
disabled in Apple School Manager and enabling it is committee-gated. It is kept because
the app is built and tested, not because it can currently ship.

## Prerequisites already satisfied

- **Both schemes shared.** `AutoSignDisplay.xcscheme` and `AutoStreamDisplay.xcscheme`
  are committed under `xcshareddata/xcschemes`. Xcode Cloud cannot see a scheme that is
  not shared, and this is the most common reason a first workflow finds nothing to
  build — Xcode's target duplication leaves the new scheme in `xcuserdata`, where CI
  will never find it.
- **No external dependencies.** No Swift Package Manager references, so there is no
  resolution step and no `ci_scripts/ci_post_clone.sh` to write.
- **Automatic signing** with `DEVELOPMENT_TEAM = Y3TW367T4G`, which is what Xcode
  Cloud expects.

## Creating the workflows

One workflow per app record, both watching the same branch. Configured in
**Xcode → Product → Xcode Cloud → Manage Workflows**, or the app's Xcode Cloud tab in
App Store Connect.

For each:

1. Connect the source repository and grant Xcode Cloud access.
2. **Start condition** — a tag pattern is a better fit than every push to `main`, since
   a release should be an explicit act. Use distinct patterns so the two release
   independently: `sign-v*` and `stream-v*`.
3. **Actions**
   - *Test* — the matching scheme, one tvOS simulator destination. One destination, not
     several: tvOS clones simulators under parallel testing and hangs rather than fails.
   - *Archive* — platform tvOS, deployment preparation **App Store Connect**.
4. **Post-action** — TestFlight, or App Store Connect distribution.

## What is and is not version-controlled

Worth being clear about, given the intent to run this GitOps-style:

- **Workflow configuration is not in the repo.** Start conditions, actions, and
  environment live in App Store Connect and are edited through a UI. There is no file
  to review, diff, or roll back.
- **`ci_scripts/` is in the repo.** Xcode Cloud runs `ci_post_clone.sh`,
  `ci_pre_xcodebuild.sh`, and `ci_post_xcodebuild.sh` from a `ci_scripts` directory
  beside the Xcode project, when present. That is the only part of the pipeline that
  is version-controlled.

This project has no `ci_scripts/` because it needs none. Add one only when there is
real work for it to do.

## Build numbers

Xcode Cloud exposes `CI_BUILD_NUMBER` and increments it per run. **Confirm on the
first archive that the build number actually reaches the uploaded binary.** If App
Store Connect reports a build number you did not expect, the fix is a
`ci_pre_xcodebuild.sh` that writes `CI_BUILD_NUMBER` into the build settings.

The version string is `MARKETING_VERSION`, set per target and currently `1.1` for both.
It must match the App Store Connect version record or the upload is rejected — and it is
a per-target setting, so the two identities can diverge without touching the source.

## Submitting for review

Xcode Cloud delivers a build. It does not submit for review. Once the build finishes
processing:

1. <https://appstoreconnect.apple.com> → My Apps → the relevant record
2. On the version page, **Build** → select the build
3. **Add for Review** / **Submit**

## If the Test action hangs

A known trap in this project: `xcodebuild` spawns cloned simulators when parallel
testing is enabled, and tvOS runs can hang at the home screen rather than fail.
Locally this is handled with `-parallel-testing-enabled NO`. If an Xcode Cloud test
action hangs, disable parallel testing in the test action's settings before looking
anywhere else.

## Local verification

Xcode Cloud replaces local archiving, but the simulator scripts remain the way to
check a change before pushing:

```bash
./scripts/run-tests.sh              # full suite against a tvOS simulator
./scripts/run-tests.sh --managed    # exercise the MDM path
./scripts/run.sh                    # build, install, launch
```

## If Xcode Cloud turns out not to be an option

Local build-and-upload scripts existed and were removed when this route was chosen.
They handled archive, export, `altool` validation and upload, with an `--import-p12`
path for an externally supplied signing identity. Recover them with:

```bash
git log --oneline --diff-filter=D -- scripts/release.sh
git revert <the commit that removed them>
```

They cannot work without a distribution certificate in the keychain, which is the
constraint that led here in the first place.
