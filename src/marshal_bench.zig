//! Per-item marshal/decode/alloc microbenchmark for the Roc TigerBeetle client.
//!
//! Drives the *real* host entrypoints (`createAccounts`/`createTransfers`/
//! `lookupAccounts` in `tb_host.zig`) with `tb_host.bench_loopback = true`, so the
//! genuine marshal (Roc->C) + result alloc + decode (C->Roc) path runs with **no
//! network** — `submit` returns a zeroed, full-length result buffer instead of
//! hitting the cluster. This isolates the CPU/allocation cost that survives the
//! move to a coroutine host (see the plan), and answers "does an extra allocation
//! matter" with concrete ns/op, allocs/op, bytes/op.
//!
//! It calls only the entrypoints, never the internal converters, so it keeps
//! working — and simply reports lower numbers — once the Roc struct field-ordering
//! change removes marshaling. That makes this the tool that proves that change worked.
//!
//! Note: `submit` loopback returns one dense result per input element, so the
//! decode side of create_* is measured at worst case (real TB create results are
//! sparser). lookup_accounts decodes a full N accounts, matching real reads.

const std = @import("std");
const builtin = @import("builtin");
const abi = @import("roc_platform_abi.zig");
const tb_host = @import("tb_host.zig");

/// Allocator wrapper that counts calls + bytes without capturing stack traces
/// (so it doesn't skew timing the way std.testing.FailingAllocator would).
const Counting = struct {
    child: std.mem.Allocator,
    n_alloc: usize = 0,
    n_free: usize = 0,
    n_resize: usize = 0,
    n_remap: usize = 0,
    bytes: usize = 0,

    fn allocator(self: *Counting) std.mem.Allocator {
        return .{ .ptr = self, .vtable = &.{
            .alloc = allocFn,
            .resize = resizeFn,
            .remap = remapFn,
            .free = freeFn,
        } };
    }

    fn allocFn(ctx: *anyopaque, len: usize, alignment: std.mem.Alignment, ret_addr: usize) ?[*]u8 {
        const self: *Counting = @ptrCast(@alignCast(ctx));
        const r = self.child.rawAlloc(len, alignment, ret_addr);
        if (r != null) {
            self.n_alloc += 1;
            self.bytes += len;
        }
        return r;
    }

    fn resizeFn(ctx: *anyopaque, memory: []u8, alignment: std.mem.Alignment, new_len: usize, ret_addr: usize) bool {
        const self: *Counting = @ptrCast(@alignCast(ctx));
        self.n_resize += 1;
        return self.child.rawResize(memory, alignment, new_len, ret_addr);
    }

    fn remapFn(ctx: *anyopaque, memory: []u8, alignment: std.mem.Alignment, new_len: usize, ret_addr: usize) ?[*]u8 {
        const self: *Counting = @ptrCast(@alignCast(ctx));
        self.n_remap += 1;
        return self.child.rawRemap(memory, alignment, new_len, ret_addr);
    }

    fn freeFn(ctx: *anyopaque, memory: []u8, alignment: std.mem.Alignment, ret_addr: usize) void {
        const self: *Counting = @ptrCast(@alignCast(ctx));
        self.n_free += 1;
        self.child.rawFree(memory, alignment, ret_addr);
    }
};

const Op = enum { create_accounts, create_transfers, lookup_accounts };

const Stats = struct {
    ns_per_op: f64,
    allocs_per_op: f64,
    frees_per_op: f64,
    bytes_per_op: f64,
};

fn run(comptime op: Op, base: std.mem.Allocator, n: usize, iters: usize, warmup: usize) Stats {
    const io = std.Io.Threaded.global_single_threaded.io();

    var counting = Counting{ .child = base };
    const a = counting.allocator();
    var env: abi.RocEnv = .{ .allocator = a, .roc_io = abi.RocIo.default() };
    var host = abi.makeRocHost(&env);
    tb_host.init(&host, io);
    tb_host.bench_loopback = true;

    var total_ns: u64 = 0;
    var total_allocs: usize = 0;
    var total_frees: usize = 0;
    var total_bytes: usize = 0;

    var it: usize = 0;
    const total_iters = warmup + iters;
    while (it < total_iters) : (it += 1) {
        const measure = it >= warmup;

        // Build the input list OUTSIDE the timed/counted region: that is the
        // caller's work, not the host marshaling we want to isolate.
        switch (op) {
            .create_accounts => {
                const input = abi.RocListWith(abi.TigerBeetleAccount, false).allocate(n, &host);
                if (input.elements_ptr) |p| {
                    for (0..n) |i| p[i] = std.mem.zeroes(abi.TigerBeetleAccount);
                }
                const a0 = counting.n_alloc;
                const f0 = counting.n_free;
                const b0 = counting.bytes;
                const t0 = std.Io.Clock.awake.now(io).toNanoseconds();
                const out = tb_host.createAccounts(input);
                const t1 = std.Io.Clock.awake.now(io).toNanoseconds();
                const dt: u64 = @intCast(t1 - t0);
                if (measure) {
                    total_ns += dt;
                    total_allocs += counting.n_alloc - a0;
                    total_frees += counting.n_free - f0;
                    total_bytes += counting.bytes - b0;
                }
                out.decref(&host);
            },
            .create_transfers => {
                const input = abi.RocListWith(abi.TigerBeetleTransfer, false).allocate(n, &host);
                if (input.elements_ptr) |p| {
                    for (0..n) |i| p[i] = std.mem.zeroes(abi.TigerBeetleTransfer);
                }
                const a0 = counting.n_alloc;
                const f0 = counting.n_free;
                const b0 = counting.bytes;
                const t0 = std.Io.Clock.awake.now(io).toNanoseconds();
                const out = tb_host.createTransfers(input);
                const t1 = std.Io.Clock.awake.now(io).toNanoseconds();
                const dt: u64 = @intCast(t1 - t0);
                if (measure) {
                    total_ns += dt;
                    total_allocs += counting.n_alloc - a0;
                    total_frees += counting.n_free - f0;
                    total_bytes += counting.bytes - b0;
                }
                out.decref(&host);
            },
            .lookup_accounts => {
                const input = abi.RocListWith(u128, false).allocate(n, &host);
                if (input.elements_ptr) |p| {
                    for (0..n) |i| p[i] = @intCast(i + 1);
                }
                const a0 = counting.n_alloc;
                const f0 = counting.n_free;
                const b0 = counting.bytes;
                const t0 = std.Io.Clock.awake.now(io).toNanoseconds();
                const out = tb_host.lookupAccounts(input);
                const t1 = std.Io.Clock.awake.now(io).toNanoseconds();
                const dt: u64 = @intCast(t1 - t0);
                if (measure) {
                    total_ns += dt;
                    total_allocs += counting.n_alloc - a0;
                    total_frees += counting.n_free - f0;
                    total_bytes += counting.bytes - b0;
                }
                out.decref(&host);
            },
        }
    }

    const fi: f64 = @floatFromInt(iters);
    return .{
        .ns_per_op = @as(f64, @floatFromInt(total_ns)) / fi,
        .allocs_per_op = @as(f64, @floatFromInt(total_allocs)) / fi,
        .frees_per_op = @as(f64, @floatFromInt(total_frees)) / fi,
        .bytes_per_op = @as(f64, @floatFromInt(total_bytes)) / fi,
    };
}

pub fn main() void {
    var dbg = std.heap.DebugAllocator(.{}){};
    defer _ = dbg.deinit();

    const Case = struct { name: []const u8, a: std.mem.Allocator };
    const cases = [_]Case{
        .{ .name = "DebugAllocator (Debug builds / leak-checking)", .a = dbg.allocator() },
        .{ .name = "smp_allocator (production in release, after host.zig fix)", .a = std.heap.smp_allocator },
    };
    // batch sizes mirror the end-to-end sweep; 1 isolates the per-call floor,
    // 8189 = the true single-message max for 128-byte events (1 MiB - 256B header
    // - 128B multi-batch trailer slot, / 128).
    const sizes = [_]usize{ 1, 10, 100, 1000, 8189 };

    std.debug.print("\nTigerBeetle Roc client - marshal/decode/alloc microbench (no network)\n", .{});
    std.debug.print("optimize = {s}\n\n", .{@tagName(builtin.mode)});

    for (cases) |c| {
        std.debug.print("== allocator: {s} ==\n", .{c.name});
        std.debug.print("{s:>16} {s:>7} {s:>12} {s:>12} {s:>10} {s:>10} {s:>12}\n", .{ "op", "batch", "ns/op", "ns/item", "allocs/op", "frees/op", "bytes/op" });
        inline for (.{ Op.create_accounts, Op.create_transfers, Op.lookup_accounts }) |op| {
            for (sizes) |n| {
                const iters = std.math.clamp(@as(usize, 1_000_000) / n, 50, 100_000);
                const warmup = @max(@as(usize, 10), iters / 20);
                const s = run(op, c.a, n, iters, warmup);
                std.debug.print("{s:>16} {d:>7} {d:>12.1} {d:>12.3} {d:>10.2} {d:>10.2} {d:>12.0}\n", .{
                    @tagName(op),
                    n,
                    s.ns_per_op,
                    s.ns_per_op / @as(f64, @floatFromInt(n)),
                    s.allocs_per_op,
                    s.frees_per_op,
                    s.bytes_per_op,
                });
            }
        }
        std.debug.print("\n", .{});
    }
}
