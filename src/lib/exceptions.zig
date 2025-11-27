//! Exception handling and definition
//!
//! Provides types and utilities for catching, raising, and defining
//! Python exceptions from Zig code.

const py = @import("python.zig");
const PyObject = py.PyObject;

/// Represents a caught Python exception
pub const PythonException = struct {
    exc_type: ?*PyObject,
    exc_value: ?*PyObject,
    exc_traceback: ?*PyObject,

    /// Get the exception type (e.g., ValueError, TypeError)
    pub fn getType(self: PythonException) ?*PyObject {
        return self.exc_type;
    }

    /// Get the exception value/message
    pub fn getValue(self: PythonException) ?*PyObject {
        return self.exc_value;
    }

    /// Get the exception traceback
    pub fn getTraceback(self: PythonException) ?*PyObject {
        return self.exc_traceback;
    }

    /// Check if this exception matches a specific type
    pub fn matches(self: PythonException, exc_type: *PyObject) bool {
        return py.PyErr_GivenExceptionMatches(self.exc_type, exc_type);
    }

    /// Check if this is a ValueError
    pub fn isValueError(self: PythonException) bool {
        return self.matches(py.PyExc_ValueError());
    }

    /// Check if this is a TypeError
    pub fn isTypeError(self: PythonException) bool {
        return self.matches(py.PyExc_TypeError());
    }

    /// Check if this is a KeyError
    pub fn isKeyError(self: PythonException) bool {
        return self.matches(py.PyExc_KeyError());
    }

    /// Check if this is an IndexError
    pub fn isIndexError(self: PythonException) bool {
        return self.matches(py.PyExc_IndexError());
    }

    /// Check if this is a RuntimeError
    pub fn isRuntimeError(self: PythonException) bool {
        return self.matches(py.PyExc_RuntimeError());
    }

    /// Check if this is a StopIteration
    pub fn isStopIteration(self: PythonException) bool {
        return self.matches(py.PyExc_StopIteration());
    }

    /// Check if this is a ZeroDivisionError
    pub fn isZeroDivisionError(self: PythonException) bool {
        return self.matches(py.PyExc_ZeroDivisionError());
    }

    /// Check if this is an AttributeError
    pub fn isAttributeError(self: PythonException) bool {
        return self.matches(py.PyExc_AttributeError());
    }

    /// Get the string representation of the exception value
    pub fn getMessage(self: PythonException) ?[]const u8 {
        if (self.exc_value) |val| {
            const str_obj = py.PyObject_Str(val) orelse return null;
            defer py.Py_DecRef(str_obj);
            return py.PyUnicode_AsUTF8(str_obj);
        }
        return null;
    }

    /// Re-raise this exception (restore it to Python's error state)
    pub fn reraise(self: PythonException) void {
        // Restore takes ownership, so we incref first if we want to keep our references
        if (self.exc_type) |t| py.Py_IncRef(t);
        if (self.exc_value) |v| py.Py_IncRef(v);
        if (self.exc_traceback) |tb| py.Py_IncRef(tb);
        py.PyErr_Restore(self.exc_type, self.exc_value, self.exc_traceback);
    }

    /// Release the exception references (call when you've handled the exception)
    pub fn deinit(self: *PythonException) void {
        if (self.exc_type) |t| py.Py_DecRef(t);
        if (self.exc_value) |v| py.Py_DecRef(v);
        if (self.exc_traceback) |tb| py.Py_DecRef(tb);
        self.exc_type = null;
        self.exc_value = null;
        self.exc_traceback = null;
    }
};

/// Catch the current Python exception if one is set
/// Returns null if no exception is pending
/// Usage:
///   if (catchException()) |*exc| {
///       defer exc.deinit();
///       if (exc.isValueError()) { ... }
///   }
pub fn catchException() ?PythonException {
    if (py.PyErr_Occurred() == null) {
        return null;
    }

    var exc = PythonException{
        .exc_type = null,
        .exc_value = null,
        .exc_traceback = null,
    };

    py.PyErr_Fetch(&exc.exc_type, &exc.exc_value, &exc.exc_traceback);
    py.PyErr_NormalizeException(&exc.exc_type, &exc.exc_value, &exc.exc_traceback);

    return exc;
}

/// Check if an exception is pending without clearing it
pub fn exceptionPending() bool {
    return py.PyErr_Occurred() != null;
}

/// Clear any pending exception
pub fn clearException() void {
    py.PyErr_Clear();
}

/// Raise a Python exception with a message
pub fn raiseException(exc_type: *PyObject, message: [*:0]const u8) void {
    py.PyErr_SetString(exc_type, message);
}

/// Raise a ValueError with a message
pub fn raiseValueError(message: [*:0]const u8) void {
    py.PyErr_SetString(py.PyExc_ValueError(), message);
}

/// Raise a TypeError with a message
pub fn raiseTypeError(message: [*:0]const u8) void {
    py.PyErr_SetString(py.PyExc_TypeError(), message);
}

/// Raise a RuntimeError with a message
pub fn raiseRuntimeError(message: [*:0]const u8) void {
    py.PyErr_SetString(py.PyExc_RuntimeError(), message);
}

/// Raise a KeyError with a message
pub fn raiseKeyError(message: [*:0]const u8) void {
    py.PyErr_SetString(py.PyExc_KeyError(), message);
}

/// Raise an IndexError with a message
pub fn raiseIndexError(message: [*:0]const u8) void {
    py.PyErr_SetString(py.PyExc_IndexError(), message);
}

/// Standard Python exception types for use as bases
pub const PyExc = struct {
    pub fn Exception() *PyObject {
        return py.PyExc_Exception();
    }
    pub fn TypeError() *PyObject {
        return py.PyExc_TypeError();
    }
    pub fn ValueError() *PyObject {
        return py.PyExc_ValueError();
    }
    pub fn RuntimeError() *PyObject {
        return py.PyExc_RuntimeError();
    }
    pub fn IndexError() *PyObject {
        return py.PyExc_IndexError();
    }
    pub fn KeyError() *PyObject {
        return py.PyExc_KeyError();
    }
    pub fn AttributeError() *PyObject {
        return py.PyExc_AttributeError();
    }
    pub fn StopIteration() *PyObject {
        return py.PyExc_StopIteration();
    }
};

/// Base exception type enum for compile-time specification
pub const ExcBase = enum {
    Exception,
    TypeError,
    ValueError,
    RuntimeError,
    IndexError,
    KeyError,
    AttributeError,
    StopIteration,

    pub fn toPyObject(self: ExcBase) *PyObject {
        return switch (self) {
            .Exception => py.PyExc_Exception(),
            .TypeError => py.PyExc_TypeError(),
            .ValueError => py.PyExc_ValueError(),
            .RuntimeError => py.PyExc_RuntimeError(),
            .IndexError => py.PyExc_IndexError(),
            .KeyError => py.PyExc_KeyError(),
            .AttributeError => py.PyExc_AttributeError(),
            .StopIteration => py.PyExc_StopIteration(),
        };
    }
};

/// Exception definition for the module
pub const ExceptionDef = struct {
    /// Name of the exception (e.g., "MyError")
    name: [*:0]const u8,
    /// Full qualified name (e.g., "mymodule.MyError") - set during module init
    full_name: ?[*:0]const u8 = null,
    /// Base exception type
    base: ExcBase = .Exception,
    /// Documentation string
    doc: ?[*:0]const u8 = null,
    /// Runtime storage for the created exception type
    exception_type: ?*PyObject = null,
};

/// Create an exception definition
/// Supports two syntaxes:
/// - Full options: pyoz.exception("MyError", .{ .doc = "...", .base = .ValueError })
/// - Shorthand:    pyoz.exception("MyError", .ValueError)
pub fn exception(comptime name: [*:0]const u8, comptime opts: anytype) ExceptionDef {
    const OptsType = @TypeOf(opts);
    const type_info = @typeInfo(OptsType);

    // Check if opts is an enum literal (shorthand syntax like .ValueError)
    if (type_info == .enum_literal) {
        const base: ExcBase = opts; // coerce enum literal to ExcBase
        return .{
            .name = name,
            .doc = null,
            .base = base,
        };
    }

    // Check if opts is an ExcBase enum value
    if (OptsType == ExcBase) {
        return .{
            .name = name,
            .doc = null,
            .base = opts,
        };
    }

    // Otherwise expect a struct with optional doc and base fields
    return .{
        .name = name,
        .doc = if (@hasField(OptsType, "doc")) opts.doc else null,
        .base = if (@hasField(OptsType, "base")) opts.base else .Exception,
    };
}

/// Helper to raise a custom exception
pub fn raise(exc: *const ExceptionDef, msg: [*:0]const u8) void {
    if (exc.exception_type) |exc_type| {
        py.PyErr_SetString(exc_type, msg);
    } else {
        // Fallback to RuntimeError if exception wasn't initialized
        py.PyErr_SetString(py.PyExc_RuntimeError(), msg);
    }
}
