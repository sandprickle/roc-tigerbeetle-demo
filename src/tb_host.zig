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
        .uninitialized => {},
    }
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

// --- create_accounts! ------------------------------------------------------

// The glue-generated result element `{ timestamp, status }`. `status` is a
// payloadless tag union whose generated type name is the concatenation of all
// 27 status names; we reach it via @FieldType instead of spelling it out.
const ResultRecord = abi.__AnonStruct6;
const StatusTag = @FieldType(ResultRecord, "status");

/// Hosted function: TigerBeetle.create_accounts!
/// List(Account) => List({ status : CreateAccountStatus, timestamp : U64 })
pub fn createAccounts(
    arg0: abi.RocListWith(abi.TigerBeetleAccount, false),
) callconv(.c) abi.RocListWith(ResultRecord, false) {
    const host = g_host.?;
    const gpa = g_gpa.?;

    var owned = arg0;
    defer owned.decref(host);

    const roc_accounts = owned.items();
    const n = roc_accounts.len;
    if (n == 0) return abi.RocListWith(ResultRecord, false).empty();

    // Roc reorders record fields, so marshal field-by-field rather than reinterpret.
    const tb_accounts = gpa.alloc(tb.Account, n) catch fatal("out of memory");
    defer gpa.free(tb_accounts);
    for (roc_accounts, tb_accounts) |src, *dst| {
        dst.* = .{
            .id = src.id,
            .debits_pending = src.debits_pending,
            .debits_posted = src.debits_posted,
            .credits_pending = src.credits_pending,
            .credits_posted = src.credits_posted,
            .user_data_128 = src.user_data_128,
            .user_data_64 = src.user_data_64,
            .user_data_32 = src.user_data_32,
            .reserved = 0,
            .ledger = src.ledger,
            .code = src.code,
            .flags = src.flags,
            .timestamp = src.timestamp,
        };
    }

    const result_buf = gpa.alloc(u8, n * @sizeOf(tb.CreateAccountResult)) catch fatal("out of memory");
    defer gpa.free(result_buf);

    const client = ensureClient() orelse
        fatal("failed to initialize client (is `tigerbeetle start` running on 127.0.0.1:3000?)");

    var completion = Completion{ .out = result_buf };
    var packet = tb.Packet{
        .user_data = &completion,
        .data = tb_accounts.ptr,
        .data_size = @intCast(tb_accounts.len * @sizeOf(tb.Account)),
        .user_tag = 0,
        .operation = .create_accounts,
        .status = .ok,
        .opaque_fields = undefined,
    };

    if (tb.tb_client_submit(client, &packet) != .ok) fatal("tb_client_submit failed (client closed?)");
    completion.done.waitUncancelable(std.Io.Threaded.global_single_threaded.io());
    if (completion.status != .ok) fatal("create_accounts did not complete OK (see TB_PACKET_STATUS)");

    // Dense results: one tb_create_account_result_t per submitted account.
    const results: [*]const tb.CreateAccountResult = @ptrCast(@alignCast(result_buf.ptr));
    const result_count = completion.out_len / @sizeOf(tb.CreateAccountResult);

    const out = abi.RocListWith(ResultRecord, false).allocate(result_count, host);
    if (out.elements_ptr) |out_ptr| {
        for (0..result_count) |i| {
            const res = results[i];
            out_ptr[i] = .{ .timestamp = res.timestamp, .status = statusToRoc(res.status) };
        }
    }
    return out;
}

/// Map a TB status code to the Roc `CreateAccountStatus` tag. Names line up 1:1
/// except TB's `user_data_NNN` vs Roc's `user_dataNNN`.
fn statusToRoc(status: tb.CreateAccountStatus) StatusTag {
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

/// Print a TigerBeetle host-level error to stderr and exit. Used for transport
/// failures (no cluster, client closed, malformed request) that have no
/// representation in the per-account result list.
fn fatal(comptime msg: []const u8) noreturn {
    const io = std.Io.Threaded.global_single_threaded.io();
    std.Io.File.stderr().writeStreamingAll(io, "[TigerBeetle] " ++ msg ++ "\n") catch {};
    std.process.exit(1);
}
