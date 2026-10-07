//! Base types for class inheritance
//!
//! Provides base type accessors for inheriting from Python built-in types
//! like list, dict, set, Exception, etc.

const py = @import("python.zig");
const PyTypeObject = py.PyTypeObject;
const PyObject = py.PyObject;

/// Get Python base type objects for use with __base__ declaration
/// Usage in struct: pub const __base__ = pyoz.bases.Exception;
pub const bases = struct {
    /// Base: object (default, usually not needed)
    pub fn object() ?*PyTypeObject {
        return py.types.typeObject("PyBaseObject_Type");
    }

    /// Base: Exception
    pub fn Exception() ?*PyTypeObject {
        return @ptrCast(py.PyExc_Exception());
    }

    /// Base: ValueError
    pub fn ValueError() ?*PyTypeObject {
        return @ptrCast(py.PyExc_ValueError());
    }

    /// Base: TypeError
    pub fn TypeError() ?*PyTypeObject {
        return @ptrCast(py.PyExc_TypeError());
    }

    /// Base: RuntimeError
    pub fn RuntimeError() ?*PyTypeObject {
        return @ptrCast(py.PyExc_RuntimeError());
    }

    /// Base: list
    pub fn list() ?*PyTypeObject {
        return py.types.typeObject("PyList_Type");
    }

    /// Base: dict
    pub fn dict() ?*PyTypeObject {
        return py.types.typeObject("PyDict_Type");
    }

    /// Base: set
    pub fn set() ?*PyTypeObject {
        return py.types.typeObject("PySet_Type");
    }

    /// Base: tuple
    pub fn tuple() ?*PyTypeObject {
        return py.types.typeObject("PyTuple_Type");
    }

    /// Base: str
    pub fn str() ?*PyTypeObject {
        return py.types.typeObject("PyUnicode_Type");
    }

    /// Base: int
    pub fn int() ?*PyTypeObject {
        return py.types.typeObject("PyLong_Type");
    }

    /// Base: float
    pub fn float() ?*PyTypeObject {
        return py.types.typeObject("PyFloat_Type");
    }
};

/// Cast self pointer to PyObject for use with Python C API functions.
/// Use this in classes that inherit from Python built-in types (list, dict, etc.)
/// where 'self' is actually a pointer to the Python object.
///
/// Example:
/// ```zig
/// const Stack = struct {
///     pub const __base__ = pyoz.bases.list;
///
///     pub fn push(self: *Stack, item: *pyoz.PyObject) void {
///         _ = pyoz.py.PyList_Append(pyoz.object(self), item);
///     }
/// };
/// ```
pub fn object(ptr: anytype) *PyObject {
    const PtrType = @TypeOf(ptr);
    const ptr_info = @typeInfo(PtrType).pointer;
    if (ptr_info.is_const) {
        return @ptrCast(@alignCast(@constCast(ptr)));
    }
    return @ptrCast(@alignCast(ptr));
}
