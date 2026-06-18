//! TigerBeetle C client FFI bindings.
//!
//! Hand-written from the vendored `tb_client.h` (the prebuilt `libtb_client.a`
//! is linked via the platform's `targets.inputs`). The C client header is
//! auto-generated and ABI-stable, so transcribing the handful of types we use
//! is cheaper than wiring a `translate-c` build step. The `comptime` layout
//! assertions at the bottom guard against drift between these declarations and
//! the linked library — a wrong field offset would be silent memory corruption.

const std = @import("std");

// =============================================================================
// Data structures
// =============================================================================

/// `tb_account_t` — 128 bytes.
pub const Account = extern struct {
    id: u128,
    debits_pending: u128,
    debits_posted: u128,
    credits_pending: u128,
    credits_posted: u128,
    user_data_128: u128,
    user_data_64: u64,
    user_data_32: u32,
    reserved: u32,
    ledger: u32,
    code: u16,
    flags: u16,
    timestamp: u64,
};

/// `tb_transfer_t` — 128 bytes.
pub const Transfer = extern struct {
    id: u128,
    debit_account_id: u128,
    credit_account_id: u128,
    amount: u128,
    pending_id: u128,
    user_data_128: u128,
    user_data_64: u64,
    user_data_32: u32,
    timeout: u32,
    ledger: u32,
    code: u16,
    flags: u16,
    timestamp: u64,
};

/// `tb_create_account_result_t` — one entry per submitted account (dense).
/// `status == .created` (0xFFFFFFFF) means success.
pub const CreateAccountResult = extern struct {
    timestamp: u64,
    status: CreateAccountStatus,
    reserved: u32 = 0,
};

// =============================================================================
// Enums
// =============================================================================

/// `TB_OPERATION` — stored in `Packet.operation` (a `u8`).
pub const Operation = enum(u8) {
    pulse = 128,
    get_change_events = 137,
    lookup_accounts = 140,
    lookup_transfers = 141,
    get_account_transfers = 142,
    get_account_balances = 143,
    query_accounts = 144,
    query_transfers = 145,
    create_accounts = 146,
    create_transfers = 147,
    _,
};

/// `TB_INIT_STATUS` — returned by `tb_client_init`.
pub const InitStatus = enum(c_int) {
    success = 0,
    unexpected = 1,
    out_of_memory = 2,
    address_invalid = 3,
    address_limit_exceeded = 4,
    system_resources = 5,
    network_subsystem = 6,
    _,
};

/// `TB_CLIENT_STATUS` — returned by `tb_client_submit` / `tb_client_deinit`.
pub const ClientStatus = enum(c_int) {
    ok = 0,
    invalid = 1,
    _,
};

/// `TB_PACKET_STATUS` — written to `Packet.status` (a `u8`) by the client.
pub const PacketStatus = enum(u8) {
    ok = 0,
    too_much_data = 1,
    client_evicted = 2,
    client_release_too_low = 3,
    client_release_too_high = 4,
    client_shutdown = 5,
    invalid_operation = 6,
    invalid_data_size = 7,
    _,
};

/// `TB_CREATE_ACCOUNT_STATUS` — per-account result code (a `u32`).
pub const CreateAccountStatus = enum(u32) {
    created = 0xFFFFFFFF,
    linked_event_failed = 1,
    linked_event_chain_open = 2,
    timestamp_must_be_zero = 3,
    reserved_field = 4,
    reserved_flag = 5,
    id_must_not_be_zero = 6,
    id_must_not_be_int_max = 7,
    flags_are_mutually_exclusive = 8,
    debits_pending_must_be_zero = 9,
    debits_posted_must_be_zero = 10,
    credits_pending_must_be_zero = 11,
    credits_posted_must_be_zero = 12,
    ledger_must_not_be_zero = 13,
    code_must_not_be_zero = 14,
    exists_with_different_flags = 15,
    exists_with_different_user_data_128 = 16,
    exists_with_different_user_data_64 = 17,
    exists_with_different_user_data_32 = 18,
    exists_with_different_ledger = 19,
    exists_with_different_code = 20,
    exists = 21,
    imported_event_expected = 22,
    imported_event_not_expected = 23,
    imported_event_timestamp_out_of_range = 24,
    imported_event_timestamp_must_not_advance = 25,
    imported_event_timestamp_must_not_regress = 26,
    _,
};

// =============================================================================
// Opaque/pinned handles
// =============================================================================

/// `tb_client_t` — opaque, must remain pinned (stable address) for its lifetime.
pub const Client = extern struct {
    opaque_fields: [4]u64,
};

/// `tb_packet_t` — opaque request state, must remain pinned for the request.
pub const Packet = extern struct {
    user_data: ?*anyopaque,
    data: ?*anyopaque,
    data_size: u32,
    user_tag: u16,
    operation: Operation,
    status: PacketStatus,
    opaque_fields: [64]u8,
};

// =============================================================================
// Functions
// =============================================================================

/// Per-client completion callback. Invoked on the client's own thread when a
/// submitted packet completes. `result` is non-null iff `packet.status == .ok`,
/// and is only valid for the duration of the callback — copy it out before
/// returning.
pub const CompletionCallback = *const fn (
    userdata: usize,
    packet: *Packet,
    timestamp: u64,
    result: ?[*]const u8,
    result_size: u32,
) callconv(.c) void;

pub extern fn tb_client_init(
    client_out: *Client,
    cluster_id: *const [16]u8,
    address_ptr: [*]const u8,
    address_len: u32,
    completion_ctx: usize,
    completion_callback: CompletionCallback,
) callconv(.c) InitStatus;

pub extern fn tb_client_submit(client: *Client, packet: *Packet) callconv(.c) ClientStatus;

pub extern fn tb_client_deinit(client: *Client) callconv(.c) ClientStatus;

// =============================================================================
// ABI layout assertions — must match tb_client.h exactly.
// =============================================================================

comptime {
    std.debug.assert(@sizeOf(Account) == 128);
    std.debug.assert(@alignOf(Account) == 16);
    std.debug.assert(@offsetOf(Account, "credits_posted") == 64);
    std.debug.assert(@offsetOf(Account, "user_data_64") == 96);
    std.debug.assert(@offsetOf(Account, "ledger") == 112);
    std.debug.assert(@offsetOf(Account, "code") == 116);
    std.debug.assert(@offsetOf(Account, "flags") == 118);
    std.debug.assert(@offsetOf(Account, "timestamp") == 120);

    std.debug.assert(@sizeOf(Transfer) == 128);
    std.debug.assert(@offsetOf(Transfer, "amount") == 48);
    std.debug.assert(@offsetOf(Transfer, "timeout") == 108);
    std.debug.assert(@offsetOf(Transfer, "timestamp") == 120);

    std.debug.assert(@sizeOf(CreateAccountResult) == 16);
    std.debug.assert(@offsetOf(CreateAccountResult, "status") == 8);

    std.debug.assert(@sizeOf(Client) == 32);

    std.debug.assert(@sizeOf(Packet) == 88);
    std.debug.assert(@offsetOf(Packet, "data") == 8);
    std.debug.assert(@offsetOf(Packet, "data_size") == 16);
    std.debug.assert(@offsetOf(Packet, "user_tag") == 20);
    std.debug.assert(@offsetOf(Packet, "operation") == 22);
    std.debug.assert(@offsetOf(Packet, "status") == 23);
    std.debug.assert(@offsetOf(Packet, "opaque_fields") == 24);
}
