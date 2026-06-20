import Host

Utc := { nanos : I128 }.{
	now! : () => Utc
	now! = || {
		nanos: Host.posix_time!(),
	}

	# Nanoseconds since the Unix epoch. Handy for measuring elapsed time:
	# `Utc.now!().to_nanos() - start.to_nanos()`.
	to_nanos : Utc -> I128
	to_nanos = |utc| utc.nanos
}
