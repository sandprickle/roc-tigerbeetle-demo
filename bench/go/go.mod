module go_bench

go 1.22

require github.com/tigerbeetle/tigerbeetle-go v0.0.0

// No network access; use the local TigerBeetle checkout's Go client.
replace github.com/tigerbeetle/tigerbeetle-go => /Users/bryce/src/oss/tigerbeetle/src/clients/go
