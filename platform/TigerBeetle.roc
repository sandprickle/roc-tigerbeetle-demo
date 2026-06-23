TigerBeetle := [].{
	Client :: {}.{
		create_accounts! : Client, List(Account) => List(CreateAccountResult)

		create_transfers! : Client, List(Transfer) => List(CreateTransferResult)

		lookup_accounts! : Client, List(U128) => List(Account)

		lookup_transfers! : Client, List(U128) => List(Transfer)

		get_account_transfers! : Client, AccountFilter => List(Transfer)

		get_account_balances! : Client, AccountFilter => List(AccountBalance)

		query_accounts! : Client, QueryFilter => List(Account)

		query_transfers! : Client, QueryFilter => List(Transfer)

		## Initializes a new TigerBeetle Client.
		init! : { cluster_id : U128, addresses : Str } => Try(Client, InitErr)

		InitErr := [
			Unexpected,
			OutOfMemory,
			AddressInvalid,
			AddressLimitExceeded,
			SystemResources,
			NetworkSubsystem,
		]
	}

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
		_reserved : U32,
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

		Flags : AccountFlags
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
			init = |{ id, debit_account_id, credit_account_id, amount, ledger }| {
				id,
				debit_account_id,
				credit_account_id,
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

			Flags : TransferFlags
		}

	# `tb_account_filter_t` — selects the transfers/balances involving one account
	# for get_account_transfers! and get_account_balances!.
	AccountFilter := {
		account_id : U128,
		user_data_128 : U128,
		user_data_64 : U64,
		user_data_32 : U32,
		code : U16,
		# 58 bytes
		_reserved : (
			U16,
			U16,
			U16,
			U16,
			U16,
			U16,
			U16,
			U16,
			U16,
			U16,
			U16,
			U16,
			U16,
			U16,
			U16,
			U16,
			U16,
			U16,
			U16,
			U16,
			U16,
			U16,
			U16,
			U16,
			U16,
			U16,
			U16,
			U16,
			U16,
		),
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
	AccountBalance := {
		debits_pending : U128,
		debits_posted : U128,
		credits_pending : U128,
		credits_posted : U128,
		timestamp : U64,
		_reserved : (U64, U64, U64, U64, U64, U64, U64), # 56 bytes
	}

	# `tb_query_filter_t` — selects accounts/transfers by their secondary indexes
	# for query_accounts! and query_transfers!.
	QueryFilter := {
		user_data_128 : U128,
		user_data_64 : U64,
		user_data_32 : U32,
		ledger : U32,
		code : U16,
		_reserved : (U16, U16, U16), # 6 bytes
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

	CreateTransferResult :: {
		timestamp : U64,
		status : U32,
		_reserved : U32,
	}.{
		status_created = 0xFFFFFFFF.U32
		status_exists = 46.U32

		is_created : CreateTransferResult -> Bool
		is_created = |result| result.status == status_created

		is_ok : CreateTransferResult -> Bool
		is_ok = |result| result.status == status_created or result.status == status_exists

		timestamp : CreateTransferResult -> U64
		timestamp = |result| result.timestamp

		status : CreateTransferResult -> Status
		status = |result| match result.status {
			0xFFFFFFFF => Created
			1 => LinkedEventFailed
			2 => LinkedEventChainOpen
			3 => TimestampMustBeZero
			4 => ReservedFlag
			5 => IdMustNotBeZero
			6 => IdMustNotBeIntMax
			7 => FlagsAreMutuallyExclusive
			8 => DebitAccountIdMustNotBeZero
			9 => DebitAccountIdMustNotBeIntMax
			10 => CreditAccountIdMustNotBeZero
			11 => CreditAccountIdMustNotBeIntMax
			12 => AccountsMustBeDifferent
			13 => PendingIdMustBeZero
			14 => PendingIdMustNotBeZero
			15 => PendingIdMustNotBeIntMax
			16 => PendingIdMustBeDifferent
			17 => TimeoutReservedForPendingTransfer
			19 => LedgerMustNotBeZero
			20 => CodeMustNotBeZero
			21 => DebitAccountNotFound
			22 => CreditAccountNotFound
			23 => AccountsMustHaveTheSameLedger
			24 => TransferMustHaveTheSameLedgerAsAccounts
			25 => PendingTransferNotFound
			26 => PendingTransferNotPending
			27 => PendingTransferHasDifferentDebitAccountId
			28 => PendingTransferHasDifferentCreditAccountId
			29 => PendingTransferHasDifferentLedger
			30 => PendingTransferHasDifferentCode
			31 => ExceedsPendingTransferAmount
			32 => PendingTransferHasDifferentAmount
			33 => PendingTransferAlreadyPosted
			34 => PendingTransferAlreadyVoided
			35 => PendingTransferExpired
			36 => ExistsWithDifferentFlags
			37 => ExistsWithDifferentDebitAccountId
			38 => ExistsWithDifferentCreditAccountId
			39 => ExistsWithDifferentAmount
			40 => ExistsWithDifferentPendingId
			41 => ExistsWithDifferentUserData128
			42 => ExistsWithDifferentUserData64
			43 => ExistsWithDifferentUserData32
			44 => ExistsWithDifferentTimeout
			45 => ExistsWithDifferentCode
			46 => Exists
			47 => OverflowsDebitsPending
			48 => OverflowsCreditsPending
			49 => OverflowsDebitsPosted
			50 => OverflowsCreditsPosted
			51 => OverflowsDebits
			52 => OverflowsCredits
			53 => OverflowsTimeout
			54 => ExceedsCredits
			55 => ExceedsDebits
			56 => ImportedEventExpected
			57 => ImportedEventNotExpected
			58 => ImportedEventTimestampOutOfRange
			59 => ImportedEventTimestampMustNotAdvance
			60 => ImportedEventTimestampMustNotRegress
			61 => ImportedEventTimestampMustPostdateDebitAccount
			62 => ImportedEventTimestampMustPostdateCreditAccount
			63 => ImportedEventTimeoutMustBeZero
			64 => ClosingTransferMustBePending
			65 => DebitAccountAlreadyClosed
			66 => CreditAccountAlreadyClosed
			67 => ExistsWithDifferentLedger
			68 => IdAlreadyFailed
			_ => {
				crash "Unknown create_transfers status: ${result.status.to_str()}"
			}
		}

		Status := [
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
	}

	CreateAccountResult :: {
		timestamp : U64,
		status : U32,
		_reserved : U32,
	}.{
		status_created = 0xFFFFFFFF.U32
		status_exists = 21.U32

		is_created : CreateAccountResult -> Bool
		is_created = |result| result.status == status_created

		is_ok : CreateAccountResult -> Bool
		is_ok = |result| result.status == status_created or result.status == status_exists

		timestamp : CreateAccountResult -> U64
		timestamp = |result| result.timestamp

		status : CreateAccountResult -> Status
		status = |result| match result.status {
			0xFFFFFFFF => Created
			1 => LinkedEventFailed
			2 => LinkedEventChainOpen
			3 => TimestampMustBeZero
			4 => ReservedField
			5 => ReservedFlag
			6 => IdMustNotBeZero
			7 => IdMustNotBeIntMax
			8 => FlagsAreMutuallyExclusive
			9 => DebitsPendingMustBeZero
			10 => DebitsPostedMustBeZero
			11 => CreditsPendingMustBeZero
			12 => CreditsPostedMustBeZero
			13 => LedgerMustNotBeZero
			14 => CodeMustNotBeZero
			15 => ExistsWithDifferentFlags
			16 => ExistsWithDifferentUserData128
			17 => ExistsWithDifferentUserData64
			18 => ExistsWithDifferentUserData32
			19 => ExistsWithDifferentLedger
			20 => ExistsWithDifferentCode
			21 => Exists
			22 => ImportedEventExpected
			23 => ImportedEventNotExpected
			24 => ImportedEventTimestampOutOfRange
			25 => ImportedEventTimestampMustNotAdvance
			26 => ImportedEventTimestampMustNotRegress
			_ => {
				crash "Unknown create_accounts status: ${result.status.to_str()}"
			}
		}

		Status := [
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

	}
	# Generate a TigerBeetle time-based identifier (host-managed state keeps
	# these monotonically increasing, even within a single millisecond).
	id! : () => U128
}
