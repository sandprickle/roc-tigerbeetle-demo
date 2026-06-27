//! TigerBeetle hosted functions for the Roc platform.
//!
//! A single TB client is created explicitly via `TigerBeetle.Client.init!` and
//! reused for the life of the process (see `g_tb_client`). TB's API is
//! asynchronous — `tb_client_submit`
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

// Roc now lays out nominal/opaque record types (declared with `:=` / `::`) in
// declaration order, reordering fields only when it reduces padding. That makes
// these Roc records byte-for-byte identical to TigerBeetle's C client structs, so
// the host can hand a Roc value straight to TB and read TB's results straight
// back into a Roc list with no per-field marshaling. The assertions below pin
// that equivalence: if either side's layout ever drifts, the build fails loudly
// here instead of silently corrupting memory at runtime.
//
// CreateAccountsResult / CreateTransfersResult are deliberately excluded — their
// `status` is a u8 Roc tag vs TB's u32 result code, so they never match and keep
// going through the explicit converters below.
comptime {
    assertSameLayout(abi.TigerBeetleAccount, tb.Account, "Account");
    assertSameLayout(abi.TigerBeetleTransfer, tb.Transfer, "Transfer");
    assertSameLayout(abi.TigerBeetleAccountFilter, tb.AccountFilter, "AccountFilter");
    assertSameLayout(abi.TigerBeetleAccountBalance, tb.AccountBalance, "AccountBalance");
    assertSameLayout(abi.TigerBeetleQueryFilter, tb.QueryFilter, "QueryFilter");
}

/// Compile error unless `Roc` and `Tb` have identical size and alignment — the
/// precondition for every cross-type cast and in-place result decode in this file.
fn assertSameLayout(comptime Roc: type, comptime Tb: type, comptime name: []const u8) void {
    if (@sizeOf(Roc) != @sizeOf(Tb)) @compileError(std.fmt.comptimePrint(
        "TigerBeetle.{s}: Roc size {d} != TB size {d}",
        .{ name, @sizeOf(Roc), @sizeOf(Tb) },
    ));
    if (@alignOf(Roc) != @alignOf(Tb)) @compileError(std.fmt.comptimePrint(
        "TigerBeetle.{s}: Roc align {d} != TB align {d}",
        .{ name, @alignOf(Roc), @alignOf(Tb) },
    ));
}

// Wired up by host.zig at startup, before any hosted function runs.
var g_host: ?*abi.RocHost = null;
var g_io: std.Io = std.Io.Threaded.global_single_threaded.io();

/// Share the host context with this module. Called once from `platform_main`.
pub fn init(host: *abi.RocHost, io: ?std.Io) void {
    g_host = host;
    if (io) |override_io| {
        g_io = override_io;
    }
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
    const Self = @This();
    last_ms: u64 = 0,
    last_random: u128 = 0,

    /// Advance the state for `now_ms` and return the packed 128-bit id. A fresh
    /// random (from `randomFn`, masked to 80 bits) is drawn only when time moves
    /// forward or the 80-bit random saturates; on the common same-ms path the
    /// random is just incremented by one to stay monotonic.
    ///
    /// Accepts `now_ms` and `randomFn` to aid in testing
    fn next(
        self: *Self,
        now_ms: u64,
        randomFn: *const fn () u128,
    ) u128 {
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

fn randomBits128() u128 {
    var buf = [_]u8{0} ** 16;
    std.Io.random(g_io, &buf);
    return @bitCast(buf);
}

fn nowMs() u64 {
    const now_ns = std.Io.Clock.real.now(g_io).toNanoseconds(); // i128 nanos
    return if (now_ns <= 0) 0 else @intCast(@divFloor(now_ns, 1_000_000));
}

var g_id_state: IdState = .{};

/// 128 random bits from the platform RNG; callers mask to the width they need.
/// Hosted function: TigerBeetle.id! — exported as `roc_tb_id` by host.zig.
pub fn nextId() callconv(.c) u128 {
    return g_id_state.next(nowMs(), &randomBits128);
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

/// TigerBeetle client. API design of TigerBeetle.roc should prevent this from
/// being accessed before it's initialized, but just in case we've made it an
/// optional so we can fail gracefully if the unthinkable happens.
var g_tb_client: ?tb.Client = null;

pub fn initClient(
    args: abi.TigerBeetleClientInitArgs,
) callconv(.c) abi.Try {
    // The `addresses` RocStr is owned by this hosted call; release it on exit.
    // TB parses the addresses during init and does not retain the pointer.
    const addresses = args.addresses;
    defer addresses.decref(g_host.?);

    // tb_client_init writes the live client into storage WE own, and that
    // storage must stay pinned for the client's life — so make the global
    // non-null first and hand TB a pointer to its payload. A zeroed Client is a
    // safe placeholder: init overwrites it, and on failure we reset to null so
    // submit!/deinit never treat a never-initialized client as live.
    g_tb_client = std.mem.zeroes(tb.Client);

    const status = tb.tb_client_init(
        &g_tb_client.?,
        &@bitCast(args.cluster_id),
        addresses.asU8ptr(),
        @intCast(addresses.len()),
        0, // per-client ctx unused; per-call ctx travels in packet.user_data
        &onCompletion,
    );

    if (status != .success) g_tb_client = null;

    return switch (status) {
        .success => tryOk(),
        .unexpected => tryErr(.unexpected),
        .out_of_memory => tryErr(.out_of_memory),
        .address_invalid => tryErr(.address_invalid),
        .address_limit_exceeded => tryErr(.address_limit_exceeded),
        .system_resources => tryErr(.system_resources),
        .network_subsystem => tryErr(.network_subsystem),
        else => fatal("Unknown status"),
    };
}

fn tryOk() abi.Try {
    return abi.Try{ .payload = .{ .ok = {} }, .tag = abi.TryTag.Ok };
}

const TigerBeetleClientInitErr =
    abi.AddressInvalidOrAddressLimitExceededOrNetworkSubsystemOrOutOfMemoryOrSystemResourcesOrUnexpected;
fn tryErr(err: TigerBeetleClientInitErr) abi.Try {
    return abi.Try{
        .payload = .{ .err = err },
        .tag = abi.TryTag.Err,
    };
}
/// Tear down the shared client, if one was created. Called at process exit.
pub fn deinitClient() void {
    if (g_tb_client) |*client| {
        _ = tb.tb_client_deinit(client);
    }
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
    ctx.done.post(g_io);
}

// --- async -> sync submit helper -------------------------------------------

/// Submit one packet for `operation` carrying `data`, block until TB's
/// completion callback fires, and copy up to `out.len` result bytes into `out`.
/// Returns the number of result bytes written. Transport-level failures are
/// fatal — they have no per-event representation in the result list.
///
/// `data` is the request body exactly as TB expects it on the wire and `out` is
/// the caller's correctly-aligned result buffer. Because the Roc and TB layouts
/// are identical (asserted at the top of this file), `data` is now a Roc value's
/// own bytes and `out` is a Roc list's own backing store — see `submitInto`.
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
    // Capture by pointer (`|*c|`), not by value: tb.Client "must remain pinned
    // (stable address) for its lifetime", so submit against the global's storage
    // rather than a transient stack copy.
    const client: *tb.Client = if (g_tb_client) |*c| c else fatal(
        "TigerBeetle client was not initialized in time. This is a bug!",
    );

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

    const submit_status = tb.tb_client_submit(client, &packet);
    if (submit_status != .ok) fatal("tb_client_submit failed (client closed?)");

    completion.done.waitUncancelable(g_io);
    if (completion.status != .ok) fatal("request did not complete OK (see TB_PACKET_STATUS)");

    return completion.out_len;
}

/// Submit `operation` carrying `data` and have TB write its results straight into
/// a freshly allocated Roc list — no scratch buffer, no per-element copy. Sound
/// only because `RocType` and `TbType` share an identical layout (asserted at
/// comptime), so the bytes TB writes already *are* a valid array of `RocType`.
///
/// The list is allocated at `capacity` (the caller's upper bound on the count)
/// and its length is trimmed to whatever TB actually returns. Leftover capacity
/// past the count is harmless: `RocType` is non-refcounted, so the untouched tail
/// is never read and is freed with the rest on decref.
///
/// SEAM: if a large `filter.limit` paired with a small result set is ever found
/// to pin too much memory, this is the single place to add a conditional shrink —
/// `allocate` an exact-size list, `@memcpy` `count` elements, decref this one.
/// Encapsulated here so callers never change.
fn allocAndSubmit(
    comptime ResultTypeRoc: type,
    comptime ResultTypeTb: type,
    host: *abi.RocHost,
    operation: tb.Operation,
    data: []const u8,
    capacity: usize,
) abi.RocListWith(ResultTypeRoc, false) {
    const size_match = @sizeOf(ResultTypeRoc) == @sizeOf(ResultTypeTb);
    const align_match = @alignOf(ResultTypeRoc) == @alignOf(ResultTypeTb);
    comptime if (!size_match or !align_match)
        @compileError("submitInto requires identical Roc/TB layouts");

    const List = abi.RocListWith(ResultTypeRoc, false);
    if (capacity == 0) return List.empty();

    var list = List.allocate(capacity, host);
    const dest: [*]u8 = @ptrCast(list.elements_ptr.?);
    const n_out = submit(
        operation,
        data,
        dest[0 .. capacity * @sizeOf(ResultTypeRoc)],
    );
    list.length = n_out / @sizeOf(ResultTypeRoc);
    return list;
}

// --- create_accounts! / create_transfers! ----------------------------------

/// Hosted function: TigerBeetle.create_accounts!
/// List(Account) => List({ status : CreateAccountStatus, timestamp : U64 })
pub fn createAccounts(
    arg0: abi.RocListWith(abi.TigerBeetleAccount, false),
) callconv(.c) abi.RocListWith(
    abi.TigerBeetleCreateAccountResult,
    false,
) {
    for (arg0.items()) |acct| {
        std.log.debug(
            "[HOST] Creating account: {}\n",
            .{acct},
        );
    }
    const host = g_host.?;
    // const gpa = g_gpa.?;
    var owned = arg0;
    defer owned.decref(host);

    const roc_accounts = owned.items();
    return allocAndSubmit(
        abi.TigerBeetleCreateAccountResult,
        tb.CreateAccountResult,
        host,
        .create_accounts,
        std.mem.sliceAsBytes(roc_accounts),
        roc_accounts.len,
    );
}

/// Hosted function: TigerBeetle.create_transfers!
/// List(Transfer) => List({ status : CreateTransferStatus, timestamp : U64 })
pub fn createTransfers(
    arg0: abi.RocListWith(abi.TigerBeetleTransfer, false),
) callconv(.c) abi.RocListWith(
    abi.TigerBeetleCreateTransferResult,
    false,
) {
    for (arg0.items()) |acct| {
        std.log.debug(
            "[HOST] Creating transfer: {}\n",
            .{acct},
        );
    }
    const host = g_host.?;
    var owned = arg0;
    defer owned.decref(host);

    const roc_transfers = owned.items();
    return allocAndSubmit(
        abi.TigerBeetleCreateTransferResult,
        tb.CreateTransferResult,
        host,
        .create_transfers,
        std.mem.sliceAsBytes(roc_transfers),
        roc_transfers.len,
    );
}

// --- lookup_accounts! / lookup_transfers! ----------------------------------

/// Hosted function: TigerBeetle.lookup_accounts!
/// List(U128) => List(Account) — at most one account per id (misses omitted).
pub fn lookupAccounts(
    arg0: abi.RocListWith(u128, false),
) callconv(.c) abi.RocListWith(abi.TigerBeetleAccount, false) {
    const host = g_host.?;
    var owned = arg0;
    defer owned.decref(host);

    // Ids are already u128 in TB's wire layout and tb.Account matches
    // TigerBeetleAccount, so both request and response are zero-copy.
    const ids = owned.items();
    return allocAndSubmit(
        abi.TigerBeetleAccount,
        tb.Account,
        host,
        .lookup_accounts,
        std.mem.sliceAsBytes(ids),
        ids.len,
    );
}

/// Hosted function: TigerBeetle.lookup_transfers!
/// List(U128) => List(Transfer) — at most one transfer per id (misses omitted).
pub fn lookupTransfers(
    arg0: abi.RocListWith(u128, false),
) callconv(.c) abi.RocListWith(abi.TigerBeetleTransfer, false) {
    const host = g_host.?;
    var owned = arg0;
    defer owned.decref(host);

    const ids = owned.items();
    return allocAndSubmit(
        abi.TigerBeetleTransfer,
        tb.Transfer,
        host,
        .lookup_transfers,
        std.mem.sliceAsBytes(ids),
        ids.len,
    );
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
    // AccountFilter matches tb.AccountFilter, so pass its bytes straight through.
    return allocAndSubmit(
        abi.TigerBeetleTransfer,
        tb.Transfer,
        host,
        .get_account_transfers,
        std.mem.asBytes(&arg0),
        arg0.limit,
    );
}

/// Hosted function: TigerBeetle.get_account_balances!
/// AccountFilter => List(AccountBalance)
pub fn getAccountBalances(
    arg0: abi.TigerBeetleAccountFilter,
) callconv(.c) abi.RocListWith(abi.TigerBeetleAccountBalance, false) {
    const host = g_host.?;
    return allocAndSubmit(
        abi.TigerBeetleAccountBalance,
        tb.AccountBalance,
        host,
        .get_account_balances,
        std.mem.asBytes(&arg0),
        arg0.limit,
    );
}

// --- query_accounts! / query_transfers! ------------------------------------

/// Hosted function: TigerBeetle.query_accounts!
/// QueryFilter => List(Account) — bounded by `filter.limit`.
pub fn queryAccounts(
    arg0: abi.TigerBeetleQueryFilter,
) callconv(.c) abi.RocListWith(abi.TigerBeetleAccount, false) {
    const host = g_host.?;
    // QueryFilter matches tb.QueryFilter, so pass its bytes straight through.
    return allocAndSubmit(
        abi.TigerBeetleAccount,
        tb.Account,
        host,
        .query_accounts,
        std.mem.asBytes(&arg0),
        arg0.limit,
    );
}

/// Hosted function: TigerBeetle.query_transfers!
/// QueryFilter => List(Transfer) — bounded by `filter.limit`.
pub fn queryTransfers(
    arg0: abi.TigerBeetleQueryFilter,
) callconv(.c) abi.RocListWith(abi.TigerBeetleTransfer, false) {
    const host = g_host.?;
    return allocAndSubmit(
        abi.TigerBeetleTransfer,
        tb.Transfer,
        host,
        .query_transfers,
        std.mem.asBytes(&arg0),
        arg0.limit,
    );
}

/// Print a TigerBeetle host-level error to stderr and exit. Used for transport
/// failures (no cluster, client closed, malformed request) that have no
/// representation in the per-account result list.
fn fatal(comptime msg: []const u8) noreturn {
    std.Io.File.stderr().writeStreamingAll(
        g_io,
        "[TigerBeetle] " ++ msg ++ "\n",
    ) catch {};
    std.process.exit(1);
}
