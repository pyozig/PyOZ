//! Error Mapping
//!
//! Provides utilities for mapping Zig errors to Python exceptions.

const std = @import("std");
const py = @import("python.zig");
const exceptions = @import("exceptions.zig");
const ExcBase = exceptions.ExcBase;

/// Define how a Zig error maps to a Python exception type
pub const ErrorMapping = struct {
    /// The Zig error name (e.g., "OutOfMemory", "InvalidArgument")
    error_name: []const u8,
    /// The Python exception type to use
    exc_type: ExcBase,
    /// Custom message (if null, uses the error name)
    message: ?[*:0]const u8 = null,
};

/// Create an error mapping entry
pub fn mapError(comptime error_name: []const u8, comptime exc_type: ExcBase) ErrorMapping {
    return .{
        .error_name = error_name,
        .exc_type = exc_type,
        .message = null,
    };
}

/// Create an error mapping with custom message
pub fn mapErrorMsg(comptime error_name: []const u8, comptime exc_type: ExcBase, comptime message: [*:0]const u8) ErrorMapping {
    return .{
        .error_name = error_name,
        .exc_type = exc_type,
        .message = message,
    };
}

/// Helper to set a Python exception from a Zig error using the mapping
pub fn setErrorFromMapping(comptime mappings: []const ErrorMapping, err: anyerror) void {
    // If a Python exception is already set (e.g., by conversion code), preserve it
    if (py.PyErr_Occurred() != null) {
        return;
    }

    const err_name = @errorName(err);

    // Search for a mapping
    inline for (mappings) |mapping| {
        if (std.mem.eql(u8, err_name, mapping.error_name)) {
            const exc = mapping.exc_type.toPyObject();
            if (mapping.message) |msg| {
                py.PyErr_SetString(exc, msg);
            } else {
                py.PyErr_SetString(exc, err_name.ptr);
            }
            return;
        }
    }

    // Default: RuntimeError with error name
    py.PyErr_SetString(py.PyExc_RuntimeError(), err_name.ptr);
}
