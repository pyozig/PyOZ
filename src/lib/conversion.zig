//! Type Conversion Module
//!
//! Provides conversion between Zig types and Python objects.
//! This is the core conversion engine used by function wrappers and class methods.

const std = @import("std");
const py = @import("python.zig");
const class_mod = @import("class.zig");
const PyObject = py.PyObject;

// Import all types
const complex_types = @import("types/complex.zig");
pub const Complex = complex_types.Complex;
pub const Complex32 = complex_types.Complex32;

const datetime_types = @import("types/datetime.zig");
pub const Date = datetime_types.Date;
pub const Time = datetime_types.Time;
pub const DateTime = datetime_types.DateTime;
pub const TimeDelta = datetime_types.TimeDelta;

const bytes_types = @import("types/bytes.zig");
pub const Bytes = bytes_types.Bytes;
pub const ByteArray = bytes_types.ByteArray;

const path_types = @import("types/path.zig");
pub const Path = path_types.Path;

const decimal_mod = @import("types/decimal.zig");
pub const Decimal = decimal_mod.Decimal;
pub const initDecimal = decimal_mod.initDecimal;
pub const PyDecimal_Check = decimal_mod.PyDecimal_Check;
pub const PyDecimal_FromString = decimal_mod.PyDecimal_FromString;
pub const PyDecimal_AsString = decimal_mod.PyDecimal_AsString;

const buffer_types = @import("types/buffer.zig");
pub const BufferView = buffer_types.BufferView;
pub const BufferViewMut = buffer_types.BufferViewMut;
pub const BufferInfo = buffer_types.BufferInfo;
const checkBufferFormat = buffer_types.checkBufferFormat;
const checkBufferFormatAbi3 = buffer_types.checkBufferFormatAbi3;

const abi3_enabled = py.types.abi3_enabled;

const iterator_types = @import("collections/iterator.zig");
const LazyIteratorWrapper = iterator_types.LazyIteratorWrapper;

/// Type conversion implementations - creates a converter aware of registered classes
pub fn Converter(comptime class_types: []const type) type {
    return struct {
        /// Convert Zig value to Python object
        pub fn toPy(comptime T: type, value: T) ?*PyObject {
            const info = @typeInfo(T);

            return switch (info) {
                .int => |int_info| {
                    // Handle 128-bit integers via string conversion
                    if (int_info.bits > 64) {
                        var buf: [48]u8 = undefined;
                        const str = std.fmt.bufPrintZ(&buf, "{d}", .{value}) catch return null;
                        return py.PyLong_FromString(str, null, 10);
                    }
                    if (int_info.signedness == .signed) {
                        return py.PyLong_FromLongLong(@intCast(value));
                    } else {
                        return py.PyLong_FromUnsignedLongLong(@intCast(value));
                    }
                },
                .comptime_int => py.PyLong_FromLongLong(@intCast(value)),
                .float => py.PyFloat_FromDouble(@floatCast(value)),
                .comptime_float => py.PyFloat_FromDouble(@floatCast(value)),
                .bool => py.Py_RETURN_BOOL(value),
                .pointer => |ptr| {
                    // Handle *PyObject directly - just return it as-is
                    if (ptr.child == PyObject) {
                        return value;
                    }
                    // String slice
                    if (ptr.size == .slice and ptr.child == u8) {
                        return py.PyUnicode_FromStringAndSize(value.ptr, @intCast(value.len));
                    }
                    // Null-terminated string (many-pointer)
                    if (ptr.size == .many and ptr.child == u8 and ptr.sentinel_ptr != null) {
                        return py.PyUnicode_FromString(value);
                    }
                    // String literal (*const [N:0]u8) - pointer to null-terminated array
                    if (ptr.size == .one) {
                        const child_info = @typeInfo(ptr.child);
                        if (child_info == .array) {
                            const arr = child_info.array;
                            if (arr.child == u8 and arr.sentinel_ptr != null) {
                                return py.PyUnicode_FromString(value);
                            }
                        }
                    }
                    // Generic slice -> Python list
                    if (ptr.size == .slice) {
                        const list = py.PyList_New(@intCast(value.len)) orelse return null;
                        for (value, 0..) |item, i| {
                            const py_item = toPy(ptr.child, item) orelse {
                                py.Py_DecRef(list);
                                return null;
                            };
                            // PyList_SetItem steals reference
                            if (py.PyList_SetItem(list, @intCast(i), py_item) < 0) {
                                py.Py_DecRef(list);
                                return null;
                            }
                        }
                        return list;
                    }
                    // Check if it's a pointer to a registered class - wrap it
                    inline for (class_types) |ClassType| {
                        if (ptr.child == ClassType) {
                            // TODO: Create a new Python object wrapping this pointer
                            // For now, return null - we'd need to copy the data
                            return null;
                        }
                    }
                    return null;
                },
                .optional => {
                    if (value) |v| {
                        return toPy(@TypeOf(v), v);
                    } else {
                        // If an exception is already set, return null (error indicator)
                        // Otherwise return None
                        if (py.PyErr_Occurred() != null) {
                            return null;
                        }
                        return py.Py_RETURN_NONE();
                    }
                },
                .error_union => {
                    if (value) |v| {
                        return toPy(@TypeOf(v), v);
                    } else |_| {
                        return null;
                    }
                },
                .void => py.Py_RETURN_NONE(),
                .@"struct" => |struct_info| {
                    // Handle Complex type - convert to Python complex
                    if (@hasDecl(T, "_is_pyoz_complex")) {
                        return py.PyComplex_FromDoubles(value.real, value.imag);
                    }

                    // Handle DateTime types
                    if (@hasDecl(T, "_is_pyoz_datetime")) {
                        return py.PyDateTime_FromDateAndTime(
                            @intCast(value.year),
                            @intCast(value.month),
                            @intCast(value.day),
                            @intCast(value.hour),
                            @intCast(value.minute),
                            @intCast(value.second),
                            @intCast(value.microsecond),
                        );
                    }

                    if (@hasDecl(T, "_is_pyoz_date")) {
                        return py.PyDate_FromDate(
                            @intCast(value.year),
                            @intCast(value.month),
                            @intCast(value.day),
                        );
                    }

                    if (@hasDecl(T, "_is_pyoz_time")) {
                        return py.PyTime_FromTime(
                            @intCast(value.hour),
                            @intCast(value.minute),
                            @intCast(value.second),
                            @intCast(value.microsecond),
                        );
                    }

                    if (@hasDecl(T, "_is_pyoz_timedelta")) {
                        return py.PyDelta_FromDSU(
                            value.days,
                            value.seconds,
                            value.microseconds,
                        );
                    }

                    // Handle Bytes type
                    if (@hasDecl(T, "_is_pyoz_bytes")) {
                        return py.PyBytes_FromStringAndSize(value.data.ptr, @intCast(value.data.len));
                    }

                    // Handle ByteArray type
                    if (@hasDecl(T, "_is_pyoz_bytearray")) {
                        return py.PyByteArray_FromStringAndSize(value.data.ptr, @intCast(value.data.len));
                    }

                    // Handle Path type
                    if (@hasDecl(T, "_is_pyoz_path")) {
                        return py.PyPath_FromString(value.path);
                    }

                    // Handle Decimal type
                    if (@hasDecl(T, "_is_pyoz_decimal")) {
                        return PyDecimal_FromString(value.value);
                    }

                    // Handle tuple returns - convert struct to Python tuple
                    if (struct_info.is_tuple) {
                        const fields = struct_info.fields;
                        const tuple = py.PyTuple_New(@intCast(fields.len)) orelse return null;
                        inline for (fields, 0..) |field, i| {
                            const py_val = toPy(field.type, @field(value, field.name)) orelse {
                                py.Py_DecRef(tuple);
                                return null;
                            };
                            // PyTuple_SetItem steals reference, so don't decref py_val
                            if (py.PyTuple_SetItem(tuple, @intCast(i), py_val) < 0) {
                                py.Py_DecRef(tuple);
                                return null;
                            }
                        }
                        return tuple;
                    }

                    // Check if this is a Dict type - convert entries to Python dict
                    if (@hasDecl(T, "_is_pyoz_dict")) {
                        const dict = py.PyDict_New() orelse return null;
                        for (value.entries) |entry| {
                            const py_key = toPy(T.KeyType, entry.key) orelse {
                                py.Py_DecRef(dict);
                                return null;
                            };
                            const py_val = toPy(T.ValueType, entry.value) orelse {
                                py.Py_DecRef(py_key);
                                py.Py_DecRef(dict);
                                return null;
                            };
                            if (py.PyDict_SetItem(dict, py_key, py_val) < 0) {
                                py.Py_DecRef(py_key);
                                py.Py_DecRef(py_val);
                                py.Py_DecRef(dict);
                                return null;
                            }
                            py.Py_DecRef(py_key);
                            py.Py_DecRef(py_val);
                        }
                        return dict;
                    }

                    // Check if this is an Iterator type - convert items to Python list
                    if (@hasDecl(T, "_is_pyoz_iterator")) {
                        const list = py.PyList_New(@intCast(value.items.len)) orelse return null;
                        for (value.items, 0..) |item, i| {
                            const py_item = toPy(T.ElementType, item) orelse {
                                py.Py_DecRef(list);
                                return null;
                            };
                            // PyList_SetItem steals reference
                            if (py.PyList_SetItem(list, @intCast(i), py_item) < 0) {
                                py.Py_DecRef(list);
                                return null;
                            }
                        }
                        return list;
                    }

                    // Check if this is a LazyIterator type - create Python iterator object
                    if (@hasDecl(T, "_is_pyoz_lazy_iterator")) {
                        const Wrapper = LazyIteratorWrapper(T.ElementType, T.StateType);
                        return Wrapper.create(value);
                    }

                    // Check if this is a Set or FrozenSet type - convert items to Python set
                    if (@hasDecl(T, "_is_pyoz_set") or @hasDecl(T, "_is_pyoz_frozenset")) {
                        const is_frozen = @hasDecl(T, "_is_pyoz_frozenset");
                        const set_obj = if (is_frozen)
                            py.PyFrozenSet_New(null)
                        else
                            py.PySet_New(null);
                        const set = set_obj orelse return null;

                        for (value.items) |item| {
                            const py_item = toPy(T.ElementType, item) orelse {
                                py.Py_DecRef(set);
                                return null;
                            };
                            if (py.PySet_Add(set, py_item) < 0) {
                                py.Py_DecRef(py_item);
                                py.Py_DecRef(set);
                                return null;
                            }
                            py.Py_DecRef(py_item);
                        }
                        return set;
                    }

                    // Check if this is a registered class type - create a new Python object
                    inline for (class_types) |ClassType| {
                        if (T == ClassType) {
                            const Wrapper = class_mod.getWrapper(ClassType);
                            // Allocate a new Python object - use getType() which works in both ABI3 and non-ABI3 modes
                            const py_obj = py.PyObject_New(Wrapper.PyWrapper, Wrapper.getType()) orelse return null;
                            // Copy the data
                            py_obj.getData().* = value;
                            return @ptrCast(py_obj);
                        }
                    }

                    return null;
                },
                else => null,
            };
        }

        /// Convert Python object to Zig value with class type awareness
        pub fn fromPy(comptime T: type, obj: *PyObject) !T {
            const info = @typeInfo(T);

            // Check if T is a pointer to a registered class type
            if (info == .pointer) {
                const ptr_info = info.pointer;
                const Child = ptr_info.child;

                // Handle *PyObject directly - just return the object as-is
                if (Child == PyObject) {
                    return obj;
                }

                // Check each registered class type
                inline for (class_types) |ClassType| {
                    if (Child == ClassType) {
                        const Wrapper = class_mod.getWrapper(ClassType);
                        if (ptr_info.is_const) {
                            return Wrapper.unwrapConst(obj) orelse return error.TypeError;
                        } else {
                            return Wrapper.unwrap(obj) orelse return error.TypeError;
                        }
                    }
                }

                // Handle string slices
                if (ptr_info.size == .slice and ptr_info.child == u8) {
                    if (!py.PyUnicode_Check(obj)) {
                        return error.TypeError;
                    }
                    var size: py.Py_ssize_t = 0;
                    const ptr_data = py.PyUnicode_AsUTF8AndSize(obj, &size) orelse return error.ConversionError;
                    return ptr_data[0..@intCast(size)];
                }

                return error.TypeError;
            }

            // Check struct types with markers
            if (info == .@"struct") {
                // Check if T is Complex type
                if (@hasDecl(T, "_is_pyoz_complex")) {
                    if (py.PyComplex_Check(obj)) {
                        return T{
                            .real = py.PyComplex_RealAsDouble(obj),
                            .imag = py.PyComplex_ImagAsDouble(obj),
                        };
                    } else if (py.PyFloat_Check(obj)) {
                        return T{
                            .real = py.PyFloat_AsDouble(obj),
                            .imag = 0.0,
                        };
                    } else if (py.PyLong_Check(obj)) {
                        return T{
                            .real = py.PyLong_AsDouble(obj),
                            .imag = 0.0,
                        };
                    }
                    return error.TypeError;
                }

                // Check if T is DateTime type
                if (@hasDecl(T, "_is_pyoz_datetime")) {
                    if (py.PyDateTime_Check(obj)) {
                        return T{
                            .year = @intCast(py.PyDateTime_GET_YEAR(obj)),
                            .month = @intCast(py.PyDateTime_GET_MONTH(obj)),
                            .day = @intCast(py.PyDateTime_GET_DAY(obj)),
                            .hour = @intCast(py.PyDateTime_DATE_GET_HOUR(obj)),
                            .minute = @intCast(py.PyDateTime_DATE_GET_MINUTE(obj)),
                            .second = @intCast(py.PyDateTime_DATE_GET_SECOND(obj)),
                            .microsecond = @intCast(py.PyDateTime_DATE_GET_MICROSECOND(obj)),
                        };
                    }
                    return error.TypeError;
                }

                // Check if T is Date type
                if (@hasDecl(T, "_is_pyoz_date")) {
                    if (py.PyDate_Check(obj)) {
                        return T{
                            .year = @intCast(py.PyDateTime_GET_YEAR(obj)),
                            .month = @intCast(py.PyDateTime_GET_MONTH(obj)),
                            .day = @intCast(py.PyDateTime_GET_DAY(obj)),
                        };
                    }
                    return error.TypeError;
                }

                // Check if T is Time type
                if (@hasDecl(T, "_is_pyoz_time")) {
                    if (py.PyTime_Check(obj)) {
                        return T{
                            .hour = @intCast(py.PyDateTime_TIME_GET_HOUR(obj)),
                            .minute = @intCast(py.PyDateTime_TIME_GET_MINUTE(obj)),
                            .second = @intCast(py.PyDateTime_TIME_GET_SECOND(obj)),
                            .microsecond = @intCast(py.PyDateTime_TIME_GET_MICROSECOND(obj)),
                        };
                    }
                    return error.TypeError;
                }

                // Check if T is TimeDelta type
                if (@hasDecl(T, "_is_pyoz_timedelta")) {
                    if (py.PyDelta_Check(obj)) {
                        return T{
                            .days = py.PyDateTime_DELTA_GET_DAYS(obj),
                            .seconds = py.PyDateTime_DELTA_GET_SECONDS(obj),
                            .microseconds = py.PyDateTime_DELTA_GET_MICROSECONDS(obj),
                        };
                    }
                    return error.TypeError;
                }

                // Check if T is Bytes type
                if (@hasDecl(T, "_is_pyoz_bytes")) {
                    if (py.PyBytes_Check(obj)) {
                        const size = py.PyBytes_Size(obj);
                        const ptr = py.PyBytes_AsString(obj) orelse return error.ConversionError;
                        return T{ .data = ptr[0..@intCast(size)] };
                    } else if (py.PyByteArray_Check(obj)) {
                        const size = py.PyByteArray_Size(obj);
                        const ptr = py.PyByteArray_AsString(obj) orelse return error.ConversionError;
                        return T{ .data = ptr[0..@intCast(size)] };
                    }
                    return error.TypeError;
                }

                // Check if T is ByteArray type
                if (@hasDecl(T, "_is_pyoz_bytearray")) {
                    if (py.PyByteArray_Check(obj)) {
                        const size = py.PyByteArray_Size(obj);
                        const ptr = py.PyByteArray_AsString(obj) orelse return error.ConversionError;
                        return T{ .data = ptr[0..@intCast(size)] };
                    }
                    return error.TypeError;
                }

                // Check if T is Decimal type
                if (@hasDecl(T, "_is_pyoz_decimal")) {
                    if (PyDecimal_Check(obj)) {
                        const str_val = PyDecimal_AsString(obj) orelse return error.ConversionError;
                        return T{ .value = str_val };
                    } else if (py.PyLong_Check(obj) or py.PyFloat_Check(obj)) {
                        // Also accept int/float - convert via str()
                        const str_obj = py.PyObject_Str(obj) orelse return error.ConversionError;
                        defer py.Py_DecRef(str_obj);
                        var size: py.Py_ssize_t = 0;
                        const ptr = py.PyUnicode_AsUTF8AndSize(str_obj, &size) orelse return error.ConversionError;
                        return T{ .value = ptr[0..@intCast(size)] };
                    }
                    return error.TypeError;
                }

                // Check if T is Path type
                if (@hasDecl(T, "_is_pyoz_path")) {
                    if (py.PyUnicode_Check(obj)) {
                        // Plain strings - the memory is owned by the input object
                        var size: py.Py_ssize_t = 0;
                        const ptr = py.PyUnicode_AsUTF8AndSize(obj, &size) orelse return error.ConversionError;
                        return T.init(ptr[0..@intCast(size)]);
                    } else if (py.PyPath_Check(obj)) {
                        // pathlib.Path - need to get string with reference to keep memory alive
                        const result = py.PyPath_AsStringWithRef(obj) orelse return error.ConversionError;
                        return T.fromPyObject(result.py_str, result.path);
                    }
                    return error.TypeError;
                }

                // Check if T is a DictView type
                if (@hasDecl(T, "_is_pyoz_dict_view")) {
                    if (!py.PyDict_Check(obj)) {
                        return error.TypeError;
                    }
                    return T{ .py_dict = obj };
                }

                // Check if T is a ListView type
                if (@hasDecl(T, "_is_pyoz_list_view")) {
                    if (!py.PyList_Check(obj)) {
                        return error.TypeError;
                    }
                    return T{ .py_list = obj };
                }

                // Check if T is a SetView type
                if (@hasDecl(T, "_is_pyoz_set_view")) {
                    if (!py.PyAnySet_Check(obj)) {
                        return error.TypeError;
                    }
                    return T{ .py_set = obj };
                }

                // Check if T is an IteratorView type
                if (@hasDecl(T, "_is_pyoz_iterator_view")) {
                    // Get an iterator from the object (works for any iterable)
                    const iter = py.PyObject_GetIter(obj) orelse {
                        py.PyErr_SetString(py.PyExc_TypeError(), "Object is not iterable");
                        return error.TypeError;
                    };
                    return T{ .py_iter = iter };
                }

                // Check if T is a BufferView or BufferViewMut type
                if (@hasDecl(T, "_is_pyoz_buffer") or @hasDecl(T, "_is_pyoz_buffer_mut")) {
                    const ElementType = T.ElementType;
                    const is_mutable = @hasDecl(T, "_is_pyoz_buffer_mut");

                    if (abi3_enabled) {
                        // ABI3 mode: use memoryview + tobytes() for copy-based access
                        // BufferViewMut is not supported in ABI3 (compile error in types/buffer.zig)
                        if (is_mutable) {
                            @compileError("BufferViewMut is not available in ABI3 mode");
                        }

                        return convertBufferAbi3(T, ElementType, obj) catch |err| {
                            return err;
                        };
                    } else {
                        // Non-ABI3 mode: zero-copy via PyObject_GetBuffer
                        // Check if object supports buffer protocol
                        if (!py.PyObject_CheckBuffer(obj)) {
                            py.PyErr_SetString(py.PyExc_TypeError(), "Object does not support buffer protocol");
                            return error.TypeError;
                        }

                        var buffer: py.Py_buffer = std.mem.zeroes(py.Py_buffer);
                        const flags: c_int = if (is_mutable)
                            py.PyBUF_WRITABLE | py.PyBUF_FORMAT | py.PyBUF_ND | py.PyBUF_STRIDES | py.PyBUF_ANY_CONTIGUOUS
                        else
                            py.PyBUF_FORMAT | py.PyBUF_ND | py.PyBUF_STRIDES | py.PyBUF_ANY_CONTIGUOUS;

                        if (py.PyObject_GetBuffer(obj, &buffer, flags) < 0) {
                            return error.TypeError;
                        }

                        // Validate the format matches the expected element type
                        if (buffer.format) |fmt| {
                            if (!checkBufferFormat(ElementType, fmt)) {
                                py.PyBuffer_Release(&buffer);
                                py.PyErr_SetString(py.PyExc_TypeError(), "Buffer format does not match expected type");
                                return error.TypeError;
                            }
                        }

                        // Validate item size
                        if (buffer.itemsize != @sizeOf(ElementType)) {
                            py.PyBuffer_Release(&buffer);
                            py.PyErr_SetString(py.PyExc_TypeError(), "Buffer item size mismatch");
                            return error.TypeError;
                        }

                        // Calculate total number of elements
                        // Validate ndim is non-negative before casting
                        if (buffer.ndim < 0) {
                            py.PyBuffer_Release(&buffer);
                            py.PyErr_SetString(py.PyExc_ValueError(), "Buffer has negative ndim");
                            return error.ValueError;
                        }
                        var num_elements: usize = 1;
                        const ndim: usize = @intCast(buffer.ndim);
                        if (buffer.shape) |shape| {
                            for (0..ndim) |i| {
                                // Validate shape values are non-negative before casting
                                if (shape[i] < 0) {
                                    py.PyBuffer_Release(&buffer);
                                    py.PyErr_SetString(py.PyExc_ValueError(), "Buffer has negative shape dimension");
                                    return error.ValueError;
                                }
                                num_elements *= @intCast(shape[i]);
                            }
                        } else {
                            num_elements = @intCast(@divExact(buffer.len, buffer.itemsize));
                        }

                        // Validate buffer pointer is not null (defensive check)
                        if (buffer.buf == null) {
                            py.PyBuffer_Release(&buffer);
                            py.PyErr_SetString(py.PyExc_ValueError(), "Buffer has null data pointer");
                            return error.ValueError;
                        }

                        // Create the slice from the buffer
                        const ptr: [*]ElementType = @ptrCast(@alignCast(buffer.buf.?));

                        if (is_mutable) {
                            return T{
                                .data = ptr[0..num_elements],
                                .ndim = ndim,
                                .shape = if (buffer.shape) |s| s[0..ndim] else &[_]py.Py_ssize_t{@intCast(num_elements)},
                                .strides = if (buffer.strides) |s| s[0..ndim] else null,
                                ._py_obj = obj,
                                ._buffer = buffer,
                            };
                        } else {
                            return T{
                                .data = ptr[0..num_elements],
                                .ndim = ndim,
                                .shape = if (buffer.shape) |s| s[0..ndim] else &[_]py.Py_ssize_t{@intCast(num_elements)},
                                .strides = if (buffer.strides) |s| s[0..ndim] else null,
                                ._py_obj = obj,
                                ._buffer = buffer,
                                // _shape_storage is void in non-ABI3 mode, so we use {}
                                ._shape_storage = if (abi3_enabled) undefined else {},
                            };
                        }
                    }
                }
            }

            return switch (info) {
                .int => |int_info| {
                    if (!py.PyLong_Check(obj)) {
                        return error.TypeError;
                    }
                    // Handle 128-bit integers via string conversion
                    if (int_info.bits > 64) {
                        const str_obj = py.PyObject_Str(obj) orelse return error.ConversionError;
                        defer py.Py_DecRef(str_obj);
                        var size: py.Py_ssize_t = 0;
                        const ptr = py.PyUnicode_AsUTF8AndSize(str_obj, &size) orelse return error.ConversionError;
                        const str = ptr[0..@intCast(size)];
                        if (int_info.signedness == .signed) {
                            return std.fmt.parseInt(T, str, 10) catch return error.ConversionError;
                        } else {
                            return std.fmt.parseUnsigned(T, str, 10) catch return error.ConversionError;
                        }
                    }
                    if (int_info.signedness == .signed) {
                        const val = py.PyLong_AsLongLong(obj);
                        if (py.PyErr_Occurred() != null) return error.ConversionError;
                        // Truncate to target type (wrap on overflow, like C)
                        return @truncate(val);
                    } else {
                        const val = py.PyLong_AsUnsignedLongLong(obj);
                        if (py.PyErr_Occurred() != null) return error.ConversionError;
                        // Truncate to target type (wrap on overflow, like C)
                        return @truncate(val);
                    }
                },
                .float => {
                    if (py.PyFloat_Check(obj)) {
                        return @floatCast(py.PyFloat_AsDouble(obj));
                    } else if (py.PyLong_Check(obj)) {
                        return @floatCast(py.PyLong_AsDouble(obj));
                    }
                    return error.TypeError;
                },
                .bool => {
                    return py.PyObject_IsTrue(obj) == 1;
                },
                .optional => |opt| {
                    if (py.PyNone_Check(obj)) {
                        return null;
                    }
                    return try fromPy(opt.child, obj);
                },
                .array => |arr| {
                    // Fixed-size array from Python list
                    if (!py.PyList_Check(obj)) {
                        return error.TypeError;
                    }
                    const list_len = py.PyList_Size(obj);
                    if (list_len != arr.len) {
                        return error.WrongArgumentCount;
                    }
                    var result: T = undefined;
                    for (0..arr.len) |i| {
                        const item = py.PyList_GetItem(obj, @intCast(i)) orelse return error.InvalidArgument;
                        result[i] = try fromPy(arr.child, item);
                    }
                    return result;
                },
                else => error.TypeError,
            };
        }
    };
}

/// ABI3 buffer conversion using memoryview + tobytes()
/// This is a copy-based fallback when PyObject_GetBuffer is not available
fn convertBufferAbi3(comptime T: type, comptime ElementType: type, obj: *PyObject) !T {
    const c = py.c;

    // Create a memoryview from the object
    const memview = c.PyMemoryView_FromObject(obj) orelse {
        py.PyErr_SetString(py.PyExc_TypeError(), "Object does not support buffer protocol");
        return error.TypeError;
    };
    defer py.Py_DecRef(memview);

    // Get format string for validation
    const format_obj = c.PyObject_GetAttrString(memview, "format") orelse {
        py.PyErr_SetString(py.PyExc_TypeError(), "Cannot get buffer format");
        return error.TypeError;
    };
    defer py.Py_DecRef(format_obj);

    var format_size: py.Py_ssize_t = 0;
    const format_ptr = py.PyUnicode_AsUTF8AndSize(format_obj, &format_size) orelse {
        py.PyErr_SetString(py.PyExc_TypeError(), "Cannot get buffer format string");
        return error.TypeError;
    };
    const format_str = format_ptr[0..@intCast(format_size)];

    // Validate format matches expected type
    if (!checkBufferFormatAbi3(ElementType, format_str)) {
        py.PyErr_SetString(py.PyExc_TypeError(), "Buffer format does not match expected type");
        return error.TypeError;
    }

    // Get itemsize for validation
    const itemsize_obj = c.PyObject_GetAttrString(memview, "itemsize") orelse {
        py.PyErr_SetString(py.PyExc_TypeError(), "Cannot get buffer itemsize");
        return error.TypeError;
    };
    defer py.Py_DecRef(itemsize_obj);
    const itemsize: usize = @intCast(py.PyLong_AsLongLong(itemsize_obj));

    if (itemsize != @sizeOf(ElementType)) {
        py.PyErr_SetString(py.PyExc_TypeError(), "Buffer item size mismatch");
        return error.TypeError;
    }

    // Get shape
    const shape_obj = c.PyObject_GetAttrString(memview, "shape") orelse {
        py.PyErr_SetString(py.PyExc_TypeError(), "Cannot get buffer shape");
        return error.TypeError;
    };
    defer py.Py_DecRef(shape_obj);

    const tuple_size = py.PyTuple_Size(shape_obj);
    // Validate ndim is non-negative (shouldn't happen with real memoryview, but defensive)
    if (tuple_size < 0) {
        py.PyErr_SetString(py.PyExc_ValueError(), "Buffer has negative ndim");
        return error.ValueError;
    }
    const ndim: usize = @intCast(tuple_size);
    var result: T = undefined;

    // Store shape values
    var num_elements: usize = 1;
    for (0..@min(ndim, 8)) |i| {
        const dim_obj = py.PyTuple_GetItem(shape_obj, @intCast(i)) orelse {
            return error.TypeError;
        };
        const dim_val: py.Py_ssize_t = @intCast(py.PyLong_AsLongLong(dim_obj));
        // Validate shape dimension is non-negative before casting
        if (dim_val < 0) {
            py.PyErr_SetString(py.PyExc_ValueError(), "Buffer has negative shape dimension");
            return error.ValueError;
        }
        result._shape_storage[i] = dim_val;
        num_elements *= @intCast(dim_val);
    }

    // Call tobytes() to get the data as a bytes object
    const tobytes_method = c.PyObject_GetAttrString(memview, "tobytes") orelse {
        py.PyErr_SetString(py.PyExc_TypeError(), "Cannot get tobytes method");
        return error.TypeError;
    };
    defer py.Py_DecRef(tobytes_method);

    // Call tobytes() with empty tuple (PyObject_CallNoArgs is not in Limited API)
    const empty_tuple = c.PyTuple_New(0) orelse {
        return error.TypeError;
    };
    defer py.Py_DecRef(empty_tuple);

    const bytes_obj = c.PyObject_Call(tobytes_method, empty_tuple, null) orelse {
        return error.TypeError;
    };
    // Don't defer decref - we store it in the result for later cleanup

    // Get pointer to bytes data
    var bytes_ptr: [*c]u8 = undefined;
    var bytes_len: py.Py_ssize_t = 0;
    if (c.PyBytes_AsStringAndSize(bytes_obj, &bytes_ptr, &bytes_len) < 0) {
        py.Py_DecRef(bytes_obj);
        return error.TypeError;
    }

    // Verify length matches
    const expected_len = num_elements * @sizeOf(ElementType);
    if (@as(usize, @intCast(bytes_len)) != expected_len) {
        py.Py_DecRef(bytes_obj);
        py.PyErr_SetString(py.PyExc_TypeError(), "Buffer size mismatch");
        return error.TypeError;
    }

    // Create slice from bytes data
    const data_ptr: [*]const ElementType = @ptrCast(@alignCast(bytes_ptr));

    result.data = data_ptr[0..num_elements];
    result.ndim = ndim;
    result.shape = result._shape_storage[0..ndim];
    result.strides = null; // ABI3 data is always contiguous (it's a copy)
    result._py_obj = obj;
    result._buffer = bytes_obj; // Store bytes object for cleanup

    return result;
}

/// Basic conversions (no class awareness) - for backwards compatibility
pub const Conversions = Converter(&[_]type{});
