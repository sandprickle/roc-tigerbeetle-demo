#!/usr/bin/env bash
set -euo pipefail

# Build TigerBeetle's C client (release-stamped) and vendor the static archive
# for each Roc-supported target into platform/targets/.
#
# The path to a local TigerBeetle checkout must be in $ROC_TB_TIGERBEETLE_REPO.
#
#   ROC_TB_TIGERBEETLE_REPO=~/src/oss/tigerbeetle ./vendor_tb_client.sh [VERSION]
#
# VERSION (optional) overrides the version the client is stamped with. When
# omitted, the highest stable semver git tag in the TB repo is used. The stamp
# must match the cluster's release, or a real-release cluster evicts the client
# (client_release_too_high). See the tigerbeetle-integration-gotchas note.

root_dir="$(cd "$(dirname "$0")" && pwd)"

# --- Locate the TigerBeetle checkout -----------------------------------------
tb="${ROC_TB_TIGERBEETLE_REPO:-}"
if [[ -z "$tb" ]]; then
    echo "error: set ROC_TB_TIGERBEETLE_REPO to your local tigerbeetle checkout." >&2
    echo "usage: ROC_TB_TIGERBEETLE_REPO=/path/to/tigerbeetle $0 [VERSION]" >&2
    exit 1
fi
if [[ ! -d "$tb" ]]; then
    echo "error: ROC_TB_TIGERBEETLE_REPO is not a directory: $tb" >&2
    exit 1
fi
if [[ ! -f "$tb/build.zig" || ! -f "$tb/zig/download.sh" ]]; then
    echo "error: $tb does not look like a tigerbeetle checkout" \
        "(missing build.zig or zig/download.sh)." >&2
    exit 1
fi

# --- Ensure TigerBeetle's pinned Zig is ready --------------------------------
# TigerBeetle vendors its own Zig under ./zig; download.sh fetches the pinned
# version. Build with that, never a system zig.
zig="$tb/zig/zig"
if [[ ! -x "$zig" ]] || ! "$zig" version >/dev/null 2>&1; then
    echo "[zig] $zig not ready -> running $tb/zig/download.sh"
    (cd "$tb" && ./zig/download.sh)
fi
if [[ ! -x "$zig" ]] || ! "$zig" version >/dev/null 2>&1; then
    echo "error: TigerBeetle's zig is still not runnable at $zig after download." >&2
    exit 1
fi
echo "[zig] ready: $("$zig" version)"

# --- Determine the version to stamp ------------------------------------------
# Highest stable tag only: pure MAJOR.MINOR.PATCH, excluding legacy release-*
# and the lone "test" tag.
if [[ $# -ge 1 ]]; then
    version="$1"
else
    version="$(git -C "$tb" tag --list --sort=-version:refname |
        grep -E '^[0-9]+\.[0-9]+\.[0-9]+$' | head -n1 || true)"
fi
if [[ -z "$version" ]]; then
    echo "error: could not determine a stable version tag in $tb" \
        "(pass one explicitly: $0 X.Y.Z)." >&2
    exit 1
fi
echo "[version] stamping client as $version"

# --- Build the release-stamped C client --------------------------------------
# -Drelease == ReleaseSafe (the TigerBeetle ethos / our bench baseline). This
# cross-compiles every platform into src/clients/c/lib/<zig-triple>/.
echo "[build] $zig build clients:c -Drelease" \
    "-Dconfig-release=$version -Dconfig-release-client-min=$version"
(cd "$tb" && "$zig" build clients:c \
    -Drelease \
    -Dconfig-release="$version" \
    -Dconfig-release-client-min="$version")

# --- Copy the static archive per Roc-supported target ------------------------
# Static archive only (what the Roc host links), linux-musl not gnu. arm64win is
# intentionally absent: TigerBeetle ships no aarch64-windows client.
lib_root="$tb/src/clients/c/lib"
targets_dir="$root_dir/platform/targets"

copy_one() {
    local roc_target="$1" triple="$2" srcfile="$3"
    local src="$lib_root/$triple/$srcfile"
    local dst="$targets_dir/$roc_target/$srcfile"
    if [[ ! -f "$src" ]]; then
        echo "error: expected build output missing: $src" >&2
        exit 1
    fi
    mkdir -p "$targets_dir/$roc_target"
    cp "$src" "$dst"
    echo "  ✓ $roc_target <- $triple/$srcfile ($(du -h "$dst" | cut -f1))"
}

echo "[copy] vendoring static client libs into platform/targets/"
copy_one x64mac x86_64-macos libtb_client.a
copy_one arm64mac aarch64-macos libtb_client.a
copy_one x64musl x86_64-linux-musl libtb_client.a
copy_one arm64musl aarch64-linux-musl libtb_client.a
copy_one x64win x86_64-windows tb_client.lib
echo "  - arm64win skipped (TigerBeetle has no aarch64-windows client)"

echo "[done] vendored TigerBeetle client $version into platform/targets/"
