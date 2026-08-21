#!/usr/bin/env bash
# Stamp the package version (contract.patch from version.properties) into lib/src/version.dart and pubspec.yaml.
# The full semver goes into the `x-spider-sdk` identity header on every request. Mirrors the sibling SDKs.
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
contract="$(grep '^contract=' "$REPO_ROOT/version.properties" | cut -d= -f2 | tr -d '[:space:]')"
patch="$(grep '^patch=' "$REPO_ROOT/version.properties" | cut -d= -f2 | tr -d '[:space:]')"
version="${contract}.${patch}"

printf '// Stamped from version.properties (contract.patch) by scripts/stamp-version.sh at release. Do not edit.\nconst sdkVersion = '"'"'%s'"'"';\n' "$version" \
    > "$REPO_ROOT/lib/src/version.dart"
# Keep the pubspec version in lockstep (perl -i works on both macOS and Linux CI).
perl -i -pe "s/^version: .*/version: ${version}/" "$REPO_ROOT/pubspec.yaml"
echo "stamped sdkVersion = $version"
