#!/usr/bin/env bash
#
# make-release-kit.sh — assemble NightCityMP distributable release kits.
#
# Produces two artifacts under the output directory (default: dist/):
#
#   1. NightCityMP-<version>-player.zip
#        A game-root overlay the player extracts over their Cyberpunk 2077
#        install (the folder containing bin/, archive/, r6/). Merges:
#          - the client mod (Artifacts.zip from a green Windows CI run):
#              red4ext/plugins/zzzCyberpunkMP/{CyberpunkMP.dll,assets/...}
#          - the pinned third-party runtime stack (RED4ext, redscript, Codeware,
#            ArchiveXL, TweakXL, Input Loader), each downloaded/verified against
#            release/assets-manifest.json and unzipped into the same overlay.
#          - NightCityMP-{README,LICENSE,THIRD_PARTY_NOTICES,assets-manifest}.
#
#   2. NightCityMP-<version>-linux-server.tar.gz
#        The Linux dedicated server (Server.Loader + runtime) plus a launcher.
#        NOTE: the third-party client stack is NOT part of the server tarball —
#        RED4ext/redscript/Codeware/... are Windows game-client mods and the
#        dedicated server does not load them.
#
# Integrity: every third-party download is verified against the sha256 pinned in
# release/assets-manifest.json (fail-closed). First-party CI artifacts are trusted
# by provenance (green run on the project's own repo), not hash-pinned here.
#
# This script never touches any game install and never pushes anything.
#
# Requirements on this machine: bash, gh (authenticated), curl, sha256sum,
# unzip, tar, gzip, jq, python3.
#
# Usage:
#   scripts/make-release-kit.sh [options]
#
# Options:
#   --version <v>        Kit version (default: read from manifest .kit.version).
#   --out <dir>          Output directory (default: <repo>/dist).
#   --assets-dir <dir>   Use pre-downloaded third-party zips from here instead of
#                        downloading (files found by name, recursively). sha256 is
#                        still verified. Handy for offline / already-staged runs.
#   --client-run <id>    GitHub Actions run id to pull the client Artifacts.zip
#                        from (workflow: windows.yml, artifact name: build).
#   --client-branch <b>  Resolve the latest SUCCESSFUL windows.yml run on this
#                        branch when --client-run is not given (default: main).
#   --client-zip <path>  Use a local Artifacts.zip directly (skip gh entirely).
#   --server-dir <dir>   Path to a built server tree (build/linux/x86_64/release).
#   --server-run <id>    GitHub Actions run id to pull a Linux server artifact from
#                        (requires linux.yml to upload one — see README/manifest).
#   --skip-server        Build only the player zip.
#   --skip-player        Build only the server tarball.
#   --dry-run            Resolve and verify all inputs, print the plan, write
#                        nothing. Exits non-zero if the plan is incoherent.
#   -h, --help           Show this help.
#
# Exit status: 0 on success (or a coherent dry-run); non-zero on any error,
# missing required input, or checksum mismatch.

set -euo pipefail

# ---------------------------------------------------------------------------
# Paths & constants
# ---------------------------------------------------------------------------
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
MANIFEST="$REPO_ROOT/release/assets-manifest.json"
NOTICES="$REPO_ROOT/THIRD_PARTY_NOTICES.md"
README="$REPO_ROOT/README.md"
LICENSE="$REPO_ROOT/LICENSE.md"
REPO_SLUG="blyatiful1/NightCityMP"
CLIENT_ARTIFACT_NAME="build"

# ---------------------------------------------------------------------------
# Logging
# ---------------------------------------------------------------------------
info() { printf '\033[1;36m[*]\033[0m %s\n' "$*" >&2; }
ok()   { printf '\033[1;32m[+]\033[0m %s\n' "$*" >&2; }
warn() { printf '\033[1;33m[!]\033[0m %s\n' "$*" >&2; }
die()  { printf '\033[1;31m[x]\033[0m %s\n' "$*" >&2; exit 1; }
plan() { printf '\033[1;35m[plan]\033[0m %s\n' "$*" >&2; }

# ---------------------------------------------------------------------------
# Defaults / args
# ---------------------------------------------------------------------------
VERSION=""
OUT_DIR="$REPO_ROOT/dist"
ASSETS_DIR=""
CLIENT_RUN=""
CLIENT_BRANCH="main"
CLIENT_ZIP=""
SERVER_DIR=""
SERVER_RUN=""
SKIP_SERVER=0
SKIP_PLAYER=0
DRY_RUN=0

usage() { sed -n '2,72p' "$0" | sed 's/^# \{0,1\}//'; exit 0; }

while [[ $# -gt 0 ]]; do
  case "$1" in
    --version)       VERSION="${2:?}"; shift 2 ;;
    --out)           OUT_DIR="${2:?}"; shift 2 ;;
    --assets-dir)    ASSETS_DIR="${2:?}"; shift 2 ;;
    --client-run)    CLIENT_RUN="${2:?}"; shift 2 ;;
    --client-branch) CLIENT_BRANCH="${2:?}"; shift 2 ;;
    --client-zip)    CLIENT_ZIP="${2:?}"; shift 2 ;;
    --server-dir)    SERVER_DIR="${2:?}"; shift 2 ;;
    --server-run)    SERVER_RUN="${2:?}"; shift 2 ;;
    --skip-server)   SKIP_SERVER=1; shift ;;
    --skip-player)   SKIP_PLAYER=1; shift ;;
    --dry-run)       DRY_RUN=1; shift ;;
    -h|--help)       usage ;;
    *)               die "unknown argument: $1 (see --help)" ;;
  esac
done

# ---------------------------------------------------------------------------
# Tool + input preflight
# ---------------------------------------------------------------------------
need_cmd() { command -v "$1" >/dev/null 2>&1 || die "required command not found: $1"; }
for c in bash curl sha256sum unzip tar gzip jq python3; do need_cmd "$c"; done
# gh is only needed when we actually pull a CI artifact.
GH_OK=0
if command -v gh >/dev/null 2>&1 && gh auth status >/dev/null 2>&1; then GH_OK=1; fi

[[ -f "$MANIFEST" ]] || die "manifest not found: $MANIFEST"
jq empty "$MANIFEST" 2>/dev/null || die "manifest is not valid JSON: $MANIFEST"
[[ -f "$NOTICES" ]] || die "THIRD_PARTY_NOTICES.md not found: $NOTICES"

[[ -z "$VERSION" ]] && VERSION="$(jq -r '.kit.version' "$MANIFEST")"
[[ -n "$VERSION" && "$VERSION" != "null" ]] || die "could not determine kit version"

PLAYER_ZIP="$OUT_DIR/NightCityMP-${VERSION}-player.zip"
SERVER_TAR="$OUT_DIR/NightCityMP-${VERSION}-linux-server.tar.gz"

# Scratch workspace (auto-cleaned).
WORK="$(mktemp -d "${TMPDIR:-/tmp}/ncmp-relkit.XXXXXX")"
cleanup() { rm -rf "$WORK"; }
trap cleanup EXIT

info "NightCityMP release kit — version ${VERSION}"
info "repo:   $REPO_ROOT"
info "out:    $OUT_DIR"
[[ $DRY_RUN -eq 1 ]] && warn "DRY RUN — no files will be written"

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

# verify_sha256 <file> <expected-hex>
verify_sha256() {
  local file="$1" expected="$2" got
  got="$(sha256sum "$file" | awk '{print $1}')"
  if [[ "$got" != "$expected" ]]; then
    die "sha256 MISMATCH for $(basename "$file"): expected $expected, got $got"
  fi
  ok "sha256 verified: $(basename "$file")"
}

# find_local_asset <archive_filename> — echo path if present under ASSETS_DIR.
find_local_asset() {
  local fname="$1"
  [[ -n "$ASSETS_DIR" ]] || return 1
  if [[ -f "$ASSETS_DIR/$fname" ]]; then
    printf '%s\n' "$ASSETS_DIR/$fname"; return 0
  fi
  local hit
  hit="$(find "$ASSETS_DIR" -type f -name "$fname" 2>/dev/null | head -n1)"
  [[ -n "$hit" ]] && { printf '%s\n' "$hit"; return 0; }
  return 1
}

# zip a directory's contents at archive root (deterministic ordering).
zip_tree() {
  local src="$1" out="$2"
  python3 - "$src" "$out" <<'PY'
import os, sys, zipfile
src, out = sys.argv[1], sys.argv[2]
with zipfile.ZipFile(out, 'w', zipfile.ZIP_DEFLATED) as z:
    for root, dirs, files in os.walk(src):
        dirs.sort()
        for f in sorted(files):
            full = os.path.join(root, f)
            z.write(full, os.path.relpath(full, src))
PY
}

# ---------------------------------------------------------------------------
# Third-party assets: obtain (local or download) + verify against manifest
# ---------------------------------------------------------------------------
ASSET_CACHE="$WORK/assets"
mkdir -p "$ASSET_CACHE"

# Populates a global array ASSET_PATHS[name]=path with verified zips.
declare -A ASSET_PATHS=()

obtain_assets() {
  local n i name url sha fname src
  n="$(jq '.third_party | length' "$MANIFEST")"
  info "resolving $n pinned third-party components"
  for ((i=0; i<n; i++)); do
    name="$(jq -r ".third_party[$i].name" "$MANIFEST")"
    url="$(jq -r ".third_party[$i].url" "$MANIFEST")"
    sha="$(jq -r ".third_party[$i].sha256" "$MANIFEST")"
    fname="$(jq -r ".third_party[$i].archive_filename" "$MANIFEST")"

    if src="$(find_local_asset "$fname")"; then
      info "$name: using local $src"
    else
      if [[ $DRY_RUN -eq 1 ]]; then
        plan "$name: would download $url -> $ASSET_CACHE/$fname"
        plan "$name: would verify sha256 $sha"
        continue
      fi
      info "$name: downloading $url"
      curl -fL --retry 3 --retry-delay 2 -o "$ASSET_CACHE/$fname" "$url" \
        || die "$name: download failed ($url)"
      src="$ASSET_CACHE/$fname"
    fi

    verify_sha256 "$src" "$sha"
    ASSET_PATHS["$name"]="$src"
  done
}

# ---------------------------------------------------------------------------
# Client artifact (Artifacts.zip from a green Windows CI run)
# ---------------------------------------------------------------------------
CLIENT_ZIP_RESOLVED=""
CLIENT_RUN_ID=""

resolve_client_run() {
  # Set CLIENT_RUN_ID: explicit --client-run, else latest successful windows.yml.
  if [[ -n "$CLIENT_RUN" ]]; then CLIENT_RUN_ID="$CLIENT_RUN"; return 0; fi
  [[ $GH_OK -eq 1 ]] || die "gh not authenticated; pass --client-run/--client-zip"
  local id
  id="$(gh run list -R "$REPO_SLUG" --workflow=windows.yml \
        --branch "$CLIENT_BRANCH" --status success --limit 1 \
        --json databaseId --jq '.[0].databaseId' 2>/dev/null || true)"
  [[ -n "$id" && "$id" != "null" ]] \
    || die "no successful windows.yml run on branch '$CLIENT_BRANCH'; pass --client-run"
  CLIENT_RUN_ID="$id"
}

obtain_client_zip() {
  if [[ -n "$CLIENT_ZIP" ]]; then
    [[ -f "$CLIENT_ZIP" ]] || die "--client-zip not found: $CLIENT_ZIP"
    CLIENT_ZIP_RESOLVED="$CLIENT_ZIP"
    info "client: using local $CLIENT_ZIP"
    return 0
  fi
  resolve_client_run; local run_id="$CLIENT_RUN_ID"
  if [[ $DRY_RUN -eq 1 ]]; then
    plan "client: would 'gh run download $run_id -R $REPO_SLUG -n $CLIENT_ARTIFACT_NAME'"
    return 0
  fi
  info "client: downloading artifact '$CLIENT_ARTIFACT_NAME' from run $run_id"
  local dl="$WORK/client"; mkdir -p "$dl"
  gh run download "$run_id" -R "$REPO_SLUG" -n "$CLIENT_ARTIFACT_NAME" -D "$dl" \
    || die "gh run download failed for run $run_id"
  CLIENT_ZIP_RESOLVED="$(find "$dl" -type f -name 'Artifacts.zip' | head -n1)"
  [[ -n "$CLIENT_ZIP_RESOLVED" ]] || die "Artifacts.zip not found in run $run_id artifact"
  info "client: got $CLIENT_ZIP_RESOLVED"
}

# ---------------------------------------------------------------------------
# Player zip
# ---------------------------------------------------------------------------
build_player() {
  info "=== PLAYER zip ==="
  obtain_assets
  obtain_client_zip

  if [[ $DRY_RUN -eq 1 ]]; then
    plan "would extract Artifacts.zip + $(jq '.third_party|length' "$MANIFEST") third-party zips into one game-root overlay"
    plan "would add NightCityMP-{README.md,LICENSE.md,THIRD_PARTY_NOTICES.md,assets-manifest.json}"
    plan "would write $PLAYER_ZIP"
    return 0
  fi

  local stage="$WORK/player"; mkdir -p "$stage"
  info "unpacking client overlay"
  unzip -oq "$CLIENT_ZIP_RESOLVED" -d "$stage"
  local name
  for name in "${!ASSET_PATHS[@]}"; do
    info "unpacking $name"
    unzip -oq "${ASSET_PATHS[$name]}" -d "$stage"
  done

  # Docs at overlay root, name-spaced so they never clobber a game file.
  cp "$README"   "$stage/NightCityMP-README.md"
  cp "$LICENSE"  "$stage/NightCityMP-LICENSE.md"
  cp "$NOTICES"  "$stage/NightCityMP-THIRD_PARTY_NOTICES.md"
  cp "$MANIFEST" "$stage/NightCityMP-assets-manifest.json"

  mkdir -p "$OUT_DIR"
  info "zipping -> $PLAYER_ZIP"
  zip_tree "$stage" "$PLAYER_ZIP"
  ok "player zip: $PLAYER_ZIP ($(du -h "$PLAYER_ZIP" | cut -f1))"
  # Sanity: the DLL must be at the load-order path.
  python3 - "$PLAYER_ZIP" <<'PY'
import sys, zipfile
need = "red4ext/plugins/zzzCyberpunkMP/CyberpunkMP.dll"
names = zipfile.ZipFile(sys.argv[1]).namelist()
sys.exit(0 if need in names else f"FATAL: {need} missing from player zip")
PY
  ok "verified CyberpunkMP.dll at plugin load-order path"
}

# ---------------------------------------------------------------------------
# Linux server tarball
# ---------------------------------------------------------------------------
SERVER_SRC=""

resolve_server_source() {
  # Set SERVER_SRC to a dir containing the built server. Return 1 if none exists
  # (as opposed to an explicitly-given-but-invalid input, which is fatal).
  SERVER_SRC=""
  if [[ -n "$SERVER_DIR" ]]; then
    [[ -d "$SERVER_DIR" ]] || die "--server-dir not found: $SERVER_DIR"
    SERVER_SRC="$SERVER_DIR"; return 0
  fi
  if [[ -n "$SERVER_RUN" ]]; then
    [[ $GH_OK -eq 1 ]] || die "gh not authenticated; cannot use --server-run"
    if [[ $DRY_RUN -eq 1 ]]; then SERVER_SRC="<gh:run/$SERVER_RUN>"; return 0; fi
    local dl="$WORK/server-dl"; mkdir -p "$dl"
    gh run download "$SERVER_RUN" -R "$REPO_SLUG" -D "$dl" \
      || die "gh run download failed for server run $SERVER_RUN"
    # gh places each artifact under a <artifact-name>/ subdir, so Server.Loader is
    # not at $dl root — locate it wherever it landed and use its directory.
    local found; found="$(find "$dl" -type f -name Server.Loader | head -n1)"
    [[ -n "$found" ]] || die "Server.Loader not found in downloaded artifact (run $SERVER_RUN)"
    SERVER_SRC="$(dirname "$found")"; return 0
  fi
  # Fallback: a local build tree at the conventional path.
  local conv="$REPO_ROOT/build/linux/x86_64/release"
  if [[ -f "$conv/Server.Loader" ]]; then SERVER_SRC="$conv"; return 0; fi
  return 1  # nothing available
}

build_server() {
  info "=== LINUX SERVER tarball ==="
  if ! resolve_server_source; then
    if [[ $DRY_RUN -eq 1 ]]; then
      warn "no Linux server build available (linux.yml uploads none yet); a real run would ABORT here"
      plan "provide --server-dir <build/linux/x86_64/release>, --server-run <id>, or --skip-server"
      return 0
    fi
    die "no Linux server build available.
      linux.yml does not yet upload an artifact, and no local build was found.
      Provide one of: --server-dir <build/linux/x86_64/release>, --server-run <id>
      (once linux.yml uploads Server.Loader), or pass --skip-server."
  fi
  local src="$SERVER_SRC"
  info "server source: $src"

  if [[ $DRY_RUN -eq 1 ]]; then
    plan "would stage Server.Loader + runtime from $src"
    plan "would add start-server.sh launcher + LICENSE + THIRD_PARTY_NOTICES"
    plan "would write $SERVER_TAR"
    return 0
  fi

  [[ -f "$src/Server.Loader" ]] || die "Server.Loader not found in $src"
  local top="NightCityMP-${VERSION}-linux-server"
  local stage="$WORK/server/$top"; mkdir -p "$stage"
  cp -a "$src"/. "$stage"/
  cp "$LICENSE"  "$stage/LICENSE.md"
  cp "$NOTICES"  "$stage/THIRD_PARTY_NOTICES.md"

  # Self-contained launcher (the repo scripts/start-server.sh assumes the
  # in-tree ../build path; the tarball ships binaries alongside the script).
  cat > "$stage/start-server.sh" <<'LAUNCH'
#!/usr/bin/env bash
# Start the NightCityMP dedicated server (Linux).
# Set real CYBERPUNKMP_ADMIN_USERNAME / _PASSWORD before exposing beyond localhost;
# the defaults below are for LOCAL play only. Game: UDP 11778, admin API: TCP 11778.
set -euo pipefail
cd "$(dirname "$0")"
export DOTNET_ROLL_FORWARD="${DOTNET_ROLL_FORWARD:-LatestMajor}"
export CYBERPUNKMP_ADMIN_USERNAME="${CYBERPUNKMP_ADMIN_USERNAME:-admin}"
export CYBERPUNKMP_ADMIN_PASSWORD="${CYBERPUNKMP_ADMIN_PASSWORD:-localtest123}"
echo "NightCityMP server starting (game udp :11778, admin api tcp :11778)"
echo "Stop with Ctrl+C or SIGTERM (clean shutdown)."
exec ./Server.Loader "$@"
LAUNCH
  chmod +x "$stage/start-server.sh"

  mkdir -p "$OUT_DIR"
  info "tarring -> $SERVER_TAR"
  tar -czf "$SERVER_TAR" -C "$WORK/server" "$top"
  ok "server tarball: $SERVER_TAR ($(du -h "$SERVER_TAR" | cut -f1))"
}

# ---------------------------------------------------------------------------
# Run
# ---------------------------------------------------------------------------
[[ $SKIP_PLAYER -eq 0 ]] && build_player || info "skipping player zip (--skip-player)"
[[ $SKIP_SERVER -eq 0 ]] && build_server || info "skipping server tarball (--skip-server)"

# Checksums for whatever we actually produced.
if [[ $DRY_RUN -eq 0 ]]; then
  info "=== checksums ==="
  ( cd "$OUT_DIR" && \
    for f in "NightCityMP-${VERSION}-player.zip" "NightCityMP-${VERSION}-linux-server.tar.gz"; do
      [[ -f "$f" ]] && sha256sum "$f" | tee -a SHA256SUMS.txt
    done ) || true
  ok "done — artifacts in $OUT_DIR"
else
  ok "dry run complete — plan is coherent, nothing written"
fi
