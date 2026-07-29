
Host := [].{
	posix_time! : () => I128

	tb_client_init! : { cluster_id : U128, addresses : Str } => Try(
		{},
		[
			Unexpected,
			OutOfMemory,
			AddressInvalid,
			AddressLimitExceeded,
			SystemResources,
			NetworkSubsystem,
		],
	)
}
