#!/usr/bin/env bash
set -euo pipefail

# Build TigerBeetle's C client and server from whatever commit the local TB
# checkout has at HEAD, vendor the client static archive for each Roc-supported
# target into platform/targets/, and copy the matching server binary to
# tigerbeetle-bin/tigerbeetle (used by start_tb.sh).
#
# The path to a local TigerBeetle checkout must be in $ROC_TB_TIGERBEETLE_REPO.
# This script never moves that checkout; check out the commit you want first.
#
#   ROC_TB_TIGERBEETLE_REPO=~/src/oss/tigerbeetle ./vendor_tb_client.sh
#
# Why main and unstamped: tagged releases (0.17.x) pin zig 0.14.1, which doesn't
# work on current macOS; main pins zig 0.16. Builds are left unstamped (no
# -Dconfig-release), so client and server both report release 65535.0.0. That
# only works if both come from the SAME commit, hence building the server here
# too. The commit sha is embedded automatically (build.zig defaults -Dgit-commit
# to `git rev-parse HEAD`; `tigerbeetle version` shows 65535.0.0+<sha>) and is
# recorded in platform/targets/TB_COMMIT.

root_dir="$(cd "$(dirname "$0")" && pwd)"

# --- Locate the TigerBeetle checkout -----------------------------------------
tb="${ROC_TB_TIGERBEETLE_REPO:-}"
if [[ -z "$tb" ]]; then
    echo "error: set ROC_TB_TIGERBEETLE_REPO to your local tigerbeetle checkout." >&2
    echo "usage: ROC_TB_TIGERBEETLE_REPO=/path/to/tigerbeetle $0" >&2
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

# --- Identify the commit being built -----------------------------------------
if [[ $# -gt 0 ]]; then
    echo "error: $0 takes no arguments (it builds the TB checkout's HEAD)." >&2
    exit 1
fi
sha="$(git -C "$tb" rev-parse HEAD)"
echo "[commit] building tigerbeetle $sha (unstamped, release 65535.0.0)"
if [[ -n "$(git -C "$tb" status --porcelain --untracked-files=no)" ]]; then
    echo "warning: $tb has uncommitted changes; the build won't match $sha exactly." >&2
fi

# --- Build the C client and the server ---------------------------------------
# -Drelease == ReleaseSafe (the TigerBeetle ethos / our bench baseline).
# clients:c cross-compiles every platform into src/clients/c/lib/<zig-triple>/;
# the plain build produces ./tigerbeetle for the host.
echo "[build] $zig build clients:c -Drelease"
(cd "$tb" && "$zig" build clients:c -Drelease)
echo "[build] $zig build -Drelease"
(cd "$tb" && "$zig" build -Drelease)

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

bin_dir="$root_dir/tigerbeetle-bin"
mkdir -p "$bin_dir"
cp "$tb/tigerbeetle" "$bin_dir/tigerbeetle"
echo "  ✓ tigerbeetle-bin/tigerbeetle <- $("$bin_dir/tigerbeetle" version | head -n1)"

echo "$sha" >"$targets_dir/TB_COMMIT"
echo "[done] vendored TigerBeetle client + server @ $sha"
