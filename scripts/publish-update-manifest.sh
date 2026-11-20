#!/usr/bin/env bash
#
# Publish Hesper Remote's auto-update manifests to the repo's `updates` branch.
#
# The in-app updater (hbb_common::version_check_request) GETs
#   https://raw.githubusercontent.com/<repo>/updates/<os>-<arch>.json
# for the running platform, where each file is a tiny
#   {"url":"<latest GitHub release asset>"}.
# The client parses the version out of the asset filename and offers an update.
#
# raw.githubusercontent.com is CDN-served + unauthenticated (no API rate limit),
# and the asset it points at is a signed GitHub release download. Only assets that
# resolve publicly are ever named (see write() below).
#
# Usage:  scripts/publish-update-manifest.sh <version>      # e.g. 1.5.32
#         DRY_RUN=1 scripts/publish-update-manifest.sh <version>   # show, never push
# Auth:   uses your ambient git credentials (gh/credential helper) or, in CI,
#         GITHUB_TOKEN via the checked-out remote.
set -euo pipefail

V="${1:?usage: $(basename "$0") <version>   e.g. 1.5.32}"
REPO="${HESPER_REPO:-${GITHUB_REPOSITORY:-arke-technologies/hesper-remote-engine}}"
BASE="https://github.com/${REPO}/releases/download"

tmp="$(mktemp -d)"; trap 'rm -rf "$tmp"' EXIT
# Clone the `updates` branch; create it as a clean orphan the first time.
if git clone --quiet --depth 1 --branch updates "https://github.com/${REPO}.git" "$tmp/u" 2>/dev/null; then
  cd "$tmp/u"
else
  git clone --quiet --depth 1 "https://github.com/${REPO}.git" "$tmp/u"
  cd "$tmp/u"
  git checkout --quiet --orphan updates
  git rm -rqf . 2>/dev/null || true
fi

# Each platform ships from its own tag (v / win-v / linux-v) and run, so a version
# can be published for one platform while another is still building. A manifest
# is only ever pointed at an asset that RESOLVES publicly right now (a draft or a
# missing asset answers 404) and is never moved to an older version. Otherwise
# the platform keeps its current manifest. This stops the in-app updater from
# offering a download that 404s (2026-11-20: the macOS 1.5.37 publish advertised
# the Windows and Linux 1.5.37 drafts).
resolves() { [ "$(curl -sIL -o /dev/null -m 30 -w '%{http_code}' "$1")" = "200" ]; }
ver_of() { sed -nE 's/.*HesperRemote-([0-9]+(\.[0-9]+)+)-.*/\1/p' "$1" 2>/dev/null | head -1; }
older() { [ "$1" != "$2" ] && [ "$(printf '%s\n%s\n' "$1" "$2" | sort -V | head -1)" = "$1" ]; }
write() {
  local name="$1" url="$2" cur
  cur="$(ver_of "$name.json")"
  if [ -n "$cur" ] && older "$V" "$cur"; then
    echo "  $name: keeping $cur (never downgrade to $V)"; return
  fi
  if ! resolves "$url"; then
    echo "  $name: $V asset does not resolve yet (draft or not built); keeping ${cur:-none}"; return
  fi
  printf '{"url":"%s"}\n' "$url" > "$name.json"
  echo "  $name: -> $V"
}
write linux-x86_64   "${BASE}/linux-v${V}/HesperRemote-${V}-x86_64.deb"
write macos-x86_64   "${BASE}/v${V}/HesperRemote-${V}-x86_64.dmg"
write macos-aarch64  "${BASE}/v${V}/HesperRemote-${V}-aarch64.dmg"
write windows-x86_64 "${BASE}/win-v${V}/HesperRemote-${V}-x86_64-windows-setup.exe"

cat > README.md <<EOF
# Hesper Remote — auto-update manifests

Last run: **${V}** (each platform moves only once its own asset is published).

$(for f in linux-x86_64 macos-x86_64 macos-aarch64 windows-x86_64; do [ -f "$f.json" ] && printf -- '- `%s`: %s\n' "$f" "$(ver_of "$f.json")"; done)

Each \`<os>-<arch>.json\` is \`{"url":"<latest release asset>"}\`, fetched by the
in-app updater (\`hbb_common::version_check_request\`) for the running platform.

Regenerate with \`scripts/publish-update-manifest.sh <version>\` from the repo.
EOF

git add -A
if [ "${DRY_RUN:-}" = "1" ]; then
  echo "DRY_RUN: would commit:"; git --no-pager diff --cached --stat; exit 0
fi
if git diff --cached --quiet -- '*.json'; then
  echo "no manifest moved for ${V}; nothing to publish"
  exit 0
fi
git -c user.name="hesper-ci" -c user.email="support@hesperitsm.com" \
  commit -qm "chore(updates): manifests -> ${V}"
git push --quiet origin updates
echo "published manifests -> ${V} on the 'updates' branch"
