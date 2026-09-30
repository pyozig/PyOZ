//! Function Wrapper Generators
//!
//! Provides utilities for generating Python-callable wrapper functions
//! from Zig functions, with support for keyword arguments and error mapping.

const std = @import("std");
const aio = @import("aio.zig");
const py = @import("python.zig");
const PyObject = py.PyObject;
const conversion = @import("conversion.zig");
const Converter = conversion.Converter;
const class_mod = @import("class.zig");
const ClassInfo = class_mod.ClassInfo;
const errors_mod = @import("errors.zig");
const ErrorMapping = errors_mod.ErrorMapping;
const setErrorFromMapping = errors_mod.setErrorFromMapping;
const root = @import("root.zig");
const unwrapSignature = root.unwrapSignature;
const unwrapSignatureValue = root.unwrapSignatureValue;

/// Generate a Python-callable wrapper for a Zig function with class type awareness
pub fn wrapFunctionWithClasses(comptime zig_func: anytype, comptime class_infos: []const ClassInfo) py.PyCFunction {
    const Conv = Converter(class_infos);
    const Fn = @TypeOf(zig_func);
    const fn_info = @typeInfo(Fn).@"fn";
    const params = fn_info.params;
    const ReturnType = unwrapSignature(fn_info.return_type orelse void);

    return struct {
        fn wrapper(self: ?*PyObject, args: ?*PyObject) callconv(.c) ?*PyObject {
            _ = self;

            var zig_args = parseArgs(params, args) catch |err| {
                setError(err);
                return null;
            };
            // Ensure BufferView arguments are released after the function call
            defer releaseBufferViews(&zig_args);

            const raw_result = @call(.auto, zig_func, zig_args);
            const result = unwrapSignatureValue(@TypeOf(raw_result), raw_result);
            return handleReturn(ReturnType, result);
        }

        fn parseArgs(comptime parameters: anytype, args: ?*PyObject) !ArgsTuple(parameters) {
            var result: ArgsTuple(parameters) = undefined;

            if (parameters.len == 0) {
                return result;
            }

            const py_args = args orelse return error.MissingArguments;
            const arg_count = py.PyTuple_Size(py_args);

            if (arg_count != parameters.len) {
                return error.WrongArgumentCount;
            }

            inline for (parameters, 0..) |param, i| {
                const item = py.PyTuple_GetItem(py_args, @intCast(i)) orelse return error.InvalidArgument;
                result[i] = try Conv.fromPy(param.type.?, item);
            }

            return result;
        }

        fn releaseBufferViews(zig_args: *ArgsTuple(params)) void {
            inline for (0..params.len) |i| {
                const ParamType = params[i].type.?;
                const param_info = @typeInfo(ParamType);
                if (param_info == .@"struct" and @hasDecl(ParamType, "is_buffer_view") and ParamType.is_buffer_view) {
                    zig_args[i].release();
                }
                // Release Path types that hold Python object references
                if (ParamType == conversion.Path) {
                    zig_args[i].deinit();
                }
            }
        }

        fn handleReturn(comptime RT: type, result: anytype) ?*PyObject {
            const rt_info = @typeInfo(RT);

            if (rt_info == .error_union) {
                if (result) |value| {
                    return Conv.toPy(@TypeOf(value), value);
                } else |err| {
                    setError(err);
                    return null;
                }
            } else {
                return Conv.toPy(RT, result);
            }
        }

        fn setError(err: anyerror) void {
            // Don't overwrite an exception already set by Python
            // (e.g., KeyboardInterrupt from checkSignals)
            if (py.PyErr_Occurred() != null) return;
            const msg = @errorName(err);
            const exc_type = mapErrorToExc(err);
            py.PyErr_SetString(exc_type, msg.ptr);
        }
    }.wrapper;
}

/// Map a Zig error to the appropriate Python exception type.
fn mapErrorToExc(err: anyerror) *PyObject {
    return errors_mod.mapWellKnownError(@errorName(err));
}

/// Generate a Python-callable wrapper for a Zig function (no class awareness)
pub fn wrapFunction(comptime zig_func: anytype) py.PyCFunction {
    return wrapFunctionWithClasses(zig_func, &[_]ClassInfo{});
}

/// Helper type for argument tuple
pub fn ArgsTuple(comptime params: anytype) type {
    var types: [params.len]type = undefined;
    for (params, 0..) |param, i| {
        types[i] = param.type.?;
    }
    return std.meta.Tuple(&types);
}

/// Type for keyword function signature (C calling convention)
pub const PyCFunctionWithKeywords = *const fn (?*PyObject, ?*PyObject, ?*PyObject) callconv(.c) ?*PyObject;

/// True if `T` is a `pyoz.Args(...)` wrapper (named keyword arguments).
pub fn isArgs(comptime T: type) bool {
    return @typeInfo(T) == .@"struct" and @hasDecl(T, "is_pyoz_args");
}

/// Parse positional and keyword arguments into the struct wrapped by
/// `pyoz.Args(ArgsStructType)`, following Python's rules: positional values
/// fill fields in order, keywords by name, then field defaults (optionals
/// default to null). Returns null with a TypeError set, using CPython's
/// wording; `func_name` (may be empty) prefixes the messages, e.g.
/// "translate() got an unexpected keyword argument 'dz'".
/// Release the result with `releaseNamedArgs` after the call.
pub fn parseNamedArgs(
    comptime ArgsStructType: type,
    comptime class_infos: []const ClassInfo,
    comptime func_name: []const u8,
    args: ?*py.PyObject,
    kwargs: ?*py.PyObject,
) ?ArgsStructType {
    const Conv = Converter(class_infos);
    const fields = @typeInfo(ArgsStructType).@"struct".fields;
    const prefix = if (func_name.len > 0) func_name ++ "() " else "";
    var result: ArgsStructType = undefined;

    const pos_count: usize = if (args) |a| @intCast(py.PyTuple_Size(a)) else 0;
    if (pos_count > fields.len) {
        _ = py.c.PyErr_Format(py.PyExc_TypeError(), prefix ++ "takes at most %d positional arguments (%zd given)", @as(c_int, fields.len), @as(py.Py_ssize_t, @intCast(pos_count)));
        return null;
    }

    var keywords_used: py.Py_ssize_t = 0;
    inline for (fields, 0..) |field, i| {
        const keyword: ?*py.PyObject = if (kwargs) |kw| py.PyDict_GetItemString(kw, field.name.ptr) else null;
        if (keyword != null) {
            if (i < pos_count) {
                py.PyErr_SetString(py.PyExc_TypeError(), prefix ++ "got multiple values for argument '" ++ field.name ++ "'");
                return null;
            }
            keywords_used += 1;
        }

        const item: ?*py.PyObject = if (i < pos_count) py.PyTuple_GetItem(args.?, @intCast(i)) else keyword;
        if (item) |obj| {
            @field(result, field.name) = convertField(Conv, field.type, obj) catch {
                // Keep a specific error from the conversion (e.g. OverflowError)
                if (py.PyErr_Occurred() == null)
                    py.PyErr_SetString(py.PyExc_TypeError(), prefix ++ "argument '" ++ field.name ++ "' has the wrong type");
                releaseFields(ArgsStructType, &result, i);
                return null;
            };
        } else if (field.defaultValue()) |default| {
            @field(result, field.name) = default;
        } else if (@typeInfo(field.type) == .optional) {
            @field(result, field.name) = null;
        } else {
            py.PyErr_SetString(py.PyExc_TypeError(), prefix ++ "missing required argument '" ++ field.name ++ "'");
            releaseFields(ArgsStructType, &result, i);
            return null;
        }
    }

    // Every keyword must have matched a field
    if (kwargs) |kw| if (keywords_used < py.PyDict_Size(kw)) {
        var pos: py.Py_ssize_t = 0;
        var key: ?*py.PyObject = null;
        var value: ?*py.PyObject = null;
        while (py.PyDict_Next(kw, &pos, &key, &value) != 0) {
            if (!isField(fields, key.?)) {
                _ = py.c.PyErr_Format(py.PyExc_TypeError(), prefix ++ "got an unexpected keyword argument '%U'", key);
                break;
            }
        }
        releaseFields(ArgsStructType, &result, fields.len);
        return null;
    };

    return result;
}

fn convertField(comptime Conv: type, comptime F: type, obj: *py.PyObject) !F {
    if (@typeInfo(F) == .optional) {
        if (py.PyNone_Check(obj)) return null;
        return try Conv.fromPy(@typeInfo(F).optional.child, obj);
    }
    return Conv.fromPy(F, obj);
}

fn isField(comptime fields: []const std.builtin.Type.StructField, key: *py.PyObject) bool {
    var len: py.Py_ssize_t = 0;
    const name = py.PyUnicode_AsUTF8AndSize(key, &len) orelse {
        py.PyErr_Clear();
        return false;
    };
    inline for (fields) |f| if (std.mem.eql(u8, f.name, name[0..@intCast(len)])) return true;
    return false;
}

/// Release what parsed arguments hold (Path references, buffer views).
pub fn releaseNamedArgs(comptime ArgsStructType: type, parsed: *ArgsStructType) void {
    releaseFields(ArgsStructType, parsed, @typeInfo(ArgsStructType).@"struct".fields.len);
}

/// Release the first `count` fields (those already converted).
fn releaseFields(comptime ArgsStructType: type, parsed: *ArgsStructType, count: usize) void {
    inline for (@typeInfo(ArgsStructType).@"struct".fields, 0..) |field, i| {
        if (i < count) releaseValue(field.type, &@field(parsed, field.name));
    }
}

fn releaseValue(comptime F: type, v: *F) void {
    switch (@typeInfo(F)) {
        .optional => |o| if (v.*) |*inner| releaseValue(o.child, inner),
        .@"struct" => {
            if (@hasDecl(F, "is_buffer_view") and F.is_buffer_view) v.release();
            if (F == conversion.Path) v.deinit();
        },
        else => {},
    }
}

/// Generate a Python-callable wrapper for a Zig function with named keyword arguments.
/// The function should take Args(SomeStruct) as its parameter.
pub fn wrapFunctionWithNamedKeywords(comptime zig_func: anytype, comptime class_infos: []const ClassInfo) PyCFunctionWithKeywords {
    return wrapFunctionWithNamedKeywordsAndErrorMapping(zig_func, class_infos, &.{});
}

/// `wrapFunctionWithNamedKeywords` applying the module's error mappings to
/// returned Zig errors, like `wrapFunctionWithErrorMapping` does for
/// positional functions.
pub fn wrapFunctionWithNamedKeywordsAndErrorMapping(
    comptime zig_func: anytype,
    comptime class_infos: []const ClassInfo,
    comptime error_mappings: []const ErrorMapping,
) PyCFunctionWithKeywords {
    const Conv = Converter(class_infos);
    const Fn = @TypeOf(zig_func);
    const fn_info = @typeInfo(Fn).@"fn";
    const params = fn_info.params;
    const ReturnType = unwrapSignature(fn_info.return_type orelse void);

    // Get the Args wrapper type and the inner struct type
    const ArgsWrapperType = params[0].type.?;
    const ArgsStructType = if (@typeInfo(ArgsWrapperType) == .@"struct" and @hasDecl(ArgsWrapperType, "ArgsStruct"))
        ArgsWrapperType.ArgsStruct
    else
        @compileError("kwfunc parameter must be wrapped in pyoz.Args(T). Change `fn(" ++
            @typeName(ArgsWrapperType) ++ ")` to `fn(pyoz.Args(YourArgsStruct))`");

    return struct {
        fn wrapper(self: ?*PyObject, args: ?*PyObject, kwargs: ?*PyObject) callconv(.c) ?*PyObject {
            _ = self;

            var result_args = parseNamedArgs(ArgsStructType, class_infos, "", args, kwargs) orelse return null;
            defer releaseNamedArgs(ArgsStructType, &result_args);

            // Call function with wrapped args
            const wrapped_args = ArgsWrapperType{ .value = result_args };
            const raw_result = zig_func(wrapped_args);
            const result = unwrapSignatureValue(@TypeOf(raw_result), raw_result);

            return handleReturn(ReturnType, result);
        }

        fn handleReturn(comptime RT: type, result: anytype) ?*PyObject {
            const rt_info = @typeInfo(RT);
            if (rt_info == .error_union) {
                if (result) |value| {
                    if (comptime aio.isAsyncPending(@TypeOf(value))) return value.bind(Conv, error_mappings);
                    return Conv.toPy(@TypeOf(value), value);
                } else |err| {
                    // Module mappings first, then well-known error names; an
                    // exception already set by Python (e.g. KeyboardInterrupt
                    // from checkSignals) is kept.
                    setErrorFromMapping(error_mappings, err);
                    return null;
                }
            } else {
                return Conv.toPy(RT, result);
            }
        }
    }.wrapper;
}

/// Generate a wrapper with custom error mapping
pub fn wrapFunctionWithErrorMapping(comptime zig_func: anytype, comptime class_infos: []const ClassInfo, comptime error_mappings: []const ErrorMapping) py.PyCFunction {
    const Conv = Converter(class_infos);
    const Fn = @TypeOf(zig_func);
    const fn_info = @typeInfo(Fn).@"fn";
    const params = fn_info.params;
    const ReturnType = unwrapSignature(fn_info.return_type orelse void);

    return struct {
        fn wrapper(self: ?*PyObject, args: ?*PyObject) callconv(.c) ?*PyObject {
            _ = self;

            var zig_args = parseArgs(params, args) catch |err| {
                setMappedError(err);
                return null;
            };
            // Ensure BufferView arguments are released after the function call
            defer releaseBufferViews(&zig_args);

            const raw_result = @call(.auto, zig_func, zig_args);
            const result = unwrapSignatureValue(@TypeOf(raw_result), raw_result);
            return handleReturn(ReturnType, result);
        }

        fn parseArgs(comptime parameters: anytype, args: ?*PyObject) !ArgsTuple(parameters) {
            var parse_result: ArgsTuple(parameters) = undefined;

            if (parameters.len == 0) {
                return parse_result;
            }

            const py_args = args orelse return error.MissingArguments;
            const arg_count = py.PyTuple_Size(py_args);

            if (arg_count != parameters.len) {
                return error.WrongArgumentCount;
            }

            inline for (parameters, 0..) |param, i| {
                const item = py.PyTuple_GetItem(py_args, @intCast(i)) orelse return error.InvalidArgument;
                parse_result[i] = try Conv.fromPy(param.type.?, item);
            }

            return parse_result;
        }

        fn releaseBufferViews(zig_args: *ArgsTuple(params)) void {
            inline for (0..params.len) |i| {
                const ParamType = params[i].type.?;
                const param_info = @typeInfo(ParamType);
                if (param_info == .@"struct" and @hasDecl(ParamType, "is_buffer_view") and ParamType.is_buffer_view) {
                    zig_args[i].release();
                }
                // Release Path types that hold Python object references
                if (ParamType == conversion.Path) {
                    zig_args[i].deinit();
                }
            }
        }

        fn handleReturn(comptime RT: type, result: anytype) ?*PyObject {
            const rt_info = @typeInfo(RT);

            if (rt_info == .error_union) {
                if (result) |value| {
                    if (comptime aio.isAsyncPending(@TypeOf(value))) return value.bind(Conv, error_mappings);
                    return Conv.toPy(@TypeOf(value), value);
                } else |err| {
                    setMappedError(err);
                    return null;
                }
            } else {
                return Conv.toPy(RT, result);
            }
        }

        fn setMappedError(err: anyerror) void {
            setErrorFromMapping(error_mappings, err);
        }
    }.wrapper;
}

/// Generate a Python-callable wrapper for a function with optional params as kwargs.
/// Used by .from auto-scan when functions have ?T parameters.
/// Required (non-optional) params are positional-only; optional (?T) params
/// can be passed positionally or as keyword arguments, defaulting to null.
/// `param_names_str` is a comma-separated list of parameter names (from source parsing).
pub fn wrapAutoKeywordFunction(
    comptime zig_func: anytype,
    comptime class_infos: []const ClassInfo,
    comptime param_names_str: []const u8,
) PyCFunctionWithKeywords {
    return wrapAutoKeywordFunctionWithErrorMapping(zig_func, class_infos, param_names_str, &.{});
}

/// `wrapAutoKeywordFunction` applying the module's error mappings to returned
/// Zig errors.
pub fn wrapAutoKeywordFunctionWithErrorMapping(
    comptime zig_func: anytype,
    comptime class_infos: []const ClassInfo,
    comptime param_names_str: []const u8,
    comptime error_mappings: []const ErrorMapping,
) PyCFunctionWithKeywords {
    const Conv = Converter(class_infos);
    const Fn = @TypeOf(zig_func);
    const fn_info = @typeInfo(Fn).@"fn";
    const params = fn_info.params;
    const ReturnType = unwrapSignature(fn_info.return_type orelse void);

    // Build comptime string data for each parameter
    const ParamMeta = struct {
        kw_name: [*:0]const u8,
        type_err_msg: [*:0]const u8,
        missing_err_msg: [*:0]const u8,
    };
    const param_meta = comptime blk: {
        var meta: [params.len]ParamMeta = undefined;
        for (0..params.len) |i| {
            const name = getParamName(param_names_str, i);
            meta[i] = .{
                .kw_name = (name ++ "\x00")[0..name.len :0].ptr,
                .type_err_msg = ("Invalid type for argument: " ++ name ++ "\x00")[0 .. "Invalid type for argument: ".len + name.len :0].ptr,
                .missing_err_msg = ("Missing required argument: " ++ name ++ "\x00")[0 .. "Missing required argument: ".len + name.len :0].ptr,
            };
        }
        break :blk meta;
    };

    return struct {
        fn wrapper(self: ?*PyObject, args: ?*PyObject, kwargs: ?*PyObject) callconv(.c) ?*PyObject {
            _ = self;

            var zig_args: ArgsTuple(params) = undefined;
            const pos_count: usize = if (args) |a| @intCast(py.PyTuple_Size(a)) else 0;

            inline for (params, 0..) |param, i| {
                const ParamType = param.type.?;
                const is_optional = @typeInfo(ParamType) == .optional;
                const meta = param_meta[i];

                if (i < pos_count) {
                    // Provided as positional argument
                    const item = py.PyTuple_GetItem(args.?, @intCast(i)) orelse {
                        py.PyErr_SetString(py.PyExc_TypeError(), meta.type_err_msg);
                        return null;
                    };
                    if (is_optional and py.PyNone_Check(item)) {
                        zig_args[i] = null;
                    } else if (is_optional) {
                        const inner_type = @typeInfo(ParamType).optional.child;
                        zig_args[i] = Conv.fromPy(inner_type, item) catch {
                            if (py.PyErr_Occurred() == null) {
                                py.PyErr_SetString(py.PyExc_TypeError(), meta.type_err_msg);
                            }
                            return null;
                        };
                    } else {
                        zig_args[i] = Conv.fromPy(ParamType, item) catch {
                            if (py.PyErr_Occurred() == null) {
                                py.PyErr_SetString(py.PyExc_TypeError(), meta.type_err_msg);
                            }
                            return null;
                        };
                    }
                } else if (is_optional) {
                    // Optional param — try kwargs, default to null
                    if (kwargs) |kw| {
                        if (py.PyDict_GetItemString(kw, meta.kw_name)) |item| {
                            if (py.PyNone_Check(item)) {
                                zig_args[i] = null;
                            } else {
                                const inner_type = @typeInfo(ParamType).optional.child;
                                zig_args[i] = Conv.fromPy(inner_type, item) catch {
                                    if (py.PyErr_Occurred() == null) {
                                        py.PyErr_SetString(py.PyExc_TypeError(), meta.type_err_msg);
                                    }
                                    return null;
                                };
                            }
                        } else {
                            zig_args[i] = null;
                        }
                    } else {
                        zig_args[i] = null;
                    }
                } else {
                    // Required param not provided
                    py.PyErr_SetString(py.PyExc_TypeError(), meta.missing_err_msg);
                    return null;
                }
            }

            // Ensure BufferView arguments are released after the function call
            defer releaseBufferViews(&zig_args);

            const raw_result = @call(.auto, zig_func, zig_args);
            const result = unwrapSignatureValue(@TypeOf(raw_result), raw_result);
            return handleReturn(ReturnType, result);
        }

        fn releaseBufferViews(zig_args: *ArgsTuple(params)) void {
            inline for (0..params.len) |i| {
                const ParamType = params[i].type.?;
                const param_info = @typeInfo(ParamType);
                if (param_info == .@"struct" and @hasDecl(ParamType, "is_buffer_view") and ParamType.is_buffer_view) {
                    zig_args[i].release();
                }
                // Release Path types that hold Python object references
                if (ParamType == conversion.Path) {
                    zig_args[i].deinit();
                }
            }
        }

        fn handleReturn(comptime RT: type, result: anytype) ?*PyObject {
            const rt_info = @typeInfo(RT);
            if (rt_info == .error_union) {
                if (result) |value| {
                    if (comptime aio.isAsyncPending(@TypeOf(value))) return value.bind(Conv, error_mappings);
                    return Conv.toPy(@TypeOf(value), value);
                } else |err| {
                    setErrorFromMapping(error_mappings, err);
                    return null;
                }
            } else {
                return Conv.toPy(RT, result);
            }
        }
    }.wrapper;
}

/// Extract the Nth parameter name from a comma-separated string.
/// e.g., getParamName("entries, ring, flags", 1) -> "ring"
/// Falls back to "argN" if the index is out of range.
fn getParamName(comptime names_str: []const u8, comptime idx: usize) []const u8 {
    comptime {
        var current_idx: usize = 0;
        var start: usize = 0;
        var i: usize = 0;

        while (i <= names_str.len) : (i += 1) {
            if (i == names_str.len or names_str[i] == ',') {
                if (current_idx == idx) {
                    var s = start;
                    var e = i;
                    while (s < e and names_str[s] == ' ') s += 1;
                    while (e > s and names_str[e - 1] == ' ') e -= 1;
                    return names_str[s..e];
                }
                current_idx += 1;
                start = i + 1;
            }
        }
        return std.fmt.comptimePrint("arg{d}", .{idx});
    }
}

// ============================================================================
// Function Definition Helpers
// ============================================================================

/// Function definition entry - stores info needed to wrap at module creation time
pub fn FuncDefEntry(comptime Func: type) type {
    return struct {
        name: [*:0]const u8,
        func: Func,
        doc: ?[*:0]const u8,
        /// Comma-separated Python parameter names for stubs and `help()`.
        /// Zig reflection cannot recover parameter names, so without this
        /// they appear as arg0, arg1, ...
        params: ?[]const u8 = null,

        /// Name the Python-visible parameters, e.g. `.withParams("url, timeout")`.
        pub fn withParams(self: @This(), comptime names: []const u8) @This() {
            var copy = self;
            copy.params = names;
            return copy;
        }
    };
}

/// Helper to create a function entry
pub fn func(comptime name: [*:0]const u8, comptime function: anytype, comptime doc: ?[*:0]const u8) FuncDefEntry(@TypeOf(function)) {
    return .{
        .name = name,
        .func = function,
        .doc = doc,
    };
}

// ============================================================================
// Keyword Arguments Support
// ============================================================================

/// Define named keyword arguments using a struct.
/// Each field becomes a keyword argument with its name.
/// Optional fields (?T) have a default of null.
/// Fields with default values use those defaults.
///
/// Example:
/// ```zig
/// const GreetArgs = struct {
///     name: []const u8,              // Required
///     greeting: ?[]const u8 = null,  // Optional, default null
///     times: i64 = 1,                // Optional, default 1
/// };
///
/// fn greet(args: pyoz.Args(GreetArgs)) []const u8 {
///     const greeting = args.greeting orelse "Hello";
///     // ...
/// }
/// ```
pub fn Args(comptime T: type) type {
    return struct {
        pub const ArgsStruct = T;
        pub const is_pyoz_args = true;
        value: T,

        // Allow direct field access via the wrapper
        pub fn get(self: @This()) T {
            return self.value;
        }
    };
}

/// Wrapper type for functions with keyword arguments using Args(T)
pub fn KwFuncDefEntry(comptime Func: type) type {
    return struct {
        name: [*:0]const u8,
        func: Func,
        doc: ?[*:0]const u8,
        is_named_kwargs: bool = true,
    };
}

/// Create a function entry with keyword arguments.
/// The function should accept Args(YourArgsStruct) as its parameter.
pub fn kwfunc(comptime name: [*:0]const u8, comptime function: anytype, comptime doc: ?[*:0]const u8) KwFuncDefEntry(@TypeOf(function)) {
    return .{
        .name = name,
        .func = function,
        .doc = doc,
        .is_named_kwargs = true,
    };
}
