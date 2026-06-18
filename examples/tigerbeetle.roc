app [main!] { pf: platform "../platform/main.roc" }

import pf.Stdout
import pf.TigerBeetle as Tb

# Requires a local TigerBeetle running on 127.0.0.1:3000 (cluster 0):
#   tigerbeetle format --cluster=0 --replica=0 --replica-count=1 0_0.tigerbeetle
#   tigerbeetle start --addresses=3000 0_0.tigerbeetle

main! : List(Str) => Try({}, [Exit(I32)])
main! = |_args| {
	# Two valid accounts plus one invalid (id 0) to show both result paths.
	accounts = [
		Tb.Account.init({ id: 3, ledger: 700 }).code(10),
		Tb.Account.init({ id: 2, ledger: 700 }).code(10),
		Tb.Account.init({ id: 0, ledger: 700 }).code(10),
	]

	Stdout.line!("Creating ${accounts.len().to_str()} accounts...")

	results = Tb.create_accounts!(accounts)

	for { status, timestamp } in results {
		msg = match status {
			Created => "  created (timestamp=${timestamp.to_str()})"
			Exists => "  exists (timestamp=${timestamp.to_str()})"
			IdMustNotBeZero => "  error: id must not be zero"
			LedgerMustNotBeZero => "  error: ledger must not be zero"
			CodeMustNotBeZero => "  error: code must not be zero"
			_ => "  error: other"
		}
		Stdout.line!(msg)
	}

	Ok({})
}
