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

/// `tb_account_filter_t` — 128 bytes. Selects the transfers/balances involving
/// one account for get_account_transfers / get_account_balances.
pub const AccountFilter = extern struct {
    account_id: u128,
    user_data_128: u128,
    user_data_64: u64,
    user_data_32: u32,
    code: u16,
    reserved: [58]u8,
    timestamp_min: u64,
    timestamp_max: u64,
    limit: u32,
    flags: u32,
};

/// `tb_account_balance_t` — 128 bytes. A point-in-time balance returned by
/// get_account_balances (only for accounts opened with the `history` flag).
pub const AccountBalance = extern struct {
    debits_pending: u128,
    debits_posted: u128,
    credits_pending: u128,
    credits_posted: u128,
    timestamp: u64,
    reserved: [56]u8,
};

/// `tb_query_filter_t` — 64 bytes. Selects accounts/transfers by their secondary
/// indexes for query_accounts / query_transfers.
pub const QueryFilter = extern struct {
    user_data_128: u128,
    user_data_64: u64,
    user_data_32: u32,
    ledger: u32,
    code: u16,
    reserved: [6]u8,
    timestamp_min: u64,
    timestamp_max: u64,
    limit: u32,
    flags: u32,
};

/// `tb_create_account_result_t` — one entry per submitted account (dense).
/// `status == .created` (0xFFFFFFFF) means success.
pub const CreateAccountResult = extern struct {
    timestamp: u64,
    status: CreateAccountStatus,
    reserved: u32 = 0,
};

/// `tb_create_transfer_result_t` — one entry per submitted transfer (dense).
/// `status == .created` (0xFFFFFFFF) means success.
pub const CreateTransferResult = extern struct {
    timestamp: u64,
    status: CreateTransferStatus,
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

/// `TB_CREATE_TRANSFER_STATUS` — per-transfer result code (a `u32`).
pub const CreateTransferStatus = enum(u32) {
    created = 0xFFFFFFFF,
    linked_event_failed = 1,
    linked_event_chain_open = 2,
    timestamp_must_be_zero = 3,
    reserved_flag = 4,
    id_must_not_be_zero = 5,
    id_must_not_be_int_max = 6,
    flags_are_mutually_exclusive = 7,
    debit_account_id_must_not_be_zero = 8,
    debit_account_id_must_not_be_int_max = 9,
    credit_account_id_must_not_be_zero = 10,
    credit_account_id_must_not_be_int_max = 11,
    accounts_must_be_different = 12,
    pending_id_must_be_zero = 13,
    pending_id_must_not_be_zero = 14,
    pending_id_must_not_be_int_max = 15,
    pending_id_must_be_different = 16,
    timeout_reserved_for_pending_transfer = 17,
    ledger_must_not_be_zero = 19,
    code_must_not_be_zero = 20,
    debit_account_not_found = 21,
    credit_account_not_found = 22,
    accounts_must_have_the_same_ledger = 23,
    transfer_must_have_the_same_ledger_as_accounts = 24,
    pending_transfer_not_found = 25,
    pending_transfer_not_pending = 26,
    pending_transfer_has_different_debit_account_id = 27,
    pending_transfer_has_different_credit_account_id = 28,
    pending_transfer_has_different_ledger = 29,
    pending_transfer_has_different_code = 30,
    exceeds_pending_transfer_amount = 31,
    pending_transfer_has_different_amount = 32,
    pending_transfer_already_posted = 33,
    pending_transfer_already_voided = 34,
    pending_transfer_expired = 35,
    exists_with_different_flags = 36,
    exists_with_different_debit_account_id = 37,
    exists_with_different_credit_account_id = 38,
    exists_with_different_amount = 39,
    exists_with_different_pending_id = 40,
    exists_with_different_user_data_128 = 41,
    exists_with_different_user_data_64 = 42,
    exists_with_different_user_data_32 = 43,
    exists_with_different_timeout = 44,
    exists_with_different_code = 45,
    exists = 46,
    overflows_debits_pending = 47,
    overflows_credits_pending = 48,
    overflows_debits_posted = 49,
    overflows_credits_posted = 50,
    overflows_debits = 51,
    overflows_credits = 52,
    overflows_timeout = 53,
    exceeds_credits = 54,
    exceeds_debits = 55,
    imported_event_expected = 56,
    imported_event_not_expected = 57,
    imported_event_timestamp_out_of_range = 58,
    imported_event_timestamp_must_not_advance = 59,
    imported_event_timestamp_must_not_regress = 60,
    imported_event_timestamp_must_postdate_debit_account = 61,
    imported_event_timestamp_must_postdate_credit_account = 62,
    imported_event_timeout_must_be_zero = 63,
    closing_transfer_must_be_pending = 64,
    debit_account_already_closed = 65,
    credit_account_already_closed = 66,
    exists_with_different_ledger = 67,
    id_already_failed = 68,
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
    std.debug.assert(@sizeOf(CreateTransferResult) == 16);
    std.debug.assert(@offsetOf(CreateTransferResult, "status") == 8);

    std.debug.assert(@sizeOf(AccountFilter) == 128);
    std.debug.assert(@offsetOf(AccountFilter, "reserved") == 46);
    std.debug.assert(@offsetOf(AccountFilter, "timestamp_min") == 104);
    std.debug.assert(@offsetOf(AccountFilter, "limit") == 120);
    std.debug.assert(@offsetOf(AccountFilter, "flags") == 124);

    std.debug.assert(@sizeOf(AccountBalance) == 128);
    std.debug.assert(@offsetOf(AccountBalance, "timestamp") == 64);
    std.debug.assert(@offsetOf(AccountBalance, "reserved") == 72);

    std.debug.assert(@sizeOf(QueryFilter) == 64);
    std.debug.assert(@offsetOf(QueryFilter, "reserved") == 34);
    std.debug.assert(@offsetOf(QueryFilter, "timestamp_min") == 40);
    std.debug.assert(@offsetOf(QueryFilter, "flags") == 60);

    std.debug.assert(@sizeOf(Client) == 32);

    std.debug.assert(@sizeOf(Packet) == 88);
    std.debug.assert(@offsetOf(Packet, "data") == 8);
    std.debug.assert(@offsetOf(Packet, "data_size") == 16);
    std.debug.assert(@offsetOf(Packet, "user_tag") == 20);
    std.debug.assert(@offsetOf(Packet, "operation") == 22);
    std.debug.assert(@offsetOf(Packet, "status") == 23);
    std.debug.assert(@offsetOf(Packet, "opaque_fields") == 24);
}
