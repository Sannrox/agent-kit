#!/usr/bin/env bash
# Build release artifacts into --out without publishing or attesting.
#
# Usage:
#   bash scripts/release-package.sh --out dist [--tag vX.Y.Z] [--git-sha SHA]
#        [--skip-build] [--skip-test] [--skip-github]
set -euo pipefail

ROOT_PATH="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_PATH"

OUT=""
TAG=""
GIT_SHA=""
SKIP_BUILD=0
SKIP_TEST=0
SKIP_GITHUB=0

fail() {
  printf 'release-package: %s\n' "$1" >&2
  exit 1
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --out) OUT="${2:-}"; shift 2 ;;
    --tag) TAG="${2:-}"; shift 2 ;;
    --git-sha) GIT_SHA="${2:-}"; shift 2 ;;
    --skip-build) SKIP_BUILD=1; shift ;;
    --skip-test) SKIP_TEST=1; shift ;;
    --skip-github) SKIP_GITHUB=1; shift ;;
    *) fail "unknown argument: $1" ;;
  esac
done

[[ -n "$OUT" ]] || fail "usage: $0 --out dist [--tag vX.Y.Z] [--git-sha SHA]"
mkdir -p "$OUT"
OUT="$(cd "$OUT" && pwd)"

workspace_version() {
  python3 -c 'import re,sys; from pathlib import Path; text=Path(sys.argv[1]).read_text(); m=re.search(r"(?ms)^\[workspace\.package\][^\[]*?^version\s*=\s*\"([^\"]+)\"", text); sys.exit("Cargo.toml has no [workspace.package] version") if not m else print(m.group(1))' "$ROOT_PATH/Cargo.toml"
}

VERSION="$(workspace_version)"
if [[ -n "$TAG" ]]; then
  [[ "${TAG#v}" == "$VERSION" ]] || fail "tag ${TAG} does not match workspace version ${VERSION}"
  python3 "$ROOT_PATH/scripts/changelog-notes.py" "$VERSION" >"${OUT}/RELEASE_NOTES.md"
fi
if [[ -z "$GIT_SHA" ]]; then
  GIT_SHA="$(git rev-parse HEAD)"
fi
[[ "$GIT_SHA" =~ ^[0-9a-f]{40}$ ]] || fail "git sha must be a full lowercase SHA"

if [[ "$SKIP_TEST" -eq 0 ]]; then
  bash scripts/validate-kit.sh
  cargo test --locked --workspace
fi

if [[ "$SKIP_BUILD" -eq 0 ]]; then
  cargo build --locked --workspace --all-targets --release
  tar -C "$ROOT_PATH" -czf "${OUT}/agent-kit-${VERSION}.tar.gz" \
    AGENTS.md CHANGELOG.md LICENSE README.md RELEASING.md \
    Cargo.lock Cargo.toml rust-toolchain.toml \
    crates skills templates scripts security
fi

python3 "$ROOT_PATH/scripts/release-sbom.py" "${OUT}/agent-kit.cdx.json"

python3 -c '
import hashlib, pathlib, sys
out = pathlib.Path(sys.argv[1])
lines = []
for path in sorted(p for p in out.iterdir() if p.is_file() and p.name != "SHA256SUMS"):
    digest = hashlib.sha256(path.read_bytes()).hexdigest()
    lines.append(f"{digest}  {path.name}")
(out / "SHA256SUMS").write_text("\n".join(lines) + ("\n" if lines else ""))
' "$OUT"

LABEL_ARGS=()
if [[ -n "$TAG" && "$SKIP_GITHUB" -eq 0 ]] && command -v gh >/dev/null 2>&1; then
  prev="$(git tag --list 'v*' --sort=-version:refname)"
  prev="$(awk -v cur="$TAG" '$0 != cur { print; exit }' <<<"$prev")"
  search=()
  if [[ -n "$prev" ]]; then
    since="$(git log -1 --format=%cs "$prev" 2>/dev/null || true)"
    if [[ -n "$since" ]]; then
      search+=(--search "merged:>=${since}")
    fi
  fi
  while IFS= read -r label; do
    [[ -n "$label" ]] && LABEL_ARGS+=("--label" "$label")
  done < <(gh pr list --state merged --limit 100 "${search[@]}" --json labels --jq '.[].labels[].name' 2>/dev/null || true)
fi

manifest_args=(
  --component agent-kit
  --version "$VERSION"
  --git-sha "$GIT_SHA"
  --dist "$OUT"
  --out "${OUT}/agent-kit-release.json"
)
if [[ -n "$TAG" ]]; then
  manifest_args+=(--tag "$TAG")
fi
if [[ ${#LABEL_ARGS[@]} -gt 0 ]]; then
  manifest_args+=("${LABEL_ARGS[@]}")
fi
python3 "$ROOT_PATH/scripts/release-manifest.py" "${manifest_args[@]}"

echo "version=${VERSION}"
echo "artifacts in ${OUT}:"
cat "${OUT}/SHA256SUMS"
echo "images: none (this component does not publish a container image)"
