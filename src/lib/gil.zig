//! GIL (Global Interpreter Lock) Control
//!
//! Provides utilities for releasing and acquiring the GIL for multi-threaded
//! Python extensions.

const py = @import("python.zig");
const unwrapSignature = @import("root.zig").unwrapSignature;
const unwrapSignatureValue = @import("root.zig").unwrapSignatureValue;

/// RAII-style GIL releaser. Releases the GIL on creation, reacquires on deinit.
/// Use this when you have CPU-intensive code that doesn't touch Python objects.
///
/// Example:
/// ```zig
/// fn heavy_computation(n: i64) i64 {
///     // Release the GIL while doing CPU-intensive work
///     const gil = pyoz.releaseGIL();
///     defer gil.acquire();
///
///     // This code runs without the GIL - other Python threads can run
///     var result: i64 = 0;
///     for (0..@intCast(n)) |i| {
///         result += compute(i);
///     }
///     return result;
/// }
/// ```
pub const GILGuard = struct {
    state: ?*py.PyThreadState,

    /// Reacquire the GIL
    pub fn acquire(self: GILGuard) void {
        py.PyEval_RestoreThread(self.state);
    }
};

/// Release the GIL, allowing other Python threads to run.
/// Returns a guard that must be used to reacquire the GIL.
/// IMPORTANT: Do not access any Python objects while the GIL is released!
pub fn releaseGIL() GILGuard {
    return .{ .state = py.PyEval_SaveThread() };
}

/// Low-level GIL state for acquiring GIL from non-Python threads
pub const GILState = struct {
    state: py.PyGILState_STATE,

    /// Release the GIL
    pub fn release(self: GILState) void {
        py.PyGILState_Release(self.state);
    }
};

/// Acquire the GIL from a non-Python thread.
/// Use this when calling into Python from a Zig thread that wasn't created by Python.
pub fn acquireGIL() GILState {
    return .{ .state = py.PyGILState_Ensure() };
}

/// Release the GIL, call a function, then reacquire the GIL.
/// The function must not access any Python objects.
///
/// Example:
/// ```zig
/// fn heavy_work(data: []const u8) i64 {
///     return pyoz.allowThreads(compute, .{data});
/// }
/// ```
pub fn allowThreads(comptime func: anytype, args: anytype) unwrapSignature(@typeInfo(@TypeOf(func)).@"fn".return_type.?) {
    const RawReturnType = @typeInfo(@TypeOf(func)).@"fn".return_type.?;
    const state = py.PyEval_SaveThread();
    const raw_result = @call(.auto, func, args);
    py.PyEval_RestoreThread(state);
    return unwrapSignatureValue(RawReturnType, raw_result);
}

/// Like `allowThreads` but for functions that return errors.
/// Releases the GIL, calls the function, reacquires the GIL, then propagates the error.
pub fn allowThreadsTry(comptime func: anytype, args: anytype) unwrapSignature(@typeInfo(@TypeOf(func)).@"fn".return_type.?) {
    const RawReturnType = @typeInfo(@TypeOf(func)).@"fn".return_type.?;
    const state = py.PyEval_SaveThread();
    defer py.PyEval_RestoreThread(state);
    return unwrapSignatureValue(RawReturnType, @call(.auto, func, args));
}
