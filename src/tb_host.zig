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
