#!/usr/bin/env bash
set -euo pipefail

ROC_COMMIT=$(python3 ci/get_roc_commit.py)
ROC_COMMIT_SHORT="${ROC_COMMIT:0:8}"
NEED_BUILD=false

# Check if roc exists and matches pinned commit
if [ -d "roc-src" ] && [ -f "roc-src/zig-out/bin/roc" ]; then
  CACHED_VERSION=$(./roc-src/zig-out/bin/roc version 2>/dev/null || echo "unknown")
  if echo "$CACHED_VERSION" | grep -q "$ROC_COMMIT_SHORT"; then
    echo "roc already at correct version: $CACHED_VERSION"
  else
    echo "Cached roc ($CACHED_VERSION) doesn't match pinned commit ($ROC_COMMIT_SHORT)"
    echo "Removing stale roc-src..."
    rm -rf roc-src
    NEED_BUILD=true
  fi
else
  NEED_BUILD=true
fi

if [ "$NEED_BUILD" = true ]; then
  echo "Building roc from pinned commit $ROC_COMMIT..."

  rm -rf roc-src
  git init roc-src
  cd roc-src
  git remote add origin https://github.com/roc-lang/roc
  git fetch --depth 1 origin "$ROC_COMMIT"
  git checkout --detach "$ROC_COMMIT"

  zig build roc

  # Add to GITHUB_PATH if running in CI, otherwise add to local PATH
  if [ -n "${GITHUB_PATH:-}" ]; then
    echo "$(pwd)/zig-out/bin" >> "$GITHUB_PATH"
  else
    export PATH="$(pwd)/zig-out/bin:$PATH"
  fi

  cd ..
fi

# Ensure roc is in PATH for local runs
export PATH="$(pwd)/roc-src/zig-out/bin:$PATH"

# Skip zig build if SKIP_ZIG_BUILD is set (useful when a caller only needs Roc bootstrapping)
if [ -z "${SKIP_ZIG_BUILD:-}" ]; then
  echo ""
  echo "Building platform..."
  zig build

  echo ""
  echo "Running tests..."
  zig build test -- --verbose

  echo ""
  echo "Running bundle..."
  BUNDLE_OUTPUT=$(./bundle.sh 2>&1)
  echo "$BUNDLE_OUTPUT"
  BUNDLE_PATH=$(echo "$BUNDLE_OUTPUT" | awk '/^Created:/ { print $2; exit }')

  if [ -z "$BUNDLE_PATH" ]; then
    echo "Error: Could not extract bundle path from output"
    exit 1
  fi

  echo ""
  echo "Running tests with bundled platform..."
  ci/test_bundled_examples.sh "$BUNDLE_PATH"
fi
