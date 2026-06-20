app [main!] { pf: platform "../platform/main.roc" }

import pf.Stdout
import pf.TigerBeetle as Tb

# Exercises every TigerBeetle hosted function against a live cluster on
# 127.0.0.1:3000 (cluster 0). See start_tb.sh.

main! : List(Str) => Try({}, [Exit(I32)])
main! = |_args| {
	ledger = 700

	id_a = Tb.id!()
	id_b = Tb.id!()

	# Open two accounts with the `history` flag so balance snapshots are kept.
	accounts = [
		Tb.Account.init({ id: id_a, ledger }).code(10).flags(Tb.AccountFlags.history),
		Tb.Account.init({ id: id_b, ledger }).code(10).flags(Tb.AccountFlags.history),
	]
	for { status } in Tb.create_accounts!(accounts) {
		Stdout.line!(
			match status {
				Created => "account created"
				Exists => "account exists"
				_ => "account error"
			},
		)
	}

	# Move 100 from A to B.
	transfer_id = Tb.id!()
	transfers = [
		Tb.Transfer.init(
			{
				id: transfer_id,
				debit_account_id: id_a,
				credit_account_id: id_b,
				amount: 100,
				ledger,
			},
		).code(10),
	]
	for { status } in Tb.create_transfers!(transfers) {
		Stdout.line!(
			match status {
				Created => "transfer created"
				DebitAccountNotFound => "debit account not found"
				CreditAccountNotFound => "credit account not found"
				ExceedsCredits => "exceeds credits"
				ExceedsDebits => "exceeds debits"
				Exists => "transfer exists"
				_ => "transfer error"
			},
		)
	}

	# Look the accounts back up by id.
	looked = Tb.lookup_accounts!([id_a, id_b])
	Stdout.line!("lookup_accounts -> ${looked.len().to_str()}")
	for acct in looked {
		Stdout.line!("  ${acct.id.to_str()} debits=${acct.debits_posted.to_str()} credits=${acct.credits_posted.to_str()}")
	}

	# Look the transfer back up by id.
	ltrans = Tb.lookup_transfers!([transfer_id])
	Stdout.line!("lookup_transfers -> ${ltrans.len().to_str()}")
	for t in ltrans {
		Stdout.line!("  ${t.id.to_str()} amount=${t.amount.to_str()}")
	}

	# Every transfer involving account A (debits or credits).
	a_filter = Tb.AccountFilter.init({ account_id: id_a })
		.limit(10)
		.flags(Tb.AccountFilterFlags.debits + Tb.AccountFilterFlags.credits)
	Stdout.line!("get_account_transfers -> ${Tb.get_account_transfers!(a_filter).len().to_str()}")

	# Balance snapshots for account A.
	bals = Tb.get_account_balances!(a_filter)
	Stdout.line!("get_account_balances -> ${bals.len().to_str()}")
	for b in bals {
		Stdout.line!("  credits=${b.credits_posted.to_str()} debits=${b.debits_posted.to_str()}")
	}

	# Secondary-index queries by ledger + code.
	q = Tb.QueryFilter.init().ledger(ledger).code(10).limit(10)
	Stdout.line!("query_accounts -> ${Tb.query_accounts!(q).len().to_str()}")
	Stdout.line!("query_transfers -> ${Tb.query_transfers!(q).len().to_str()}")

	Ok({})
}
