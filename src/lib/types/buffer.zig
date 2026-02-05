//! Buffer types for Python interop
//!
//! Provides BufferView and BufferViewMut for access to numpy arrays
//! and other objects supporting the Python buffer protocol.
//!
//! In non-ABI3 mode: Zero-copy access via PyObject_GetBuffer
//! In ABI3 mode: Copy-based access via memoryview.tobytes() (Limited API compatible)

const std = @import("std");
const py = @import("../python.zig");
const PyObject = py.PyObject;
const Py_ssize_t = py.Py_ssize_t;

// Import complex types for format checking
const complex_types = @import("complex.zig");
const Complex = complex_types.Complex;
const Complex32 = complex_types.Complex32;

const abi3_enabled = py.types.abi3_enabled;
const c = py.c;

/// Whether zero-copy buffer access is available (not in ABI3 mode)
pub const zero_copy_available = py.buffer.available;

/// Whether buffer consumer is available (always true - ABI3 uses copy-based fallback)
pub const available = true;

// ============================================================================
// BufferView - works in both modes
// ============================================================================

/// Buffer info struct for implementing the buffer protocol
/// Return this from your __buffer__ method to expose memory to Python/numpy
/// NOTE: Not available in ABI3 mode (producer only)
pub const BufferInfo = struct {
    ptr: [*]u8,
    len: usize,
    readonly: bool = false,
    format: ?[*:0]u8 = null, // e.g., "d" for f64, "l" for i64, "B" for u8
    itemsize: usize = 1,
    ndim: usize = 1,
    shape: ?[*]Py_ssize_t = null,
    strides: ?[*]Py_ssize_t = null,

    comptime {
        if (abi3_enabled) {
            @compileError(
                \\BufferInfo (buffer producer) is not available in ABI3 mode.
                \\The buffer protocol cannot be implemented in the Limited API.
                \\Use a regular method returning bytes or a list instead.
            );
        }
    }
};

/// View into a Python buffer (numpy array, bytes, memoryview, etc.)
/// Use this as a function parameter type to receive numpy arrays.
///
/// In non-ABI3 mode: Zero-copy access (data points directly to Python memory)
/// In ABI3 mode: Copy-based access (data is copied via memoryview.tobytes())
///
/// The view is valid only during the function call - do not store references to the data.
/// For mutable access, use BufferViewMut(T) (non-ABI3 only).
///
/// Supported element types: i8, i16, i32, i64, u8, u16, u32, u64, f32, f64, Complex, Complex32
///
/// Example:
/// ```zig
/// fn sum_array(arr: pyoz.BufferView(f64)) f64 {
///     var total: f64 = 0;
///     for (arr.data) |v| total += v;
///     return total;
/// }
/// ```
///
/// Python usage:
/// ```python
/// import numpy as np
/// arr = np.array([1.0, 2.0, 3.0], dtype=np.float64)
/// result = mymodule.sum_array(arr)
/// ```
pub fn BufferView(comptime T: type) type {
    return struct {
        pub const _is_pyoz_buffer = true;

        /// The underlying data as a Zig slice (read-only)
        data: []const T,
        /// Number of dimensions (1 for 1D array, 2 for 2D, etc.)
        ndim: usize,
        /// Shape of each dimension
        shape: []const Py_ssize_t,
        /// Strides for each dimension (in bytes) - null in ABI3 mode
        strides: ?[]const Py_ssize_t,

        // Internal fields differ between ABI3 and non-ABI3 modes
        /// The Python object (for reference counting)
        _py_obj: *PyObject,

        // Non-ABI3: buffer view that must be released
        // ABI3: bytes object containing copied data
        _buffer: if (abi3_enabled) ?*PyObject else py.Py_buffer,

        // ABI3 mode: we need to store shape values since we get them from Python
        _shape_storage: if (abi3_enabled) [8]Py_ssize_t else void,

        const Self = @This();
        pub const ElementType = T;
        pub const is_buffer_view = true;
        pub const is_mutable = false;
        pub const is_zero_copy = !abi3_enabled;

        /// Get the total number of elements
        pub fn len(self: Self) usize {
            return self.data.len;
        }

        /// Check if the buffer is empty
        pub fn isEmpty(self: Self) bool {
            return self.data.len == 0;
        }

        /// Check if the buffer is C-contiguous (row-major)
        pub fn isContiguous(self: Self) bool {
            if (abi3_enabled) {
                // In ABI3 mode, data is always contiguous (it's a copy)
                return true;
            } else {
                return self._buffer.strides == null or self.ndim == 1;
            }
        }

        /// Get element at a flat index
        pub fn get(self: Self, index: usize) T {
            return self.data[index];
        }

        /// Get element at 2D index (row, col) - only valid for 2D arrays
        /// Returns error.DimensionMismatch if called on non-2D array
        pub fn get2D(self: Self, row: usize, col: usize) !T {
            if (self.ndim != 2) {
                py.PyErr_SetString(py.PyExc_ValueError(), "get2D requires a 2D array");
                return error.DimensionMismatch;
            }
            if (abi3_enabled) {
                // ABI3: data is always C-contiguous
                const num_cols: usize = @intCast(self.shape[1]);
                return self.data[row * num_cols + col];
            } else {
                if (self.strides) |strd| {
                    // Validate strides are non-negative before casting
                    if (strd[0] < 0 or strd[1] < 0) {
                        py.PyErr_SetString(py.PyExc_ValueError(), "Buffer has negative strides");
                        return error.ValueError;
                    }
                    // Use strides for non-contiguous access
                    const byte_offset = @as(usize, @intCast(strd[0])) * row + @as(usize, @intCast(strd[1])) * col;
                    const ptr: [*]const T = @ptrCast(@alignCast(self._buffer.buf.?));
                    const byte_ptr: [*]const u8 = @ptrCast(ptr);
                    return @as(*const T, @ptrCast(@alignCast(byte_ptr + byte_offset))).*;
                } else {
                    // C-contiguous
                    const num_cols: usize = @intCast(self.shape[1]);
                    return self.data[row * num_cols + col];
                }
            }
        }

        /// Get the shape as a slice of usizes (convenience method)
        pub fn getShape(self: Self) []const Py_ssize_t {
            return self.shape;
        }

        /// Get number of rows (for 2D arrays)
        pub fn rows(self: Self) usize {
            if (self.ndim < 1) return 0;
            return @intCast(self.shape[0]);
        }

        /// Get number of columns (for 2D arrays)
        pub fn cols(self: Self) usize {
            if (self.ndim < 2) return self.len();
            return @intCast(self.shape[1]);
        }

        /// Iterate over elements (flat iteration)
        pub fn iterator(self: Self) Iterator {
            return .{ .data = self.data, .index = 0 };
        }

        pub const Iterator = struct {
            data: []const T,
            index: usize,

            pub fn next(self: *Iterator) ?T {
                if (self.index >= self.data.len) return null;
                const val = self.data[self.index];
                self.index += 1;
                return val;
            }

            pub fn reset(self: *Iterator) void {
                self.index = 0;
            }
        };

        /// Release the buffer - called automatically by the wrapper
        pub fn release(self: *Self) void {
            if (abi3_enabled) {
                // ABI3: release the bytes object containing the copied data
                if (self._buffer) |bytes_obj| {
                    py.Py_DecRef(bytes_obj);
                }
            } else {
                py.PyBuffer_Release(&self._buffer);
            }
        }
    };
}

/// Mutable zero-copy view into a Python buffer (numpy array, bytearray, etc.)
/// Use this when you need to modify the array data in-place.
///
/// NOTE: Not available in ABI3 mode - mutable buffer access requires direct
/// memory access which is not possible through the Limited API.
///
/// Example:
/// ```zig
/// fn scale_array(arr: pyoz.BufferViewMut(f64), factor: f64) void {
///     for (arr.data) |*v| v.* *= factor;
/// }
/// ```
///
/// Python usage:
/// ```python
/// import numpy as np
/// arr = np.array([1.0, 2.0, 3.0], dtype=np.float64)
/// mymodule.scale_array(arr, 2.0)  # Modifies arr in-place!
/// print(arr)  # [2.0, 4.0, 6.0]
/// ```
pub fn BufferViewMut(comptime T: type) type {
    if (abi3_enabled) {
        @compileError(
            \\BufferViewMut is not available in ABI3 mode.
            \\
            \\Mutable buffer access requires direct memory access which is not
            \\possible through the Python Limited API.
            \\
            \\Workarounds:
            \\  - Use BufferView (read-only) and return a new list/array
            \\  - Accept a list, modify it, and return a new list
            \\  - Set abi3 = false in your build configuration
        );
    }

    return struct {
        pub const _is_pyoz_buffer_mut = true;

        /// The underlying data as a mutable Zig slice
        data: []T,
        /// Number of dimensions
        ndim: usize,
        /// Shape of each dimension
        shape: []const Py_ssize_t,
        /// Strides for each dimension (in bytes)
        strides: ?[]const Py_ssize_t,
        /// The Python object (for reference counting)
        _py_obj: *PyObject,
        /// The buffer view (must be released)
        _buffer: py.Py_buffer,

        const Self = @This();
        pub const ElementType = T;
        pub const is_buffer_view = true;
        pub const is_mutable = true;

        /// Get the total number of elements
        pub fn len(self: Self) usize {
            return self.data.len;
        }

        /// Check if the buffer is empty
        pub fn isEmpty(self: Self) bool {
            return self.data.len == 0;
        }

        /// Check if the buffer is C-contiguous
        pub fn isContiguous(self: Self) bool {
            return self._buffer.strides == null or self.ndim == 1;
        }

        /// Get element at a flat index
        pub fn get(self: Self, index: usize) T {
            return self.data[index];
        }

        /// Set element at a flat index
        pub fn set(self: Self, index: usize, value: T) void {
            self.data[index] = value;
        }

        /// Get element at 2D index (row, col)
        /// Returns error.DimensionMismatch if called on non-2D array
        pub fn get2D(self: Self, row: usize, col: usize) !T {
            if (self.ndim != 2) {
                py.PyErr_SetString(py.PyExc_ValueError(), "get2D requires a 2D array");
                return error.DimensionMismatch;
            }
            if (self.strides) |strd| {
                // Validate strides are non-negative before casting
                if (strd[0] < 0 or strd[1] < 0) {
                    py.PyErr_SetString(py.PyExc_ValueError(), "Buffer has negative strides");
                    return error.ValueError;
                }
                const byte_offset = @as(usize, @intCast(strd[0])) * row + @as(usize, @intCast(strd[1])) * col;
                const ptr: [*]T = @ptrCast(@alignCast(self._buffer.buf.?));
                const byte_ptr: [*]u8 = @ptrCast(ptr);
                return @as(*T, @ptrCast(@alignCast(byte_ptr + byte_offset))).*;
            } else {
                const cols_count: usize = @intCast(self.shape[1]);
                return self.data[row * cols_count + col];
            }
        }

        /// Set element at 2D index (row, col)
        /// Returns error.DimensionMismatch if called on non-2D array
        pub fn set2D(self: Self, row: usize, col: usize, value: T) !void {
            if (self.ndim != 2) {
                py.PyErr_SetString(py.PyExc_ValueError(), "set2D requires a 2D array");
                return error.DimensionMismatch;
            }
            if (self.strides) |strd| {
                // Validate strides are non-negative before casting
                if (strd[0] < 0 or strd[1] < 0) {
                    py.PyErr_SetString(py.PyExc_ValueError(), "Buffer has negative strides");
                    return error.ValueError;
                }
                const byte_offset = @as(usize, @intCast(strd[0])) * row + @as(usize, @intCast(strd[1])) * col;
                const ptr: [*]T = @ptrCast(@alignCast(self._buffer.buf.?));
                const byte_ptr: [*]u8 = @ptrCast(ptr);
                @as(*T, @ptrCast(@alignCast(byte_ptr + byte_offset))).* = value;
            } else {
                const cols_count: usize = @intCast(self.shape[1]);
                self.data[row * cols_count + col] = value;
            }
        }

        /// Get the shape
        pub fn getShape(self: Self) []const Py_ssize_t {
            return self.shape;
        }

        /// Get number of rows (for 2D arrays)
        pub fn rows(self: Self) usize {
            if (self.ndim < 1) return 0;
            return @intCast(self.shape[0]);
        }

        /// Get number of columns (for 2D arrays)
        pub fn cols(self: Self) usize {
            if (self.ndim < 2) return self.len();
            return @intCast(self.shape[1]);
        }

        /// Fill the entire buffer with a value
        pub fn fill(self: Self, value: T) void {
            for (self.data) |*elem| {
                elem.* = value;
            }
        }

        /// Release the buffer - called automatically by the wrapper
        pub fn release(self: *Self) void {
            py.PyBuffer_Release(&self._buffer);
        }
    };
}

/// Get the expected buffer format character for a Zig type
pub fn getBufferFormat(comptime T: type) []const u8 {
    return switch (T) {
        f64 => "d",
        f32 => "f",
        i64 => "q",
        u64 => "Q",
        i32 => "i",
        u32 => "I",
        i16 => "h",
        u16 => "H",
        i8 => "b",
        u8 => "B",
        Complex => "Zd", // complex128 (two f64)
        Complex32 => "Zf", // complex64 (two f32)
        else => @compileError("Unsupported buffer element type: " ++ @typeName(T)),
    };
}

/// Check if a buffer format matches the expected type
pub fn checkBufferFormat(comptime T: type, format: ?[*:0]const u8) bool {
    if (format) |fmt| {
        const fmt_slice = std.mem.sliceTo(fmt, 0);
        if (fmt_slice.len == 0) return false;

        // Handle platform-specific and complex format codes
        return switch (T) {
            // Platform-specific: numpy uses 'l' for int64 on some platforms instead of 'q'
            i64 => fmt_slice.len >= 1 and (fmt_slice[fmt_slice.len - 1] == 'q' or fmt_slice[fmt_slice.len - 1] == 'l'),
            u64 => fmt_slice.len >= 1 and (fmt_slice[fmt_slice.len - 1] == 'Q' or fmt_slice[fmt_slice.len - 1] == 'L'),
            // Complex types: format is "Zd" (complex128) or "Zf" (complex64)
            Complex => std.mem.eql(u8, fmt_slice, "Zd"),
            Complex32 => std.mem.eql(u8, fmt_slice, "Zf"),
            else => {
                const expected = getBufferFormat(T);
                return fmt_slice.len >= 1 and fmt_slice[fmt_slice.len - 1] == expected[0];
            },
        };
    }
    return false;
}

/// Check buffer format for ABI3 mode (format comes as Python string)
pub fn checkBufferFormatAbi3(comptime T: type, format_str: []const u8) bool {
    if (format_str.len == 0) return false;

    return switch (T) {
        i64 => format_str[0] == 'q' or format_str[0] == 'l',
        u64 => format_str[0] == 'Q' or format_str[0] == 'L',
        Complex => std.mem.eql(u8, format_str, "Zd"),
        Complex32 => std.mem.eql(u8, format_str, "Zf"),
        else => {
            const expected = getBufferFormat(T);
            return format_str[0] == expected[0];
        },
    };
}
