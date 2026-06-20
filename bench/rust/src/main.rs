// End-to-end throughput benchmark for the official TigerBeetle Rust client.
//
// Mirrors bench/go/main.go and bench/roc/roc_bench.roc exactly: same workload
// (two accounts; transfers in batches of {10,100,1000,8189}), the same sequential
// transfer ids, and the same synchronous one-batch-in-flight model. Each
// `create_transfers` future is awaited to completion before the next batch is
// submitted, so at most one request is ever in flight — identical to Go's
// blocking `CreateTransfers` and the Roc host. Any difference vs the Go/Roc
// numbers is therefore per-call client overhead, not async-vs-sync pipelining.
//
// The Rust client is async; we drive it on a single-threaded executor
// (futures::executor::block_on), matching TB's own Rust sample and the
// single-threaded Go/Roc drivers. The client can still overlap its internal
// marshalling with the in-flight network round-trip, which is the one place the
// async client may legitimately pull ahead even under this fair-sequential model.
//
// Build optimized and run against a *fresh* cluster (transfer ids start at 1, so
// re-running against a used cluster would hit already-existing transfers):
//   cd bench/rust && cargo build --release && TB_ADDRESS=3000 ./target/release/rust_bench
//
// Needs a production-mode cluster (see ../../start_tb.sh) for batches up to 8189.

use std::time::Instant;
use tigerbeetle as tb;

const LEDGER: u32 = 700;
const CODE: u16 = 10;

fn main() -> Result<(), Box<dyn std::error::Error>> {
    futures::executor::block_on(run())
}

async fn run() -> Result<(), Box<dyn std::error::Error>> {
    let addr = std::env::var("TB_ADDRESS").unwrap_or_else(|_| "3000".to_string());
    let client = tb::Client::new(0, &addr)?;

    // Unique account ids (like the Roc bench's Tb.id!()) so accounts never
    // collide across runs; the id space is separate from transfer ids.
    let id_a = tb::id();
    let id_b = tb::id();
    client
        .create_accounts(&[
            tb::Account { id: id_a, ledger: LEDGER, code: CODE, ..Default::default() },
            tb::Account { id: id_b, ledger: LEDGER, code: CODE, ..Default::default() },
        ])?
        .await?;

    println!("batch_size,batches,transfers,elapsed_ms,transfers_per_sec");

    // Global, ever-increasing transfer id so every transfer is a fresh create.
    let mut next_id: u128 = 1;

    // Single-request max for 128-byte transfers is 8189 (1 MiB - 256 B header -
    // 128 B multi-batch trailer slot, / 128), not the folklore 8190.
    let configs = [(10usize, 1000usize), (100, 500), (1000, 50), (8189, 12)];

    for (size, batches) in configs {
        // One untimed warm-up batch.
        next_id = submit_batch(&client, id_a, id_b, size, next_id).await?;

        let start = Instant::now();
        for _ in 0..batches {
            next_id = submit_batch(&client, id_a, id_b, size, next_id).await?;
        }
        let elapsed = start.elapsed();

        let total = size * batches;
        let per_sec = (total as f64 / elapsed.as_secs_f64()) as u64;
        println!("{},{},{},{},{}", size, batches, total, elapsed.as_millis(), per_sec);
    }

    let _ = client.close().await;
    Ok(())
}

// Build `count` transfers (sequential ids from `first_id`), submit them as one
// request, await the result, and return the next unused id. Per-event results are
// discarded, matching the Go/Roc drivers.
async fn submit_batch(
    client: &tb::Client,
    debit: u128,
    credit: u128,
    count: usize,
    first_id: u128,
) -> Result<u128, Box<dyn std::error::Error>> {
    let mut batch = Vec::with_capacity(count);
    let mut id = first_id;
    for _ in 0..count {
        batch.push(tb::Transfer {
            id,
            debit_account_id: debit,
            credit_account_id: credit,
            amount: 1,
            ledger: LEDGER,
            code: CODE,
            ..Default::default()
        });
        id += 1;
    }
    let _ = client.create_transfers(&batch)?.await?;
    Ok(id)
}
