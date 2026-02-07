//! Callable protocol for class generation
//!
//! Implements __call__ to make instances callable

const std = @import("std");
const py = @import("../python.zig");
const conversion = @import("../conversion.zig");

const class_mod = @import("mod.zig");
const ClassInfo = class_mod.ClassInfo;

/// Build callable protocol for a given type
pub fn CallableProtocol(comptime _: [*:0]const u8, comptime T: type, comptime Parent: type, comptime class_infos: []const ClassInfo) type {
    const Conv = conversion.Converter(class_infos);

    return struct {
        pub fn py_call(self_obj: ?*py.PyObject, args: ?*py.PyObject, kwargs: ?*py.PyObject) callconv(.c) ?*py.PyObject {
            _ = kwargs;
            const self: *Parent.PyWrapper = @ptrCast(@alignCast(self_obj orelse return null));

            const extra_args = parseCallArgs(args) catch |err| {
                const msg = @errorName(err);
                py.PyErr_SetString(py.PyExc_TypeError(), msg.ptr);
                return null;
            };

            const result = callCallMethod(self.getData(), extra_args);

            return handleCallReturn(result);
        }

        fn parseCallArgs(py_args: ?*py.PyObject) !CallArgsTuple() {
            const CallFn = @TypeOf(T.__call__);
            const call_params = @typeInfo(CallFn).@"fn".params;
            const extra_param_count = call_params.len - 1;

            var result: CallArgsTuple() = undefined;

            if (extra_param_count == 0) {
                return result;
            }

            const args_tuple = py_args orelse return error.MissingArguments;
            const arg_count = py.PyTuple_Size(args_tuple);

            if (arg_count != extra_param_count) {
                return error.WrongArgumentCount;
            }

            comptime var i: usize = 0;
            inline for (1..call_params.len) |param_idx| {
                const item = py.PyTuple_GetItem(args_tuple, @intCast(i)) orelse return error.InvalidArgument;
                result[i] = try Conv.fromPy(call_params[param_idx].type.?, item);
                i += 1;
            }

            return result;
        }

        fn CallArgsTuple() type {
            const CallFn = @TypeOf(T.__call__);
            const call_params = @typeInfo(CallFn).@"fn".params;
            if (call_params.len <= 1) return std.meta.Tuple(&[_]type{});
            var types: [call_params.len - 1]type = undefined;
            for (1..call_params.len) |i| {
                types[i - 1] = call_params[i].type.?;
            }
            return std.meta.Tuple(&types);
        }

        fn callCallMethod(self_ptr: anytype, extra: CallArgsTuple()) @typeInfo(@TypeOf(T.__call__)).@"fn".return_type.? {
            const CallFn = @TypeOf(T.__call__);
            const call_params = @typeInfo(CallFn).@"fn".params;
            if (call_params.len == 1) {
                return @call(.auto, T.__call__, .{self_ptr});
            } else {
                return @call(.auto, T.__call__, .{self_ptr} ++ extra);
            }
        }

        fn handleCallReturn(result: @typeInfo(@TypeOf(T.__call__)).@"fn".return_type.?) ?*py.PyObject {
            const CallFn = @TypeOf(T.__call__);
            const ReturnType = @typeInfo(CallFn).@"fn".return_type.?;
            const rt_info = @typeInfo(ReturnType);

            if (rt_info == .error_union) {
                if (result) |value| {
                    return Conv.toPy(@TypeOf(value), value);
                } else |err| {
                    if (py.PyErr_Occurred() == null) {
                        const msg = @errorName(err);
                        py.PyErr_SetString(py.PyExc_RuntimeError(), msg.ptr);
                    }
                    return null;
                }
            } else if (rt_info == .optional) {
                if (result) |value| {
                    return Conv.toPy(@TypeOf(value), value);
                } else {
                    if (py.PyErr_Occurred() == null) {
                        py.PyErr_SetString(py.PyExc_RuntimeError(), "__call__ returned null");
                    }
                    return null;
                }
            } else if (ReturnType == void) {
                return py.Py_RETURN_NONE();
            } else {
                return Conv.toPy(ReturnType, result);
            }
        }
    };
}
