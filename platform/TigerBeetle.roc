TigerBeetle := [].{
	Client :: {}.{

		## Create one or more `Account`s.
		##
		## [Official Docs](https://docs.tigerbeetle.com/reference/requests/create_accounts/)
		create_accounts! : Client, List(Account) => List(CreateAccountResult)

		## Create one or more `Transfers`. A successfully created transfer will
		## modify the amount fields of its debit and credit accounts.
		##
		## [Official Docs](https://docs.tigerbeetle.com/reference/requests/create_transfers/)
		create_transfers! : Client, List(Transfer) => List(CreateTransferResult)

		## Fetch one or more `Account`s by their `id`s.
		##
		## [Official Docs](https://docs.tigerbeetle.com/reference/requests/lookup_accounts/)
		lookup_accounts! : Client, List(U128) => List(Account)

		## Fetch one or more `Transfer`s by their `id`s.
		##
		## [Official Docs](https://docs.tigerbeetle.com/reference/requests/lookup_transfers/)
		lookup_transfers! : Client, List(U128) => List(Transfer)

		## Fetch `Transfer`s involving a given `Account`.
		##
		## [Official Docs](https://docs.tigerbeetle.com/reference/requests/get_account_transfers/)
		get_account_transfers! : Client, AccountFilter => List(Transfer)

		## Fetch the historical `AccountBalance`s of a given `Account`.
		##
		## [Official Docs](https://docs.tigerbeetle.com/reference/requests/get_account_balances/)
		get_account_balances! : Client, AccountFilter => List(AccountBalance)

		## Query `Account`s by the intersection of some fields and by timestamp range.
		##
		## [Official Docs](https://docs.tigerbeetle.com/reference/requests/query_accounts/)
		query_accounts! : Client, QueryFilter => List(Account)

		## Query `Transfer`s by the intersection of some fields and by timestamp range.
		##
		## [Official Docs](https://docs.tigerbeetle.com/reference/requests/query_transfers/)
		query_transfers! : Client, QueryFilter => List(Transfer)

		## Initialize a new TigerBeetle client.
		init! : { cluster_id : U128, addresses : Str } => Try(
			Client,
			[
				Unexpected,
				OutOfMemory,
				AddressInvalid,
				AddressLimitExceeded,
				SystemResources,
				NetworkSubsystem,
				..,
			],
		)
	}

	## A record storing the cumulative effect of committed `Transfer`s.
	##
	## [Official Docs](https://docs.tigerbeetle.com/reference/account/)
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
		# Opt in to declaration ordering
		_ : {},
	}.{
		init : {
			id : U128,
			ledger : U32,
			code : U16,
		} -> Account
		init = |{ id, ledger, code }| {
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
			code,
			flags: 0,
			timestamp: 0,
		}

		flags : Account, List(Flags) -> Account
		flags = |account, new_flags| {
			..account,
			flags: Flags.build(new_flags),
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

		Flags := [
			Linked,

			## Mutually exclusive wth `CreditsMustNotExceedDebits`
			DebitsMustNotExceedCredits,

			## Mutually exclusive wth `DebitsMustNotExceedCredits`
			CreditsMustNotExceedDebits,
			History,
			Imported,
			Closed,
		].{
			none = 0.U16
			linked = 1.U16
			debits_must_not_exceed_credits = 2.U16
			credits_must_not_exceed_debits = 4.U16
			history = 8.U16
			imported = 16.U16
			closed = 32.U16

			build : List(Flags) -> U16
			build = |flag_list| flag_list.fold(
				none,
				|acc, flag| acc.bitwise_or(
					match flag {
						Linked => linked
						DebitsMustNotExceedCredits =>
							debits_must_not_exceed_credits
						CreditsMustNotExceedDebits =>
							credits_must_not_exceed_debits
						History => history
						Imported => imported
						Closed => closed
					},
				),
			)
		}
	}

	## An immutable record of a financial transaction between two accounts.
	##
	## [Official Docs](https://docs.tigerbeetle.com/reference/transfer/)
	Transfer := {
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
		# Opt in to declaration ordering
		_ : {},
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

		flags : Transfer, List(Flags) -> Transfer
		flags = |transfer, new_flags| {
			..transfer,
			flags: Flags.build(new_flags),
		}

		Flags := [
			Linked,
			Pending,
			PostPendingTransfer,
			VoidPendingTransfer,
			BalancingDebit,
			BalancingCredit,
			ClosingDebit,
			ClosingCredit,
			Imported,
		].{
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

			build : List(Flags) -> U16
			build = |flag_list| flag_list.fold(
				none,
				|acc, flag| acc.bitwise_or(
					match flag {
						Linked => linked
						Pending => pending
						PostPendingTransfer => post_pending_transfer
						VoidPendingTransfer => void_pending_transfer
						BalancingDebit => balancing_debit
						BalancingCredit => balancing_credit
						ClosingDebit => closing_debit
						ClosingCredit => closing_credit
						Imported => imported
					},
				),
			)
		}
	}

	## A record storing the `Account`’s balance at a given point in time.
	##
	## Only Accounts with the flag `History` set retain historical balances.
	##
	## [Official Docs](https://docs.tigerbeetle.com/reference/account-balance/)
	AccountBalance := {
		debits_pending : U128,
		debits_posted : U128,
		credits_pending : U128,
		credits_posted : U128,
		timestamp : U64,
		_reserved : Reserved56,
	}

	## A record containing the filter parameters for querying the account
	## transfers and the account historical balances.
	##
	## [Official Docs](https://docs.tigerbeetle.com/reference/account-filter/)
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
		# Opt in to declaration ordering
		_ : {},
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

		flags : AccountFilter, List(Flags) -> AccountFilter
		flags = |filter, new_flags| {
			..filter,
			flags: Flags.build(new_flags),
		}

		Flags := [Debits, Credits].{
			none = 0.U32
			debits = 1.U32
			credits = 2.U32
			reversed = 4.U32

			build : List(Flags) -> U32
			build = |flag_list| flag_list.fold(
				none,
				|acc, flag| acc.bitwise_or(
					match flag {
						Debits => 1.U32
						Credits => 2.U32
					},
				),
			)
		}
	}

	## A record containing the filter parameters for querying accounts and
	## querying transfers.
	##
	## [Official Docs](https://docs.tigerbeetle.com/reference/query-filter/)
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

		## There are currently no valid values for `flags` other than 0
		_flags : U32,
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

	}

	## [Official Docs](https://docs.tigerbeetle.com/reference/requests/create_transfers/#result)
	CreateTransferResult :: {
		timestamp : U64,
		status : U32,
		_reserved : Reserved4,
	}.{
		status_created = 0xFFFFFFFF.U32
		status_exists = 46.U32

		is_created : CreateTransferResult -> Bool
		is_created = |result| result.status == status_created

		is_ok : CreateTransferResult -> Bool
		is_ok = |result| result.status == status_created or result.status == status_exists

		timestamp : CreateTransferResult -> U64
		timestamp = |result| result.timestamp

		status_int : CreateTransferResult -> U32
		status_int = |result| result.status

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

	## [Official Docs](https://docs.tigerbeetle.com/reference/requests/create_accounts/#result)
	CreateAccountResult :: {
		timestamp : U64,
		status : U32,
		_reserved : Reserved4,
	}.{
		status_created = 0xFFFFFFFF.U32
		status_exists = 21.U32

		is_created : CreateAccountResult -> Bool
		is_created = |result| result.status == status_created

		is_ok : CreateAccountResult -> Bool
		is_ok = |result| result.status == status_created or result.status == status_exists

		timestamp : CreateAccountResult -> U64
		timestamp = |result| result.timestamp

		status_int : CreateAccountResult -> U32
		status_int = |result| result.status

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

	## 4 byte reserved field that must always be 0
	Reserved4 :: U32.{
		from_numeral : Numeral -> Try(Reserved4, [InvalidNumeral(Str), ..])
		from_numeral = |numeral| match U8.from_numeral(numeral) {
			Ok(0) => Ok(Reserved4.(0))
			_ => Err(InvalidNumeral("reserved must be 0"))
		}
	}

	## 6 byte reserved field that must always be 0
	Reserved6 :: (U16, U16, U16).{
		from_numeral : Numeral -> Try(Reserved6, [InvalidNumeral(Str), ..])
		from_numeral = |numeral| match U8.from_numeral(numeral) {
			Ok(0) => Ok(Reserved6.(0, 0, 0))
			_ => Err(InvalidNumeral("reserved must be 0"))
		}
	}

	## 56 byte reserved field that must always be 0
	Reserved56 :: (U64, U64, U64, U64, U64, U64, U64).{
		from_numeral : Numeral -> Try(Reserved56, [InvalidNumeral(Str), ..])
		from_numeral = |numeral| match U8.from_numeral(numeral) {
			Ok(0) => Ok(Reserved56.(0, 0, 0, 0, 0, 0, 0))
			_ => Err(InvalidNumeral("reserved must be 0"))
		}
	}

	## 58 byte reserved field that must always be 0
	Reserved58 :: (U16, U16, U16, U16, U16, U16, U16, U16, U16, U16, U16, U16, U16, U16, U16, U16, U16, U16, U16, U16, U16, U16, U16, U16, U16, U16, U16, U16, U16).{
		from_numeral : Numeral -> Try(Reserved58, [InvalidNumeral(Str), ..])
		from_numeral = |numeral| match U8.from_numeral(numeral) {
			Ok(0) => Ok(
				Reserved58.(0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0),
			)
			_ => Err(InvalidNumeral("reserved must be 0"))
		}
	}

	## Generate a TigerBeetle time-based identifier.
	##
	## [Official Docs](https://docs.tigerbeetle.com/coding/data-modeling/#tigerbeetle-time-based-identifiers-recommended)
	id! : () => U128
}
