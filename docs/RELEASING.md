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

## The record

| | |
|---|---|
| Bundle identifier | `edu.princeton.autosigndisplay` |
| App Store Connect Apple ID | `6757710459` |
| Team | `Y3TW367T4G` (Princeton University) |
| Version being submitted | 1.0 |

Builds attach to the record automatically by bundle identifier.

## Prerequisites already satisfied

- **Shared scheme.** `AutoSignDisplay.xcscheme` is committed under
  `xcshareddata/xcschemes`. Xcode Cloud cannot see a scheme that is not shared, and
  this is the most common reason a first workflow finds nothing to build.
- **No external dependencies.** No Swift Package Manager references, so there is no
  resolution step and no `ci_scripts/ci_post_clone.sh` to write.
- **Automatic signing** with `DEVELOPMENT_TEAM = Y3TW367T4G`, which is what Xcode
  Cloud expects.

## Creating the workflow

Workflows are configured in **Xcode → Product → Xcode Cloud → Manage Workflows**, or
on the app's Xcode Cloud tab in App Store Connect.

1. Connect the source repository and grant Xcode Cloud access.
2. **Start condition** — a tag pattern such as `v*` suits this better than every push
   to `main`, since a release should be an explicit act.
3. **Actions**
   - *Test* — scheme `AutoSignDisplay`, a tvOS simulator destination.
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

The version string is `MARKETING_VERSION` in the project, currently `1.0`. It must
match the App Store Connect version record or the upload is rejected.

## Submitting for review

Xcode Cloud delivers a build. It does not submit for review. Once the build finishes
processing:

1. <https://appstoreconnect.apple.com> → My Apps → AutoSignDisplay
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
