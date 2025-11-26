//! Python C API bindings via @cImport
//!
//! This module imports the Python C API from the system headers.
//! The correct Python version is determined at build time based on
//! which Python headers are provided to the compiler.

const std = @import("std");

// Import Python C API from system headers
pub const c = @cImport({
    @cDefine("PY_SSIZE_T_CLEAN", "1");
    @cInclude("Python.h");
    @cInclude("datetime.h");
    @cInclude("structmember.h");
});

// ============================================================================
// Re-export essential types
// ============================================================================

pub const PyObject = c.PyObject;
pub const Py_ssize_t = c.Py_ssize_t;
pub const PyTypeObject = c.PyTypeObject;

// Method definition
pub const PyMethodDef = c.PyMethodDef;
pub const PyCFunction = *const fn (?*PyObject, ?*PyObject) callconv(.c) ?*PyObject;

// Member/GetSet definitions for class attributes
pub const PyMemberDef = c.PyMemberDef;
pub const PyGetSetDef = c.PyGetSetDef;
pub const getter = *const fn (?*PyObject, ?*anyopaque) callconv(.c) ?*PyObject;
pub const setter = *const fn (?*PyObject, ?*PyObject, ?*anyopaque) callconv(.c) c_int;

// Type slots for heap types
pub const PyType_Slot = c.PyType_Slot;
pub const PyType_Spec = c.PyType_Spec;

// Module definition
pub const PyModuleDef = c.PyModuleDef;
pub const PyModuleDef_Base = c.PyModuleDef_Base;

// Python 3.12+ uses an anonymous union for ob_refcnt (PEP 683 immortal objects)
// We detect this at comptime and handle both cases
const has_direct_ob_refcnt = @hasField(c.PyObject, "ob_refcnt");

pub const PyModuleDef_HEAD_INIT: PyModuleDef_Base = blk: {
    var base: PyModuleDef_Base = std.mem.zeroes(PyModuleDef_Base);
    base.m_init = null;
    base.m_index = 0;
    base.m_copy = null;
    // Set ob_refcnt based on Python version struct layout
    if (has_direct_ob_refcnt) {
        base.ob_base.ob_refcnt = 1;
    } else {
        // Python 3.12+: ob_refcnt is inside anonymous union, access via pointer
        const ob_ptr: *Py_ssize_t = @ptrCast(&base.ob_base);
        ob_ptr.* = 1;
    }
    base.ob_base.ob_type = null;
    break :blk base;
};

// Method flags
pub const METH_VARARGS: c_int = c.METH_VARARGS;
pub const METH_KEYWORDS: c_int = c.METH_KEYWORDS;
pub const METH_NOARGS: c_int = c.METH_NOARGS;
pub const METH_O: c_int = c.METH_O;
pub const METH_STATIC: c_int = c.METH_STATIC;
pub const METH_CLASS: c_int = c.METH_CLASS;

// Type flags
pub const Py_TPFLAGS_DEFAULT: c_ulong = c.Py_TPFLAGS_DEFAULT;
pub const Py_TPFLAGS_HAVE_GC: c_ulong = c.Py_TPFLAGS_HAVE_GC;
pub const Py_TPFLAGS_BASETYPE: c_ulong = c.Py_TPFLAGS_BASETYPE;
pub const Py_TPFLAGS_HEAPTYPE: c_ulong = c.Py_TPFLAGS_HEAPTYPE;

// Sequence and Mapping protocols
pub const PySequenceMethods = c.PySequenceMethods;
pub const PyMappingMethods = c.PyMappingMethods;

// Buffer protocol
pub const Py_buffer = c.Py_buffer;
pub const PyBufferProcs = c.PyBufferProcs;
pub const PyBUF_SIMPLE: c_int = c.PyBUF_SIMPLE;
pub const PyBUF_WRITABLE: c_int = c.PyBUF_WRITABLE;
pub const PyBUF_FORMAT: c_int = c.PyBUF_FORMAT;
pub const PyBUF_ND: c_int = c.PyBUF_ND;
pub const PyBUF_STRIDES: c_int = c.PyBUF_STRIDES;

pub inline fn PyBuffer_FillInfo(view: *Py_buffer, obj: ?*PyObject, buf: ?*anyopaque, len: Py_ssize_t, readonly: c_int, flags: c_int) c_int {
    return c.PyBuffer_FillInfo(view, obj, buf, len, readonly, flags);
}

// GIL (Global Interpreter Lock) control
// Note: We define PyThreadState as opaque and use extern declarations to avoid
// cImport issues with Python 3.12+ where the struct contains anonymous structs
// that Zig's cImport cannot translate.
pub const PyThreadState = opaque {};
pub const PyGILState_STATE = c_uint;

// Extern declarations for GIL functions - avoids cImport resolving PyThreadState struct
pub extern fn PyEval_SaveThread() ?*PyThreadState;
pub extern fn PyEval_RestoreThread(state: ?*PyThreadState) void;
pub extern fn PyGILState_Ensure() PyGILState_STATE;
pub extern fn PyGILState_Release(state: PyGILState_STATE) void;

// Type slots
pub const Py_tp_init: c_int = c.Py_tp_init;
pub const Py_tp_new: c_int = c.Py_tp_new;
pub const Py_tp_dealloc: c_int = c.Py_tp_dealloc;
pub const Py_tp_methods: c_int = c.Py_tp_methods;
pub const Py_tp_members: c_int = c.Py_tp_members;
pub const Py_tp_getset: c_int = c.Py_tp_getset;
pub const Py_tp_doc: c_int = c.Py_tp_doc;
pub const Py_tp_repr: c_int = c.Py_tp_repr;
pub const Py_tp_str: c_int = c.Py_tp_str;

// ============================================================================
// Object creation functions
// ============================================================================

pub inline fn PyLong_FromLongLong(v: c_longlong) ?*PyObject {
    return c.PyLong_FromLongLong(v);
}

pub inline fn PyLong_FromString(str: [*:0]const u8, pend: [*c][*c]u8, base: c_int) ?*PyObject {
    return c.PyLong_FromString(str, pend, base);
}

pub inline fn PyLong_FromUnsignedLongLong(v: c_ulonglong) ?*PyObject {
    return c.PyLong_FromUnsignedLongLong(v);
}

pub inline fn PyFloat_FromDouble(v: f64) ?*PyObject {
    return c.PyFloat_FromDouble(v);
}

// Complex number creation
pub inline fn PyComplex_FromDoubles(real: f64, imag: f64) ?*PyObject {
    return c.PyComplex_FromDoubles(real, imag);
}

pub inline fn PyComplex_RealAsDouble(obj: *PyObject) f64 {
    return c.PyComplex_RealAsDouble(obj);
}

pub inline fn PyComplex_ImagAsDouble(obj: *PyObject) f64 {
    return c.PyComplex_ImagAsDouble(obj);
}

pub inline fn PyComplex_Check(obj: *PyObject) bool {
    // Reimplemented to avoid cImport issues with _PyObject_CAST_CONST
    const obj_type = Py_TYPE(obj) orelse return false;
    const complex_type: *PyTypeObject = @ptrCast(&c.PyComplex_Type);
    return obj_type == complex_type or c.PyType_IsSubtype(obj_type, complex_type) != 0;
}

pub inline fn PyUnicode_FromString(s: [*:0]const u8) ?*PyObject {
    return c.PyUnicode_FromString(s);
}

pub inline fn PyUnicode_FromStringAndSize(s: [*]const u8, size: Py_ssize_t) ?*PyObject {
    return c.PyUnicode_FromStringAndSize(s, size);
}

pub inline fn PyBool_FromLong(v: c_long) ?*PyObject {
    return c.PyBool_FromLong(v);
}

// ============================================================================
// Object extraction functions
// ============================================================================

pub inline fn PyLong_AsLongLong(obj: *PyObject) c_longlong {
    return c.PyLong_AsLongLong(obj);
}

pub inline fn PyLong_AsUnsignedLongLong(obj: *PyObject) c_ulonglong {
    return c.PyLong_AsUnsignedLongLong(obj);
}

pub inline fn PyLong_AsDouble(obj: *PyObject) f64 {
    return c.PyLong_AsDouble(obj);
}

pub inline fn PyFloat_AsDouble(obj: *PyObject) f64 {
    return c.PyFloat_AsDouble(obj);
}

pub inline fn PyUnicode_AsUTF8(obj: *PyObject) ?[*:0]const u8 {
    return c.PyUnicode_AsUTF8(obj);
}

pub inline fn PyUnicode_AsUTF8AndSize(obj: *PyObject, size: *Py_ssize_t) ?[*]const u8 {
    return c.PyUnicode_AsUTF8AndSize(obj, size);
}

// ============================================================================
// Type checking
// ============================================================================
// Note: We reimplement these instead of using C macros because the macros
// use _PyObject_CAST_CONST which Zig's cImport can't translate in Python 3.9,
// and Python 3.12+ has anonymous unions that cause opaque type issues.

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

/// Check if an object is an instance of a type (or subtype)
/// Reimplemented to avoid cImport issues with _PyObject_CAST_CONST macro
pub inline fn PyObject_TypeCheck(obj: *PyObject, type_obj: *PyTypeObject) bool {
    const obj_type = Py_TYPE(obj) orelse return false;
    return obj_type == type_obj or c.PyType_IsSubtype(obj_type, type_obj) != 0;
}

// ============================================================================
// Singletons - MUST increment refcount when returning these!
// ============================================================================

pub inline fn Py_None() *PyObject {
    return @ptrCast(&c._Py_NoneStruct);
}

pub inline fn Py_True() *PyObject {
    return @ptrCast(&c._Py_TrueStruct);
}

pub inline fn Py_False() *PyObject {
    return @ptrCast(&c._Py_FalseStruct);
}

/// Return None with proper reference counting (use this when returning from functions)
pub inline fn Py_RETURN_NONE() *PyObject {
    const none = Py_None();
    Py_IncRef(none);
    return none;
}

/// Return True with proper reference counting
pub inline fn Py_RETURN_TRUE() *PyObject {
    const t = Py_True();
    Py_IncRef(t);
    return t;
}

/// Return False with proper reference counting
pub inline fn Py_RETURN_FALSE() *PyObject {
    const f = Py_False();
    Py_IncRef(f);
    return f;
}

/// Return a boolean with proper reference counting
pub inline fn Py_RETURN_BOOL(val: bool) *PyObject {
    return if (val) Py_RETURN_TRUE() else Py_RETURN_FALSE();
}

/// Return NotImplemented (for comparison operators)
pub inline fn Py_NotImplemented() *PyObject {
    const ni = @as(*PyObject, @ptrCast(&c._Py_NotImplementedStruct));
    Py_IncRef(ni);
    return ni;
}

// ============================================================================
// Tuple operations
// ============================================================================

pub inline fn PyTuple_Size(obj: *PyObject) Py_ssize_t {
    return c.PyTuple_Size(obj);
}

pub inline fn PyTuple_GetItem(obj: *PyObject, pos: Py_ssize_t) ?*PyObject {
    return c.PyTuple_GetItem(obj, pos);
}

pub inline fn PyTuple_New(size: Py_ssize_t) ?*PyObject {
    return c.PyTuple_New(size);
}

pub inline fn PyTuple_SetItem(obj: *PyObject, pos: Py_ssize_t, item: *PyObject) c_int {
    return c.PyTuple_SetItem(obj, pos, item);
}

/// Create a tuple from a comptime-known tuple of PyObject pointers
pub fn PyTuple_Pack(args: anytype) ?*PyObject {
    const ArgsType = @TypeOf(args);
    const args_info = @typeInfo(ArgsType);
    if (args_info != .@"struct" or !args_info.@"struct".is_tuple) {
        @compileError("Expected tuple argument");
    }
    const n = args_info.@"struct".fields.len;
    const tuple = PyTuple_New(n) orelse return null;
    inline for (0..n) |i| {
        const item: *PyObject = args[i];
        Py_IncRef(item); // SetItem steals reference
        _ = PyTuple_SetItem(tuple, @intCast(i), item);
    }
    return tuple;
}

// ============================================================================
// List operations
// ============================================================================

pub inline fn PyList_New(size: Py_ssize_t) ?*PyObject {
    return c.PyList_New(size);
}

pub inline fn PyList_Size(obj: *PyObject) Py_ssize_t {
    return c.PyList_Size(obj);
}

pub inline fn PyList_GetItem(obj: *PyObject, pos: Py_ssize_t) ?*PyObject {
    return c.PyList_GetItem(obj, pos);
}

pub inline fn PyList_SetItem(obj: *PyObject, pos: Py_ssize_t, item: *PyObject) c_int {
    return c.PyList_SetItem(obj, pos, item);
}

pub inline fn PyList_Append(obj: *PyObject, item: *PyObject) c_int {
    return c.PyList_Append(obj, item);
}

pub inline fn PyList_SetSlice(obj: *PyObject, low: Py_ssize_t, high: Py_ssize_t, itemlist: ?*PyObject) c_int {
    return c.PyList_SetSlice(obj, low, high, itemlist);
}

pub inline fn PyList_Insert(obj: *PyObject, index: Py_ssize_t, item: *PyObject) c_int {
    return c.PyList_Insert(obj, index, item);
}

// ============================================================================
// Dict operations
// ============================================================================

pub inline fn PyDict_New() ?*PyObject {
    return c.PyDict_New();
}

pub inline fn PyDict_SetItemString(obj: *PyObject, key: [*:0]const u8, val: *PyObject) c_int {
    return c.PyDict_SetItemString(obj, key, val);
}

pub inline fn PyDict_GetItemString(obj: *PyObject, key: [*:0]const u8) ?*PyObject {
    return c.PyDict_GetItemString(obj, key);
}

pub inline fn PyDict_Size(obj: *PyObject) Py_ssize_t {
    return c.PyDict_Size(obj);
}

pub inline fn PyDict_Keys(obj: *PyObject) ?*PyObject {
    return c.PyDict_Keys(obj);
}

pub inline fn PyDict_Values(obj: *PyObject) ?*PyObject {
    return c.PyDict_Values(obj);
}

pub inline fn PyDict_Items(obj: *PyObject) ?*PyObject {
    return c.PyDict_Items(obj);
}

pub inline fn PyDict_SetItem(obj: *PyObject, key: *PyObject, val: *PyObject) c_int {
    return c.PyDict_SetItem(obj, key, val);
}

pub inline fn PyDict_GetItem(obj: *PyObject, key: *PyObject) ?*PyObject {
    return c.PyDict_GetItem(obj, key);
}

pub inline fn PyDict_Next(obj: *PyObject, pos: *Py_ssize_t, key: *?*PyObject, value: *?*PyObject) c_int {
    return c.PyDict_Next(obj, pos, key, value);
}

// ============================================================================
// Set operations
// ============================================================================

pub inline fn PySet_New(iterable: ?*PyObject) ?*PyObject {
    return c.PySet_New(iterable);
}

pub inline fn PyFrozenSet_New(iterable: ?*PyObject) ?*PyObject {
    return c.PyFrozenSet_New(iterable);
}

pub inline fn PySet_Size(obj: *PyObject) Py_ssize_t {
    return c.PySet_Size(obj);
}

pub inline fn PySet_Contains(obj: *PyObject, key: *PyObject) c_int {
    return c.PySet_Contains(obj, key);
}

pub inline fn PySet_Add(obj: *PyObject, key: *PyObject) c_int {
    return c.PySet_Add(obj, key);
}

pub inline fn PySet_Discard(obj: *PyObject, key: *PyObject) c_int {
    return c.PySet_Discard(obj, key);
}

pub inline fn PySet_Pop(obj: *PyObject) ?*PyObject {
    return c.PySet_Pop(obj);
}

pub inline fn PySet_Clear(obj: *PyObject) c_int {
    return c.PySet_Clear(obj);
}

pub inline fn PySet_Check(obj: *PyObject) bool {
    // Can't use c.PySet_Check due to C macro translation issues
    // Manually check: Py_IS_TYPE(ob, &PySet_Type) || PyType_IsSubtype(Py_TYPE(ob), &PySet_Type)
    const obj_type = Py_TYPE(obj);
    const set_type: *PyTypeObject = @ptrCast(&c.PySet_Type);
    return obj_type == set_type or c.PyType_IsSubtype(obj_type, set_type) != 0;
}

pub inline fn PyFrozenSet_Check(obj: *PyObject) bool {
    // Can't use c.PyFrozenSet_Check due to C macro translation issues
    const obj_type = Py_TYPE(obj);
    const frozenset_type: *PyTypeObject = @ptrCast(&c.PyFrozenSet_Type);
    return obj_type == frozenset_type or c.PyType_IsSubtype(obj_type, frozenset_type) != 0;
}

pub inline fn PyAnySet_Check(obj: *PyObject) bool {
    return PySet_Check(obj) or PyFrozenSet_Check(obj);
}

// ============================================================================
// Iterator protocol
// ============================================================================

pub inline fn PyObject_GetIter(obj: *PyObject) ?*PyObject {
    return c.PyObject_GetIter(obj);
}

pub inline fn PyIter_Next(iter: *PyObject) ?*PyObject {
    return c.PyIter_Next(iter);
}

// ============================================================================
// Sequence operations
// ============================================================================

pub inline fn PySequence_List(obj: *PyObject) ?*PyObject {
    return c.PySequence_List(obj);
}

// ============================================================================
// Error handling
// ============================================================================

pub inline fn PyErr_SetString(exc: *PyObject, msg: [*:0]const u8) void {
    c.PyErr_SetString(exc, msg);
}

pub inline fn PyErr_Occurred() ?*PyObject {
    return c.PyErr_Occurred();
}

pub inline fn PyErr_Clear() void {
    c.PyErr_Clear();
}

pub inline fn PyErr_ExceptionMatches(exc: *PyObject) c_int {
    return c.PyErr_ExceptionMatches(@ptrCast(exc));
}

/// Fetch the current exception (type, value, traceback)
/// Clears the exception state. Caller owns the references.
pub inline fn PyErr_Fetch(ptype: *?*PyObject, pvalue: *?*PyObject, ptraceback: *?*PyObject) void {
    c.PyErr_Fetch(@ptrCast(ptype), @ptrCast(pvalue), @ptrCast(ptraceback));
}

/// Restore a previously fetched exception
pub inline fn PyErr_Restore(ptype: ?*PyObject, pvalue: ?*PyObject, ptraceback: ?*PyObject) void {
    c.PyErr_Restore(ptype, pvalue, ptraceback);
}

/// Normalize an exception (ensures value is an instance of type)
pub inline fn PyErr_NormalizeException(ptype: *?*PyObject, pvalue: *?*PyObject, ptraceback: *?*PyObject) void {
    c.PyErr_NormalizeException(@ptrCast(ptype), @ptrCast(pvalue), @ptrCast(ptraceback));
}

/// Check if a given exception matches a specific type
pub inline fn PyErr_GivenExceptionMatches(given: ?*PyObject, exc: *PyObject) bool {
    return c.PyErr_GivenExceptionMatches(given, exc) != 0;
}

/// Set an exception with an object value
pub inline fn PyErr_SetObject(exc: *PyObject, value: *PyObject) void {
    c.PyErr_SetObject(exc, value);
}

/// Get exception info (for except clause use)
pub inline fn PyErr_GetExcInfo(ptype: *?*PyObject, pvalue: *?*PyObject, ptraceback: *?*PyObject) void {
    c.PyErr_GetExcInfo(@ptrCast(ptype), @ptrCast(pvalue), @ptrCast(ptraceback));
}

pub inline fn PyObject_GenericGetAttr(obj: ?*PyObject, name: ?*PyObject) ?*PyObject {
    return @ptrCast(c.PyObject_GenericGetAttr(@ptrCast(obj), @ptrCast(name)));
}

pub inline fn PyObject_GenericSetAttr(obj: ?*PyObject, name: ?*PyObject, value: ?*PyObject) c_int {
    return c.PyObject_GenericSetAttr(@ptrCast(obj), @ptrCast(name), @ptrCast(value));
}

// Exception types - accessed via function to avoid comptime issues
pub inline fn PyExc_RuntimeError() *PyObject {
    return @ptrCast(c.PyExc_RuntimeError);
}

pub inline fn PyExc_TypeError() *PyObject {
    return @ptrCast(c.PyExc_TypeError);
}

pub inline fn PyExc_ValueError() *PyObject {
    return @ptrCast(c.PyExc_ValueError);
}

pub inline fn PyExc_AttributeError() *PyObject {
    return @ptrCast(c.PyExc_AttributeError);
}

pub inline fn PyExc_IndexError() *PyObject {
    return @ptrCast(c.PyExc_IndexError);
}

pub inline fn PyExc_KeyError() *PyObject {
    return @ptrCast(c.PyExc_KeyError);
}

pub inline fn PyExc_ZeroDivisionError() *PyObject {
    return @ptrCast(c.PyExc_ZeroDivisionError);
}

pub inline fn PyExc_StopIteration() *PyObject {
    return @ptrCast(c.PyExc_StopIteration);
}

pub inline fn PyExc_Exception() *PyObject {
    return @ptrCast(c.PyExc_Exception);
}

/// Create a new exception type
pub inline fn PyErr_NewException(name: [*:0]const u8, base: ?*PyObject, dict: ?*PyObject) ?*PyObject {
    return c.PyErr_NewException(name, base, dict);
}

// ============================================================================
// Type operations
// ============================================================================

pub inline fn PyType_FromSpec(spec: *PyType_Spec) ?*PyObject {
    return c.PyType_FromSpec(spec);
}

pub inline fn PyType_Ready(type_obj: *PyTypeObject) c_int {
    return c.PyType_Ready(type_obj);
}

pub inline fn PyType_GenericAlloc(type_obj: *PyTypeObject, nitems: Py_ssize_t) ?*PyObject {
    return c.PyType_GenericAlloc(type_obj, nitems);
}

pub inline fn PyType_GenericNew(type_obj: *PyTypeObject, args: ?*PyObject, kwds: ?*PyObject) ?*PyObject {
    return c.PyType_GenericNew(type_obj, args, kwds);
}

// ============================================================================
// Object operations
// ============================================================================

pub inline fn PyObject_Init(obj: *PyObject, type_obj: *PyTypeObject) ?*PyObject {
    return c.PyObject_Init(obj, type_obj);
}

pub inline fn PyObject_New(comptime T: type, type_obj: *PyTypeObject) ?*T {
    // Use type's tp_basicsize for allocation - this is important for subclasses
    // which may have larger basicsize to accommodate __dict__ and __weakref__
    const size: usize = @intCast(type_obj.tp_basicsize);
    const alloc_size = @max(size, @sizeOf(T));
    const obj = c.PyObject_Malloc(alloc_size);
    if (obj == null) return null;
    const typed: *T = @ptrCast(@alignCast(obj));
    if (c.PyObject_Init(@ptrCast(typed), type_obj) == null) {
        c.PyObject_Free(obj);
        return null;
    }
    return typed;
}

pub inline fn PyObject_Del(obj: anytype) void {
    c.PyObject_Free(@ptrCast(obj));
}

pub inline fn PyObject_ClearWeakRefs(obj: *PyObject) void {
    c.PyObject_ClearWeakRefs(obj);
}

pub inline fn PyObject_Repr(obj: *PyObject) ?*PyObject {
    return c.PyObject_Repr(obj);
}

pub inline fn PyObject_Str(obj: *PyObject) ?*PyObject {
    return c.PyObject_Str(obj);
}

/// Call a callable object with arguments
pub inline fn PyObject_CallObject(callable: *PyObject, args: ?*PyObject) ?*PyObject {
    return c.PyObject_CallObject(callable, args);
}

/// Call a callable object with args and kwargs
pub inline fn PyObject_Call(callable: *PyObject, args: *PyObject, kwargs: ?*PyObject) ?*PyObject {
    return c.PyObject_Call(callable, args, kwargs);
}

pub inline fn PyObject_SetAttrString(obj: *PyObject, name: [*:0]const u8, value: *PyObject) c_int {
    return c.PyObject_SetAttrString(obj, name, value);
}

// ============================================================================
// Module creation
// ============================================================================

pub inline fn PyModule_Create(def: *PyModuleDef) ?*PyObject {
    return c.PyModule_Create2(def, c.PYTHON_API_VERSION);
}

pub inline fn PyModule_AddObject(module: *PyObject, name: [*:0]const u8, value: *PyObject) c_int {
    return c.PyModule_AddObject(module, name, value);
}

pub inline fn PyModule_AddIntConstant(module: *PyObject, name: [*:0]const u8, value: c_long) c_int {
    return c.PyModule_AddIntConstant(module, name, value);
}

pub inline fn PyModule_AddStringConstant(module: *PyObject, name: [*:0]const u8, value: [*:0]const u8) c_int {
    return c.PyModule_AddStringConstant(module, name, value);
}

pub inline fn PyModule_AddType(module: *PyObject, type_obj: *PyTypeObject) c_int {
    return c.PyModule_AddType(module, type_obj);
}

// ============================================================================
// Reference counting
// ============================================================================

pub inline fn Py_IncRef(obj: ?*PyObject) void {
    c.Py_IncRef(obj);
}

pub inline fn Py_DecRef(obj: ?*PyObject) void {
    c.Py_DecRef(obj);
}

pub inline fn PyObject_IsTrue(obj: *PyObject) c_int {
    return c.PyObject_IsTrue(obj);
}

// ============================================================================
// String formatting
// ============================================================================

pub inline fn PyUnicode_FromFormat(format: [*:0]const u8, args: anytype) ?*PyObject {
    return @call(.auto, c.PyUnicode_FromFormat, .{format} ++ args);
}

// ============================================================================
// DateTime API
// ============================================================================

/// The datetime CAPI - lazily initialized on first use
var datetime_api: ?*c.PyDateTime_CAPI = null;

/// Ensure datetime API is initialized (called automatically by datetime functions)
fn ensureDateTimeAPI() ?*c.PyDateTime_CAPI {
    if (datetime_api) |api| return api;
    datetime_api = @ptrCast(@alignCast(c.PyCapsule_Import("datetime.datetime_CAPI", 0)));
    return datetime_api;
}

/// Explicitly initialize the datetime API (optional - happens automatically on first use)
pub fn PyDateTime_Import() bool {
    return ensureDateTimeAPI() != null;
}

/// Check if datetime API is initialized
pub fn PyDateTime_IsInitialized() bool {
    return datetime_api != null;
}

/// Create a date object
pub fn PyDate_FromDate(year: c_int, month: c_int, day: c_int) ?*PyObject {
    const api = ensureDateTimeAPI() orelse return null;
    const func = api.Date_FromDate orelse return null;
    return func(year, month, day, api.DateType);
}

/// Create a datetime object
pub fn PyDateTime_FromDateAndTime(year: c_int, month: c_int, day: c_int, hour: c_int, minute: c_int, second: c_int, usecond: c_int) ?*PyObject {
    const api = ensureDateTimeAPI() orelse return null;
    const func = api.DateTime_FromDateAndTime orelse return null;
    return func(year, month, day, hour, minute, second, usecond, @ptrCast(&c._Py_NoneStruct), api.DateTimeType);
}

/// Create a time object
pub fn PyTime_FromTime(hour: c_int, minute: c_int, second: c_int, usecond: c_int) ?*PyObject {
    const api = ensureDateTimeAPI() orelse return null;
    const func = api.Time_FromTime orelse return null;
    return func(hour, minute, second, usecond, @ptrCast(&c._Py_NoneStruct), api.TimeType);
}

/// Create a timedelta object
pub fn PyDelta_FromDSU(days: c_int, seconds: c_int, useconds: c_int) ?*PyObject {
    const api = ensureDateTimeAPI() orelse return null;
    const func = api.Delta_FromDelta orelse return null;
    return func(days, seconds, useconds, 1, api.DeltaType);
}

/// Check if object is a date (or datetime)
pub fn PyDate_Check(obj: *PyObject) bool {
    const api = ensureDateTimeAPI() orelse return false;
    return c.PyType_IsSubtype(Py_TYPE(obj), @ptrCast(api.DateType)) != 0;
}

/// Check if object is a datetime
pub fn PyDateTime_Check(obj: *PyObject) bool {
    const api = ensureDateTimeAPI() orelse return false;
    return c.PyType_IsSubtype(Py_TYPE(obj), @ptrCast(api.DateTimeType)) != 0;
}

/// Check if object is a time
pub fn PyTime_Check(obj: *PyObject) bool {
    const api = ensureDateTimeAPI() orelse return false;
    return c.PyType_IsSubtype(Py_TYPE(obj), @ptrCast(api.TimeType)) != 0;
}

/// Check if object is a timedelta
pub fn PyDelta_Check(obj: *PyObject) bool {
    const api = ensureDateTimeAPI() orelse return false;
    return c.PyType_IsSubtype(Py_TYPE(obj), @ptrCast(api.DeltaType)) != 0;
}

/// Get year from date/datetime
pub fn PyDateTime_GET_YEAR(obj: *PyObject) c_int {
    const date: *c.PyDateTime_Date = @ptrCast(obj);
    return (@as(c_int, date.data[0]) << 8) | @as(c_int, date.data[1]);
}

/// Get month from date/datetime
pub fn PyDateTime_GET_MONTH(obj: *PyObject) c_int {
    const date: *c.PyDateTime_Date = @ptrCast(obj);
    return @as(c_int, date.data[2]);
}

/// Get day from date/datetime
pub fn PyDateTime_GET_DAY(obj: *PyObject) c_int {
    const date: *c.PyDateTime_Date = @ptrCast(obj);
    return @as(c_int, date.data[3]);
}

/// Get hour from datetime/time
pub fn PyDateTime_DATE_GET_HOUR(obj: *PyObject) c_int {
    const dt: *c.PyDateTime_DateTime = @ptrCast(obj);
    return @as(c_int, dt.data[4]);
}

/// Get minute from datetime/time
pub fn PyDateTime_DATE_GET_MINUTE(obj: *PyObject) c_int {
    const dt: *c.PyDateTime_DateTime = @ptrCast(obj);
    return @as(c_int, dt.data[5]);
}

/// Get second from datetime/time
pub fn PyDateTime_DATE_GET_SECOND(obj: *PyObject) c_int {
    const dt: *c.PyDateTime_DateTime = @ptrCast(obj);
    return @as(c_int, dt.data[6]);
}

/// Get microsecond from datetime/time
pub fn PyDateTime_DATE_GET_MICROSECOND(obj: *PyObject) c_int {
    const dt: *c.PyDateTime_DateTime = @ptrCast(obj);
    return (@as(c_int, dt.data[7]) << 16) | (@as(c_int, dt.data[8]) << 8) | @as(c_int, dt.data[9]);
}

/// Get hour from time object
pub fn PyDateTime_TIME_GET_HOUR(obj: *PyObject) c_int {
    const t: *c.PyDateTime_Time = @ptrCast(obj);
    return @as(c_int, t.data[0]);
}

/// Get minute from time object
pub fn PyDateTime_TIME_GET_MINUTE(obj: *PyObject) c_int {
    const t: *c.PyDateTime_Time = @ptrCast(obj);
    return @as(c_int, t.data[1]);
}

/// Get second from time object
pub fn PyDateTime_TIME_GET_SECOND(obj: *PyObject) c_int {
    const t: *c.PyDateTime_Time = @ptrCast(obj);
    return @as(c_int, t.data[2]);
}

/// Get microsecond from time object
pub fn PyDateTime_TIME_GET_MICROSECOND(obj: *PyObject) c_int {
    const t: *c.PyDateTime_Time = @ptrCast(obj);
    return (@as(c_int, t.data[3]) << 16) | (@as(c_int, t.data[4]) << 8) | @as(c_int, t.data[5]);
}

/// Get days from timedelta
pub fn PyDateTime_DELTA_GET_DAYS(obj: *PyObject) c_int {
    const delta: *c.PyDateTime_Delta = @ptrCast(obj);
    return delta.days;
}

/// Get seconds from timedelta
pub fn PyDateTime_DELTA_GET_SECONDS(obj: *PyObject) c_int {
    const delta: *c.PyDateTime_Delta = @ptrCast(obj);
    return delta.seconds;
}

/// Get microseconds from timedelta
pub fn PyDateTime_DELTA_GET_MICROSECONDS(obj: *PyObject) c_int {
    const delta: *c.PyDateTime_Delta = @ptrCast(obj);
    return delta.microseconds;
}

// ============================================================================
// Bytes/ByteArray operations
// ============================================================================

pub inline fn PyBytes_FromStringAndSize(str: [*]const u8, size: Py_ssize_t) ?*PyObject {
    return c.PyBytes_FromStringAndSize(str, size);
}

pub inline fn PyBytes_AsStringAndSize(obj: *PyObject, buffer: *[*]u8, length: *Py_ssize_t) c_int {
    return c.PyBytes_AsStringAndSize(obj, @ptrCast(buffer), length);
}

pub inline fn PyBytes_Size(obj: *PyObject) Py_ssize_t {
    return c.PyBytes_Size(obj);
}

pub inline fn PyBytes_AsString(obj: *PyObject) ?[*]u8 {
    return c.PyBytes_AsString(obj);
}

pub inline fn PyBytes_Check(obj: *PyObject) bool {
    const bytes_type: *PyTypeObject = @ptrCast(&c.PyBytes_Type);
    return Py_TYPE(obj) == bytes_type or c.PyType_IsSubtype(Py_TYPE(obj), bytes_type) != 0;
}

pub inline fn PyByteArray_FromStringAndSize(str: ?[*]const u8, size: Py_ssize_t) ?*PyObject {
    return c.PyByteArray_FromStringAndSize(str, size);
}

pub inline fn PyByteArray_AsString(obj: *PyObject) ?[*]u8 {
    return c.PyByteArray_AsString(obj);
}

pub inline fn PyByteArray_Size(obj: *PyObject) Py_ssize_t {
    return c.PyByteArray_Size(obj);
}

pub inline fn PyByteArray_Check(obj: *PyObject) bool {
    const ba_type: *PyTypeObject = @ptrCast(&c.PyByteArray_Type);
    return Py_TYPE(obj) == ba_type or c.PyType_IsSubtype(Py_TYPE(obj), ba_type) != 0;
}

// ============================================================================
// Path operations (pathlib.Path)
// ============================================================================

var pathlib_path_type: ?*PyObject = null;

/// Get the pathlib.Path type (lazily imported)
fn getPathType() ?*PyObject {
    if (pathlib_path_type) |t| return t;

    // Import pathlib module
    const pathlib = c.PyImport_ImportModule("pathlib") orelse return null;
    defer Py_DecRef(pathlib);

    // Get Path class
    pathlib_path_type = c.PyObject_GetAttrString(pathlib, "Path");
    return pathlib_path_type;
}

/// Create a pathlib.Path from a string
pub fn PyPath_FromString(path: []const u8) ?*PyObject {
    const path_type = getPathType() orelse return null;
    const py_str = PyUnicode_FromStringAndSize(path.ptr, @intCast(path.len)) orelse return null;
    defer Py_DecRef(py_str);

    // Call Path(str)
    const args = PyTuple_Pack(.{py_str}) orelse return null;
    defer Py_DecRef(args);

    return c.PyObject_CallObject(path_type, args);
}

/// Check if an object is a pathlib.Path (or os.PathLike)
pub fn PyPath_Check(obj: *PyObject) bool {
    // Check for __fspath__ method (os.PathLike protocol)
    return c.PyObject_HasAttrString(obj, "__fspath__") != 0;
}

/// Get string from a path-like object using os.fspath()
pub fn PyPath_AsString(obj: *PyObject) ?[]const u8 {
    // Call os.fspath() on the object to get the string representation
    const fspath_result = c.PyOS_FSPath(obj) orelse return null;
    defer Py_DecRef(fspath_result);

    // Convert to string
    if (PyUnicode_Check(fspath_result)) {
        var size: Py_ssize_t = 0;
        const ptr = PyUnicode_AsUTF8AndSize(fspath_result, &size) orelse return null;
        return ptr[0..@intCast(size)];
    }
    return null;
}

// ============================================================================
// Python Embedding API
// ============================================================================

/// Input modes for PyRun_String
pub const Py_single_input = c.Py_single_input; // Single interactive statement
pub const Py_file_input = c.Py_file_input; // Module/file (sequence of statements)
pub const Py_eval_input = c.Py_eval_input; // Single expression

/// Initialize the Python interpreter
/// Must be called before any other Python API functions
pub fn Py_Initialize() void {
    c.Py_Initialize();
}

/// Initialize the Python interpreter with options
/// If initsigs is 0, skips signal handler registration
pub fn Py_InitializeEx(initsigs: c_int) void {
    c.Py_InitializeEx(initsigs);
}

/// Check if Python is initialized
pub fn Py_IsInitialized() bool {
    return c.Py_IsInitialized() != 0;
}

/// Finalize the Python interpreter
/// Frees all memory allocated by Python
pub fn Py_Finalize() void {
    c.Py_Finalize();
}

/// Finalize with error code
/// Returns 0 on success, -1 if an error occurred
pub fn Py_FinalizeEx() c_int {
    return c.Py_FinalizeEx();
}

/// Run a simple string of Python code
/// Returns 0 on success, -1 on error (exception is printed)
pub fn PyRun_SimpleString(code: [*:0]const u8) c_int {
    return c.PyRun_SimpleStringFlags(code, null);
}

/// Run a string of Python code with globals and locals dicts
/// mode: Py_eval_input (expression), Py_file_input (statements), or Py_single_input (interactive)
/// Returns the result object or null on error
pub fn PyRun_String(code: [*:0]const u8, mode: c_int, globals: *PyObject, locals: *PyObject) ?*PyObject {
    return c.PyRun_StringFlags(code, mode, globals, locals, null);
}

/// Get the __main__ module
pub fn PyImport_AddModule(name: [*:0]const u8) ?*PyObject {
    return c.PyImport_AddModule(name);
}

/// Import a module by name
pub fn PyImport_ImportModule(name: [*:0]const u8) ?*PyObject {
    return c.PyImport_ImportModule(name);
}

/// Get the dictionary of a module
pub fn PyModule_GetDict(module: *PyObject) ?*PyObject {
    return c.PyModule_GetDict(module);
}

/// Get a global variable from __main__
pub fn PyMain_GetGlobal(name: [*:0]const u8) ?*PyObject {
    const main_module = PyImport_AddModule("__main__") orelse return null;
    const main_dict = PyModule_GetDict(main_module) orelse return null;
    return PyDict_GetItemString(main_dict, name);
}

/// Set a global variable in __main__
pub fn PyMain_SetGlobal(name: [*:0]const u8, value: *PyObject) bool {
    const main_module = PyImport_AddModule("__main__") orelse return false;
    const main_dict = PyModule_GetDict(main_module) orelse return false;
    return PyDict_SetItemString(main_dict, name, value) == 0;
}

/// Evaluate a Python expression and return the result
/// Returns null on error (use PyErr_Occurred to check)
pub fn PyEval_Expression(expr: [*:0]const u8) ?*PyObject {
    const main_module = PyImport_AddModule("__main__") orelse return null;
    const main_dict = PyModule_GetDict(main_module) orelse return null;
    return PyRun_String(expr, Py_eval_input, main_dict, main_dict);
}

/// Execute Python statements
/// Returns true on success, false on error
pub fn PyExec_Statements(code: [*:0]const u8) bool {
    return PyRun_SimpleString(code) == 0;
}

/// Call a Python callable with arguments
pub fn PyObject_CallFunction(callable: *PyObject, args: ?*PyObject) ?*PyObject {
    return c.PyObject_CallObject(callable, args);
}

/// Get an attribute from an object
pub fn PyObject_GetAttr(obj: *PyObject, name: *PyObject) ?*PyObject {
    return c.PyObject_GetAttr(obj, name);
}

/// Get an attribute from an object by name string
pub fn PyObject_GetAttrString(obj: *PyObject, name: [*:0]const u8) ?*PyObject {
    return c.PyObject_GetAttrString(obj, name);
}

/// Set an attribute on an object
pub fn PyObject_SetAttr(obj: *PyObject, name: *PyObject, value: *PyObject) c_int {
    return c.PyObject_SetAttr(obj, name, value);
}

/// Check if object is an instance of a class
pub fn PyObject_IsInstance(obj: *PyObject, cls: *PyObject) c_int {
    return c.PyObject_IsInstance(obj, cls);
}

/// Print the current exception to stderr and clear it
pub fn PyErr_Print() void {
    c.PyErr_Print();
}
