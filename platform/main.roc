platform ""
	requires {
		main! : List(Str) => Try({}, [Exit(I32)])
	}
	exposes [Stdout, Stderr, Stdin, Utc, TigerBeetle]
	packages {}
	provides { "roc_main": main_for_host! }
	hosted {
		"roc_stderr_line": Stderr.line!,
		"roc_stdin_line": Stdin.line!,
		"roc_stdout_line": Stdout.line!,
		"roc_host_posix_time": Host.posix_time!,
		"roc_host_random_U64": Host.random_U64!,
		"roc_host_random_U128": Host.random_U128!,
		"roc_tb_create_accounts": TigerBeetle.create_accounts!,
		"roc_tb_id": TigerBeetle.id!,
	}
	targets: {
		inputs: "targets/",
		x64mac: { inputs: ["libhost.a", app] },
		arm64mac: { inputs: ["libhost.a", "libtb_client.a", app] },
		x64musl: { inputs: ["crt1.o", "libhost.a", app, "libc.a"] },
		arm64musl: { inputs: ["crt1.o", "libhost.a", app, "libc.a"] },
		x64win: { inputs: ["host.lib", app] },
		arm64win: { inputs: ["host.lib", app] },
	}

import Stdout
import Stderr
import Stdin
import Utc
import Host
import TigerBeetle

main_for_host! : List(Str) => I32
main_for_host! = |args| {
	result = main!(args)
	match result {
		Ok({}) => 0
		Err(Exit(code)) => code
	}
}
