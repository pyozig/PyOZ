//! Awaitables for the async protocols (`__await__`, `__anext__`, `__aenter__`,
//! `__aexit__`).
//!
//! Python requires these dunders to produce awaitables. PyOZ converts whatever
//! the Zig method returns:
//!
//!   * a `pyoz.asyncFn` / `pyoz.asyncMethod` result: the asyncio.Future itself;
//!   * a raw `*PyObject`: assumed to already be an awaitable (e.g. a coroutine
//!     obtained by calling a Python `async def`), passed through;
//!   * any other Zig value: a *ready* awaitable that completes immediately with
//!     the converted value. It never suspends, so it works under any event loop
//!     (asyncio, trio, anyio, a bare `coro.send(None)` driver).
//!
//! For `__anext__`, a `null` optional ends the iteration: the awaitable raises
//! `StopAsyncIteration`, both when `__anext__` itself returns null and when an
//! async task's `?T` result resolves to null.

const std = @import("std");
const py = @import("python.zig");
const c = py.c;
const PyObject = py.PyObject;
const slots = @import("python/slots.zig");
const lazy = @import("python/lazy.zig");
const errors_mod = @import("errors.zig");
const aio = @import("aio.zig");

// ============================================================================
// Ready awaitable: `await r` evaluates to a value (or raises) without suspending
// ============================================================================

const Ready = extern struct {
    ob_base: PyObject,
    /// Owned. The result, or the exception instance when `is_exc`. Taken (set
    /// to null) by the first `__next__`, so the awaitable is single-shot.
    payload: ?*PyObject,
    is_exc: bool,
};

fn readyIterNext(self_obj: ?*PyObject) callconv(.c) ?*PyObject {
    const self: *Ready = @ptrCast(@alignCast(self_obj orelse return null));
    // Atomic take: two free-threaded awaiters of one object must not both consume it.
    const payload = @atomicRmw(?*PyObject, &self.payload, .Xchg, null, .acq_rel) orelse return null;
    defer py.Py_DecRef(payload);
    if (self.is_exc) {
        const tp = c.PyObject_Type(payload) orelse return null;
        defer py.Py_DecRef(tp);
        c.PyErr_SetObject(tp, payload);
        return null;
    }
    // The result travels in StopIteration.value. Pass an instance so a tuple or
    // exception result is not unpacked as constructor arguments.
    const stop = c.PyObject_CallFunctionObjArgs(py.PyExc_StopIteration(), payload, @as(?*PyObject, null)) orelse return null;
    defer py.Py_DecRef(stop);
    c.PyErr_SetObject(py.PyExc_StopIteration(), stop);
    return null;
}

fn readySelf(self_obj: ?*PyObject) callconv(.c) ?*PyObject {
    const o = self_obj orelse return null;
    py.Py_IncRef(o);
    return o;
}

// Generator-style methods, for code that drives `__await__()` iterators by hand.
// The awaitable never suspends, so the sent value is ignored.

fn readySend(self_obj: ?*PyObject, _: ?*PyObject) callconv(.c) ?*PyObject {
    const r = readyIterNext(self_obj);
    if (r == null and py.PyErr_Occurred() == null) c.PyErr_SetNone(py.PyExc_StopIteration());
    return r;
}

fn readyThrow(self_obj: ?*PyObject, args: ?*PyObject) callconv(.c) ?*PyObject {
    readyDrop(self_obj);
    var typ: ?*PyObject = null;
    var val: ?*PyObject = null;
    var tb: ?*PyObject = null;
    if (c.PyArg_UnpackTuple(args, "throw", 1, 3, &typ, &val, &tb) == 0) return null;
    // throw(exc_instance) or throw(ExcType[, value]): raise it in the caller.
    if (c.PyObject_IsInstance(typ.?, py.PyExc_BaseException()) == 1) {
        const tp = c.PyObject_Type(typ.?) orelse return null;
        defer py.Py_DecRef(tp);
        c.PyErr_SetObject(tp, typ.?);
    } else {
        c.PyErr_SetObject(typ.?, if (val) |v| v else py.Py_None());
    }
    return null;
}

fn readyClose(self_obj: ?*PyObject, _: ?*PyObject) callconv(.c) ?*PyObject {
    readyDrop(self_obj);
    return py.Py_RETURN_NONE();
}

fn readyDrop(self_obj: ?*PyObject) void {
    const self: *Ready = @ptrCast(@alignCast(self_obj orelse return));
    if (@atomicRmw(?*PyObject, &self.payload, .Xchg, null, .acq_rel)) |p| py.Py_DecRef(p);
}

var ready_methods = [_]py.PyMethodDef{
    .{ .ml_name = "send", .ml_meth = @ptrCast(&readySend), .ml_flags = py.METH_O, .ml_doc = null },
    .{ .ml_name = "throw", .ml_meth = @ptrCast(&readyThrow), .ml_flags = py.METH_VARARGS, .ml_doc = null },
    .{ .ml_name = "close", .ml_meth = @ptrCast(&readyClose), .ml_flags = py.METH_NOARGS, .ml_doc = null },
    .{ .ml_name = null, .ml_meth = null, .ml_flags = 0, .ml_doc = null },
};

fn readyDealloc(self_obj: ?*PyObject) callconv(.c) void {
    const o = self_obj orelse return;
    const self: *Ready = @ptrCast(@alignCast(o));
    if (self.payload) |p| py.Py_DecRef(p);
    const tp = py.Py_TYPE(o);
    py.PyObject_Del(o);
    if (tp) |t| py.Py_DecRef(@ptrCast(@alignCast(t)));
}

var ready_slots = [_]py.PyType_Slot{
    .{ .slot = slots.am_await, .pfunc = @ptrCast(@constCast(&readySelf)) },
    .{ .slot = slots.tp_iter, .pfunc = @ptrCast(@constCast(&readySelf)) },
    .{ .slot = slots.tp_iternext, .pfunc = @ptrCast(@constCast(&readyIterNext)) },
    .{ .slot = slots.tp_dealloc, .pfunc = @ptrCast(@constCast(&readyDealloc)) },
    .{ .slot = slots.tp_methods, .pfunc = @ptrCast(@constCast(&ready_methods)) },
    .{ .slot = slots.tp_doc, .pfunc = @ptrCast(@constCast("Completed awaitable returned by a PyOZ async dunder.")) },
    .{ .slot = 0, .pfunc = null },
};

var ready_spec = py.PyType_Spec{
    .name = "pyoz.ReadyAwaitable",
    .basicsize = @sizeOf(Ready),
    .itemsize = 0,
    .flags = @as(c_uint, py.Py_TPFLAGS_DEFAULT |
        (if (@hasDecl(c, "Py_TPFLAGS_DISALLOW_INSTANTIATION")) c.Py_TPFLAGS_DISALLOW_INSTANTIATION else 0)),
    .slots = @ptrCast(&ready_slots),
};

var ready_type: lazy.LazyObject = .{};

fn readyType() ?*PyObject {
    if (ready_type.get()) |t| return t;
    const t = c.PyType_FromSpec(&ready_spec) orelse return null;
    return ready_type.publish(t);
}

fn isReady(obj: *PyObject) bool {
    const t = ready_type.get() orelse return false;
    return @as(?*anyopaque, @ptrCast(py.Py_TYPE(obj))) == @as(?*anyopaque, @ptrCast(t));
}

/// New ready awaitable. Steals `payload` (also on failure).
fn newReady(payload: *PyObject, is_exc: bool) ?*PyObject {
    const tp = readyType() orelse {
        py.Py_DecRef(payload);
        return null;
    };
    const obj = py.PyType_GenericAlloc(@ptrCast(@alignCast(tp)), 0) orelse {
        py.Py_DecRef(payload);
        return null;
    };
    const r: *Ready = @ptrCast(@alignCast(obj));
    r.payload = payload;
    r.is_exc = is_exc;
    return obj;
}

/// Awaitable completing with `value`. Steals `value`.
pub fn ready(value: *PyObject) ?*PyObject {
    return newReady(value, false);
}

/// Awaitable raising StopAsyncIteration (end of an async iterator).
pub fn stopAsyncIteration() ?*PyObject {
    const exc = c.PyObject_CallObject(py.PyExc_StopAsyncIteration(), null) orelse return null;
    return newReady(exc, true);
}

// ============================================================================
// Converting async dunder results
// ============================================================================

pub const Mode = enum {
    /// `__anext__`: a null optional means "iteration finished".
    anext,
    /// `__await__`, `__aenter__`, `__aexit__`: a null optional is `None`.
    value,
};

fn isPyObjectPtr(comptime R: type) bool {
    const info = @typeInfo(R);
    return info == .pointer and info.pointer.size == .one and info.pointer.child == PyObject;
}

fn isSelfPtr(comptime R: type, comptime T: type) bool {
    const info = @typeInfo(R);
    return info == .pointer and info.pointer.size == .one and info.pointer.child == T;
}

/// Turn the result of an async dunder into a new awaitable reference, or null
/// with a Python exception set. `R` is the return type after `pyoz.Signature`
/// unwrapping; `self_obj`/`self_data` enable the `return self` pattern.
pub fn toAwaitable(
    comptime Conv: type,
    comptime T: type,
    comptime R: type,
    result: R,
    comptime mode: Mode,
    self_obj: *PyObject,
    self_data: *const T,
) ?*PyObject {
    switch (@typeInfo(R)) {
        .error_union => |eu| {
            const value = result catch |err| {
                if (py.PyErr_Occurred() == null) {
                    const msg = @errorName(err);
                    py.PyErr_SetString(errors_mod.mapWellKnownError(msg), msg.ptr);
                }
                return null;
            };
            return toAwaitable(Conv, T, eu.payload, value, mode, self_obj, self_data);
        },
        .optional => |opt| {
            if (result) |value| return toAwaitable(Conv, T, opt.child, value, mode, self_obj, self_data);
            if (py.PyErr_Occurred() != null) return null;
            return switch (mode) {
                .anext => stopAsyncIteration(),
                .value => ready(py.Py_RETURN_NONE()),
            };
        },
        .void => return ready(py.Py_RETURN_NONE()),
        else => {},
    }
    if (comptime aio.isAsyncPending(R)) {
        if (mode == .anext) result.job.common.null_stops = true;
        return Conv.toPy(R, result);
    }
    if (comptime isPyObjectPtr(R)) return result; // caller-provided awaitable (owned)
    if (comptime isSelfPtr(R, T)) {
        if (result == self_data) {
            py.Py_IncRef(self_obj);
            return ready(self_obj);
        }
    }
    const value = Conv.toPy(R, result) orelse return null;
    return ready(value);
}

var await_name: lazy.LazyObject = .{};

/// The iterator `__await__` must return, for any awaitable. Steals `aw`.
pub fn awaitIterator(aw: *PyObject) ?*PyObject {
    if (isReady(aw)) return aw; // already its own iterator
    defer py.Py_DecRef(aw);
    const name = await_name.get() orelse blk: {
        const n = c.PyUnicode_InternFromString("__await__") orelse return null;
        break :blk await_name.publish(n);
    };
    return c.PyObject_CallMethodObjArgs(aw, name, @as(?*PyObject, null));
}

/// Element type an async dunder's awaitable resolves to (for stubs).
/// Strips error unions, `pyoz.Signature`, async-task wrappers and, for
/// `__anext__`, the optional that signals the end of iteration.
pub fn ResolvedType(comptime R: type, comptime mode: Mode) type {
    return switch (@typeInfo(R)) {
        .error_union => |eu| ResolvedType(eu.payload, mode),
        .optional => |opt| if (mode == .anext) ResolvedType(opt.child, mode) else ?ResolvedType(opt.child, mode),
        .@"struct" => if (aio.isAsyncPending(R)) ResolvedType(R.Result, mode) else R,
        else => R,
    };
}
