app [main!] { pf: platform "../platform/main.roc" }

import pf.Stdout
import pf.TigerBeetle

# Demonstrates creating TigerBeetle accounts from Roc.
#
# Requires a local TigerBeetle running on 127.0.0.1:3000 (cluster 0):
#   tigerbeetle format --cluster=0 --replica=0 --replica-count=1 0_0.tigerbeetle
#   tigerbeetle start --addresses=3000 0_0.tigerbeetle

main! : List(Str) => Try({}, [Exit(I32)])
main! = |_args| {
    # Two valid accounts plus one invalid (id 0) to show both result paths.
    accounts = [
        TigerBeetle.Account.init({ id: 1, ledger: 700 }).code(10),
        TigerBeetle.Account.init({ id: 2, ledger: 700 }).code(10),
        TigerBeetle.Account.init({ id: 0, ledger: 700 }).code(10),
    ]

    Stdout.line!("Creating ${accounts.len().to_str()} accounts...")

    results = TigerBeetle.create_accounts!(accounts)

    for r in results {
        line = match r.status {
            Created => "  created (timestamp=${r.timestamp.to_str()})"
            Exists => "  exists (timestamp=${r.timestamp.to_str()})"
            IdMustNotBeZero => "  error: id must not be zero"
            LedgerMustNotBeZero => "  error: ledger must not be zero"
            CodeMustNotBeZero => "  error: code must not be zero"
            _ => "  error: other"
        }
        Stdout.line!(line)
    }

    Ok({})
}
