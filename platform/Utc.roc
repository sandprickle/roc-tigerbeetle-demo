import Host

Utc := { nanos : I128 }.{
	now! : () => Utc
	now! = || {
		nanos: Host.posix_time!(),
	}
}
