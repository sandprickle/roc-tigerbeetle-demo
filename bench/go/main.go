// Fair-sequential throughput driver for the official TigerBeetle Go client.
//
// Mirrors examples/roc_bench.roc exactly: same workload (two accounts, transfers
// in batches of {10,100,1000,8189}), same sequential transfer ids, and the same
// synchronous one-batch-in-flight model (Go's CreateTransfers blocks per call —
// identical to the Roc host). So any difference vs the Roc numbers is pure
// per-call client overhead, not async-vs-sync.
//
//	cd bench/go && GOPROXY=off go build -o go_bench . && TB_ADDRESS=3000 ./go_bench
package main

import (
	"encoding/binary"
	"fmt"
	"math/bits"
	"os"
	"time"

	. "github.com/tigerbeetle/tigerbeetle-go"
)

func main() {
	addr := os.Getenv("TB_ADDRESS")
	if addr == "" {
		addr = "3000"
	}

	client, err := NewClient(ToUint128(0), []string{addr})
	if err != nil {
		panic(err)
	}
	defer client.Close()

	const ledger = uint32(700)
	accountIdA := ToUint128(1)
	accountIdB := ToUint128(2)
	if _, err := client.CreateAccounts([]Account{
		{ID: accountIdA, Ledger: ledger, Code: 10},
		{ID: accountIdB, Ledger: ledger, Code: 10},
	}); err != nil {
		panic(err)
	}

	fmt.Println("batch_size,batches,transfers,elapsed_ms,transfers_per_sec")

	configs := []struct{ size, batches int }{
		// {10, 50},
		// {100, 50},
		{240, 50},
		// {1000, 50},
		// {5000, 50},
		// {8189, 50},
	}

	for _, cfg := range configs {
		// One untimed warm-up batch.
		_ = submitBatch(client, accountIdA, accountIdB, ledger, cfg.size, ID())

		id := ID()
		start := time.Now()
		for b := 0; b < cfg.batches; b++ {
			id = submitBatch(client, accountIdA, accountIdB, ledger, cfg.size, id)
		}
		elapsed := time.Since(start)

		total := cfg.size * cfg.batches
		perSec := int64(float64(total) / elapsed.Seconds())
		fmt.Printf("%d,%d,%d,%d,%d\n", cfg.size, cfg.batches, total, elapsed.Milliseconds(), perSec)
	}
}

// Build `count` transfers (sequential ids from `firstID`), submit them as one
// request, and return the next unused id.
func submitBatch(client Client, debit, credit Uint128, ledger uint32, count int, firstID Uint128) Uint128 {
	batch := make([]Transfer, count)
	id := firstID
	for i := range count {
		batch[i] = Transfer{
			ID:              id,
			DebitAccountID:  debit,
			CreditAccountID: credit,
			Amount:          ToUint128(1),
			Ledger:          ledger,
			Code:            10,
		}
		id = nextID(id)
	}
	if _, err := client.CreateTransfers(batch); err != nil {
		panic(err)
	}
	return id
}

// nextID returns id + 1. The client's Uint128 wraps C's __uint128_t, so Go
// can't do arithmetic on it directly. Add the two 64-bit halves with a
// hardware carry (bits.Add64 compiles to ADD+ADC) and reassemble little-endian
// — no big.Int, no allocation. Mirrors the `id + 1` step in the Roc/Rust benches.
func nextID(id Uint128) Uint128 {
	lo, hi := id.Uint64() // little-endian: lo = first 8 bytes, hi = last 8
	lo, carry := bits.Add64(lo, 1, 0)
	hi += carry
	var b [16]byte
	binary.LittleEndian.PutUint64(b[0:8], lo)
	binary.LittleEndian.PutUint64(b[8:16], hi)
	return BytesToUint128(b)
}
