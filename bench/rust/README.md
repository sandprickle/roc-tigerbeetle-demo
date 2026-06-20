# Rust e2e benchmark

End-to-end throughput driver for the **official TigerBeetle Rust client**, the
counterpart to `bench/go` (official Go client) and `bench/roc` (this repo's Roc
client). Same workload, same fair-sequential one-batch-in-flight model, so the
three are directly comparable; see the header comment in `src/main.rs` for the
async caveat.

## Prerequisite: build the client's static lib

The TB Rust client links a prebuilt `libtb_client.a` that is **not** checked in
(its `assets/lib/` is gitignored). Produce it once from your tigerbeetle checkout
— this builds the lib for every platform (incl. Linux) and regenerates bindings:

```console
cd ~/src/oss/tigerbeetle
./zig/zig build clients:rust -Drelease   # -Drelease == ReleaseSafe, the TB ethos
```

The dependency path in `Cargo.toml` assumes that checkout lives at
`~/src/oss/tigerbeetle`. Adjust it if yours differs (e.g. on the Linux box).

## Run

Against a **fresh** cluster (transfer ids start at 1), matching the other benches:

```console
# Terminal 1: fresh single-replica cluster on :3000
./start_tb.sh                      # from repo root

# Terminal 2:
cd bench/rust
cargo build --release
TB_ADDRESS=3000 ./target/release/rust_bench
```

Output is the same CSV as the Go/Roc benches:
`batch_size,batches,transfers,elapsed_ms,transfers_per_sec`.

## Notes

- **Build mode.** Plain `cargo build --release` is the idiomatic production build
  (matches Go's default optimized build); the heavy lifting lives in the
  ReleaseSafe `libtb_client.a` regardless. To mirror the ReleaseSafe ethos on the
  thin Rust glue too, add `overflow-checks = true` / `debug-assertions = true`
  under `[profile.release]` — negligible effect, since the per-call work is in the
  Zig lib.
- **Linux target.** The default `x86_64-unknown-linux-gnu` triple makes `build.rs`
  look for the `x86_64-linux-gnu.2.27` lib in `assets/lib/`. The all-platform
  build above produces it. (The Roc platform uses a *musl* lib; don't cross them.)
- Trustworthy numbers come from Linux (io_uring + O_DIRECT); macOS fsync is slow
  and high-variance, so treat local runs as a smoke test of the code path.
