//! TigerBeetle hosted functions for the Roc platform.
//!
//! A single TB client is created lazily on first use and reused for the life of
//! the process (see `g_tb`). TB's API is asynchronous — `tb_client_submit`
//! completes via `onCompletion` on the client's own thread — but Roc's hosted
//! functions are synchronous, so each call submits one packet and blocks on a
//! semaphore until the completion callback fires. This is sound because Roc runs
//! `main!` single-threaded, so we only ever have one request in flight.
//!
//! (Zig 0.16 moved the thread sync primitives under `std.Io`; there is no
//! `std.Thread.ResetEvent`, so we use `std.Io.Semaphore`, which bottoms out in
//! kernel futex wait/wake and is safe to signal from TB's own thread.)

const std = @import("std");
const builtin = @import("builtin");
const abi = @import("roc_platform_abi.zig");
const tb = @import("tb_client.zig");

// Wired up by host.zig at startup, before any hosted function runs.
var g_host: ?*abi.RocHost = null;
var g_gpa: ?std.mem.Allocator = null;

/// Share the host context with this module. Called once from `platform_main`.
pub fn init(host: *abi.RocHost, gpa: std.mem.Allocator) void {
    g_host = host;
    g_gpa = gpa;
}

// --- id! (TigerBeetle time-based identifiers) ------------------------------
//
// 128-bit ids with a 48-bit millisecond timestamp in the high bits and 80 bits
// of randomness in the low bits, packed as `timestamp << 80 | random`. They are
// lexicographically sortable and monotonically increasing, which keeps
// TigerBeetle's LSM tree efficient. Monotonicity within a single millisecond
// requires persistent state, so this lives in the host. Matches the algorithm
// used by every official TB client (see TigerBeetle's Rust client `id()`).
//
// Roc runs `main!` single-threaded, so plain globals are safe — no lock needed.

const U80_MASK: u128 = 0xFFFF_FFFF_FFFF_FFFF_FFFF; // 20 hex F's = 80 bits
const TS48_MASK: u128 = 0xFFFF_FFFF_FFFF; // 48-bit millisecond timestamp

/// Generator state for TigerBeetle time-based ids. The transition logic in
/// `next` is pure (it owns no clock or RNG) so it can be unit-tested
/// deterministically; `nextId` below wires in the real clock and RNG.
const IdState = struct {
    last_ms: u64 = 0,
    last_random: u128 = 0,

    /// Advance the state for `now_ms` and return the packed 128-bit id. A fresh
    /// random (from `randomFn`, masked to 80 bits) is drawn only when time moves
    /// forward or the 80-bit random saturates; on the common same-ms path the
    /// random is just incremented by one to stay monotonic.
    fn next(self: *IdState, now_ms: u64, randomFn: *const fn () u128) u128 {
        if (now_ms > self.last_ms) {
            // Time advanced: adopt it and pick a fresh random.
            self.last_ms = now_ms;
            self.last_random = randomFn() & U80_MASK;
        } else if (self.last_random == U80_MASK) {
            // Same/earlier ms and the random would overflow 80 bits: carry into
            // the next ms and re-randomize (ids run up to 1ms ahead until the
            // clock catches up). Never reset the random to 0 — that would break
            // monotonicity.
            self.last_ms += 1;
            self.last_random = randomFn() & U80_MASK;
        } else {
            // Same or earlier ms: keep the timestamp, bump the random by one.
            self.last_random += 1;
        }
        return ((@as(u128, self.last_ms) & TS48_MASK) << 80) | self.last_random;
    }
};

var g_id_state: IdState = .{};

/// 128 random bits from the platform RNG; callers mask to the width they need.
fn randomU128Bits() u128 {
    const io = std.Io.Threaded.global_single_threaded.io();
    var buf = [_]u8{0} ** 16;
    std.Io.random(io, &buf);
    return @bitCast(buf);
}

/// Hosted function: TigerBeetle.id! — exported as `roc_tb_id` by host.zig.
pub fn nextId() callconv(.c) u128 {
    const io = std.Io.Threaded.global_single_threaded.io();
    const now_ns = std.Io.Clock.real.now(io).toNanoseconds(); // i128 nanos
    const now_ms: u64 = if (now_ns <= 0) 0 else @intCast(@divFloor(now_ns, 1_000_000));
    return g_id_state.next(now_ms, &randomU128Bits);
}

// Unit tests for the id transition logic. `next` takes its randomness as a
// function pointer so these can pin it to a known value; the same-ms increment
// path must not consume it at all.
var test_random: u128 = 0;
fn testRandom() u128 {
    return test_random;
}

test "id: monotonic +1 within the same millisecond" {
    var s: IdState = .{ .last_ms = 1000, .last_random = 5 };
    test_random = 0xDEAD; // must NOT be consumed on the same-ms path
    const a = s.next(1000, &testRandom);
    const b = s.next(1000, &testRandom);
    const c = s.next(1000, &testRandom);
    try std.testing.expect(a < b and b < c);
    try std.testing.expectEqual(@as(u128, 1000), a >> 80); // timestamp unchanged
    try std.testing.expectEqual(@as(u128, 1000), c >> 80);
    try std.testing.expectEqual(@as(u128, 6), a & U80_MASK); // random bumped by one
    try std.testing.expectEqual(@as(u128, 7), b & U80_MASK);
    try std.testing.expectEqual(@as(u128, 8), c & U80_MASK);
}

test "id: advancing time draws a fresh random and stays ordered" {
    var s: IdState = .{}; // last_ms = 0, so the first call sees time advance
    test_random = 0xAB;
    const a = s.next(1000, &testRandom);
    test_random = 0xCD;
    const b = s.next(1001, &testRandom);
    try std.testing.expectEqual(@as(u128, 1000), a >> 80);
    try std.testing.expectEqual(@as(u128, 0xAB), a & U80_MASK);
    try std.testing.expectEqual(@as(u128, 1001), b >> 80);
    try std.testing.expectEqual(@as(u128, 0xCD), b & U80_MASK);
    try std.testing.expect(a < b); // higher timestamp bits dominate
}

test "id: clock moving backward still yields monotonic ids" {
    var s: IdState = .{ .last_ms = 1000, .last_random = 5 };
    const prev = (@as(u128, 1000) << 80) | 5;
    const id = s.next(900, &testRandom); // clock regressed
    try std.testing.expect(id > prev);
    try std.testing.expectEqual(@as(u128, 1000), id >> 80); // kept the old ms
    try std.testing.expectEqual(@as(u128, 6), id & U80_MASK); // random + 1
}

test "id: 80-bit random overflow carries into the next millisecond" {
    var s: IdState = .{ .last_ms = 1000, .last_random = U80_MASK };
    const prev = (@as(u128, 1000) << 80) | U80_MASK;
    test_random = 0x77;
    const id = s.next(1000, &testRandom); // same ms, random saturated
    try std.testing.expect(id > prev);
    try std.testing.expectEqual(@as(u128, 1001), id >> 80); // carried +1ms
    try std.testing.expectEqual(@as(u128, 0x77), id & U80_MASK); // fresh random
}

test "id: random is masked to 80 bits and never corrupts the timestamp" {
    var s: IdState = .{};
    test_random = ~@as(u128, 0); // all 128 bits set
    const id = s.next(1000, &testRandom);
    try std.testing.expectEqual(@as(u128, 1000), id >> 80); // timestamp intact
    try std.testing.expectEqual(U80_MASK, id & U80_MASK); // clamped to 80 bits
}

test "id: timestamp is masked to 48 bits" {
    var s: IdState = .{};
    test_random = 0;
    const huge_ms: u64 = (1 << 48) | 0x1234; // bit 48 must be dropped
    const id = s.next(huge_ms, &testRandom);
    try std.testing.expectEqual(@as(u128, 0x1234), id >> 80);
}

// --- client lifecycle ------------------------------------------------------

const cluster_id: [16]u8 = [_]u8{0} ** 16; // local single-node cluster
const address: []const u8 = "127.0.0.1:3000";

const Bridge = struct {
    client: tb.Client = undefined,
    state: enum { uninitialized, ready, failed } = .uninitialized,
};
var g_tb: Bridge = .{};

/// Lazily initialize the shared client. Returns null if init fails.
fn ensureClient() ?*tb.Client {
    switch (g_tb.state) {
        .ready => return &g_tb.client,
        .failed => return null,
        .uninitialized => {
            const status = tb.tb_client_init(
                &g_tb.client,
                &cluster_id,
                address.ptr,
                @intCast(address.len),
                0, // per-client ctx unused; per-call ctx travels in packet.user_data
                &onCompletion,
            );
            if (status == .success) {
                g_tb.state = .ready;
                return &g_tb.client;
            }
            g_tb.state = .failed;
            return null;
        },
    }
}

/// Tear down the shared client, if one was created. Called at process exit.
pub fn deinitClient() void {
    if (g_tb.state == .ready) _ = tb.tb_client_deinit(&g_tb.client);
}

// --- async -> sync bridge --------------------------------------------------

/// Per-call state shared between the submitting thread and the completion
/// callback, handed to TB via `packet.user_data`.
const Completion = struct {
    done: std.Io.Semaphore = .{}, // starts at 0 permits
    out: []u8, // caller-owned buffer the result bytes are copied into
    out_len: u32 = 0,
    status: tb.PacketStatus = .ok,
};

/// Runs on the TB client thread. `result` is only valid for this call, so copy
/// it out before signaling. Synchronization with the waiter is via `done`.
fn onCompletion(
    userdata: usize,
    packet: *tb.Packet,
    timestamp: u64,
    result: ?[*]const u8,
    result_size: u32,
) callconv(.c) void {
    _ = userdata;
    _ = timestamp;
    const ctx: *Completion = @ptrCast(@alignCast(packet.user_data.?));
    ctx.status = packet.status;
    if (result) |r| {
        const n: u32 = @min(result_size, @as(u32, @intCast(ctx.out.len)));
        @memcpy(ctx.out[0..n], r[0..n]);
        ctx.out_len = n;
    }
    ctx.done.post(std.Io.Threaded.global_single_threaded.io());
}

// --- async -> sync submit helper -------------------------------------------

/// Submit one packet for `operation` carrying `data`, block until TB's
/// completion callback fires, and copy up to `out.len` result bytes into `out`.
/// Returns the number of result bytes written. Transport-level failures are
/// fatal — they have no per-event representation in the result list.
///
/// `data` is the request body exactly as TB expects it on the wire and `out` is
/// the caller's correctly-aligned result buffer. Today callers first marshal Roc
/// values into TB's C layout (the `*ToTb` helpers below); once those layouts line
/// up, a Roc list's bytes can be handed straight to `data` and only `out` needs
/// allocating.
/// Bench/test hook: when true, `submit` skips the network and returns a
/// full-length result buffer, so the marshal/decode/alloc path can be exercised
/// without a live cluster. Filled with 0xFF so the create_* status u32 reads
/// 0xFFFFFFFF (`.created`, the success path) and decodes cleanly. Never enabled in
/// production — it costs one always-false branch, and the real path below is
/// byte-for-byte identical.
pub var bench_loopback: bool = false;

fn submit(operation: tb.Operation, data: []const u8, out: []u8) u32 {
    if (bench_loopback) {
        @memset(out, 0xFF);
        return @intCast(out.len);
    }
    const client = ensureClient() orelse
        fatal("failed to initialize client (is `tigerbeetle start` running on 127.0.0.1:3000?)");

    var completion = Completion{ .out = out };
    var packet = tb.Packet{
        .user_data = &completion,
        .data = @constCast(data.ptr),
        .data_size = @intCast(data.len),
        .user_tag = 0,
        .operation = operation,
        .status = .ok,
        .opaque_fields = undefined,
    };

    if (tb.tb_client_submit(client, &packet) != .ok) fatal("tb_client_submit failed (client closed?)");
    completion.done.waitUncancelable(std.Io.Threaded.global_single_threaded.io());
    if (completion.status != .ok) fatal("request did not complete OK (see TB_PACKET_STATUS)");
    return completion.out_len;
}

/// Decode `src` (the TB C-layout results) into a freshly allocated Roc list,
/// mapping each element through `convert`. Shared by every create/read response.
fn decodeList(
    comptime TbType: type,
    comptime RocType: type,
    host: *abi.RocHost,
    src: []const TbType,
    comptime convert: fn (TbType) RocType,
) abi.RocListWith(RocType, false) {
    const out = abi.RocListWith(RocType, false).allocate(src.len, host);
    if (out.elements_ptr) |ptr| {
        for (src, 0..) |elem, i| ptr[i] = convert(elem);
    }
    return out;
}

// --- create_accounts! / create_transfers! ----------------------------------

// The glue-generated result elements `{ timestamp, status }`. `status` is a
// payloadless tag union whose generated type name is the concatenation of every
// status name; we reach it via @FieldType instead of spelling it out.
const AccountResultRecord = abi.__AnonStruct6;
const AccountStatusTag = @FieldType(AccountResultRecord, "status");
const TransferResultRecord = abi.__AnonStruct16;
const TransferStatusTag = @FieldType(TransferResultRecord, "status");

/// Hosted function: TigerBeetle.create_accounts!
/// List(Account) => List({ status : CreateAccountStatus, timestamp : U64 })
pub fn createAccounts(
    arg0: abi.RocListWith(abi.TigerBeetleAccount, false),
) callconv(.c) abi.RocListWith(AccountResultRecord, false) {
    const host = g_host.?;
    const gpa = g_gpa.?;

    var owned = arg0;
    defer owned.decref(host);

    const roc_accounts = owned.items();
    const n = roc_accounts.len;
    if (n == 0) return abi.RocListWith(AccountResultRecord, false).empty();

    // Dense results: one tb_create_account_result_t per submitted account.
    const results = gpa.alloc(tb.CreateAccountResult, n) catch fatal("out of memory");
    defer gpa.free(results);
    const n_out = submit(
        .create_accounts,
        std.mem.sliceAsBytes(roc_accounts),
        std.mem.sliceAsBytes(results),
    );

    const count = n_out / @sizeOf(tb.CreateAccountResult);
    return decodeList(
        tb.CreateAccountResult,
        AccountResultRecord,
        host,
        results[0..count],
        accountResultToRoc,
    );
}

/// Hosted function: TigerBeetle.create_transfers!
/// List(Transfer) => List({ status : CreateTransferStatus, timestamp : U64 })
pub fn createTransfers(
    arg0: abi.RocListWith(abi.TigerBeetleTransfer, false),
) callconv(.c) abi.RocListWith(TransferResultRecord, false) {
    const host = g_host.?;
    const gpa = g_gpa.?;

    var owned = arg0;
    defer owned.decref(host);

    const roc_transfers = owned.items();
    const n = roc_transfers.len;
    if (n == 0) return abi.RocListWith(TransferResultRecord, false).empty();

    // Dense results: one tb_create_transfer_result_t per submitted transfer.
    const results = gpa.alloc(tb.CreateTransferResult, n) catch fatal(
        "out of memory",
    );
    defer gpa.free(results);
    const n_out = submit(
        .create_transfers,
        std.mem.sliceAsBytes(roc_transfers),
        std.mem.sliceAsBytes(results),
    );

    const count = n_out / @sizeOf(tb.CreateTransferResult);
    return decodeList(tb.CreateTransferResult, TransferResultRecord, host, results[0..count], transferResultToRoc);
}

// --- lookup_accounts! / lookup_transfers! ----------------------------------

/// Hosted function: TigerBeetle.lookup_accounts!
/// List(U128) => List(Account) — at most one account per id (misses omitted).
pub fn lookupAccounts(
    arg0: abi.RocListWith(u128, false),
) callconv(.c) abi.RocListWith(abi.TigerBeetleAccount, false) {
    const host = g_host.?;
    const gpa = g_gpa.?;

    var owned = arg0;
    defer owned.decref(host);

    const ids = owned.items();
    const n = ids.len;
    if (n == 0) return abi.RocListWith(abi.TigerBeetleAccount, false).empty();

    const results = gpa.alloc(tb.Account, n) catch fatal("out of memory");
    defer gpa.free(results);
    // Ids are u128 in the layout TB expects, so the request needs no marshaling.
    const n_out = submit(.lookup_accounts, std.mem.sliceAsBytes(ids), std.mem.sliceAsBytes(results));

    const count = n_out / @sizeOf(tb.Account);
    return decodeList(tb.Account, abi.TigerBeetleAccount, host, results[0..count], accountToRoc);
}

/// Hosted function: TigerBeetle.lookup_transfers!
/// List(U128) => List(Transfer) — at most one transfer per id (misses omitted).
pub fn lookupTransfers(
    arg0: abi.RocListWith(u128, false),
) callconv(.c) abi.RocListWith(abi.TigerBeetleTransfer, false) {
    const host = g_host.?;
    const gpa = g_gpa.?;

    var owned = arg0;
    defer owned.decref(host);

    const ids = owned.items();
    const n = ids.len;
    if (n == 0) return abi.RocListWith(abi.TigerBeetleTransfer, false).empty();

    const results = gpa.alloc(tb.Transfer, n) catch fatal("out of memory");
    defer gpa.free(results);
    const n_out = submit(.lookup_transfers, std.mem.sliceAsBytes(ids), std.mem.sliceAsBytes(results));

    const count = n_out / @sizeOf(tb.Transfer);
    return decodeList(tb.Transfer, abi.TigerBeetleTransfer, host, results[0..count], transferToRoc);
}

// --- get_account_transfers! / get_account_balances! ------------------------
//
// Both responses are bounded by `filter.limit`, so we size the result buffer to
// it. TB treats an invalid filter (including `limit == 0`) as a zero-result
// query rather than an error, so a default-initialized filter yields an empty
// list rather than a fatal.

/// Hosted function: TigerBeetle.get_account_transfers!
/// AccountFilter => List(Transfer)
pub fn getAccountTransfers(
    arg0: abi.TigerBeetleAccountFilter,
) callconv(.c) abi.RocListWith(abi.TigerBeetleTransfer, false) {
    const host = g_host.?;
    const gpa = g_gpa.?;

    const filter = accountFilterToTb(arg0);
    const results = gpa.alloc(tb.Transfer, filter.limit) catch fatal("out of memory");
    defer gpa.free(results);
    const n_out = submit(.get_account_transfers, std.mem.asBytes(&filter), std.mem.sliceAsBytes(results));

    const count = n_out / @sizeOf(tb.Transfer);
    return decodeList(tb.Transfer, abi.TigerBeetleTransfer, host, results[0..count], transferToRoc);
}

/// Hosted function: TigerBeetle.get_account_balances!
/// AccountFilter => List(AccountBalance)
pub fn getAccountBalances(
    arg0: abi.TigerBeetleAccountFilter,
) callconv(.c) abi.RocListWith(abi.__AnonStruct25, false) {
    const host = g_host.?;
    const gpa = g_gpa.?;

    const filter = accountFilterToTb(arg0);
    const results = gpa.alloc(tb.AccountBalance, filter.limit) catch fatal("out of memory");
    defer gpa.free(results);
    const n_out = submit(.get_account_balances, std.mem.asBytes(&filter), std.mem.sliceAsBytes(results));

    const count = n_out / @sizeOf(tb.AccountBalance);
    return decodeList(tb.AccountBalance, abi.__AnonStruct25, host, results[0..count], accountBalanceToRoc);
}

// --- query_accounts! / query_transfers! ------------------------------------

/// Hosted function: TigerBeetle.query_accounts!
/// QueryFilter => List(Account) — bounded by `filter.limit`.
pub fn queryAccounts(
    arg0: abi.TigerBeetleQueryFilter,
) callconv(.c) abi.RocListWith(abi.TigerBeetleAccount, false) {
    const host = g_host.?;
    const gpa = g_gpa.?;

    const filter = queryFilterToTb(arg0);
    const results = gpa.alloc(tb.Account, filter.limit) catch fatal("out of memory");
    defer gpa.free(results);
    const n_out = submit(
        .query_accounts,
        std.mem.asBytes(&filter),
        std.mem.sliceAsBytes(results),
    );

    const count = n_out / @sizeOf(tb.Account);
    return decodeList(
        tb.Account,
        abi.TigerBeetleAccount,
        host,
        results[0..count],
        accountToRoc,
    );
}

/// Hosted function: TigerBeetle.query_transfers!
/// QueryFilter => List(Transfer) — bounded by `filter.limit`.
pub fn queryTransfers(
    arg0: abi.TigerBeetleQueryFilter,
) callconv(.c) abi.RocListWith(abi.TigerBeetleTransfer, false) {
    const host = g_host.?;
    const gpa = g_gpa.?;

    const filter = queryFilterToTb(arg0);
    const results = gpa.alloc(tb.Transfer, filter.limit) catch fatal("out of memory");
    defer gpa.free(results);
    const n_out = submit(
        .query_transfers,
        std.mem.asBytes(&filter),
        std.mem.sliceAsBytes(results),
    );

    const count = n_out / @sizeOf(tb.Transfer);
    return decodeList(
        tb.Transfer,
        abi.TigerBeetleTransfer,
        host,
        results[0..count],
        transferToRoc,
    );
}

// --- Roc <-> TB marshaling -------------------------------------------------
//
// Roc reorders record fields and rounds reserved regions up to 16-byte
// multiples, so neither accounts/transfers nor the filters share TB's C layout
// today — every field is copied explicitly. When the layouts converge these
// collapse to a pointer cast and the request-side allocations above disappear.

fn accountToRoc(src: tb.Account) abi.TigerBeetleAccount {
    return .{
        .id = src.id,
        .debits_pending = src.debits_pending,
        .debits_posted = src.debits_posted,
        .credits_pending = src.credits_pending,
        .credits_posted = src.credits_posted,
        .user_data_128 = src.user_data_128,
        .user_data_64 = src.user_data_64,
        .user_data_32 = src.user_data_32,
        .reserved = .{ .bytes = 0 },
        .ledger = src.ledger,
        .code = src.code,
        .flags = src.flags,
        .timestamp = src.timestamp,
    };
}

fn transferToRoc(src: tb.Transfer) abi.TigerBeetleTransfer {
    return .{
        .id = src.id,
        .debit_account_id = src.debit_account_id,
        .credit_account_id = src.credit_account_id,
        .amount = src.amount,
        .pending_id = src.pending_id,
        .user_data_128 = src.user_data_128,
        .user_data_64 = src.user_data_64,
        .user_data_32 = src.user_data_32,
        .timeout = src.timeout,
        .ledger = src.ledger,
        .code = src.code,
        .flags = src.flags,
        .timestamp = src.timestamp,
    };
}

fn accountFilterToTb(src: abi.TigerBeetleAccountFilter) tb.AccountFilter {
    return .{
        .account_id = src.account_id,
        .user_data_128 = src.user_data_128,
        .user_data_64 = src.user_data_64,
        .user_data_32 = src.user_data_32,
        .code = src.code,
        .reserved = [_]u8{0} ** 58,
        .timestamp_min = src.timestamp_min,
        .timestamp_max = src.timestamp_max,
        .limit = src.limit,
        .flags = src.flags,
    };
}

fn queryFilterToTb(src: abi.TigerBeetleQueryFilter) tb.QueryFilter {
    return .{
        .user_data_128 = src.user_data_128,
        .user_data_64 = src.user_data_64,
        .user_data_32 = src.user_data_32,
        .ledger = src.ledger,
        .code = src.code,
        .reserved = [_]u8{0} ** 6,
        .timestamp_min = src.timestamp_min,
        .timestamp_max = src.timestamp_max,
        .limit = src.limit,
        .flags = src.flags,
    };
}

fn accountBalanceToRoc(src: tb.AccountBalance) abi.__AnonStruct25 {
    return .{
        .debits_pending = src.debits_pending,
        .debits_posted = src.debits_posted,
        .credits_pending = src.credits_pending,
        .credits_posted = src.credits_posted,
        .reserved = std.mem.zeroes(abi.TigerBeetleReserved56),
        .timestamp = src.timestamp,
    };
}

fn accountResultToRoc(src: tb.CreateAccountResult) AccountResultRecord {
    return .{ .timestamp = src.timestamp, .status = accountStatusToRoc(src.status) };
}

fn transferResultToRoc(src: tb.CreateTransferResult) TransferResultRecord {
    return .{ .timestamp = src.timestamp, .status = transferStatusToRoc(src.status) };
}

/// Map a TB account status code to the Roc `CreateAccountStatus` tag. Names line
/// up 1:1 except TB's `user_data_NNN` vs Roc's `user_dataNNN`.
fn accountStatusToRoc(status: tb.CreateAccountStatus) AccountStatusTag {
    return switch (status) {
        .created => .created,
        .linked_event_failed => .linked_event_failed,
        .linked_event_chain_open => .linked_event_chain_open,
        .timestamp_must_be_zero => .timestamp_must_be_zero,
        .reserved_field => .reserved_field,
        .reserved_flag => .reserved_flag,
        .id_must_not_be_zero => .id_must_not_be_zero,
        .id_must_not_be_int_max => .id_must_not_be_int_max,
        .flags_are_mutually_exclusive => .flags_are_mutually_exclusive,
        .debits_pending_must_be_zero => .debits_pending_must_be_zero,
        .debits_posted_must_be_zero => .debits_posted_must_be_zero,
        .credits_pending_must_be_zero => .credits_pending_must_be_zero,
        .credits_posted_must_be_zero => .credits_posted_must_be_zero,
        .ledger_must_not_be_zero => .ledger_must_not_be_zero,
        .code_must_not_be_zero => .code_must_not_be_zero,
        .exists_with_different_flags => .exists_with_different_flags,
        .exists_with_different_user_data_128 => .exists_with_different_user_data128,
        .exists_with_different_user_data_64 => .exists_with_different_user_data64,
        .exists_with_different_user_data_32 => .exists_with_different_user_data32,
        .exists_with_different_ledger => .exists_with_different_ledger,
        .exists_with_different_code => .exists_with_different_code,
        .exists => .exists,
        .imported_event_expected => .imported_event_expected,
        .imported_event_not_expected => .imported_event_not_expected,
        .imported_event_timestamp_out_of_range => .imported_event_timestamp_out_of_range,
        .imported_event_timestamp_must_not_advance => .imported_event_timestamp_must_not_advance,
        .imported_event_timestamp_must_not_regress => .imported_event_timestamp_must_not_regress,
        else => fatal("unexpected create_account status from TigerBeetle"),
    };
}

/// Map a TB transfer status code to the Roc `CreateTransferStatus` tag. Names
/// line up 1:1 except TB's `user_data_NNN` vs Roc's `user_dataNNN`.
fn transferStatusToRoc(status: tb.CreateTransferStatus) TransferStatusTag {
    return switch (status) {
        .created => .created,
        .linked_event_failed => .linked_event_failed,
        .linked_event_chain_open => .linked_event_chain_open,
        .timestamp_must_be_zero => .timestamp_must_be_zero,
        .reserved_flag => .reserved_flag,
        .id_must_not_be_zero => .id_must_not_be_zero,
        .id_must_not_be_int_max => .id_must_not_be_int_max,
        .flags_are_mutually_exclusive => .flags_are_mutually_exclusive,
        .debit_account_id_must_not_be_zero => .debit_account_id_must_not_be_zero,
        .debit_account_id_must_not_be_int_max => .debit_account_id_must_not_be_int_max,
        .credit_account_id_must_not_be_zero => .credit_account_id_must_not_be_zero,
        .credit_account_id_must_not_be_int_max => .credit_account_id_must_not_be_int_max,
        .accounts_must_be_different => .accounts_must_be_different,
        .pending_id_must_be_zero => .pending_id_must_be_zero,
        .pending_id_must_not_be_zero => .pending_id_must_not_be_zero,
        .pending_id_must_not_be_int_max => .pending_id_must_not_be_int_max,
        .pending_id_must_be_different => .pending_id_must_be_different,
        .timeout_reserved_for_pending_transfer => .timeout_reserved_for_pending_transfer,
        .ledger_must_not_be_zero => .ledger_must_not_be_zero,
        .code_must_not_be_zero => .code_must_not_be_zero,
        .debit_account_not_found => .debit_account_not_found,
        .credit_account_not_found => .credit_account_not_found,
        .accounts_must_have_the_same_ledger => .accounts_must_have_the_same_ledger,
        .transfer_must_have_the_same_ledger_as_accounts => .transfer_must_have_the_same_ledger_as_accounts,
        .pending_transfer_not_found => .pending_transfer_not_found,
        .pending_transfer_not_pending => .pending_transfer_not_pending,
        .pending_transfer_has_different_debit_account_id => .pending_transfer_has_different_debit_account_id,
        .pending_transfer_has_different_credit_account_id => .pending_transfer_has_different_credit_account_id,
        .pending_transfer_has_different_ledger => .pending_transfer_has_different_ledger,
        .pending_transfer_has_different_code => .pending_transfer_has_different_code,
        .exceeds_pending_transfer_amount => .exceeds_pending_transfer_amount,
        .pending_transfer_has_different_amount => .pending_transfer_has_different_amount,
        .pending_transfer_already_posted => .pending_transfer_already_posted,
        .pending_transfer_already_voided => .pending_transfer_already_voided,
        .pending_transfer_expired => .pending_transfer_expired,
        .exists_with_different_flags => .exists_with_different_flags,
        .exists_with_different_debit_account_id => .exists_with_different_debit_account_id,
        .exists_with_different_credit_account_id => .exists_with_different_credit_account_id,
        .exists_with_different_amount => .exists_with_different_amount,
        .exists_with_different_pending_id => .exists_with_different_pending_id,
        .exists_with_different_user_data_128 => .exists_with_different_user_data128,
        .exists_with_different_user_data_64 => .exists_with_different_user_data64,
        .exists_with_different_user_data_32 => .exists_with_different_user_data32,
        .exists_with_different_timeout => .exists_with_different_timeout,
        .exists_with_different_code => .exists_with_different_code,
        .exists => .exists,
        .overflows_debits_pending => .overflows_debits_pending,
        .overflows_credits_pending => .overflows_credits_pending,
        .overflows_debits_posted => .overflows_debits_posted,
        .overflows_credits_posted => .overflows_credits_posted,
        .overflows_debits => .overflows_debits,
        .overflows_credits => .overflows_credits,
        .overflows_timeout => .overflows_timeout,
        .exceeds_credits => .exceeds_credits,
        .exceeds_debits => .exceeds_debits,
        .imported_event_expected => .imported_event_expected,
        .imported_event_not_expected => .imported_event_not_expected,
        .imported_event_timestamp_out_of_range => .imported_event_timestamp_out_of_range,
        .imported_event_timestamp_must_not_advance => .imported_event_timestamp_must_not_advance,
        .imported_event_timestamp_must_not_regress => .imported_event_timestamp_must_not_regress,
        .imported_event_timestamp_must_postdate_debit_account => .imported_event_timestamp_must_postdate_debit_account,
        .imported_event_timestamp_must_postdate_credit_account => .imported_event_timestamp_must_postdate_credit_account,
        .imported_event_timeout_must_be_zero => .imported_event_timeout_must_be_zero,
        .closing_transfer_must_be_pending => .closing_transfer_must_be_pending,
        .debit_account_already_closed => .debit_account_already_closed,
        .credit_account_already_closed => .credit_account_already_closed,
        .exists_with_different_ledger => .exists_with_different_ledger,
        .id_already_failed => .id_already_failed,
        else => fatal("unexpected create_transfer status from TigerBeetle"),
    };
}

/// Print a TigerBeetle host-level error to stderr and exit. Used for transport
/// failures (no cluster, client closed, malformed request) that have no
/// representation in the per-account result list.
fn fatal(comptime msg: []const u8) noreturn {
    const io = std.Io.Threaded.global_single_threaded.io();
    std.Io.File.stderr().writeStreamingAll(io, "[TigerBeetle] " ++ msg ++ "\n") catch {};
    std.process.exit(1);
}
