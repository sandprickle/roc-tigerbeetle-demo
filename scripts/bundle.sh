#!/usr/bin/env bash
set -euo pipefail

root_dir="$(cd "$(dirname "$0")" && pwd)"
cd "$root_dir/platform"

# Collect all .roc files
roc_files=(*.roc)

# Collect all host libraries from targets directories
lib_files=()
for lib in targets/*/*.a targets/*/*.o targets/*/*.lib; do
    # Skip arm64win: TigerBeetle has no aarch64-windows client, so this
    # platform doesn't support that target (commented out in main.roc).
    if [[ "$lib" == targets/arm64win/* ]]; then
        continue
    fi
    if [[ -f "$lib" ]]; then
        lib_files+=("$lib")
    fi
done

echo "Bundling ${#roc_files[@]} .roc files and ${#lib_files[@]} library files..."

roc bundle "${roc_files[@]}" "${lib_files[@]}" --output-dir "$root_dir" "$@"
