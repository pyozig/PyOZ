//! Type checking operations for Python C API
//!
//! Functions to check Python object types and get type information.

const types = @import("types.zig");
const c = types.c;
const PyObject = types.PyObject;
const PyTypeObject = types.PyTypeObject;
const Py_ssize_t = types.Py_ssize_t;
const has_direct_ob_refcnt = types.has_direct_ob_refcnt;
const singletons = @import("singletons.zig");
const Py_None = singletons.Py_None;

// ============================================================================
// Type checking
// ============================================================================
// Note: We reimplement these instead of using C macros because the macros
// use _PyObject_CAST_CONST which Zig's cImport can't translate in Python 3.9,
// and Python 3.12+ has anonymous unions that cause opaque type issues.

/// Get the type of a Python object
/// Works across all Python versions by using pointer arithmetic for 3.12+
pub inline fn Py_TYPE(obj: *PyObject) ?*PyTypeObject {
    // In Python 3.12+, ob_type is after an anonymous union, but the offset is the same
    // as Py_ssize_t (the ob_refcnt field), so we can access it directly
    if (comptime @hasField(PyObject, "ob_type")) {
        return obj.ob_type;
    } else {
        // Python 3.12+: access ob_type via pointer arithmetic
        // Layout: [ob_refcnt (Py_ssize_t)] [ob_type (*PyTypeObject)]
        const type_ptr: *?*PyTypeObject = @ptrFromInt(@intFromPtr(obj) + @sizeOf(Py_ssize_t));
        return type_ptr.*;
    }
}

/// Helper to check if object is instance of a type (using PyType_IsSubtype)
inline fn isTypeOrSubtype(obj: *PyObject, type_ptr: *PyTypeObject) bool {
    const obj_type = Py_TYPE(obj) orelse return false;
    return obj_type == type_ptr or c.PyType_IsSubtype(obj_type, type_ptr) != 0;
}

pub inline fn PyLong_Check(obj: *PyObject) bool {
    return isTypeOrSubtype(obj, @ptrCast(&c.PyLong_Type));
}

pub inline fn PyFloat_Check(obj: *PyObject) bool {
    return isTypeOrSubtype(obj, @ptrCast(&c.PyFloat_Type));
}

pub inline fn PyUnicode_Check(obj: *PyObject) bool {
    return isTypeOrSubtype(obj, @ptrCast(&c.PyUnicode_Type));
}

pub inline fn PyBool_Check(obj: *PyObject) bool {
    return isTypeOrSubtype(obj, @ptrCast(&c.PyBool_Type));
}

pub inline fn PyNone_Check(obj: *PyObject) bool {
    return obj == Py_None();
}

pub inline fn PyTuple_Check(obj: *PyObject) bool {
    return isTypeOrSubtype(obj, @ptrCast(&c.PyTuple_Type));
}

pub inline fn PyList_Check(obj: *PyObject) bool {
    return isTypeOrSubtype(obj, @ptrCast(&c.PyList_Type));
}

pub inline fn PyDict_Check(obj: *PyObject) bool {
    return isTypeOrSubtype(obj, @ptrCast(&c.PyDict_Type));
}

/// Check if an object is an instance of a type (or subtype)
/// Reimplemented to avoid cImport issues with _PyObject_CAST_CONST macro
pub inline fn PyObject_TypeCheck(obj: *PyObject, type_obj: *PyTypeObject) bool {
    return isTypeOrSubtype(obj, type_obj);
}

pub inline fn PySet_Check(obj: *PyObject) bool {
    return isTypeOrSubtype(obj, @ptrCast(&c.PySet_Type));
}

pub inline fn PyFrozenSet_Check(obj: *PyObject) bool {
    return isTypeOrSubtype(obj, @ptrCast(&c.PyFrozenSet_Type));
}

pub inline fn PyAnySet_Check(obj: *PyObject) bool {
    return PySet_Check(obj) or PyFrozenSet_Check(obj);
}

pub inline fn PyBytes_Check(obj: *PyObject) bool {
    return isTypeOrSubtype(obj, @ptrCast(&c.PyBytes_Type));
}

pub inline fn PyByteArray_Check(obj: *PyObject) bool {
    return isTypeOrSubtype(obj, @ptrCast(&c.PyByteArray_Type));
}

pub inline fn PyMemoryView_Check(obj: *PyObject) bool {
    return isTypeOrSubtype(obj, @ptrCast(&c.PyMemoryView_Type));
}

pub inline fn PyCallable_Check(obj: *PyObject) bool {
    return c.PyCallable_Check(obj) != 0;
}
