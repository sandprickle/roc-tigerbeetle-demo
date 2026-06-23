app [main!] { pf: platform "../platform/main.roc" }

import pf.Stdout
import pf.Stderr
import pf.TigerBeetle as Tb exposing [Account]

# Requires a local TigerBeetle running on 127.0.0.1:3000 (cluster 0):
#   tigerbeetle format --cluster=0 --replica=0 --replica-count=1 0_0.tigerbeetle
#   tigerbeetle start --addresses=3000 0_0.tigerbeetle

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

	Ok({})
}

demo! : Tb.Client => {}
demo! = |client| {
	# Two valid accounts plus one invalid (id 0) to show both result paths.
	accounts = [
		Account.init({ id: Tb.id!(), ledger: 700 }).code(10),
		Account.init({ id: Tb.id!(), ledger: 700 }).code(10),
		Account.init({ id: 0, ledger: 700 }).code(10),
	]

	Stdout.line!("Creating ${accounts.len().to_str()} accounts...")

	accounts.for_each!(
		|account| {
			Stdout.line!("  account ${account.id.to_str()}")
		},
	)

	results = client.create_accounts!(accounts)

	for result in results {
		timestamp = result.timestamp()
		status = result.status()

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

}
