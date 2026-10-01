#!/usr/bin/env bash
# Regenerate the routing wire models + persisted-query ids + contract version from the published contract.
#
# The generated Dart is committed on purpose: the package carries the types, not the spec, and there is no
# codegen step in the SDK's own build. Types come from spider-codegen (tiducto/spider-codegen) — our own
# generator. Mirrors spider-sdk-{kotlin,typescript,swift}/scripts/generate-contract.sh.
#
# Usage:
#   scripts/generate-contract.sh                      # fetch main from the contract repo
#   scripts/generate-contract.sh --ref v5.0           # a specific ref/tag/branch
#   scripts/generate-contract.sh --spec path/to.json  # a local routing-openapi.json, no fetch
set -euo pipefail

CONTRACT_REPO="${CONTRACT_REPO:-tiducto/spider-contract}"
CONTRACT_REF="main"
CODEGEN_REPO="${CODEGEN_REPO:-tiducto/spider-codegen}"
CODEGEN_REF="${CODEGEN_REF:-master}"
LOCAL_SPEC=""

while [[ $# -gt 0 ]]; do
    case "$1" in
        --ref) CONTRACT_REF="$2"; shift 2 ;;
        --spec) LOCAL_SPEC="$2"; shift 2 ;;
        *) echo "unknown arg: $1" >&2; exit 2 ;;
    esac
done

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CONTRACT_DIR="$REPO_ROOT/lib/src/contract"
WORK_DIR="$(mktemp -d)"
trap 'rm -rf "$WORK_DIR"' EXIT

if [[ -n "$LOCAL_SPEC" ]]; then
    echo "==> Using local spec: $LOCAL_SPEC"
    cp "$LOCAL_SPEC" "$WORK_DIR/openapi.json"
else
    echo "==> Fetching dist/routing-openapi.json from $CONTRACT_REPO@$CONTRACT_REF"
    GH_TOKEN="${CONTRACT_REPO_TOKEN:-${GH_TOKEN:-}}" \
        gh api "repos/$CONTRACT_REPO/contents/dist/routing-openapi.json?ref=$CONTRACT_REF" --jq '.content' \
        | base64 -d > "$WORK_DIR/openapi.json"
fi

CONTRACT_VERSION="$(node -e "process.stdout.write(String(require('$WORK_DIR/openapi.json').info.version))")"
echo "==> Contract version: $CONTRACT_VERSION"
printf '// Generated from the published contract'"'"'s info.version by scripts/generate-contract.sh. Do not edit.\nconst contractVersion = '"'"'%s'"'"';\n' "$CONTRACT_VERSION" > "$CONTRACT_DIR/contract_version.dart"

node - "$WORK_DIR/openapi.json" "$CONTRACT_DIR/persisted_queries.dart" <<'NODE'
const fs = require('fs');
const [specPath, outPath] = process.argv.slice(2);
const spec = JSON.parse(fs.readFileSync(specPath, 'utf8'));
const ops = [];
for (const [route, methods] of Object.entries(spec.paths || {})) {
    for (const op of Object.values(methods)) {
        const id = op && op['x-persisted-query-id'];
        if (!id) continue;
        const path = route.replace(/^\/routing\//, '');
        ops.push({ name: path.replace(/[^A-Za-z0-9]/g, ''), id, path });
    }
}
if (ops.length === 0) { console.error('ERROR: no x-persisted-query-id found'); process.exit(1); }
ops.sort((a, b) => a.name.localeCompare(b.name));
const consts = ops.map((o) => `  static const ${o.name} = PersistedOp('${o.id}', '${o.path}');`).join('\n');
fs.writeFileSync(outPath, `// Generated from the published contract's x-persisted-query-id by scripts/generate-contract.sh. Do not edit.
//
// The gateway enforces a persisted-query allowlist: clients POST { id, variables } and the id is the
// lowercase-hex SHA-256 of the canonical query text. An id the gateway has not registered is rejected 403,
// so these must never drift from the published contract — they are generated, never hand-typed.

class PersistedOp {
  final String id;
  final String path;
  const PersistedOp(this.id, this.path);
}

class PersistedQueries {
${consts}
}
`);
process.stdout.write(String(ops.length));
NODE
echo " persisted-query ids written"

if [[ -n "${CODEGEN_DIR:-}" ]]; then
    echo "==> Using local spider-codegen at $CODEGEN_DIR"
    CODEGEN="$CODEGEN_DIR"
else
    echo "==> Cloning $CODEGEN_REPO@$CODEGEN_REF"
    CODEGEN="$WORK_DIR/spider-codegen"
    GH_TOKEN="${CONTRACT_REPO_TOKEN:-${GH_TOKEN:-}}" \
        gh repo clone "$CODEGEN_REPO" "$CODEGEN" -- --depth 1 --branch "$CODEGEN_REF" \
        || { echo "ERROR: could not clone $CODEGEN_REPO@$CODEGEN_REF." >&2; exit 1; }
fi

echo "==> Building spider-codegen"
( cd "$CODEGEN" && npm ci --silent && npm run build --silent )

echo "==> Generating Dart wire models with spider-codegen"
node "$CODEGEN/dist/cli.js" --spec "$WORK_DIR/openapi.json" --lang dart --out "$WORK_DIR/gen" --optional-lists nullable

if [[ ! -f "$WORK_DIR/gen/models.dart" ]]; then
    echo "ERROR: generator produced no Dart models" >&2
    exit 1
fi
cp "$WORK_DIR/gen/models.dart" "$CONTRACT_DIR/routing.dart"

# Format everything generated in this run the way the build checks it: `dart pub get` first, since the
# package's language version picks the format style. The contract sync runs without a Dart SDK, so fetch
# the stable one (what the build uses) when none is on PATH.
DART="$(command -v dart || true)"
if [[ -z "$DART" ]]; then
    case "$(uname -s)-$(uname -m)" in
        Linux-x86_64) DART_PLATFORM=linux-x64 ;;
        Linux-aarch64) DART_PLATFORM=linux-arm64 ;;
        Darwin-arm64) DART_PLATFORM=macos-arm64 ;;
        Darwin-x86_64) DART_PLATFORM=macos-x64 ;;
        *) echo "ERROR: no dart on PATH and no Dart SDK download for $(uname -sm)" >&2; exit 1 ;;
    esac
    echo "==> No dart on PATH; fetching the stable Dart SDK ($DART_PLATFORM)"
    curl -fsSL "https://storage.googleapis.com/dart-archive/channels/stable/release/latest/sdk/dartsdk-$DART_PLATFORM-release.zip" \
        -o "$WORK_DIR/dart-sdk.zip"
    unzip -q "$WORK_DIR/dart-sdk.zip" -d "$WORK_DIR"
    DART="$WORK_DIR/dart-sdk/bin/dart"
fi
echo "==> Formatting the generated Dart"
( cd "$REPO_ROOT" && "$DART" pub get >/dev/null \
    && "$DART" format "$CONTRACT_DIR/routing.dart" "$CONTRACT_DIR/persisted_queries.dart" "$CONTRACT_DIR/contract_version.dart" >/dev/null )

echo "==> Done. Wire models -> lib/src/contract/routing.dart"
echo "    The stops + realtime wire types are hand-written (lib/src/stops.dart + lib/src/realtime.dart), not generated."
