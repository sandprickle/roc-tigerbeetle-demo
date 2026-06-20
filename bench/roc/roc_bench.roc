app [main!] { pf: platform "../../platform/main.roc" }

import pf.Stdout
import pf.Utc
import pf.TigerBeetle as Tb

# End-to-end throughput benchmark for the Roc TigerBeetle client.
#
# Creates two accounts, then submits transfers in batches of varying size against
# a live cluster on 127.0.0.1:3000, timing ONLY the submit loop. Synchronous,
# one batch in flight at a time — the same model as the Go fair-sequential driver
# in bench/go, so the two are directly comparable.
#
# Run COMPILED for real numbers (the interpreter would dominate the measurement):
#   roc build examples/bench.roc && ./bench
# Needs a production-mode cluster (see start_tb.sh) for batches up to 8190.

# Build `count` transfers (sequential ids from `first_id`), submit them as one
# request, and return the next unused id. `_ =` discards the per-event results.
submit_batch! : { debit : U128, credit : U128, ledger : U32, count : I128, first_id : U128 } => U128
submit_batch! = |{ debit, credit, ledger, count, first_id }| {
	var $id = first_id
	var $batch = []
	var $i = 0
	while $i < count {
		transfer = Tb.Transfer.init(
			{
				id: $id,
				debit_account_id: debit,
				credit_account_id: credit,
				amount: 1,
				ledger,
			},
		).code(
			10,
		)
		$batch = List.append($batch, transfer)
		$id = $id + 1.U128
		$i = $i + 1
	}
	_ = Tb.create_transfers!($batch)
	$id
}

main! : List(Str) => Try({}, [Exit(I32)])
main! = |_args| {
	ledger = 700

	id_a = Tb.id!()
	id_b = Tb.id!()
	accounts = [
		Tb.Account.init({ id: id_a, ledger }).code(10),
		Tb.Account.init({ id: id_b, ledger }).code(10),
	]
	_ = Tb.create_accounts!(accounts)

	Stdout.line!("batch_size,batches,transfers,elapsed_ms,transfers_per_sec")

	# Global, ever-increasing transfer id so every transfer is a fresh create.
	var $next_id = 1.U128

	configs = [
		{ size: 10, batches: 1000 },
		{ size: 100, batches: 500 },
		{ size: 1000, batches: 50 },
		# Single-request max for 128-byte transfers: (1 MiB - 256B header - 128B
		# multi-batch trailer slot) / 128 = 8189. (The folklore "8190" overflows by
		# one in TigerBeetle's current multi-batch wire format.)
		{ size: 8189, batches: 12 },
	]

	for cfg in configs {
		# One untimed warm-up batch.
		$next_id = submit_batch!({ debit: id_a, credit: id_b, ledger, count: cfg.size, first_id: $next_id })

		start = Utc.now!()
		var $b = 0
		while $b < cfg.batches {
			$next_id = submit_batch!({ debit: id_a, credit: id_b, ledger, count: cfg.size, first_id: $next_id })
			$b = $b + 1
		}
		elapsed_ns = Utc.now!().to_nanos() - start.to_nanos()

		total = cfg.size * cfg.batches
		elapsed_ms = elapsed_ns // 1_000_000
		per_sec = (total * 1_000_000_000) // elapsed_ns
		Stdout.line!("${cfg.size.to_str()},${cfg.batches.to_str()},${total.to_str()},${elapsed_ms.to_str()},${per_sec.to_str()}")
	}

	Ok({})
}
