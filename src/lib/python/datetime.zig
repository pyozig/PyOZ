//! DateTime API operations for Python C API
//!
//! In non-ABI3 mode, uses the efficient datetime C API (datetime.h).
//! In ABI3 mode, emulates the API using Python object calls.

const types = @import("types.zig");
const c = types.c;
const PyObject = types.PyObject;
const PyTypeObject = types.PyTypeObject;
const typecheck = @import("typecheck.zig");
const Py_TYPE = typecheck.Py_TYPE;
const refcount = @import("refcount.zig");
const numeric = @import("numeric.zig");

const abi3_enabled = types.abi3_enabled;

// ============================================================================
// DateTime API - Dual Implementation
// ============================================================================

// In non-ABI3 mode, we use the fast C API
// In ABI3 mode, we cache the datetime module and classes for efficiency
const lazy = @import("lazy.zig");
var datetime_module: ?*PyObject = null;
var date_class: ?*PyObject = null;
var datetime_class: ?*PyObject = null;
var time_class: ?*PyObject = null;
var timedelta_class: ?*PyObject = null;

// Non-ABI3: The datetime CAPI - lazily initialized on first use
var datetime_api: if (!abi3_enabled) ?*c.PyDateTime_CAPI else void =
    if (!abi3_enabled) null else {};

// Free-threading safety: each cache slot is written exactly once, by a
// successful compare-and-swap (failed CASes don't write), and `dt_ready` is
// set with release ordering only after every slot is published. Readers only
// touch the slots after observing `dt_ready`, so plain reads never race.
var dt_ready: lazy.ReadyFlag = .{};

fn publishOnce(slot: *?*PyObject, value: *PyObject) void {
    if (@cmpxchgStrong(?*PyObject, slot, null, value, .acq_rel, .acquire) != null) {
        refcount.Py_DecRef(value);
    }
}

/// Ensure datetime API/module is initialized (called automatically by datetime functions)
fn ensureDateTimeAPI() bool {
    if (dt_ready.isSet()) return true;
    if (abi3_enabled) {
        // ABI3 mode: import the datetime module and cache classes
        const module = c.PyImport_ImportModule("datetime") orelse return false;
        const names = [_][*:0]const u8{ "date", "datetime", "time", "timedelta" };
        const slots = [_]*?*PyObject{ &date_class, &datetime_class, &time_class, &timedelta_class };
        var fetched: [names.len]*PyObject = undefined;
        for (names, 0..) |name, i| {
            fetched[i] = c.PyObject_GetAttrString(module, name) orelse {
                for (fetched[0..i]) |o| refcount.Py_DecRef(o);
                refcount.Py_DecRef(module);
                return false;
            };
        }
        for (slots, fetched) |slot, obj| publishOnce(slot, obj);
        publishOnce(&datetime_module, module);
    } else {
        // Non-ABI3 mode: use the C API capsule (process-global; same pointer for every caller)
        const api: *c.PyDateTime_CAPI = @ptrCast(@alignCast(c.PyCapsule_Import("datetime.datetime_CAPI", 0) orelse return false));
        _ = @cmpxchgStrong(?*c.PyDateTime_CAPI, &datetime_api, null, api, .acq_rel, .acquire);
    }
    dt_ready.set();
    return true;
}

/// Explicitly initialize the datetime API (optional - happens automatically on first use)
pub fn PyDateTime_Import() bool {
    return ensureDateTimeAPI();
}

/// Check if datetime API is initialized
pub fn PyDateTime_IsInitialized() bool {
    return dt_ready.isSet();
}

/// Create a date object
pub fn PyDate_FromDate(year: c_int, month: c_int, day: c_int) ?*PyObject {
    if (!ensureDateTimeAPI()) return null;

    if (abi3_enabled) {
        // ABI3: call datetime.date(year, month, day)
        const args = c.Py_BuildValue("iii", year, month, day) orelse return null;
        defer refcount.Py_DecRef(args);
        return c.PyObject_Call(date_class, args, null);
    } else {
        // Non-ABI3: use the C API
        const api = datetime_api.?;
        const func = api.Date_FromDate orelse return null;
        return func(year, month, day, api.DateType);
    }
}

/// Create a datetime object
pub fn PyDateTime_FromDateAndTime(year: c_int, month: c_int, day: c_int, hour: c_int, minute: c_int, second: c_int, usecond: c_int) ?*PyObject {
    if (!ensureDateTimeAPI()) return null;

    if (abi3_enabled) {
        // ABI3: call datetime.datetime(year, month, day, hour, minute, second, usecond)
        const args = c.Py_BuildValue("iiiiiii", year, month, day, hour, minute, second, usecond) orelse return null;
        defer refcount.Py_DecRef(args);
        return c.PyObject_Call(datetime_class, args, null);
    } else {
        // Non-ABI3: use the C API
        const api = datetime_api.?;
        const func = api.DateTime_FromDateAndTime orelse return null;
        return func(year, month, day, hour, minute, second, usecond, types.pyData(PyObject, "_Py_NoneStruct"), api.DateTimeType);
    }
}

/// Create a time object
pub fn PyTime_FromTime(hour: c_int, minute: c_int, second: c_int, usecond: c_int) ?*PyObject {
    if (!ensureDateTimeAPI()) return null;

    if (abi3_enabled) {
        // ABI3: call datetime.time(hour, minute, second, usecond)
        const args = c.Py_BuildValue("iiii", hour, minute, second, usecond) orelse return null;
        defer refcount.Py_DecRef(args);
        return c.PyObject_Call(time_class, args, null);
    } else {
        // Non-ABI3: use the C API
        const api = datetime_api.?;
        const func = api.Time_FromTime orelse return null;
        return func(hour, minute, second, usecond, types.pyData(PyObject, "_Py_NoneStruct"), api.TimeType);
    }
}

/// Create a timedelta object
pub fn PyDelta_FromDSU(days: c_int, seconds: c_int, useconds: c_int) ?*PyObject {
    if (!ensureDateTimeAPI()) return null;

    if (abi3_enabled) {
        // ABI3: call datetime.timedelta(days=days, seconds=seconds, microseconds=useconds)
        // Using positional args in order: days, seconds, microseconds
        const args = c.Py_BuildValue("iii", days, seconds, useconds) orelse return null;
        defer refcount.Py_DecRef(args);
        return c.PyObject_Call(timedelta_class, args, null);
    } else {
        // Non-ABI3: use the C API
        const api = datetime_api.?;
        const func = api.Delta_FromDelta orelse return null;
        return func(days, seconds, useconds, 1, api.DeltaType);
    }
}

/// Check if object is a date (or datetime)
pub fn PyDate_Check(obj: *PyObject) bool {
    if (!ensureDateTimeAPI()) return false;

    if (abi3_enabled) {
        return c.PyObject_IsInstance(obj, date_class) == 1;
    } else {
        const api = datetime_api.?;
        return c.PyType_IsSubtype(Py_TYPE(obj), @ptrCast(api.DateType)) != 0;
    }
}

/// Check if object is a datetime
pub fn PyDateTime_Check(obj: *PyObject) bool {
    if (!ensureDateTimeAPI()) return false;

    if (abi3_enabled) {
        return c.PyObject_IsInstance(obj, datetime_class) == 1;
    } else {
        const api = datetime_api.?;
        return c.PyType_IsSubtype(Py_TYPE(obj), @ptrCast(api.DateTimeType)) != 0;
    }
}

/// Check if object is a time
pub fn PyTime_Check(obj: *PyObject) bool {
    if (!ensureDateTimeAPI()) return false;

    if (abi3_enabled) {
        return c.PyObject_IsInstance(obj, time_class) == 1;
    } else {
        const api = datetime_api.?;
        return c.PyType_IsSubtype(Py_TYPE(obj), @ptrCast(api.TimeType)) != 0;
    }
}

/// Check if object is a timedelta
pub fn PyDelta_Check(obj: *PyObject) bool {
    if (!ensureDateTimeAPI()) return false;

    if (abi3_enabled) {
        return c.PyObject_IsInstance(obj, timedelta_class) == 1;
    } else {
        const api = datetime_api.?;
        return c.PyType_IsSubtype(Py_TYPE(obj), @ptrCast(api.DeltaType)) != 0;
    }
}

// ============================================================================
// Attribute Getters - ABI3 uses Python attribute access
// ============================================================================

/// Helper to get an integer attribute from an object (ABI3 mode)
inline fn getIntAttr(obj: *PyObject, attr: [*:0]const u8) c_int {
    const attr_obj = c.PyObject_GetAttrString(obj, attr) orelse return 0;
    defer refcount.Py_DecRef(attr_obj);
    return @intCast(numeric.PyLong_AsLongLong(attr_obj));
}

/// Get year from date/datetime
pub fn PyDateTime_GET_YEAR(obj: *PyObject) c_int {
    if (abi3_enabled) {
        return getIntAttr(obj, "year");
    } else {
        const date: *c.PyDateTime_Date = @ptrCast(obj);
        return (@as(c_int, date.data[0]) << 8) | @as(c_int, date.data[1]);
    }
}

/// Get month from date/datetime
pub fn PyDateTime_GET_MONTH(obj: *PyObject) c_int {
    if (abi3_enabled) {
        return getIntAttr(obj, "month");
    } else {
        const date: *c.PyDateTime_Date = @ptrCast(obj);
        return @as(c_int, date.data[2]);
    }
}

/// Get day from date/datetime
pub fn PyDateTime_GET_DAY(obj: *PyObject) c_int {
    if (abi3_enabled) {
        return getIntAttr(obj, "day");
    } else {
        const date: *c.PyDateTime_Date = @ptrCast(obj);
        return @as(c_int, date.data[3]);
    }
}

/// Get hour from datetime/time
pub fn PyDateTime_DATE_GET_HOUR(obj: *PyObject) c_int {
    if (abi3_enabled) {
        return getIntAttr(obj, "hour");
    } else {
        const dt: *c.PyDateTime_DateTime = @ptrCast(obj);
        return @as(c_int, dt.data[4]);
    }
}

/// Get minute from datetime/time
pub fn PyDateTime_DATE_GET_MINUTE(obj: *PyObject) c_int {
    if (abi3_enabled) {
        return getIntAttr(obj, "minute");
    } else {
        const dt: *c.PyDateTime_DateTime = @ptrCast(obj);
        return @as(c_int, dt.data[5]);
    }
}

/// Get second from datetime/time
pub fn PyDateTime_DATE_GET_SECOND(obj: *PyObject) c_int {
    if (abi3_enabled) {
        return getIntAttr(obj, "second");
    } else {
        const dt: *c.PyDateTime_DateTime = @ptrCast(obj);
        return @as(c_int, dt.data[6]);
    }
}

/// Get microsecond from datetime/time
pub fn PyDateTime_DATE_GET_MICROSECOND(obj: *PyObject) c_int {
    if (abi3_enabled) {
        return getIntAttr(obj, "microsecond");
    } else {
        const dt: *c.PyDateTime_DateTime = @ptrCast(obj);
        return (@as(c_int, dt.data[7]) << 16) | (@as(c_int, dt.data[8]) << 8) | @as(c_int, dt.data[9]);
    }
}

/// Get hour from time object
pub fn PyDateTime_TIME_GET_HOUR(obj: *PyObject) c_int {
    if (abi3_enabled) {
        return getIntAttr(obj, "hour");
    } else {
        const t: *c.PyDateTime_Time = @ptrCast(obj);
        return @as(c_int, t.data[0]);
    }
}

/// Get minute from time object
pub fn PyDateTime_TIME_GET_MINUTE(obj: *PyObject) c_int {
    if (abi3_enabled) {
        return getIntAttr(obj, "minute");
    } else {
        const t: *c.PyDateTime_Time = @ptrCast(obj);
        return @as(c_int, t.data[1]);
    }
}

/// Get second from time object
pub fn PyDateTime_TIME_GET_SECOND(obj: *PyObject) c_int {
    if (abi3_enabled) {
        return getIntAttr(obj, "second");
    } else {
        const t: *c.PyDateTime_Time = @ptrCast(obj);
        return @as(c_int, t.data[2]);
    }
}

/// Get microsecond from time object
pub fn PyDateTime_TIME_GET_MICROSECOND(obj: *PyObject) c_int {
    if (abi3_enabled) {
        return getIntAttr(obj, "microsecond");
    } else {
        const t: *c.PyDateTime_Time = @ptrCast(obj);
        return (@as(c_int, t.data[3]) << 16) | (@as(c_int, t.data[4]) << 8) | @as(c_int, t.data[5]);
    }
}

/// Get days from timedelta
pub fn PyDateTime_DELTA_GET_DAYS(obj: *PyObject) c_int {
    if (abi3_enabled) {
        return getIntAttr(obj, "days");
    } else {
        const delta: *c.PyDateTime_Delta = @ptrCast(obj);
        return delta.days;
    }
}

/// Get seconds from timedelta
pub fn PyDateTime_DELTA_GET_SECONDS(obj: *PyObject) c_int {
    if (abi3_enabled) {
        return getIntAttr(obj, "seconds");
    } else {
        const delta: *c.PyDateTime_Delta = @ptrCast(obj);
        return delta.seconds;
    }
}

/// Get microseconds from timedelta
pub fn PyDateTime_DELTA_GET_MICROSECONDS(obj: *PyObject) c_int {
    if (abi3_enabled) {
        return getIntAttr(obj, "microseconds");
    } else {
        const delta: *c.PyDateTime_Delta = @ptrCast(obj);
        return delta.microseconds;
    }
}
