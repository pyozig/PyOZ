//! Python singleton objects
//!
//! None, True, False, NotImplemented
//!
//! In ABI3 mode, we use PyBool_FromLong instead of direct struct access
//! because the internal layout of _Py_TrueStruct/_Py_FalseStruct may change.

const types = @import("types.zig");
const c = types.c;
const PyObject = types.PyObject;
const refcount = @import("refcount.zig");
const Py_IncRef = refcount.Py_IncRef;

/// Whether we're in ABI3 mode
const abi3_enabled = types.abi3_enabled;

// ============================================================================
// Singletons - MUST increment refcount when returning these!
// ============================================================================

// The singletons are data of the Python DLL: types.pyData reads their address
// through the import table on Windows.

pub inline fn Py_None() *PyObject {
    return types.pyData(PyObject, "_Py_NoneStruct");
}

pub inline fn Py_True() *PyObject {
    // In ABI3 mode, use PyBool_FromLong to avoid struct layout issues
    if (abi3_enabled) {
        // PyBool_FromLong returns a new reference, but True/False are immortal
        // so we can treat it like the singleton
        return c.PyBool_FromLong(1).?;
    } else {
        return types.pyData(PyObject, "_Py_TrueStruct");
    }
}

pub inline fn Py_False() *PyObject {
    if (abi3_enabled) {
        return c.PyBool_FromLong(0).?;
    } else {
        return types.pyData(PyObject, "_Py_FalseStruct");
    }
}

/// Return None with proper reference counting (use this when returning from functions)
pub inline fn Py_RETURN_NONE() *PyObject {
    const none = Py_None();
    Py_IncRef(none);
    return none;
}

/// Return True with proper reference counting
pub inline fn Py_RETURN_TRUE() *PyObject {
    if (abi3_enabled) {
        // PyBool_FromLong already returns a new reference
        return c.PyBool_FromLong(1).?;
    } else {
        const t = Py_True();
        Py_IncRef(t);
        return t;
    }
}

/// Return False with proper reference counting
pub inline fn Py_RETURN_FALSE() *PyObject {
    if (abi3_enabled) {
        // PyBool_FromLong already returns a new reference
        return c.PyBool_FromLong(0).?;
    } else {
        const f = Py_False();
        Py_IncRef(f);
        return f;
    }
}

/// Return a boolean with proper reference counting
pub inline fn Py_RETURN_BOOL(val: bool) *PyObject {
    if (abi3_enabled) {
        return c.PyBool_FromLong(if (val) 1 else 0).?;
    } else {
        return if (val) Py_RETURN_TRUE() else Py_RETURN_FALSE();
    }
}

/// Return NotImplemented (for comparison operators)
pub inline fn Py_NotImplemented() *PyObject {
    const ni = types.pyData(PyObject, "_Py_NotImplementedStruct");
    Py_IncRef(ni);
    return ni;
}
