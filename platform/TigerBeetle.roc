TigerBeetle := [].{
	AccountFlags := U16.{
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

	AccountFilterFlags := [].{
		none = 0.U16
		debits = 1.U16
		credits = 2.U16
		reversed = 4.U16
	}

	QueryFilterFlags := [].{
		none = 0.U16
		reversed = 1.U16
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
		reserved : I32,
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

	create_accounts! : List(Account) => List(
		{
			status : CreateAccountStatus,
			timestamp : U64,
		},
	)

	# Generate a TigerBeetle time-based identifier (host-managed state keeps
	# these monotonically increasing, even within a single millisecond).
	id! : () => U128
}
