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
	"fmt"
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
	idA := ToUint128(1)
	idB := ToUint128(2)
	if _, err := client.CreateAccounts([]Account{
		{ID: idA, Ledger: ledger, Code: 10},
		{ID: idB, Ledger: ledger, Code: 10},
	}); err != nil {
		panic(err)
	}

	fmt.Println("batch_size,batches,transfers,elapsed_ms,transfers_per_sec")

	var nextID uint64 = 1
	configs := []struct{ size, batches int }{
		{10, 1000},
		{100, 500},
		{1000, 50},
		{8189, 12},
	}

	for _, cfg := range configs {
		// One untimed warm-up batch.
		nextID = submitBatch(client, idA, idB, ledger, cfg.size, nextID)

		start := time.Now()
		for b := 0; b < cfg.batches; b++ {
			nextID = submitBatch(client, idA, idB, ledger, cfg.size, nextID)
		}
		elapsed := time.Since(start)

		total := cfg.size * cfg.batches
		perSec := int64(float64(total) / elapsed.Seconds())
		fmt.Printf("%d,%d,%d,%d,%d\n", cfg.size, cfg.batches, total, elapsed.Milliseconds(), perSec)
	}
}

// Build `count` transfers (sequential ids from `firstID`), submit them as one
// request, and return the next unused id.
func submitBatch(client Client, debit, credit Uint128, ledger uint32, count int, firstID uint64) uint64 {
	batch := make([]Transfer, count)
	id := firstID
	for i := 0; i < count; i++ {
		batch[i] = Transfer{
			ID:              ToUint128(id),
			DebitAccountID:  debit,
			CreditAccountID: credit,
			Amount:          ToUint128(1),
			Ledger:          ledger,
			Code:            10,
		}
		id++
	}
	if _, err := client.CreateTransfers(batch); err != nil {
		panic(err)
	}
	return id
}
