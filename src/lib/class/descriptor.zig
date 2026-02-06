//! Descriptor protocol for class generation
//!
//! Implements __get__, __set__, __delete__

const py = @import("../python.zig");
const conversion = @import("../conversion.zig");

const class_mod = @import("mod.zig");
const ClassInfo = class_mod.ClassInfo;

/// Build descriptor protocol for a given type
pub fn DescriptorProtocol(comptime _: [*:0]const u8, comptime T: type, comptime Parent: type, comptime class_infos: []const ClassInfo) type {
    const Conv = conversion.Converter(class_infos);

    return struct {
        /// tp_descr_get: Called when descriptor is accessed on an object
        pub fn py_descr_get(descr_obj: ?*py.PyObject, obj: ?*py.PyObject, obj_type: ?*py.PyObject) callconv(.c) ?*py.PyObject {
            const descr: *Parent.PyWrapper = @ptrCast(@alignCast(descr_obj orelse return null));

            const GetFn = @TypeOf(T.__get__);
            const get_params = @typeInfo(GetFn).@"fn".params;

            if (get_params.len == 1) {
                const result = T.__get__(descr.getDataConst());
                return Conv.toPy(@TypeOf(result), result);
            } else if (get_params.len == 2) {
                const result = T.__get__(descr.getDataConst(), obj);
                return Conv.toPy(@TypeOf(result), result);
            } else if (get_params.len == 3) {
                const result = T.__get__(descr.getDataConst(), obj, obj_type);
                return Conv.toPy(@TypeOf(result), result);
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

                const zig_value = Conv.fromPy(ValueType, val) catch {
                    py.PyErr_SetString(py.PyExc_TypeError(), "invalid value type for descriptor");
                    return -1;
                };

                T.__set__(descr.getData(), target, zig_value);
                return 0;
            } else {
                if (!@hasDecl(T, "__delete__")) {
                    py.PyErr_SetString(py.PyExc_AttributeError(), "descriptor does not support deletion");
                    return -1;
                }

                T.__delete__(descr.getData(), target);
                return 0;
            }
        }
    };
}
