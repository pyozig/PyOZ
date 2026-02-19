//! Descriptor protocol for class generation
//!
//! Implements __get__, __set__, __delete__

const py = @import("../python.zig");
const conversion = @import("../conversion.zig");

const class_mod = @import("mod.zig");
const ClassInfo = class_mod.ClassInfo;
const unwrapSignature = @import("../root.zig").unwrapSignature;

/// Build descriptor protocol for a given type
pub fn DescriptorProtocol(comptime _: [*:0]const u8, comptime T: type, comptime Parent: type, comptime class_infos: []const ClassInfo) type {
    const Conv = conversion.Converter(class_infos);

    return struct {
        /// Handle return from __get__ - supports plain, error union, and optional.
        fn handleGetReturn(comptime RetType: type, result: RetType) ?*py.PyObject {
            const rt_info = @typeInfo(RetType);
            if (rt_info == .error_union) {
                if (result) |value| {
                    return Conv.toPy(@TypeOf(value), value);
                } else |err| {
                    if (py.PyErr_Occurred() == null) {
                        const msg = @errorName(err);
                        py.PyErr_SetString(py.PyExc_AttributeError(), msg.ptr);
                    }
                    return null;
                }
            } else if (rt_info == .optional) {
                if (result) |value| {
                    return Conv.toPy(@TypeOf(value), value);
                } else {
                    if (py.PyErr_Occurred() != null) return null;
                    return py.Py_RETURN_NONE();
                }
            } else {
                return Conv.toPy(RetType, result);
            }
        }

        /// Handle return from __set__/__delete__ - supports void, error union, and optional.
        fn handleDescSetReturn(comptime RetType: type, result: RetType) c_int {
            const rt_info = @typeInfo(RetType);
            if (rt_info == .error_union) {
                _ = result catch |err| {
                    if (py.PyErr_Occurred() == null) {
                        const msg = @errorName(err);
                        py.PyErr_SetString(py.PyExc_AttributeError(), msg.ptr);
                    }
                    return -1;
                };
                return 0;
            } else if (rt_info == .optional) {
                if (result == null) {
                    if (py.PyErr_Occurred() == null) {
                        py.PyErr_SetString(py.PyExc_AttributeError(), "descriptor operation failed");
                    }
                    return -1;
                }
                return 0;
            } else {
                return 0;
            }
        }

        /// tp_descr_get: Called when descriptor is accessed on an object
        pub fn py_descr_get(descr_obj: ?*py.PyObject, obj: ?*py.PyObject, obj_type: ?*py.PyObject) callconv(.c) ?*py.PyObject {
            const descr: *Parent.PyWrapper = @ptrCast(@alignCast(descr_obj orelse return null));

            const GetFn = @TypeOf(T.__get__);
            const get_params = @typeInfo(GetFn).@"fn".params;
            const RetType = unwrapSignature(@typeInfo(GetFn).@"fn".return_type.?);

            if (get_params.len == 1) {
                return handleGetReturn(RetType, T.__get__(descr.getDataConst()));
            } else if (get_params.len == 2) {
                return handleGetReturn(RetType, T.__get__(descr.getDataConst(), obj));
            } else if (get_params.len == 3) {
                return handleGetReturn(RetType, T.__get__(descr.getDataConst(), obj, obj_type));
            } else {
                py.PyErr_SetString(py.PyExc_TypeError(), "__get__ must take 1-3 parameters");
                return null;
            }
        }

        /// tp_descr_set: Called when descriptor is set or deleted on an object
        pub fn py_descr_set(descr_obj: ?*py.PyObject, obj: ?*py.PyObject, value: ?*py.PyObject) callconv(.c) c_int {
            const descr: *Parent.PyWrapper = @ptrCast(@alignCast(descr_obj orelse return -1));
            const target = obj orelse {
                py.PyErr_SetString(py.PyExc_TypeError(), "descriptor requires an object");
                return -1;
            };

            if (value) |val| {
                if (!@hasDecl(T, "__set__")) {
                    py.PyErr_SetString(py.PyExc_AttributeError(), "descriptor does not support assignment");
                    return -1;
                }

                const SetFn = @TypeOf(T.__set__);
                const set_params = @typeInfo(SetFn).@"fn".params;
                const ValueType = set_params[2].type.?;
                const SetRetType = unwrapSignature(@typeInfo(SetFn).@"fn".return_type.?);

                const zig_value = Conv.fromPy(ValueType, val) catch {
                    py.PyErr_SetString(py.PyExc_TypeError(), "invalid value type for descriptor");
                    return -1;
                };

                return handleDescSetReturn(SetRetType, T.__set__(descr.getData(), target, zig_value));
            } else {
                if (!@hasDecl(T, "__delete__")) {
                    py.PyErr_SetString(py.PyExc_AttributeError(), "descriptor does not support deletion");
                    return -1;
                }

                const DelFn = @TypeOf(T.__delete__);
                const DelRetType = unwrapSignature(@typeInfo(DelFn).@"fn".return_type.?);
                return handleDescSetReturn(DelRetType, T.__delete__(descr.getData(), target));
            }
        }
    };
}
