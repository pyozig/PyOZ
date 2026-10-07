//! Error handling operations for Python C API

const types = @import("types.zig");
const c = types.c;
const PyObject = types.PyObject;

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

/// Create a new exception type
pub inline fn PyErr_NewException(name: [*:0]const u8, base: ?*PyObject, dict: ?*PyObject) ?*PyObject {
    return c.PyErr_NewException(name, base, dict);
}

/// Print the current exception to stderr and clear it
pub inline fn PyErr_Print() void {
    c.PyErr_Print();
}

// ============================================================================
// Exception types - accessed via function to avoid comptime issues
// ============================================================================

/// The exception type stored in CPython's `PyExc_*` variable, read through
/// the import table on Windows (see types.pyData).
inline fn excObject(comptime name: anytype) *PyObject {
    return types.pyData(*PyObject, @tagName(name)).*;
}

pub inline fn PyExc_RuntimeError() *PyObject {
    return excObject(.PyExc_RuntimeError);
}

pub inline fn PyExc_TypeError() *PyObject {
    return excObject(.PyExc_TypeError);
}

pub inline fn PyExc_ValueError() *PyObject {
    return excObject(.PyExc_ValueError);
}

pub inline fn PyExc_AttributeError() *PyObject {
    return excObject(.PyExc_AttributeError);
}

pub inline fn PyExc_IndexError() *PyObject {
    return excObject(.PyExc_IndexError);
}

pub inline fn PyExc_KeyError() *PyObject {
    return excObject(.PyExc_KeyError);
}

pub inline fn PyExc_ZeroDivisionError() *PyObject {
    return excObject(.PyExc_ZeroDivisionError);
}

pub inline fn PyExc_StopIteration() *PyObject {
    return excObject(.PyExc_StopIteration);
}

pub inline fn PyExc_Exception() *PyObject {
    return excObject(.PyExc_Exception);
}

pub inline fn PyExc_ArithmeticError() *PyObject {
    return excObject(.PyExc_ArithmeticError);
}

pub inline fn PyExc_LookupError() *PyObject {
    return excObject(.PyExc_LookupError);
}

pub inline fn PyExc_AssertionError() *PyObject {
    return excObject(.PyExc_AssertionError);
}

pub inline fn PyExc_BufferError() *PyObject {
    return excObject(.PyExc_BufferError);
}

pub inline fn PyExc_EOFError() *PyObject {
    return excObject(.PyExc_EOFError);
}

pub inline fn PyExc_FileExistsError() *PyObject {
    return excObject(.PyExc_FileExistsError);
}

pub inline fn PyExc_FileNotFoundError() *PyObject {
    return excObject(.PyExc_FileNotFoundError);
}

pub inline fn PyExc_FloatingPointError() *PyObject {
    return excObject(.PyExc_FloatingPointError);
}

pub inline fn PyExc_ImportError() *PyObject {
    return excObject(.PyExc_ImportError);
}

pub inline fn PyExc_ModuleNotFoundError() *PyObject {
    return excObject(.PyExc_ModuleNotFoundError);
}

pub inline fn PyExc_IsADirectoryError() *PyObject {
    return excObject(.PyExc_IsADirectoryError);
}

pub inline fn PyExc_MemoryError() *PyObject {
    return excObject(.PyExc_MemoryError);
}

pub inline fn PyExc_NotADirectoryError() *PyObject {
    return excObject(.PyExc_NotADirectoryError);
}

pub inline fn PyExc_NotImplementedError() *PyObject {
    return excObject(.PyExc_NotImplementedError);
}

pub inline fn PyExc_OSError() *PyObject {
    return excObject(.PyExc_OSError);
}

pub inline fn PyExc_OverflowError() *PyObject {
    return excObject(.PyExc_OverflowError);
}

pub inline fn PyExc_PermissionError() *PyObject {
    return excObject(.PyExc_PermissionError);
}

pub inline fn PyExc_ProcessLookupError() *PyObject {
    return excObject(.PyExc_ProcessLookupError);
}

pub inline fn PyExc_RecursionError() *PyObject {
    return excObject(.PyExc_RecursionError);
}

pub inline fn PyExc_SystemError() *PyObject {
    return excObject(.PyExc_SystemError);
}

pub inline fn PyExc_TimeoutError() *PyObject {
    return excObject(.PyExc_TimeoutError);
}

pub inline fn PyExc_UnicodeDecodeError() *PyObject {
    return excObject(.PyExc_UnicodeDecodeError);
}

pub inline fn PyExc_UnicodeEncodeError() *PyObject {
    return excObject(.PyExc_UnicodeEncodeError);
}

pub inline fn PyExc_UnicodeError() *PyObject {
    return excObject(.PyExc_UnicodeError);
}

pub inline fn PyExc_ConnectionError() *PyObject {
    return excObject(.PyExc_ConnectionError);
}

pub inline fn PyExc_ConnectionAbortedError() *PyObject {
    return excObject(.PyExc_ConnectionAbortedError);
}

pub inline fn PyExc_ConnectionRefusedError() *PyObject {
    return excObject(.PyExc_ConnectionRefusedError);
}

pub inline fn PyExc_ConnectionResetError() *PyObject {
    return excObject(.PyExc_ConnectionResetError);
}

pub inline fn PyExc_BlockingIOError() *PyObject {
    return excObject(.PyExc_BlockingIOError);
}

pub inline fn PyExc_BrokenPipeError() *PyObject {
    return excObject(.PyExc_BrokenPipeError);
}

pub inline fn PyExc_ChildProcessError() *PyObject {
    return excObject(.PyExc_ChildProcessError);
}

pub inline fn PyExc_InterruptedError() *PyObject {
    return excObject(.PyExc_InterruptedError);
}

pub inline fn PyExc_SystemExit() *PyObject {
    return excObject(.PyExc_SystemExit);
}

pub inline fn PyExc_KeyboardInterrupt() *PyObject {
    return excObject(.PyExc_KeyboardInterrupt);
}

pub inline fn PyExc_BaseException() *PyObject {
    return excObject(.PyExc_BaseException);
}

pub inline fn PyExc_GeneratorExit() *PyObject {
    return excObject(.PyExc_GeneratorExit);
}

pub inline fn PyExc_NameError() *PyObject {
    return excObject(.PyExc_NameError);
}

pub inline fn PyExc_UnboundLocalError() *PyObject {
    return excObject(.PyExc_UnboundLocalError);
}

pub inline fn PyExc_ReferenceError() *PyObject {
    return excObject(.PyExc_ReferenceError);
}

pub inline fn PyExc_StopAsyncIteration() *PyObject {
    return excObject(.PyExc_StopAsyncIteration);
}

pub inline fn PyExc_SyntaxError() *PyObject {
    return excObject(.PyExc_SyntaxError);
}

pub inline fn PyExc_IndentationError() *PyObject {
    return excObject(.PyExc_IndentationError);
}

pub inline fn PyExc_TabError() *PyObject {
    return excObject(.PyExc_TabError);
}

pub inline fn PyExc_UnicodeTranslateError() *PyObject {
    return excObject(.PyExc_UnicodeTranslateError);
}

// ============================================================================
// Warning types
// ============================================================================

pub inline fn PyExc_Warning() *PyObject {
    return excObject(.PyExc_Warning);
}

pub inline fn PyExc_BytesWarning() *PyObject {
    return excObject(.PyExc_BytesWarning);
}

pub inline fn PyExc_DeprecationWarning() *PyObject {
    return excObject(.PyExc_DeprecationWarning);
}

pub inline fn PyExc_FutureWarning() *PyObject {
    return excObject(.PyExc_FutureWarning);
}

pub inline fn PyExc_ImportWarning() *PyObject {
    return excObject(.PyExc_ImportWarning);
}

pub inline fn PyExc_PendingDeprecationWarning() *PyObject {
    return excObject(.PyExc_PendingDeprecationWarning);
}

pub inline fn PyExc_ResourceWarning() *PyObject {
    return excObject(.PyExc_ResourceWarning);
}

pub inline fn PyExc_RuntimeWarning() *PyObject {
    return excObject(.PyExc_RuntimeWarning);
}

pub inline fn PyExc_SyntaxWarning() *PyObject {
    return excObject(.PyExc_SyntaxWarning);
}

pub inline fn PyExc_UnicodeWarning() *PyObject {
    return excObject(.PyExc_UnicodeWarning);
}

pub inline fn PyExc_UserWarning() *PyObject {
    return excObject(.PyExc_UserWarning);
}

// ============================================================================
// Signal handling
// ============================================================================

/// Check for pending signals (e.g., Ctrl+C / SIGINT).
/// Returns 0 if no signal is pending, -1 if a signal was received
/// and the corresponding Python exception (e.g., KeyboardInterrupt) has been set.
pub inline fn PyErr_CheckSignals() c_int {
    return c.PyErr_CheckSignals();
}
