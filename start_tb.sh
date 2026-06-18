#!/usr/bin/env bash
set -euxo pipefail

# Recreate a fresh single-replica cluster and run it on 127.0.0.1:3000
# (cluster 0) — matching the address/cluster hardcoded in src/tb_host.zig.
#
# Requires a 0.17.x `tigerbeetle` on PATH to match the vendored client lib at
# platform/targets/arm64mac/libtb_client.a (override with TIGERBEETLE=/path/...).
# --development lets it format/start without Direct IO (needed on macOS) and
# uses smaller cache/batch sizes.
tb="${TIGERBEETLE:-tigerbeetle}"

rm -rf ./0_0.tigerbeetle

"$tb" format --cluster=0 --replica=0 --replica-count=1 --development ./0_0.tigerbeetle

exec "$tb" start --addresses=3000 --development ./0_0.tigerbeetle
