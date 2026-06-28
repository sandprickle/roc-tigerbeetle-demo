app [main!] { pf: platform "../platform/main.roc" }

import pf.Stdout
import pf.Stderr
import pf.TigerBeetle as Tb exposing [
	Transfer,
	Account,
	AccountFilter,
	QueryFilter,
]

# Full integration test for TigerBeetle.Client.
#
# Drives every hosted function against a LIVE cluster on 127.0.0.1:3000
# (cluster 0) and checks both happy paths and failure modes — invalid
# accounts/transfers, enforced balance constraints, and the history-flag
# behaviour of get_account_balances!.
#
# This is a pure-Roc test harness: each scenario returns a labelled
# { name, passed, detail } record, `report!` prints PASS/FAIL per scenario plus
# an "N passed, M failed" summary, and `main!` exits non-zero if anything failed.
# (The host's `expect` hook only warns, so we report and drive the exit code in
# Roc instead — see the plan/README.)
#
# How to run:
#   1. Build the native host:   zig build native
#   2. Start a cluster:         ./start_tb.sh        (separate terminal)
#   3. Run:                     roc examples/integration_test.roc
#
# Expected create-result status codes are taken from the official docs, mirrored
# in platform/TigerBeetle.roc:
#   https://docs.tigerbeetle.com/reference/requests/create_accounts/#result
#   https://docs.tigerbeetle.com/reference/requests/create_transfers/#result

main! : List(Str) => Try({}, [Exit(I32)])
main! = |_args| {
	Stdout.line!("TigerBeetle.Client integration test")
	Stdout.line!("Connecting to 127.0.0.1:3000 (cluster 0)...")

	client = Tb.Client.init!({ cluster_id: 0, addresses: "3000" }).map_err!(
		|e| {
			Stderr.line!("Failed to connect: ${Str.inspect(e)}")
			Exit(1)
		},
	)?

	ledger = 700

	# Fresh ids every run so re-runs against the same cluster never collide.
	id_a = Tb.id!()
	id_b = Tb.id!()
	id_c = Tb.id!()
	id_d = Tb.id!()
	id_e = Tb.id!()
	id_f = Tb.id!()

	# Fixture accounts:
	#   A, B - plain, History (balance snapshots + happy transfer)
	#   C    - debits_must_not_exceed_credits (ExceedsCredits test)
	#   D    - credits_must_not_exceed_debits (ExceedsDebits test)
	#   E    - no History (negative get_account_balances! test)
	#   F    - different ledger (AccountsMustHaveTheSameLedger test)
	fixtures = client.create_accounts!(
		[
			Account.init({ id: id_a, ledger, code: 10 }).flags([History]),
			Account.init({ id: id_b, ledger, code: 10 }).flags([History]),
			Account.init({ id: id_c, ledger, code: 10 }).flags([DebitsMustNotExceedCredits]),
			Account.init({ id: id_d, ledger, code: 10 }).flags([CreditsMustNotExceedDebits]),
			Account.init({ id: id_e, ledger, code: 10 }),
			Account.init({ id: id_f, ledger: 701, code: 10 }),
		],
	)

	# Happy transfer A -> B, reused by lookup/transfers/balances checks.
	txn_ab = Tb.id!()
	txn_ab_results = client.create_transfers!(
		[
			Transfer.init(
				{
					id: txn_ab,
					debit_account_id: id_a,
					credit_account_id: id_b,
					amount: 100,
					ledger,
				},
			).code(10),
		],
	)

	# Ids that are never created, for the not-found checks.
	ghost_debit = Tb.id!()
	ghost_credit = Tb.id!()

	# --- Scenarios (each yields one { name, passed, detail } record) ---------

	r_init = { name: "init! connect to live cluster", passed: Bool.True, detail: "connected" }
	r_ids = check_distinct_ids!(client)
	r_accts = check_accounts_created!(client, fixtures, [id_a, id_b, id_c, id_d, id_e, id_f])

	# create_accounts! failure modes (single bad account each).
	r_acct_id0 = check_acct_status!(client, Account.init({ id: 0, ledger, code: 10 }), "create_accounts! rejects id 0", 6)
	r_acct_led0 = check_acct_status!(client, Account.init({ id: Tb.id!(), ledger: 0, code: 10 }), "create_accounts! rejects ledger 0", 13)
	r_acct_code0 = check_acct_status!(client, Account.init({ id: Tb.id!(), ledger, code: 0 }), "create_accounts! rejects code 0", 14)
	r_acct_ts = check_acct_status!(client, Account.init({ id: Tb.id!(), ledger, code: 10 }).timestamp(123), "create_accounts! rejects non-zero timestamp", 3)
	r_acct_flags = check_acct_status!(client, Account.init({ id: Tb.id!(), ledger, code: 10 }).flags([DebitsMustNotExceedCredits, CreditsMustNotExceedDebits]), "create_accounts! rejects mutually exclusive flags", 8)
	# Exists: create once (inline), then assert the second create returns Exists.
	exists_acct = Account.init({ id: Tb.id!(), ledger, code: 10 })
	_pre_acct = client.create_accounts!([exists_acct])
	r_acct_exists = check_acct_status!(client, exists_acct, "create_accounts! second create returns Exists", 21)

	# create_transfers! happy path + lookups + balance updates.
	r_txn = check_transfer_happy!(client, txn_ab, id_a, id_b, txn_ab_results)

	# create_transfers! failure modes (single bad transfer each).
	r_txn_id0 = check_txn_status!(client, Transfer.init({ id: 0, debit_account_id: id_a, credit_account_id: id_b, amount: 1, ledger }).code(10), "create_transfers! rejects id 0", 5)
	r_txn_deb0 = check_txn_status!(client, Transfer.init({ id: Tb.id!(), debit_account_id: id_a, credit_account_id: id_b, amount: 1, ledger }).code(10).debit_account_id(0), "create_transfers! rejects debit_account_id 0", 8)
	r_txn_cred0 = check_txn_status!(client, Transfer.init({ id: Tb.id!(), debit_account_id: id_a, credit_account_id: id_b, amount: 1, ledger }).code(10).credit_account_id(0), "create_transfers! rejects credit_account_id 0", 10)
	r_txn_same = check_txn_status!(client, Transfer.init({ id: Tb.id!(), debit_account_id: id_a, credit_account_id: id_a, amount: 1, ledger }).code(10), "create_transfers! rejects same debit/credit account", 12)
	r_txn_led0 = check_txn_status!(client, Transfer.init({ id: Tb.id!(), debit_account_id: id_a, credit_account_id: id_b, amount: 1, ledger: 0 }).code(10), "create_transfers! rejects ledger 0", 19)
	r_txn_code0 = check_txn_status!(client, Transfer.init({ id: Tb.id!(), debit_account_id: id_a, credit_account_id: id_b, amount: 1, ledger }), "create_transfers! rejects code 0", 20)
	# Note: no transfer-side TimestampMustBeZero check — Transfer exposes no
	# `timestamp` builder (unlike Account), and the field is opaque outside the
	# platform module. The account-side timestamp check (r_acct_ts) covers it.
	r_txn_flags = check_txn_status!(client, Transfer.init({ id: Tb.id!(), debit_account_id: id_a, credit_account_id: id_b, amount: 1, ledger }).code(10).flags([Pending, PostPendingTransfer]), "create_transfers! rejects mutually exclusive flags", 7)
	r_txn_deb_nf = check_txn_status!(client, Transfer.init({ id: Tb.id!(), debit_account_id: ghost_debit, credit_account_id: id_b, amount: 1, ledger }).code(10), "create_transfers! rejects unknown debit account", 21)
	r_txn_cred_nf = check_txn_status!(client, Transfer.init({ id: Tb.id!(), debit_account_id: id_a, credit_account_id: ghost_credit, amount: 1, ledger }).code(10), "create_transfers! rejects unknown credit account", 22)
	r_txn_ledmix = check_txn_status!(client, Transfer.init({ id: Tb.id!(), debit_account_id: id_a, credit_account_id: id_f, amount: 1, ledger }).code(10), "create_transfers! rejects accounts on different ledgers", 23)
	# Exists: create once (inline), then assert the second create returns Exists.
	exists_txn = Transfer.init({ id: Tb.id!(), debit_account_id: id_a, credit_account_id: id_b, amount: 1, ledger }).code(10)
	_pre_txn = client.create_transfers!([exists_txn])
	r_txn_exists = check_txn_status!(client, exists_txn, "create_transfers! second create returns Exists", 46)

	# Enforced balance constraints (fresh accounts have zero balances).
	r_exc_credits = check_txn_status!(client, Transfer.init({ id: Tb.id!(), debit_account_id: id_c, credit_account_id: id_a, amount: 1, ledger }).code(10), "debits_must_not_exceed_credits enforced (ExceedsCredits)", 54)
	r_exc_debits = check_txn_status!(client, Transfer.init({ id: Tb.id!(), debit_account_id: id_a, credit_account_id: id_d, amount: 1, ledger }).code(10), "credits_must_not_exceed_debits enforced (ExceedsDebits)", 55)

	# Reads / queries.
	r_la_miss = check_lookup_account_miss!(client)
	r_lt_miss = check_lookup_transfer_miss!(client)
	r_gat = check_get_account_transfers!(client, id_a, id_e)
	r_bal = check_balances_history!(client, id_a, id_e)
	r_qa = check_query_accounts!(client, ledger)
	r_qt = check_query_transfers!(client, ledger)

	# MUST be last: re-initializing resets the host's single global client.
	r_init_fail = check_init_fails!(client)

	results = [
		r_init,
		r_ids,
		r_accts,
		r_acct_id0,
		r_acct_led0,
		r_acct_code0,
		r_acct_ts,
		r_acct_flags,
		r_acct_exists,
		r_txn,
		r_txn_id0,
		r_txn_deb0,
		r_txn_cred0,
		r_txn_same,
		r_txn_led0,
		r_txn_code0,
		r_txn_flags,
		r_txn_deb_nf,
		r_txn_cred_nf,
		r_txn_ledmix,
		r_txn_exists,
		r_exc_credits,
		r_exc_debits,
		r_la_miss,
		r_lt_miss,
		r_gat,
		r_bal,
		r_qa,
		r_qt,
		r_init_fail,
	]

	report!(results)
}

# --- Report ----------------------------------------------------------------

report! = |results| {
	Stdout.line!("")
	for r in results {
		if r.passed {
			Stdout.line!("PASS  ${r.name}")
		} else {
			Stdout.line!("FAIL  ${r.name}")
			Stdout.line!("        ${r.detail}")
		}
	}

	total = List.len(results)
	passed_count = List.len(List.keep_if(results, |r| r.passed))
	failed_count = total - passed_count

	Stdout.line!("")
	Stdout.line!("${passed_count.to_str()} passed, ${failed_count.to_str()} failed (of ${total.to_str()})")

	if failed_count > 0 {
		Err(Exit(1))
	} else {
		Ok({})
	}
}

# --- Generic check helpers -------------------------------------------------

# Submit a single account and assert the result status code.
check_acct_status! = |client, account, name, expected| {
	results = client.create_accounts!([account])
	n = List.len(results)
	code = first_account_code(results)
	passed = (code == expected) and (n == 1)
	detail = "want ${expected.to_str()} (${describe_acct(expected)}), got ${code.to_str()} (${describe_acct(code)}); results=${n.to_str()}"
	{ name, passed, detail }
}

# Submit a single transfer and assert the result status code.
check_txn_status! = |client, transfer, name, expected| {
	results = client.create_transfers!([transfer])
	n = List.len(results)
	code = first_transfer_code(results)
	passed = (code == expected) and (n == 1)
	detail = "want ${expected.to_str()} (${describe_txn(expected)}), got ${code.to_str()} (${describe_txn(code)}); results=${n.to_str()}"
	{ name, passed, detail }
}

# --- Happy-path / read helpers ---------------------------------------------

check_distinct_ids! = |_client| {
	a = Tb.id!()
	b = Tb.id!()
	passed = (a != b) and (a != 0) and (b != 0)
	{ name: "id! returns distinct non-zero ids", passed, detail: "a=${a.to_str()} b=${b.to_str()}" }
}

# All fixture accounts created, and lookup_accounts! finds them all.
# Also exercises the result accessors is_created!/is_ok!/timestamp! on the
# first result.
check_accounts_created! = |client, fixtures, ids| {
	all_created = List.all(fixtures, |r| r.status_int() == 0xFFFFFFFF)
	first_ok =
		match List.first(fixtures) {
			Ok(r) => r.is_created() and r.is_ok() and (r.timestamp() != 0)
			Err(_) => Bool.False
		}
	looked = client.lookup_accounts!(ids)
	found = List.len(looked) == List.len(ids)
	passed = all_created and first_ok and found
	detail = "all_created=${bool_str(all_created)} first_ok=${bool_str(first_ok)} looked=${List.len(looked).to_str()}/${List.len(ids).to_str()}"
	{ name: "create_accounts! happy path (6 fixtures) + lookup_accounts!", passed, detail }
}

# A->B transfer was Created, lookup_transfers! finds it, and both balances moved.
# Exercises is_created/is_ok/timestamp/status/status_int on the transfer result.
check_transfer_happy! = |client, txn_id, id_a, id_b, create_results| {
	match List.first(create_results) {
		Ok(r) => {
			created = r.is_created()
			ok = r.is_ok()
			ts = r.timestamp()
			code = r.status_int()
			status_label = if created Str.inspect(r.status()) else describe_txn(code)
			looked = client.lookup_transfers!([txn_id])
			found = List.len(looked) == 1
			a = client.lookup_accounts!([id_a])
			b = client.lookup_accounts!([id_b])
			a_debits =
				match List.first(a) {
					Ok(acct) => acct.debits_posted
					Err(_) => 0
				}
			b_credits =
				match List.first(b) {
					Ok(acct) => acct.credits_posted
					Err(_) => 0
				}
			passed = created and ok and (ts != 0) and (code == 0xFFFFFFFF) and found and (a_debits == 100) and (b_credits == 100)
			detail = "code=${code.to_str()} (${status_label}) ts=${ts.to_str()} found=${bool_str(found)} a.debits_posted=${a_debits.to_str()} b.credits_posted=${b_credits.to_str()}"
			{ name: "create_transfers! happy (A->B 100) + lookup_transfers! + balances", passed, detail }
		}
		Err(_) => {
			{ name: "create_transfers! happy (A->B 100) + lookup_transfers! + balances", passed: Bool.False, detail: "no create result returned" }
		}
	}
}

check_lookup_account_miss! = |client| {
	ghost = Tb.id!()
	looked = client.lookup_accounts!([ghost])
	passed = List.len(looked) == 0
	{ name: "lookup_accounts! returns empty for unknown id", passed, detail: "len=${List.len(looked).to_str()}" }
}

check_lookup_transfer_miss! = |client| {
	ghost = Tb.id!()
	looked = client.lookup_transfers!([ghost])
	passed = List.len(looked) == 0
	{ name: "lookup_transfers! returns empty for unknown id", passed, detail: "len=${List.len(looked).to_str()}" }
}

check_get_account_transfers! = |client, id_a, id_e| {
	a_filter = AccountFilter.init({ account_id: id_a }).limit(10).flags([Debits, Credits])
	a_txns = client.get_account_transfers!(a_filter)
	e_filter = AccountFilter.init({ account_id: id_e }).limit(10).flags([Debits, Credits])
	e_txns = client.get_account_transfers!(e_filter)
	passed = (List.len(a_txns) >= 1) and (List.len(e_txns) == 0)
	{ name: "get_account_transfers! (A has >=1, E has 0)", passed, detail: "A=${List.len(a_txns).to_str()} E=${List.len(e_txns).to_str()}" }
}

# get_account_balances! only returns rows for accounts created with History.
check_balances_history! = |client, id_a, id_e| {
	a_filter = AccountFilter.init({ account_id: id_a }).limit(10).flags([Debits, Credits])
	a_bals = client.get_account_balances!(a_filter)
	e_filter = AccountFilter.init({ account_id: id_e }).limit(10).flags([Debits, Credits])
	e_bals = client.get_account_balances!(e_filter)
	passed = (List.len(a_bals) >= 1) and (List.len(e_bals) == 0)
	{ name: "get_account_balances! needs History flag (A>=1, E=0)", passed, detail: "A=${List.len(a_bals).to_str()} E=${List.len(e_bals).to_str()}" }
}

check_query_accounts! = |client, ledger| {
	hit = client.query_accounts!(QueryFilter.init().ledger(ledger).code(10).limit(100))
	miss = client.query_accounts!(QueryFilter.init().ledger(999999).code(10).limit(100))
	passed = (List.len(hit) >= 1) and (List.len(miss) == 0)
	{ name: "query_accounts! (ledger 700/code 10 >=1, ledger 999999 =0)", passed, detail: "hit=${List.len(hit).to_str()} miss=${List.len(miss).to_str()}" }
}

check_query_transfers! = |client, ledger| {
	hit = client.query_transfers!(QueryFilter.init().ledger(ledger).code(10).limit(100))
	miss = client.query_transfers!(QueryFilter.init().ledger(999999).code(10).limit(100))
	passed = (List.len(hit) >= 1) and (List.len(miss) == 0)
	{ name: "query_transfers! (ledger 700/code 10 >=1, ledger 999999 =0)", passed, detail: "hit=${List.len(hit).to_str()} miss=${List.len(miss).to_str()}" }
}

# Runs LAST: a second init! with an invalid address must fail (and resets the
# host's global client, so nothing using the client may run after this).
check_init_fails! = |_client| {
	result = Tb.Client.init!({ cluster_id: 0, addresses: "this-is-not-a-valid-address" })
	passed =
		match result {
			Ok(_) => Bool.False
			Err(_) => Bool.True
		}
	{ name: "init! returns Err for invalid address (runs last; resets client)", passed, detail: "expected Err(_)" }
}

# --- Pure helpers ----------------------------------------------------------

first_account_code = |results|
	match List.first(results) {
		Ok(r) => r.status_int()
		Err(_) => 0
	}

first_transfer_code = |results|
	match List.first(results) {
		Ok(r) => r.status_int()
		Err(_) => 0
	}

bool_str = |b| if b "yes" else "no"

# Crash-free labels for the create-account result codes we assert on.
describe_acct = |code|
	match code {
		0xFFFFFFFF => "Created"
		3 => "TimestampMustBeZero"
		6 => "IdMustNotBeZero"
		8 => "FlagsAreMutuallyExclusive"
		13 => "LedgerMustNotBeZero"
		14 => "CodeMustNotBeZero"
		21 => "Exists"
		_ => "other"
	}

# Crash-free labels for the create-transfer result codes we assert on.
describe_txn = |code|
	match code {
		0xFFFFFFFF => "Created"
		3 => "TimestampMustBeZero"
		5 => "IdMustNotBeZero"
		7 => "FlagsAreMutuallyExclusive"
		8 => "DebitAccountIdMustNotBeZero"
		10 => "CreditAccountIdMustNotBeZero"
		12 => "AccountsMustBeDifferent"
		19 => "LedgerMustNotBeZero"
		20 => "CodeMustNotBeZero"
		21 => "DebitAccountNotFound"
		22 => "CreditAccountNotFound"
		23 => "AccountsMustHaveTheSameLedger"
		46 => "Exists"
		54 => "ExceedsCredits"
		55 => "ExceedsDebits"
		_ => "other"
	}
