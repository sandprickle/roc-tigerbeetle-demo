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
submit_batch! : {
	debit : U128,
	credit : U128,
	ledger : U32,
	count : I128,
	first_id : U128,
} => U128
submit_batch! = |{ debit, credit, ledger, count, first_id }| {
	var $batch = []
	var $id = first_id
	for _i in 0..<count {
		$batch = $batch.append(
			Tb.Transfer.init(
				{
					id: $id,
					debit_account_id: debit,
					credit_account_id: credit,
					amount: 1,
					ledger,
				},
			).code(
				10,
			),
		)
		$id = $id + 1
	}
	_ = Tb.create_transfers!($batch)
	$id
}

main! : List(Str) => Try({}, [Exit(I32)])
main! = |_args| {
	ledger = 700

	acct_id_a = Tb.id!()
	acct_id_b = Tb.id!()

	accounts = [
		Tb.Account.init({ id: acct_id_a, ledger }).code(10),
		Tb.Account.init({ id: acct_id_b, ledger }).code(10),
	]
	_ = Tb.create_accounts!(accounts)

	Stdout.line!("batch_size,batches,transfers,elapsed_ms,transfers_per_sec")

	configs = [
		# { size: 10, batches: 50 },
		# { size: 100, batches: 50 },
		{ size: 240, batches: 50 },
		# { size: 1000, batches: 50 },
		# { size: 5000, batches: 10 },
		# { size: 8189, batches: 50 },
	]

	for cfg in configs {
		# One untimed warm-up batch.
		_ = submit_batch!(
			{
				debit: acct_id_a,
				credit: acct_id_b,
				ledger,
				count: cfg.size,
				first_id: Tb.id!(),
			},
		)

		# Initialize a transfer ID and then increment so that we aren't
		# measuring Tb.id!
		var $id = Tb.id!()

		start = Utc.now!()
		for _ in 0..<cfg.batches {
			$id = submit_batch!(
				{
					debit: acct_id_a,
					credit: acct_id_b,
					ledger,
					count: cfg.size,
					first_id: $id,
				},
			)
		}
		elapsed_ns = Utc.now!().to_nanos() - start.to_nanos()

		total = cfg.size * cfg.batches
		elapsed_ms = elapsed_ns // 1_000_000
		per_sec = (total * 1_000_000_000) // elapsed_ns
		Stdout.line!("${cfg.size.to_str()},${cfg.batches.to_str()},${total.to_str()},${elapsed_ms.to_str()},${per_sec.to_str()}")
	}

	Ok({})
}
