TigerBeetle := [].{
	AccountFlags := [].{
		none = 0.U16
		linked = 1.U16
		debits_must_not_exceed_credits = 2.U16
		credits_must_not_exceed_debits = 4.U16
		history = 8.U16
		imported = 16.U16
		closed = 32.U16
	}

	TransferFlags := [].{
		none = 0.U16
		linked = 1.U16
		pending = 2.U16
		post_pending_transfer = 4.U16
		void_pending_transfer = 8.U16
		balancing_debit = 16.U16
		balancing_credit = 32.U16
		closing_debit = 64.U16
		closing_credit = 128.U16
		imported = 256.U16
	}

	# `tb_account_filter_t.flags` is a `uint32_t`, so these constants are U32
	# (unlike AccountFlags/TransferFlags, whose struct fields are `uint16_t`).
	AccountFilterFlags := [].{
		none = 0.U32
		debits = 1.U32
		credits = 2.U32
		reversed = 4.U32
	}

	# `tb_query_filter_t.flags` is a `uint32_t`.
	QueryFilterFlags := [].{
		none = 0.U32
		reversed = 1.U32
	}

	Account := {
		id : U128,
		debits_pending : U128,
		debits_posted : U128,
		credits_pending : U128,
		credits_posted : U128,
		user_data_128 : U128,
		user_data_64 : U64,
		user_data_32 : U32,
		reserved : Reserved4,
		ledger : U32,
		code : U16,
		flags : U16,
		timestamp : U64,
	}.{
		init : {
			id : U128,
			ledger : U32,
		} -> Account
		init = |{ id, ledger }| {
			id,
			debits_pending: 0,
			debits_posted: 0,
			credits_pending: 0,
			credits_posted: 0,
			user_data_128: 0,
			user_data_64: 0,
			user_data_32: 0,
			reserved: 0,
			ledger,
			code: 0,
			flags: 0,
			timestamp: 0,
		}

		code : Account, U16 -> Account
		code = |account, code| {
			..account,
			code,
		}

		flags : Account, U16 -> Account
		flags = |account, new_flags| {
			..account,
			flags: new_flags,
		}
		user_data_128 : Account, U128 -> Account
		user_data_128 = |account, user_data_128| {
			..account,
			user_data_128,
		}
		user_data_64 : Account, U64 -> Account
		user_data_64 = |account, user_data_64| {
			..account,
			user_data_64,
		}

		user_data_32 : Account, U32 -> Account
		user_data_32 = |account, user_data_32| {
			..account,
			user_data_32,
		}

		timestamp : Account, U64 -> Account
		timestamp = |account, timestamp| {
			..account,
			timestamp,
		}

	}

	Transfer :=
		{
			id : U128,
			debit_account_id : U128,
			credit_account_id : U128,
			amount : U128,
			pending_id : U128,
			user_data_128 : U128,
			user_data_64 : U64,
			user_data_32 : U32,
			timeout : U32,
			ledger : U32,
			code : U16,
			flags : U16,
			timestamp : U64,
		}.{
			init : {
				id : U128,
				debit_account_id : U128,
				credit_account_id : U128,
				amount : U128,
				ledger : U32,
			} -> Transfer
			init = |{ id, amount, ledger }| {
				id,
				debit_account_id: 0,
				credit_account_id: 0,
				amount,
				pending_id: 0,
				user_data_128: 0,
				user_data_64: 0,
				user_data_32: 0,
				timeout: 0,
				ledger,
				code: 0,
				flags: 0,
				timestamp: 0,
			}

			debit_account_id : Transfer, U128 -> Transfer
			debit_account_id = |transfer, debit_account_id| {
				..transfer,
				debit_account_id,
			}

			credit_account_id : Transfer, U128 -> Transfer
			credit_account_id = |transfer, credit_account_id| {
				..transfer,
				credit_account_id,
			}

			pending_id : Transfer, U128 -> Transfer
			pending_id = |transfer, pending_id| {
				..transfer,
				pending_id,
			}

			user_data_128 : Transfer, U128 -> Transfer
			user_data_128 = |transfer, user_data_128| {
				..transfer,
				user_data_128,
			}

			user_data_64 : Transfer, U64 -> Transfer
			user_data_64 = |transfer, user_data_64| {
				..transfer,
				user_data_64,
			}

			user_data_32 : Transfer, U32 -> Transfer
			user_data_32 = |transfer, user_data_32| {
				..transfer,
				user_data_32,
			}

			timeout : Transfer, U32 -> Transfer
			timeout = |transfer, timeout| {
				..transfer,
				timeout,
			}

			code : Transfer, U16 -> Transfer
			code = |transfer, code| {
				..transfer,
				code,
			}

			flags : Transfer, U16 -> Transfer
			flags = |transfer, new_flags| {
				..transfer,
				flags: new_flags,
			}

		}

	# Fixed-size reserved regions that can only ever hold zero. Each opaque `bytes`
	# field matches its C struct's reserved size — a single integer, or a tuple
	# summing to it — and the (inferred) `from_numeral` lets the literal `0`
	# construct one while rejecting every other literal at compile time, so a
	# reserved field is zero-locked.
	Reserved4 :: { bytes : U32 }.{
		from_numeral = |numeral| match U8.from_numeral(numeral) {
			Ok(0) => {
				zeroed : Reserved4
				zeroed = { bytes: 0 }
				Ok(zeroed)
			}
			_ => Err(InvalidNumeral("reserved fields must be 0"))
		}
	}

	Reserved6 :: { bytes : (U32, U16) }.{
		from_numeral = |numeral| match U8.from_numeral(numeral) {
			Ok(0) => {
				zeroed : Reserved6
				zeroed = { bytes: (0, 0) }
				Ok(zeroed)
			}
			_ => Err(InvalidNumeral("reserved fields must be 0"))
		}
	}

	Reserved56 :: { bytes : (U128, U128, U128, U64) }.{
		from_numeral = |numeral| match U8.from_numeral(numeral) {
			Ok(0) => {
				zeroed : Reserved56
				zeroed = { bytes: (0, 0, 0, 0) }
				Ok(zeroed)
			}
			_ => Err(InvalidNumeral("reserved fields must be 0"))
		}
	}

	Reserved58 :: { bytes : (U128, U128, U128, U64, U16) }.{
		from_numeral = |numeral| match U8.from_numeral(numeral) {
			Ok(0) => {
				zeroed : Reserved58
				zeroed = { bytes: (0, 0, 0, 0, 0) }
				Ok(zeroed)
			}
			_ => Err(InvalidNumeral("reserved fields must be 0"))
		}
	}

	# `tb_account_filter_t` — selects the transfers/balances involving one account
	# for get_account_transfers! and get_account_balances!. `reserved` is a
	# zero-only Reserved58 mirroring the C struct's `reserved[58]` padding.
	AccountFilter := {
		account_id : U128,
		user_data_128 : U128,
		user_data_64 : U64,
		user_data_32 : U32,
		code : U16,
		reserved : Reserved58,
		timestamp_min : U64,
		timestamp_max : U64,
		limit : U32,
		flags : U32,
	}.{
		init : {
			account_id : U128,
		} -> AccountFilter
		init = |{ account_id }| {
			account_id,
			user_data_128: 0,
			user_data_64: 0,
			user_data_32: 0,
			code: 0,
			reserved: 0,
			timestamp_min: 0,
			timestamp_max: 0,
			limit: 0,
			flags: 0,
		}

		user_data_128 : AccountFilter, U128 -> AccountFilter
		user_data_128 = |filter, user_data_128| {
			..filter,
			user_data_128,
		}

		user_data_64 : AccountFilter, U64 -> AccountFilter
		user_data_64 = |filter, user_data_64| {
			..filter,
			user_data_64,
		}

		user_data_32 : AccountFilter, U32 -> AccountFilter
		user_data_32 = |filter, user_data_32| {
			..filter,
			user_data_32,
		}

		code : AccountFilter, U16 -> AccountFilter
		code = |filter, code| {
			..filter,
			code,
		}

		timestamp_min : AccountFilter, U64 -> AccountFilter
		timestamp_min = |filter, timestamp_min| {
			..filter,
			timestamp_min,
		}

		timestamp_max : AccountFilter, U64 -> AccountFilter
		timestamp_max = |filter, timestamp_max| {
			..filter,
			timestamp_max,
		}

		limit : AccountFilter, U32 -> AccountFilter
		limit = |filter, limit| {
			..filter,
			limit,
		}

		flags : AccountFilter, U32 -> AccountFilter
		flags = |filter, new_flags| {
			..filter,
			flags: new_flags,
		}
	}

	# `tb_account_balance_t` — a point-in-time balance returned by
	# get_account_balances! (only for accounts opened with the `history` flag).
	# `reserved` is a zero-only Reserved56 mirroring the C struct's `reserved[56]`.
	AccountBalance : {
		debits_pending : U128,
		debits_posted : U128,
		credits_pending : U128,
		credits_posted : U128,
		timestamp : U64,
		reserved : Reserved56,
	}

	# `tb_query_filter_t` — selects accounts/transfers by their secondary indexes
	# for query_accounts! and query_transfers!. `reserved` is a zero-only
	# Reserved6 mirroring the C struct's `reserved[6]` padding.
	QueryFilter := {
		user_data_128 : U128,
		user_data_64 : U64,
		user_data_32 : U32,
		ledger : U32,
		code : U16,
		reserved : Reserved6,
		timestamp_min : U64,
		timestamp_max : U64,
		limit : U32,
		flags : U32,
	}.{
		init : () -> QueryFilter
		init = || {
			user_data_128: 0,
			user_data_64: 0,
			user_data_32: 0,
			ledger: 0,
			code: 0,
			reserved: 0,
			timestamp_min: 0,
			timestamp_max: 0,
			limit: 0,
			flags: 0,
		}

		user_data_128 : QueryFilter, U128 -> QueryFilter
		user_data_128 = |filter, user_data_128| {
			..filter,
			user_data_128,
		}

		user_data_64 : QueryFilter, U64 -> QueryFilter
		user_data_64 = |filter, user_data_64| {
			..filter,
			user_data_64,
		}

		user_data_32 : QueryFilter, U32 -> QueryFilter
		user_data_32 = |filter, user_data_32| {
			..filter,
			user_data_32,
		}

		ledger : QueryFilter, U32 -> QueryFilter
		ledger = |filter, ledger| {
			..filter,
			ledger,
		}

		code : QueryFilter, U16 -> QueryFilter
		code = |filter, code| {
			..filter,
			code,
		}

		timestamp_min : QueryFilter, U64 -> QueryFilter
		timestamp_min = |filter, timestamp_min| {
			..filter,
			timestamp_min,
		}

		timestamp_max : QueryFilter, U64 -> QueryFilter
		timestamp_max = |filter, timestamp_max| {
			..filter,
			timestamp_max,
		}

		limit : QueryFilter, U32 -> QueryFilter
		limit = |filter, limit| {
			..filter,
			limit,
		}

		flags : QueryFilter, U32 -> QueryFilter
		flags = |filter, new_flags| {
			..filter,
			flags: new_flags,
		}
	}

	CreateAccountStatus : [
		Created,
		LinkedEventFailed,
		LinkedEventChainOpen,
		TimestampMustBeZero,
		ReservedField,
		ReservedFlag,
		IdMustNotBeZero,
		IdMustNotBeIntMax,
		FlagsAreMutuallyExclusive,
		DebitsPendingMustBeZero,
		DebitsPostedMustBeZero,
		CreditsPendingMustBeZero,
		CreditsPostedMustBeZero,
		LedgerMustNotBeZero,
		CodeMustNotBeZero,
		ExistsWithDifferentFlags,
		ExistsWithDifferentUserData128,
		ExistsWithDifferentUserData64,
		ExistsWithDifferentUserData32,
		ExistsWithDifferentLedger,
		ExistsWithDifferentCode,
		Exists,
		ImportedEventExpected,
		ImportedEventNotExpected,
		ImportedEventTimestampOutOfRange,
		ImportedEventTimestampMustNotAdvance,
		ImportedEventTimestampMustNotRegress,
	]

	CreateTransferStatus : [
		Created,
		LinkedEventFailed,
		LinkedEventChainOpen,
		TimestampMustBeZero,
		ReservedFlag,
		IdMustNotBeZero,
		IdMustNotBeIntMax,
		FlagsAreMutuallyExclusive,
		DebitAccountIdMustNotBeZero,
		DebitAccountIdMustNotBeIntMax,
		CreditAccountIdMustNotBeZero,
		CreditAccountIdMustNotBeIntMax,
		AccountsMustBeDifferent,
		PendingIdMustBeZero,
		PendingIdMustNotBeZero,
		PendingIdMustNotBeIntMax,
		PendingIdMustBeDifferent,
		TimeoutReservedForPendingTransfer,
		LedgerMustNotBeZero,
		CodeMustNotBeZero,
		DebitAccountNotFound,
		CreditAccountNotFound,
		AccountsMustHaveTheSameLedger,
		TransferMustHaveTheSameLedgerAsAccounts,
		PendingTransferNotFound,
		PendingTransferNotPending,
		PendingTransferHasDifferentDebitAccountId,
		PendingTransferHasDifferentCreditAccountId,
		PendingTransferHasDifferentLedger,
		PendingTransferHasDifferentCode,
		ExceedsPendingTransferAmount,
		PendingTransferHasDifferentAmount,
		PendingTransferAlreadyPosted,
		PendingTransferAlreadyVoided,
		PendingTransferExpired,
		ExistsWithDifferentFlags,
		ExistsWithDifferentDebitAccountId,
		ExistsWithDifferentCreditAccountId,
		ExistsWithDifferentAmount,
		ExistsWithDifferentPendingId,
		ExistsWithDifferentUserData128,
		ExistsWithDifferentUserData64,
		ExistsWithDifferentUserData32,
		ExistsWithDifferentTimeout,
		ExistsWithDifferentCode,
		Exists,
		OverflowsDebitsPending,
		OverflowsCreditsPending,
		OverflowsDebitsPosted,
		OverflowsCreditsPosted,
		OverflowsDebits,
		OverflowsCredits,
		OverflowsTimeout,
		ExceedsCredits,
		ExceedsDebits,
		ImportedEventExpected,
		ImportedEventNotExpected,
		ImportedEventTimestampOutOfRange,
		ImportedEventTimestampMustNotAdvance,
		ImportedEventTimestampMustNotRegress,
		ImportedEventTimestampMustPostdateDebitAccount,
		ImportedEventTimestampMustPostdateCreditAccount,
		ImportedEventTimeoutMustBeZero,
		ClosingTransferMustBePending,
		DebitAccountAlreadyClosed,
		CreditAccountAlreadyClosed,
		ExistsWithDifferentLedger,
		IdAlreadyFailed,
	]

	create_accounts! : List(Account) => List(
		{
			timestamp : U64,
			status : CreateAccountStatus,
		},
	)

	create_transfers! : List(Transfer) => List(
		{
			timestamp : U64,
			status : CreateTransferStatus,
		},
	)
	create_transfers! = |_transfers| ...

	lookup_accounts! : List(U128) => List(Account)
	lookup_accounts! = |_ids| ...

	lookup_transfers! : List(U128) => List(Transfer)
	lookup_transfers! = |_ids| ...

	get_account_transfers! : AccountFilter => List(Transfer)
	get_account_transfers! = |_filter| ...

	get_account_balances! : AccountFilter => List(AccountBalance)
	get_account_balances! = |_filter| ...

	query_accounts! : QueryFilter => List(Account)
	query_accounts! = |_filter| ...

	query_transfers! : QueryFilter => List(Transfer)
	query_transfers! = |_filter| ...

	# Generate a TigerBeetle time-based identifier (host-managed state keeps
	# these monotonically increasing, even within a single millisecond).
	id! : () => U128
}
