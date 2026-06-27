app [main!] { pf: platform "../platform/main.roc" }

import pf.Stdout
import pf.Stderr
import pf.TigerBeetle as Tb exposing [
	Transfer,
	Account,
	AccountFilter,
	QueryFilter,
]

# Exercises every TigerBeetle hosted function against a live cluster on
# 127.0.0.1:3000 (cluster 0). See start_tb.sh.

main! : List(Str) => Try({}, [Exit(I32)])
main! = |_args| {
	Stdout.line!("Connecting to TigerBeetle...")
	client = Tb.Client.init!({ cluster_id: 0, addresses: "3000" }).map_err!(
		|e| {
			Stderr.line!("Failed to connect: ${Str.inspect(e)}")
			Exit(1)
		},
	)?

	demo!(client)
}

demo! : Tb.Client => Try({}, _)
demo! = |tb| {
	ledger = 700

	id_a = Tb.id!()
	id_b = Tb.id!()

	# Open two accounts with the `history` flag so balance snapshots are kept.
	accounts = [
		Account.init({ id: id_a, ledger, code: 10 }).flags([History]),
		Account.init({ id: id_b, ledger, code: 10 }).flags([History]),
	]

	Stdout.line!("Accounts: ${Str.inspect(accounts)}")
	for result in tb.create_accounts!(accounts) {
		Stdout.line!(
			"Account: ${result.timestamp().to_str()} ${Str.inspect(result.status())}",
		)
	}

	# Move 100 from A to B.
	transfer_id = Tb.id!()
	transfers = [
		Transfer.init(
			{
				id: transfer_id,
				debit_account_id: id_a,
				credit_account_id: id_b,
				amount: 100,
				ledger,
			},
		).code(10),
	]
	Stdout.line!("Transfers:")
	Stdout.line!("${Str.inspect(transfers)}")
	for result in tb.create_transfers!(transfers) {
		Stdout.line!(
			"Transfer: ${result.timestamp().to_str()} ${Str.inspect(result.status())}",
		)
	}

	# Look the accounts back up by id.
	looked = tb.lookup_accounts!([id_a, id_b])
	Stdout.line!("lookup_accounts -> ${looked.len().to_str()}")
	for acct in looked {
		Stdout.line!("  ${acct.id.to_str()} debits=${acct.debits_posted.to_str()} credits=${acct.credits_posted.to_str()}")
	}

	# Look the transfer back up by id.
	ltrans = tb.lookup_transfers!([transfer_id])
	Stdout.line!("lookup_transfers -> ${ltrans.len().to_str()}")
	for t in ltrans {
		Stdout.line!("  ${t.id.to_str()} amount=${t.amount.to_str()}")
	}

	# Every transfer involving account A (debits or credits).
	a_filter = AccountFilter.init({ account_id: id_a })
		.limit(10)
		.flags([Debits, Credits])
	Stdout.line!("get_account_transfers -> ${tb.get_account_transfers!(a_filter).len().to_str()}")

	# Balance snapshots for account A.
	bals = tb.get_account_balances!(a_filter)
	Stdout.line!("get_account_balances -> ${bals.len().to_str()}")
	for b in bals {
		Stdout.line!("  credits=${b.credits_posted.to_str()} debits=${b.debits_posted.to_str()}")
	}

	# Secondary-index queries by ledger + code.
	q = QueryFilter.init().ledger(ledger).code(10).limit(10)
	Stdout.line!("query_accounts -> ${tb.query_accounts!(q).len().to_str()}")
	Stdout.line!("query_transfers -> ${tb.query_transfers!(q).len().to_str()}")

	Ok({})
}
