#!/bin/sh
# Xcode Cloud runs this on the build machine after checkout, before building.
#
# It exists so the static source checks run in CI. They cannot live in the test
# target: those tests located the repository through #filePath, which resolves to the
# build machine's path, and the test bundle runs in an environment that no longer has
# the checkout —
#
#   The folder "AutoSignDisplay" doesn't exist.
#   /Volumes/workspace/repository/AutoSignDisplay
#
# Here the source is present, so the checks work. A non-zero exit fails the build.

set -e

cd "$CI_PRIMARY_REPOSITORY_PATH" || exit 1
echo "Running static source checks…"
python3 scripts/check-source-patterns.py
