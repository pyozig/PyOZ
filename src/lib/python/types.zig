//! Core Python C API types
//!
//! Re-exports essential types from the Python C API.
//! When ABI3 mode is enabled, defines Py_LIMITED_API to restrict to Stable ABI.

const std = @import("std");
const builtin = @import("builtin");
const build_options = @import("build_options");

// ABI3 configuration - Python 3.10 minimum (single source of truth; see abi.zig)
pub const abi3_enabled = build_options.abi3;
pub const abi3_version = "3.10";
pub const abi3_version_hex = 0x030A0000;

// Import Python C API from system headers
// In ABI3 mode, we define Py_LIMITED_API and exclude non-stable headers
pub const c = @cImport({
    @cDefine("PY_SSIZE_T_CLEAN", "1");

    // Zig 0.16's C translator mistranslates MinGW's _FORTIFY_SOURCE inline
    // wrappers (wcscat/wcscpy declare an unused local), which breaks
    // ReleaseSafe builds for Windows. PyOZ never calls those wrappers.
    if (builtin.os.tag == .windows) {
        @cUndef("_FORTIFY_SOURCE");
    }

    // Define Py_LIMITED_API for Python 3.10 minimum
    if (abi3_enabled) {
        @cDefine("Py_LIMITED_API", "0x030A0000");
    }

    @cInclude("Python.h");

    // datetime.h and structmember.h are NOT part of the Stable ABI
    if (!abi3_enabled) {
        @cInclude("datetime.h");
        @cInclude("structmember.h");
    }
});

// ============================================================================
// Re-export essential types
// ============================================================================

pub const PyObject = c.PyObject;
pub const Py_ssize_t = c.Py_ssize_t;
pub const PyTypeObject = c.PyTypeObject;

/// Address of a built-in CPython type object (e.g. `typeObject("PyLong_Type")`).
///
/// Uses `@extern` instead of `&c.PyLong_Type`: under Py_LIMITED_API,
/// PyTypeObject is opaque and Zig 0.16's C translator refuses extern variables
/// of opaque type (it emits `@compileError`). `@extern` only needs a pointer
/// type, so this works identically in full and ABI3 modes.
pub inline fn typeObject(comptime name: []const u8) *PyTypeObject {
    return pyData(PyTypeObject, name);
}

/// Address of a data symbol exported by the Python DLL/shared library
/// (`_Py_NoneStruct`, `PyExc_TypeError`, `PyLong_Type`, ...).
///
/// On Windows such a symbol is imported: its address is only known at run
/// time, from the import table. `&c.X` lets Zig treat the address as a
/// link-time constant, which the optimizer can place in a constant (a
/// switch's table of results); the linker then fills it with the address of
/// the import slot instead of the object. `is_dll_import` makes every use
/// load the address from the slot, as `__declspec(dllimport)` does in C.
pub inline fn pyData(comptime T: type, comptime name: []const u8) *T {
    return @extern(*T, .{ .name = name, .is_dll_import = builtin.os.tag == .windows });
}

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
pub const has_direct_ob_refcnt = @hasField(c.PyObject, "ob_refcnt");

/// True when compiling against a free-threaded (PEP 703, "3.13t"/"3.14t") CPython.
/// The object header layout differs: ob_tid / ob_ref_local / ob_ref_shared.
pub const gil_disabled = @hasDecl(c, "Py_GIL_DISABLED");

/// Initialize the header of a *statically allocated* PyObject the way
/// `PyObject_HEAD_INIT` does, for every CPython layout PyOZ supports.
/// (Writing `1` into the first word is only correct for GIL builds: on
/// free-threaded builds the first word is `ob_tid`.)
pub fn initStaticHeader(ob: *c.PyObject) void {
    if (comptime gil_disabled) {
        ob.ob_tid = 0;
        ob.ob_flags = if (@hasDecl(c, "_Py_STATICALLY_ALLOCATED_FLAG")) c._Py_STATICALLY_ALLOCATED_FLAG else 0;
        ob.ob_ref_local = std.math.maxInt(u32); // _Py_IMMORTAL_REFCNT_LOCAL
        ob.ob_ref_shared = 0;
    } else if (comptime has_direct_ob_refcnt) {
        ob.ob_refcnt = 1;
    } else {
        // Python 3.12+: ob_refcnt is inside an anonymous union at offset 0
        const ob_ptr: *Py_ssize_t = @ptrCast(ob);
        ob_ptr.* = 1;
    }
    ob.ob_type = null;
}

pub const PyModuleDef_HEAD_INIT: PyModuleDef_Base = blk: {
    var base: PyModuleDef_Base = std.mem.zeroes(PyModuleDef_Base);
    base.m_init = null;
    base.m_index = 0;
    base.m_copy = null;
    initStaticHeader(&base.ob_base);
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
