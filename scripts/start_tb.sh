#!/usr/bin/env bash
set -euxo pipefail

# Recreate a fresh single-replica cluster and run it on 127.0.0.1:3000
# (cluster 0) — matching the address/cluster hardcoded in src/tb_host.zig.
#
# Uses the server vendored by ./vendor_tb_client.sh at tigerbeetle-bin/tigerbeetle,
# which is built from the same TB commit as the vendored client libs (both are
# unstamped 65535.0.0, so they must match; see platform/targets/TB_COMMIT).
# Override with TIGERBEETLE=/path/to/tigerbeetle.
# --development lets it format/start without Direct IO (needed on macOS) and
# uses smaller cache/batch sizes.
cd "$(dirname "$0")/.."
tb="${TIGERBEETLE:-$(pwd)/tigerbeetle-bin/tigerbeetle}"

rm -rf ./0_0.tigerbeetle

"$tb" format --cluster=0 --replica=0 --replica-count=1 --development ./0_0.tigerbeetle

exec "$tb" start --addresses=3000 --development ./0_0.tigerbeetle
