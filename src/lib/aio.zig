//! asyncio integration built on Zig 0.16's `std.Io`.
//!
//! `pyoz.asyncFn(f)` turns a Zig function into a Python function that returns
//! an `asyncio.Future`:
//!
//!     fn fetch(io: std.Io, arena: std.mem.Allocator, n: i64) !i64 {
//!         try io.sleep(.fromMilliseconds(50), .awake); // cancellation point
//!         ...
//!     }
//!     .funcs = &.{ pyoz.func("fetch", pyoz.asyncFn(fetch), "...") },
//!
//!     result = await mymod.fetch(3)
//!
//! * `f` runs on its own `std.Io` task (`io.concurrent`), without the GIL or an
//!   attached Python thread state, so async Zig work runs in parallel with
//!   Python and with other tasks, on every CPython build.
//! * Optional leading parameters: `std.Io` (the runtime's Io) and/or
//!   `std.mem.Allocator` (a per-call arena freed after the result is converted).
//! * Cancelling the Python task (`task.cancel()`, `asyncio.timeout`, ...) calls
//!   `Future.cancel` on the Zig task: its next `Io` call (sleep, file, net,
//!   `io.checkCancel()`) returns `error.Canceled`.
//! * The event loop never blocks on Zig: joins and cancellations are performed
//!   by a supervisor task, and a per-job atomic state machine decides which
//!   side (completion or cancellation) owns the cleanup.
//!
//! Arguments are copied at call time (the Python objects may be gone by the
//! time the task runs): ints, floats, bools, enums, optionals of those, and
//! `[]const u8` (duplicated into the job's arena) are supported.

const std = @import("std");
const Io = std.Io;
const py = @import("python.zig");
const c = py.c;
const PyObject = py.PyObject;
const conversion = @import("conversion.zig");
const errors_mod = @import("errors.zig");
const lazy = @import("python/lazy.zig");
const root = @import("root.zig");

const gpa = std.heap.smp_allocator;

// ============================================================================
// Runtime: one process-wide Io.Threaded plus a supervisor task
// ============================================================================

var threaded: Io.Threaded = undefined;
var rt_state = std.atomic.Value(u8).init(0); // 0 = uninit, 1 = initializing, 2 = ready

/// The process-wide `std.Io` used by PyOZ async functions. Also usable from
/// ordinary (synchronous) PyOZ functions that want to do Io.
pub fn io() Io {
    if (rt_state.load(.acquire) != 2) initRuntime();
    return threaded.io();
}

/// Maximum number of async jobs running at once (one OS thread each under
/// `Io.Threaded`). Excess jobs wait in a FIFO and start as others finish, so
/// logical concurrency is unbounded while thread count stays bounded.
var max_concurrency: usize = 256;

/// Set the async concurrency limit. Takes effect only before the first async
/// call (the runtime is created lazily). Returns false if already started.
pub fn setConcurrency(n: usize) bool {
    if (rt_state.load(.acquire) != 0) return false;
    max_concurrency = @max(n, 1);
    return true;
}

fn initRuntime() void {
    if (rt_state.cmpxchgStrong(0, 1, .acq_rel, .acquire) == null) {
        // +1: the supervisor task itself occupies a slot.
        threaded = .init(gpa, .{ .concurrent_limit = .limited(max_concurrency + 1) });
        const rt_io = threaded.io();
        // Process-lifetime task; never awaited.
        _ = rt_io.concurrent(supervise, .{rt_io}) catch @panic("pyoz: cannot start async supervisor");
        rt_state.store(2, .release);
    } else {
        while (rt_state.load(.acquire) != 2) std.atomic.spinLoopHint();
    }
}

/// Work item for the supervisor: join (await) or cancel a finished job.
const Common = struct {
    next: ?*Common = null,
    cancel: bool = false,
    state: std.atomic.Value(u8) = .init(running),
    refs: std.atomic.Value(u32) = .init(2), // supervisor + done-callback capsule
    next_done: ?*Common = null,
    loop: *PyObject,
    pyfut: *PyObject,
    /// Borrowing async methods: the Python object whose data the task reads.
    /// Released only once the Zig task can no longer touch it: on the loop
    /// thread after completion, or by the supervisor after a cancel-join.
    keepalive: ?*PyObject = null,
    hub: *Hub,
    finish: *const fn (*Common, Io, bool) void,
    destroy: *const fn (*Common) void,
    /// Convert the stored result and resolve the asyncio future (loop thread).
    resolve: *const fn (*Common) void,
    /// Result converter bound by the module's wrapper (knows the module's
    /// classes and error mappings). Set on the loop thread before any drain.
    convert: ?*const fn (*Common, *bool) ?*PyObject = null,
    /// Spawn the job's Io task. Written/read under `pending_mutex` or by the
    /// supervisor only, so no atomics needed for `started`.
    start: *const fn (*Common, Io) Io.ConcurrentError!void,
    started: bool = false,
    /// Returned from `__anext__`: a null `?T` result raises StopAsyncIteration
    /// instead of resolving to None. Set on the loop thread before any drain.
    null_stops: bool = false,
    /// `asyncThen`: drops the Python objects held for the completion step.
    release_held: ?*const fn (*Common) void = null,

    const running = 0;
    const posting = 1;
    const cancelled = 2;

    fn unref(self: *Common) void {
        if (self.refs.fetchSub(1, .acq_rel) == 1) self.destroy(self);
    }

    /// Drop the Python references held by the job. Requires an attached thread.
    fn releasePy(self: *Common) void {
        py.Py_DecRef(self.loop);
        py.Py_DecRef(self.pyfut);
        if (self.release_held) |release| release(self);
    }

    /// Drop the keep-alive reference. Requires an attached thread, and must only
    /// run once the Zig task has finished (it may still be reading `self`).
    fn releaseKeepalive(self: *Common) void {
        if (self.keepalive) |o| {
            self.keepalive = null;
            py.Py_DecRef(o);
        }
    }

    /// Supervisor side (no Python thread state): attach just to release.
    fn releaseKeepaliveDetached(self: *Common) void {
        if (self.keepalive == null) return;
        if (@hasDecl(c, "Py_IsFinalizing") and c.Py_IsFinalizing() != 0) return;
        const g = c.PyGILState_Ensure();
        defer c.PyGILState_Release(g);
        self.releaseKeepalive();
    }
};

/// Jobs allocated and not yet freed (joined by the supervisor and released
/// by the done-callback). Exposed for leak checks and diagnostics.
var live_jobs = std.atomic.Value(usize).init(0);

pub fn liveJobs() usize {
    return live_jobs.load(.acquire);
}

var q_mutex: Io.Mutex = .init;
var q_cond: Io.Condition = .init;
var q_head: ?*Common = null;

fn enqueue(job: *Common, cancel: bool) void {
    const i = io();
    job.cancel = cancel;
    q_mutex.lockUncancelable(i);
    job.next = q_head;
    q_head = job;
    q_mutex.unlock(i);
    q_cond.signal(i);
}

// Jobs waiting for a concurrency slot (FIFO).
var pending_mutex: Io.Mutex = .init;
var pending: std.ArrayList(*Common) = .empty;
var pending_head: usize = 0;

/// Try to start a job now; queue it if the concurrency limit is reached.
fn startOrQueue(job: *Common) !void {
    const i = io();
    pending_mutex.lockUncancelable(i);
    defer pending_mutex.unlock(i);
    if (pending.items.len == pending_head) {
        if (job.start(job, i)) |_| {
            job.started = true;
            return;
        } else |err| switch (err) {
            error.ConcurrencyUnavailable => {},
        }
    }
    try pending.append(gpa, job);
}

/// Start as many pending jobs as the limit allows (supervisor, after joins).
fn startPending(i: Io) void {
    pending_mutex.lockUncancelable(i);
    defer pending_mutex.unlock(i);
    while (pending_head < pending.items.len) {
        const job = pending.items[pending_head];
        if (job.state.load(.acquire) != Common.cancelled) {
            job.start(job, i) catch break;
            job.started = true;
        }
        pending_head += 1;
    }
    if (pending_head == pending.items.len) {
        pending.clearRetainingCapacity();
        pending_head = 0;
    }
}

/// Remove a not-yet-started job from the pending FIFO. Returns true if it was
/// pending (so it has no Io task to cancel or await).
fn unqueue(job: *Common, i: Io) bool {
    pending_mutex.lockUncancelable(i);
    defer pending_mutex.unlock(i);
    if (job.started) return false;
    for (pending.items[pending_head..], pending_head..) |p, idx| {
        if (p == job) {
            _ = pending.orderedRemove(idx);
            break;
        }
    }
    return true;
}

fn supervise(i: Io) void {
    while (true) {
        q_mutex.lockUncancelable(i);
        while (q_head == null) q_cond.waitUncancelable(i, &q_mutex);
        var it = q_head;
        q_head = null;
        q_mutex.unlock(i);
        while (it) |job| {
            it = job.next;
            if (job.cancel and unqueue(job, i)) {
                job.releaseKeepaliveDetached();
                job.unref(); // never started: nothing to cancel or await
            } else {
                job.finish(job, i, job.cancel);
            }
        }
        startPending(i);
    }
}

// ============================================================================
// Python-side glue (runs on the event loop thread)
// ============================================================================

var get_running_loop: lazy.LazyObject = .{};
var cancelled_error: lazy.LazyObject = .{};

fn asyncioAttr(cache: *lazy.LazyObject, name: [*:0]const u8) ?*PyObject {
    if (cache.get()) |o| return o;
    const mod = c.PyImport_ImportModule("asyncio") orelse return null;
    defer py.Py_DecRef(mod);
    const o = c.PyObject_GetAttrString(mod, name) orelse return null;
    return cache.publish(o);
}

/// Interned method names, created once (avoids building and hashing a new
/// `str` per call, which `PyObject_GetAttrString` does).
const Name = enum { done, set_result, set_exception, cancelled, create_future, add_done_callback, call_soon_threadsafe };
var name_cache: [@typeInfo(Name).@"enum".fields.len]lazy.LazyObject = @splat(.{});

fn nameObj(comptime n: Name) ?*PyObject {
    const slot = &name_cache[@intFromEnum(n)];
    if (slot.get()) |o| return o;
    const o = c.PyUnicode_InternFromString(@tagName(n)) orelse return null;
    return slot.publish(o);
}

fn callMethod(obj: *PyObject, comptime name: Name, arg: ?*PyObject) ?*PyObject {
    const n = nameObj(name) orelse return null;
    return if (arg) |a|
        c.PyObject_CallMethodObjArgs(obj, n, a, @as(?*PyObject, null))
    else
        c.PyObject_CallMethodObjArgs(obj, n, @as(?*PyObject, null));
}

fn isTrue(obj: ?*PyObject) bool {
    const o = obj orelse return false;
    defer py.Py_DecRef(o);
    return c.PyObject_IsTrue(o) == 1;
}

/// Per-event-loop completion hub. Workers push finished jobs onto a lock-free
/// stack without touching Python; only the push that makes the stack
/// non-empty schedules one `drain` on the loop (the sole moment a worker
/// attaches to Python). The drain resolves the whole batch on the loop thread.
const Hub = struct {
    loop: *PyObject, // strong ref; hubs live for the process
    head: ?*Common = null,
    scheduled: std.atomic.Value(bool) = .init(false),
    drain_cb: *PyObject,

    fn push(hub: *Hub, job: *Common) void {
        var old = @atomicLoad(?*Common, &hub.head, .monotonic);
        while (true) {
            job.next_done = old;
            old = @cmpxchgWeak(?*Common, &hub.head, old, job, .release, .monotonic) orelse break;
        }
        if (!hub.scheduled.swap(true, .acq_rel)) hub.scheduleDrain();
    }

    fn scheduleDrain(hub: *Hub) void {
        if (@hasDecl(c, "Py_IsFinalizing") and c.Py_IsFinalizing() != 0) return;
        const g = c.PyGILState_Ensure();
        defer c.PyGILState_Release(g);
        if (callMethod(hub.loop, .call_soon_threadsafe, hub.drain_cb)) |r| {
            py.Py_DecRef(r);
        } else {
            // Loop closed: nobody will resolve these futures; just clean up.
            c.PyErr_Clear();
            hub.scheduled.store(false, .release);
            var it = @atomicRmw(?*Common, &hub.head, .Xchg, null, .acquire);
            while (it) |job| {
                it = job.next_done;
                job.releasePy();
                job.releaseKeepalive();
                enqueue(job, false);
            }
        }
    }

    fn drain(hub: *Hub) void {
        // Clear the flag *before* taking the list: any later push schedules again.
        hub.scheduled.store(false, .release);
        var it = @atomicRmw(?*Common, &hub.head, .Xchg, null, .acquire);
        // The stack is LIFO; reverse to resolve in completion order.
        var fifo: ?*Common = null;
        while (it) |job| {
            it = job.next_done;
            job.next_done = fifo;
            fifo = job;
        }
        while (fifo) |job| {
            fifo = job.next_done;
            job.resolve(job);
            job.releasePy();
            job.releaseKeepalive();
            enqueue(job, false);
        }
    }
};

fn drainEntry(self: ?*PyObject, _: ?*PyObject) callconv(.c) ?*PyObject {
    const hub: *Hub = @ptrCast(@alignCast(c.PyCapsule_GetPointer(self, "pyoz.aio.hub") orelse return null));
    hub.drain();
    return py.Py_RETURN_NONE();
}

var drain_def = py.c.PyMethodDef{ .ml_name = "_pyoz_drain", .ml_meth = @ptrCast(&drainEntry), .ml_flags = py.METH_NOARGS, .ml_doc = null };

// Hub registry: one hub per event loop (usually just one).
var hubs_mutex: Io.Mutex = .init;
var hubs: std.ArrayList(*Hub) = .empty;

fn hubFor(loop: *PyObject) ?*Hub {
    const i = io();
    hubs_mutex.lockUncancelable(i);
    defer hubs_mutex.unlock(i);
    for (hubs.items) |h| if (h.loop == loop) return h;

    const hub = gpa.create(Hub) catch return null;
    const capsule = c.PyCapsule_New(hub, "pyoz.aio.hub", null) orelse {
        gpa.destroy(hub);
        return null;
    };
    defer py.Py_DecRef(capsule);
    const cb = c.PyCFunction_NewEx(&drain_def, capsule, null) orelse {
        gpa.destroy(hub);
        return null;
    };
    hubs.append(gpa, hub) catch {
        py.Py_DecRef(cb);
        gpa.destroy(hub);
        return null;
    };
    py.Py_IncRef(loop);
    hub.* = .{ .loop = loop, .drain_cb = cb };
    return hub;
}

/// Future done-callback: turns asyncio cancellation into Zig cancellation.
fn onDone(self: ?*PyObject, fut: ?*PyObject) callconv(.c) ?*PyObject {
    const job: *Common = @ptrCast(@alignCast(c.PyCapsule_GetPointer(self, "pyoz.aio.job") orelse return null));
    if (isTrue(callMethod(fut.?, .cancelled, null))) {
        if (job.state.cmpxchgStrong(Common.running, Common.cancelled, .acq_rel, .acquire) == null) {
            job.releasePy();
            enqueue(job, true);
        }
    }
    return py.Py_RETURN_NONE();
}

fn capsuleDestructor(capsule: ?*PyObject) callconv(.c) void {
    const job: *Common = @ptrCast(@alignCast(c.PyCapsule_GetPointer(capsule, "pyoz.aio.job") orelse return));
    job.unref();
}

var on_done_def = py.c.PyMethodDef{ .ml_name = "_pyoz_on_done", .ml_meth = @ptrCast(&onDone), .ml_flags = py.METH_O, .ml_doc = null };
// ============================================================================
// Per-function job type
// ============================================================================

fn isCopyable(comptime T: type) bool {
    return switch (@typeInfo(T)) {
        .int, .float, .bool, .@"enum" => true,
        .optional => |o| isCopyable(o.child),
        .pointer => |p| p.size == .slice and p.child == u8 and p.is_const,
        // Structs by value (PyOZ classes, Complex, datetime types, ...) are
        // copied when the call is made; they must not point into memory that
        // Python still owns, so any pointer field is rejected.
        .@"struct" => pointerFree(T),
        else => false,
    };
}

fn pointerFree(comptime T: type) bool {
    return switch (@typeInfo(T)) {
        .pointer => false,
        .@"struct" => |st| blk: {
            for (st.fields) |fld| if (!pointerFree(fld.type)) break :blk false;
            break :blk true;
        },
        .optional => |o| pointerFree(o.child),
        .array => |a| pointerFree(a.child),
        .@"union" => |u| blk: {
            for (u.fields) |fld| if (!pointerFree(fld.type)) break :blk false;
            break :blk true;
        },
        else => true,
    };
}

/// Address of the Python object that owns a PyOZ class instance's data.
/// Mirrors the layout of class/wrapper.zig's PyWrapper (header, then data at
/// the type's alignment). Builtin subclasses are rejected by the caller.
fn objectFromData(comptime T: type, p: *const T) *PyObject {
    const Probe = extern struct {
        ob_base: py.PyObject,
        data: [@sizeOf(T)]u8 align(if (@sizeOf(T) == 0) 1 else @alignOf(T)),
    };
    return @ptrFromInt(@intFromPtr(p) - @offsetOf(Probe, "data"));
}

fn isFrozenClass(comptime T: type) bool {
    return @hasDecl(T, "__frozen__") and @TypeOf(T.__frozen__) == bool and T.__frozen__;
}

/// Borrowing requires that nothing can mutate the fields while the task reads
/// them: frozen blocks Python-side setattr, and no `*T` method may exist.
fn assertBorrowable(comptime T: type) void {
    if (@hasDecl(T, "__base__")) @compileError("pyoz.asyncMethod: " ++ @typeName(T) ++
        " subclasses a builtin type; take `self: " ++ @typeName(T) ++ "` by value instead");
    if (!isFrozenClass(T)) @compileError("pyoz.asyncMethod: `self: *const " ++ @typeName(T) ++
        "` borrows the object while the task runs, so the class must be immutable: add " ++
        "`pub const __frozen__ = true;`, or take `self: " ++ @typeName(T) ++ "` by value to run on a copy");
    for (@typeInfo(T).@"struct".decls) |d| {
        const V = @TypeOf(@field(T, d.name));
        if (@typeInfo(V) == .@"fn") {
            const ps = @typeInfo(V).@"fn".params;
            if (ps.len > 0 and ps[0].type == *T) @compileError("pyoz.asyncMethod: " ++ @typeName(T) ++
                "." ++ d.name ++ " takes `*" ++ @typeName(T) ++ "` and could mutate the object while an " ++
                "async method borrows it; take `self` by value to run on a copy instead");
        }
    }
}

/// Returned by the Python-visible async wrapper. PyOZ's return conversion
/// calls `bind` with the module's Converter (and error mappings), which
/// installs the result converter and yields the asyncio.Future.
pub fn AsyncPending(comptime Job: type) type {
    return struct {
        job: *Job,
        pyfut: *PyObject,

        pub const _is_pyoz_async_pending = {};
        /// For stubs: keeps a `pyoz.Signature` wrapper, so its stub string is used.
        pub const Result = Job.StubResult;

        pub fn bind(self: @This(), comptime Conv: type, comptime error_mappings: []const errors_mod.ErrorMapping) ?*PyObject {
            self.job.common.convert = &Job.Converting(Conv, error_mappings).convert;
            return self.pyfut;
        }
    };
}

pub fn isAsyncPending(comptime T: type) bool {
    return @typeInfo(T) == .@"struct" and @hasDecl(T, "_is_pyoz_async_pending");
}

const SelfMode = enum { none, copy, borrow };

fn isHeldObject(comptime T: type) bool {
    return T == *PyObject or T == ?*PyObject;
}

/// A task result that owns something: a Python reference, or a struct with
/// `__del__` (a PyOZ class by value).
fn needsDrop(comptime T: type) bool {
    return switch (@typeInfo(T)) {
        .optional => |o| needsDrop(o.child),
        .pointer => T == *PyObject,
        .@"struct" => @hasDecl(T, "__del__"),
        else => false,
    };
}

/// Release a result that will never reach Python. Requires an attached thread.
fn dropValue(comptime T: type, value: T) void {
    switch (@typeInfo(T)) {
        .optional => |o| if (value) |v| dropValue(o.child, v),
        .pointer => py.Py_DecRef(value),
        .@"struct" => {
            var copy = value;
            T.__del__(&copy);
        },
        else => {},
    }
}

/// `then` is the completion step of `asyncThen` / `asyncMethodThen`, or `{}`.
pub fn AsyncFn(comptime f: anytype, comptime is_method: bool, comptime then: anytype) type {
    const info = @typeInfo(@TypeOf(f)).@"fn";
    const P = info.params;
    const self_n: usize = @intFromBool(is_method);
    if (is_method and P.len == 0) @compileError("pyoz.asyncMethod: the function needs a `self` parameter");
    const SelfArg = if (is_method) P[0].type.? else void;
    const self_mode: SelfMode = if (!is_method) .none else switch (@typeInfo(SelfArg)) {
        .pointer => |p| if (p.size == .one and p.is_const) .borrow else @compileError(
            "pyoz.asyncMethod: `self: *" ++ @typeName(p.child) ++ "` is not allowed: the task runs on another " ++
                "thread while Python can still use the object. Use `self: " ++ @typeName(p.child) ++
                "` (runs on a copy) or `self: *const " ++ @typeName(p.child) ++ "` on a frozen class",
        ),
        .@"struct" => .copy,
        else => @compileError("pyoz.asyncMethod: first parameter must be `self: T` or `self: *const T`"),
    };
    const SelfT = switch (self_mode) {
        .none => void,
        .copy => SelfArg,
        .borrow => @typeInfo(SelfArg).pointer.child,
    };
    if (self_mode == .copy and !pointerFree(SelfT)) @compileError("pyoz.asyncMethod: `self: " ++ @typeName(SelfT) ++
        "` by value needs pointer-free fields (a copy would alias memory Python still owns)");
    const has_io = P.len > self_n and P[self_n].type.? == Io;
    const ai = self_n + @intFromBool(has_io);
    const has_alloc = P.len > ai and P[ai].type.? == std.mem.Allocator;
    const skip = ai + @intFromBool(has_alloc);
    // A `pyoz.Signature(T, "stub")` return is unwrapped: the task stores and
    // converts T, the stub string only reaches the generated stubs.
    const RawRet = info.return_type.?;
    const Ret = root.unwrapSignature(RawRet);

    const WorkPayload = if (@typeInfo(Ret) == .error_union) @typeInfo(Ret).error_union.payload else Ret;

    // Completion step: `then(result, extra...)`. Its extra parameters follow
    // the task's own in the Python signature.
    const has_then = @TypeOf(then) != void;
    const TP = if (has_then) @typeInfo(@TypeOf(then)).@"fn".params else &[_]std.builtin.Type.Fn.Param{};
    if (has_then and (TP.len == 0 or TP[0].type.? != WorkPayload)) @compileError(
        "pyoz.asyncThen: the completion function's first parameter must be the task's result, " ++ @typeName(WorkPayload),
    );
    const extra = if (has_then) TP[1..] else TP;
    const RawThenRet = if (has_then) @typeInfo(@TypeOf(then)).@"fn".return_type.? else void;
    const ThenRet = root.unwrapSignature(RawThenRet);
    const n_work = P.len - skip;

    const vis: [n_work + extra.len]type = blk: {
        var v: [n_work + extra.len]type = undefined;
        for (P[skip..], 0..) |p, i| {
            if (!isCopyable(p.type.?)) @compileError("pyoz.asyncFn: unsupported parameter type " ++ @typeName(p.type.?) ++
                " (supported: ints, floats, bools, enums, optionals, []const u8, pointer-free structs incl. PyOZ classes by value)");
            v[i] = p.type.?;
        }
        for (extra, n_work..) |p, i| {
            if (!isHeldObject(p.type.?) and !isCopyable(p.type.?)) @compileError("pyoz.asyncThen: unsupported parameter type " ++
                @typeName(p.type.?) ++ " (supported: *pyoz.PyObject, ?*pyoz.PyObject and the types pyoz.asyncFn accepts)");
            v[i] = p.type.?;
        }
        break :blk v;
    };
    const Payload = std.meta.Tuple(&vis);
    const Conv = conversion.Converter(&.{});

    return struct {
        const Self = @This();

        common: Common,
        future: Io.Future(void) = undefined,
        arena: std.heap.ArenaAllocator,
        payload: Payload,
        self_val: if (self_mode == .copy) SelfT else void = undefined,
        self_ptr: if (self_mode == .borrow) *const SelfT else void = undefined,
        result: Ret = undefined,
        /// `result` is set and nobody has taken ownership of it yet.
        result_live: bool = false,
        /// The payload's Python objects hold a reference (see `releaseHeld`).
        held: bool = false,

        /// Drop the references to the Python objects passed to the completion
        /// step. Runs with an attached thread, from `Common.releasePy`.
        fn releaseHeld(common: *Common) void {
            const job: *Self = @fieldParentPtr("common", common);
            if (!job.held) return;
            job.held = false;
            inline for (n_work..vis.len) |i| {
                if (comptime vis[i] == *PyObject) py.Py_DecRef(job.payload[i]);
                if (comptime vis[i] == ?*PyObject) if (job.payload[i]) |o| py.Py_DecRef(o);
            }
        }

        fn run(job: *Self) void {
            var call_args: std.meta.ArgsTuple(@TypeOf(f)) = undefined;
            switch (self_mode) {
                .none => {},
                .copy => call_args[0] = job.self_val,
                .borrow => call_args[0] = job.self_ptr,
            }
            if (has_io) call_args[self_n] = io();
            if (has_alloc) call_args[ai] = job.arena.allocator();
            inline for (0..n_work) |i| call_args[skip + i] = job.payload[i];

            job.result = root.unwrapSignatureValue(RawRet, @call(.auto, f, call_args));
            job.result_live = true;

            // If Python already cancelled, the supervisor owns cleanup (and
            // drops the result once it has joined this task): just return.
            if (job.common.state.cmpxchgStrong(Common.running, Common.posting, .acq_rel, .acquire) != null) return;
            job.common.hub.push(&job.common); // no Python here (except to wake an idle loop)
        }

        /// The result never reached Python (cancelled, or the loop is closed):
        /// release what it owns. Called by the supervisor after the task has
        /// been joined, so nothing else can touch the job.
        fn dropResult(job: *Self) void {
            if (!job.result_live) return;
            job.result_live = false;
            if (comptime !needsDrop(WorkPayload)) return;
            const value = if (@typeInfo(Ret) == .error_union) job.result catch return else job.result;
            if (@hasDecl(c, "Py_IsFinalizing") and c.Py_IsFinalizing() != 0) return;
            const g = c.PyGILState_Ensure();
            defer c.PyGILState_Release(g);
            dropValue(WorkPayload, value);
        }

        fn resolve(common: *Common) void {
            // Cancelled after completion: the supervisor drops the result
            if (isTrue(callMethod(common.pyfut, .done, null))) return;
            var is_exc = false;
            const convert = common.convert orelse &Converting(Conv, &.{}).convert;
            const value = convert(common, &is_exc) orelse blk: {
                is_exc = true; // conversion raised: deliver that exception instead
                if (c.PyErr_Occurred() == null) {
                    // Never leave the awaitable pending: it would hang forever
                    py.PyErr_SetString(c.PyExc_SystemError, "pyoz: async result conversion failed without setting an exception");
                }
                break :blk fetchException() orelse return;
            };
            defer py.Py_DecRef(value);
            const r = if (is_exc) callMethod(common.pyfut, .set_exception, value) else callMethod(common.pyfut, .set_result, value);
            if (r) |o| py.Py_DecRef(o) else c.PyErr_Clear();
        }

        /// What the awaitable resolves to: the completion step's result if
        /// there is one, otherwise the task's.
        pub const ResultPayload = if (!has_then)
            WorkPayload
        else if (@typeInfo(ThenRet) == .error_union)
            @typeInfo(ThenRet).error_union.payload
        else
            ThenRet;

        /// The type stubs describe: the `pyoz.Signature` wrapper when the
        /// function that produces the final value returns one.
        pub const StubResult = blk: {
            const Final = if (has_then) RawThenRet else RawRet;
            break :blk if (Final != root.unwrapSignature(Final)) Final else ResultPayload;
        };

        pub fn Converting(comptime C: type, comptime error_mappings: []const errors_mod.ErrorMapping) type {
            return struct {
                fn convert(common: *Common, is_exc: *bool) ?*PyObject {
                    const job: *Self = @fieldParentPtr("common", common);
                    job.result_live = false; // from here the value belongs to `then` / Python
                    const work_value = if (@typeInfo(Ret) == .error_union) job.result catch |err| {
                        is_exc.* = true;
                        return makeException(err, error_mappings);
                    } else job.result;
                    const value: ResultPayload = if (!has_then) work_value else blk: {
                        // Loop thread, Python attached: the step may use any Python API.
                        var then_args: std.meta.ArgsTuple(@TypeOf(then)) = undefined;
                        then_args[0] = work_value;
                        inline for (n_work..vis.len, 1..) |i, j| then_args[j] = job.payload[i];
                        const out = root.unwrapSignatureValue(RawThenRet, @call(.auto, then, then_args));
                        const unwrapped = if (@typeInfo(ThenRet) == .error_union) out catch |err| {
                            is_exc.* = true;
                            return makeException(err, error_mappings);
                        } else out;
                        // A step that raised and returned null: deliver its exception
                        if (c.PyErr_Occurred() != null) return null;
                        break :blk unwrapped;
                    };
                    if (@typeInfo(ResultPayload) == .optional and value == null and common.null_stops) {
                        is_exc.* = true;
                        return c.PyObject_CallObject(c.PyExc_StopAsyncIteration, null);
                    }
                    return C.toPy(ResultPayload, value);
                }
            };
        }

        fn start(common: *Common, i: Io) Io.ConcurrentError!void {
            const job: *Self = @fieldParentPtr("common", common);
            job.future = try i.concurrent(run, .{job});
        }

        fn finish(common: *Common, i: Io, cancel: bool) void {
            const job: *Self = @fieldParentPtr("common", common);
            if (cancel) job.future.cancel(i) else job.future.await(i);
            job.dropResult();
            common.releaseKeepaliveDetached(); // task has finished: safe now
            common.unref();
        }

        fn destroy(common: *Common) void {
            const job: *Self = @fieldParentPtr("common", common);
            job.arena.deinit();
            gpa.destroy(job);
            _ = live_jobs.fetchSub(1, .acq_rel);
        }

        fn submit(self_arg: if (is_method) *const SelfT else void, payload: Payload) !AsyncPending(Self) {
            const loop = c.PyObject_CallObject(asyncioAttr(&get_running_loop, "get_running_loop") orelse return error.PythonError, null) orelse
                return error.PythonError;
            const pyfut = callMethod(loop, .create_future, null) orelse {
                py.Py_DecRef(loop);
                return error.PythonError;
            };

            const hub = hubFor(loop) orelse {
                py.Py_DecRef(loop);
                py.Py_DecRef(pyfut);
                if (c.PyErr_Occurred() == null) _ = c.PyErr_NoMemory();
                return error.PythonError;
            };
            const job = gpa.create(Self) catch {
                py.Py_DecRef(loop);
                py.Py_DecRef(pyfut);
                _ = c.PyErr_NoMemory();
                return error.PythonError;
            };
            _ = live_jobs.fetchAdd(1, .acq_rel);
            job.* = .{
                .common = .{ .loop = loop, .pyfut = pyfut, .hub = hub, .finish = finish, .destroy = destroy, .resolve = resolve, .start = start },
                .arena = .init(gpa),
                .payload = undefined,
            };
            switch (self_mode) {
                .none => {},
                // Snapshot taken under the object's critical section (methods
                // are wrapped by class/threading.zig on free-threaded builds).
                .copy => job.self_val = self_arg.*,
                .borrow => {
                    job.self_ptr = self_arg;
                    const obj = objectFromData(SelfT, self_arg);
                    py.Py_IncRef(obj);
                    job.common.keepalive = obj;
                },
            }
            // Copy arguments: Python-owned buffers may be freed before the task runs.
            inline for (0..vis.len) |i| {
                job.payload[i] = if (comptime @typeInfo(vis[i]) == .pointer and !isHeldObject(vis[i]))
                    job.arena.allocator().dupe(u8, payload[i]) catch {
                        abandon(job);
                        _ = c.PyErr_NoMemory();
                        return error.PythonError;
                    }
                else
                    payload[i];
            }
            // Objects for the completion step stay alive until it has run
            if (has_then) {
                inline for (n_work..vis.len) |i| {
                    if (comptime vis[i] == *PyObject) py.Py_IncRef(job.payload[i]);
                    if (comptime vis[i] == ?*PyObject) if (job.payload[i]) |o| py.Py_IncRef(o);
                }
                job.held = true;
                job.common.release_held = releaseHeld;
            }

            // Done-callback owns one job reference through its capsule.
            const capsule = c.PyCapsule_New(&job.common, "pyoz.aio.job", capsuleDestructor) orelse {
                abandon(job);
                return error.PythonError;
            };
            const cb = c.PyCFunction_NewEx(&on_done_def, capsule, null);
            py.Py_DecRef(capsule); // cb holds it (or the capsule's destructor already unref'd)
            const added = if (cb) |f_obj| callMethod(pyfut, .add_done_callback, f_obj) else null;
            if (cb) |f_obj| py.Py_DecRef(f_obj);
            if (added) |o| py.Py_DecRef(o) else {
                job.common.releasePy();
                job.common.releaseKeepalive();
                job.common.unref(); // supervisor's ref; capsule already dropped its own
                return error.PythonError;
            }

            startOrQueue(&job.common) catch {
                // Out of memory for the pending queue: fail the future.
                job.common.state.store(Common.cancelled, .release);
                const r = callMethod(pyfut, .set_exception, c.PyExc_MemoryError);
                if (r) |o| py.Py_DecRef(o) else c.PyErr_Clear();
                py.Py_IncRef(pyfut);
                job.common.releasePy();
                job.common.releaseKeepalive();
                job.common.unref();
                return .{ .job = job, .pyfut = pyfut };
            };

            py.Py_IncRef(pyfut); // the caller's reference
            return .{ .job = job, .pyfut = pyfut };
        }

        fn abandon(job: *Self) void {
            job.common.releasePy();
            job.common.releaseKeepalive();
            destroy(&job.common);
        }

        const Pending = AsyncPending(Self);
        const fn_call = switch (vis.len) {
            0 => struct {
                fn call() !Pending {
                    return submit({}, .{});
                }
            }.call,
            1 => struct {
                fn call(a: vis[0]) !Pending {
                    return submit({}, .{a});
                }
            }.call,
            2 => struct {
                fn call(a: vis[0], b: vis[1]) !Pending {
                    return submit({}, .{ a, b });
                }
            }.call,
            3 => struct {
                fn call(a: vis[0], b: vis[1], d: vis[2]) !Pending {
                    return submit({}, .{ a, b, d });
                }
            }.call,
            4 => struct {
                fn call(a: vis[0], b: vis[1], d: vis[2], e: vis[3]) !Pending {
                    return submit({}, .{ a, b, d, e });
                }
            }.call,
            5 => struct {
                fn call(a: vis[0], b: vis[1], d: vis[2], e: vis[3], g: vis[4]) !Pending {
                    return submit({}, .{ a, b, d, e, g });
                }
            }.call,
            6 => struct {
                fn call(a: vis[0], b: vis[1], d: vis[2], e: vis[3], g: vis[4], h: vis[5]) !Pending {
                    return submit({}, .{ a, b, d, e, g, h });
                }
            }.call,
            7 => struct {
                fn call(a: vis[0], b: vis[1], d: vis[2], e: vis[3], g: vis[4], h: vis[5], j: vis[6]) !Pending {
                    return submit({}, .{ a, b, d, e, g, h, j });
                }
            }.call,
            8 => struct {
                fn call(a: vis[0], b: vis[1], d: vis[2], e: vis[3], g: vis[4], h: vis[5], j: vis[6], k: vis[7]) !Pending {
                    return submit({}, .{ a, b, d, e, g, h, j, k });
                }
            }.call,
            else => @compileError("pyoz.asyncFn: at most 8 Python-visible parameters are supported"),
        };
        const method_call = switch (vis.len) {
            0 => struct {
                fn call(s: *const SelfT) !Pending {
                    comptime if (self_mode == .borrow) assertBorrowable(SelfT);
                    return submit(s, .{});
                }
            }.call,
            1 => struct {
                fn call(s: *const SelfT, a: vis[0]) !Pending {
                    comptime if (self_mode == .borrow) assertBorrowable(SelfT);
                    return submit(s, .{a});
                }
            }.call,
            2 => struct {
                fn call(s: *const SelfT, a: vis[0], b: vis[1]) !Pending {
                    comptime if (self_mode == .borrow) assertBorrowable(SelfT);
                    return submit(s, .{ a, b });
                }
            }.call,
            3 => struct {
                fn call(s: *const SelfT, a: vis[0], b: vis[1], d: vis[2]) !Pending {
                    comptime if (self_mode == .borrow) assertBorrowable(SelfT);
                    return submit(s, .{ a, b, d });
                }
            }.call,
            4 => struct {
                fn call(s: *const SelfT, a: vis[0], b: vis[1], d: vis[2], e: vis[3]) !Pending {
                    comptime if (self_mode == .borrow) assertBorrowable(SelfT);
                    return submit(s, .{ a, b, d, e });
                }
            }.call,
            5 => struct {
                fn call(s: *const SelfT, a: vis[0], b: vis[1], d: vis[2], e: vis[3], g: vis[4]) !Pending {
                    comptime if (self_mode == .borrow) assertBorrowable(SelfT);
                    return submit(s, .{ a, b, d, e, g });
                }
            }.call,
            6 => struct {
                fn call(s: *const SelfT, a: vis[0], b: vis[1], d: vis[2], e: vis[3], g: vis[4], h: vis[5]) !Pending {
                    comptime if (self_mode == .borrow) assertBorrowable(SelfT);
                    return submit(s, .{ a, b, d, e, g, h });
                }
            }.call,
            7 => struct {
                fn call(s: *const SelfT, a: vis[0], b: vis[1], d: vis[2], e: vis[3], g: vis[4], h: vis[5], j: vis[6]) !Pending {
                    comptime if (self_mode == .borrow) assertBorrowable(SelfT);
                    return submit(s, .{ a, b, d, e, g, h, j });
                }
            }.call,
            8 => struct {
                fn call(s: *const SelfT, a: vis[0], b: vis[1], d: vis[2], e: vis[3], g: vis[4], h: vis[5], j: vis[6], k: vis[7]) !Pending {
                    comptime if (self_mode == .borrow) assertBorrowable(SelfT);
                    return submit(s, .{ a, b, d, e, g, h, j, k });
                }
            }.call,
            else => @compileError("pyoz.asyncFn: at most 8 Python-visible parameters are supported"),
        };
        pub const call = if (is_method) method_call else fn_call;
    };
}

fn makeException(err: anyerror, comptime error_mappings: []const errors_mod.ErrorMapping) ?*PyObject {
    if (err == error.Canceled) {
        const exc_type = asyncioAttr(&cancelled_error, "CancelledError") orelse return null;
        return c.PyObject_CallObject(exc_type, null);
    }
    // Same mapping as synchronous functions (module `mapError`s, then well-known names).
    errors_mod.setErrorFromMapping(error_mappings, err);
    return fetchException();
}

fn fetchException() ?*PyObject {
    if (@hasDecl(c, "PyErr_GetRaisedException")) return c.PyErr_GetRaisedException();
    var t: ?*PyObject = null;
    var v: ?*PyObject = null;
    var tb: ?*PyObject = null;
    c.PyErr_Fetch(&t, &v, &tb);
    c.PyErr_NormalizeException(&t, &v, &tb);
    if (t) |o| py.Py_DecRef(o);
    if (tb) |o| py.Py_DecRef(o);
    return v;
}

/// Wrap `f` as a Python function returning an `asyncio.Future`. See module docs.
pub fn asyncFn(comptime f: anytype) @TypeOf(AsyncFn(f, false, {}).call) {
    return AsyncFn(f, false, {}).call;
}

/// `asyncFn` with a completion step. `f` runs on a worker task as usual; when
/// it succeeds, `then(result, extra...)` runs on the event loop thread with
/// Python attached, and the awaitable resolves to what `then` returns:
///
///     fn compileImpl(grammar: []const u8) !Parser { ... }            // worker, no Python
///     fn bindImpl(parser: Parser, classes: ?*pyoz.PyObject) !Parser { ... } // Python allowed
///     pyoz.func("compile_async", pyoz.asyncThen(compileImpl, bindImpl), "...")
///
///     parser = await mymod.compile_async(text, classes)
///
/// The Python signature is `f`'s parameters followed by `then`'s extra ones.
/// Those may be `*pyoz.PyObject` / `?*pyoz.PyObject` (borrowed by `then`, kept
/// alive until it has run) or any type `asyncFn` accepts. `then` is skipped if
/// `f` fails or the awaitable is cancelled. It may return an error, or raise a
/// Python exception and return null from an optional. Keep it short: it runs
/// on the event loop.
pub fn asyncThen(comptime f: anytype, comptime then: anytype) @TypeOf(AsyncFn(f, false, then).call) {
    return AsyncFn(f, false, then).call;
}

/// `asyncMethod` with a completion step; see `asyncThen`.
pub fn asyncMethodThen(comptime f: anytype, comptime then: anytype) @TypeOf(AsyncFn(f, true, then).call) {
    return AsyncFn(f, true, then).call;
}

/// Type returned (inside an error union) by calling `asyncFn(f)` from Zig, for
/// async dunders that start a task:
///
///     const fetch = pyoz.asyncFn(fetchImpl);
///     pub fn __anext__(self: *Pages) !?pyoz.Future(fetchImpl) { ... return try fetch(n); }
pub fn Future(comptime f: anytype) type {
    return AsyncPending(AsyncFn(f, false, {}));
}

/// Async instance method. The first parameter decides how `self` reaches the
/// worker thread, and PyOZ enforces the matching safety contract at comptime:
///
///   * `self: T` (by value): runs on a copy taken at call time; mutations made
///     by the task do not affect the Python object. Needs pointer-free fields.
///   * `self: *const T`: borrows the object; it is kept alive until the task is
///     joined. Only allowed on frozen classes (`__frozen__ = true`) with no
///     `*T` methods, so nothing can mutate the fields while the task reads them.
///   * `self: *T`: rejected.
///
///     fn normImpl(self: *const Vec, io: std.Io) !f64 { ... }
///     pub const norm = pyoz.asyncMethod(normImpl);
pub fn asyncMethod(comptime f: anytype) @TypeOf(AsyncFn(f, true, {}).call) {
    return AsyncFn(f, true, {}).call;
}
