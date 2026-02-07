//! Attribute access protocol for class generation
//!
//! Implements __getattr__, __setattr__, __delattr__, and frozen class support

const std = @import("std");
const py = @import("../python.zig");
const conversion = @import("../conversion.zig");

const class_mod = @import("mod.zig");
const ClassInfo = class_mod.ClassInfo;

/// Build attribute access protocol for a given type
pub fn AttributeProtocol(comptime name: [*:0]const u8, comptime T: type, comptime Parent: type, comptime class_infos: []const ClassInfo) type {
    return struct {
        /// Check if this class is frozen
        pub fn isFrozen() bool {
            if (@hasDecl(T, "__frozen__")) {
                const FrozenType = @TypeOf(T.__frozen__);
                if (FrozenType == bool) {
                    return T.__frozen__;
                }
            }
            return false;
        }

        /// tp_getattro: Called for ALL attribute access
        pub fn py_getattro(self_obj: ?*py.PyObject, name_obj: ?*py.PyObject) callconv(.c) ?*py.PyObject {
            const result = py.PyObject_GenericGetAttr(self_obj, name_obj);
            if (result != null) {
                return result;
            }

            if (py.PyErr_ExceptionMatches(py.PyExc_AttributeError()) == 0) {
                return null;
            }

            py.PyErr_Clear();

            const self: *Parent.PyWrapper = @ptrCast(@alignCast(self_obj orelse return null));
            const attr_name = conversion.Converter(class_infos).fromPy([]const u8, name_obj.?) catch {
                py.PyErr_SetString(py.PyExc_TypeError(), "attribute name must be a string");
                return null;
            };

            const GetAttrFn = @TypeOf(T.__getattr__);
            const RetType = @typeInfo(GetAttrFn).@"fn".return_type.?;

            if (@typeInfo(RetType) == .error_union) {
                const attr_result = T.__getattr__(self.getDataConst(), attr_name) catch |err| {
                    const msg = @errorName(err);
                    py.PyErr_SetString(py.PyExc_AttributeError(), msg.ptr);
                    return null;
                };
                return conversion.Converter(class_infos).toPy(@TypeOf(attr_result), attr_result);
            } else if (@typeInfo(RetType) == .optional) {
                if (T.__getattr__(self.getDataConst(), attr_name)) |attr_result| {
                    return conversion.Converter(class_infos).toPy(@TypeOf(attr_result), attr_result);
                } else {
                    py.PyErr_SetString(py.PyExc_AttributeError(), "attribute not found");
                    return null;
                }
            } else {
                const attr_result = T.__getattr__(self.getDataConst(), attr_name);
                return conversion.Converter(class_infos).toPy(RetType, attr_result);
            }
        }

        /// tp_setattro: Called for attribute assignment and deletion
        pub fn py_setattro(self_obj: ?*py.PyObject, name_obj: ?*py.PyObject, value_obj: ?*py.PyObject) callconv(.c) c_int {
            const self: *Parent.PyWrapper = @ptrCast(@alignCast(self_obj orelse return -1));
            const attr_name = conversion.Converter(class_infos).fromPy([]const u8, name_obj.?) catch {
                py.PyErr_SetString(py.PyExc_TypeError(), "attribute name must be a string");
                return -1;
            };

            if (value_obj) |value| {
                if (@hasDecl(T, "__setattr__")) {
                    const SetAttrFn = @TypeOf(T.__setattr__);
                    const set_params = @typeInfo(SetAttrFn).@"fn".params;
                    const RetType = @typeInfo(SetAttrFn).@"fn".return_type.?;

                    if (set_params.len >= 3) {
                        const ValueType = set_params[2].type.?;
                        if (ValueType == ?*py.PyObject or ValueType == *py.PyObject) {
                            // Raw PyObject - pass directly
                            if (@typeInfo(RetType) == .error_union) {
                                T.__setattr__(self.getData(), attr_name, value) catch |err| {
                                    if (py.PyErr_Occurred() == null) {
                                        const msg = @errorName(err);
                                        py.PyErr_SetString(py.PyExc_AttributeError(), msg.ptr);
                                    }
                                    return -1;
                                };
                            } else if (@typeInfo(RetType) == .optional) {
                                if (T.__setattr__(self.getData(), attr_name, value) == null) {
                                    if (py.PyErr_Occurred() == null) {
                                        py.PyErr_SetString(py.PyExc_AttributeError(), "__setattr__ failed");
                                    }
                                    return -1;
                                }
                            } else {
                                T.__setattr__(self.getData(), attr_name, value);
                            }
                            return 0;
                        } else {
                            // Convert Python object to Zig type
                            const zig_value = conversion.Converter(class_infos).fromPy(ValueType, value) catch {
                                py.PyErr_SetString(py.PyExc_TypeError(), "cannot convert value to expected type");
                                return -1;
                            };
                            if (@typeInfo(RetType) == .error_union) {
                                T.__setattr__(self.getData(), attr_name, zig_value) catch |err| {
                                    if (py.PyErr_Occurred() == null) {
                                        const msg = @errorName(err);
                                        py.PyErr_SetString(py.PyExc_AttributeError(), msg.ptr);
                                    }
                                    return -1;
                                };
                            } else if (@typeInfo(RetType) == .optional) {
                                if (T.__setattr__(self.getData(), attr_name, zig_value) == null) {
                                    if (py.PyErr_Occurred() == null) {
                                        py.PyErr_SetString(py.PyExc_AttributeError(), "__setattr__ failed");
                                    }
                                    return -1;
                                }
                            } else {
                                T.__setattr__(self.getData(), attr_name, zig_value);
                            }
                            return 0;
                        }
                    }
                }
                return py.PyObject_GenericSetAttr(self_obj, name_obj, value_obj);
            } else {
                if (@hasDecl(T, "__delattr__")) {
                    const DelAttrFn = @TypeOf(T.__delattr__);
                    const RetType = @typeInfo(DelAttrFn).@"fn".return_type.?;

                    if (@typeInfo(RetType) == .error_union) {
                        T.__delattr__(self.getData(), attr_name) catch |err| {
                            if (py.PyErr_Occurred() == null) {
                                const msg = @errorName(err);
                                py.PyErr_SetString(py.PyExc_AttributeError(), msg.ptr);
                            }
                            return -1;
                        };
                    } else if (@typeInfo(RetType) == .optional) {
                        if (T.__delattr__(self.getData(), attr_name) == null) {
                            if (py.PyErr_Occurred() == null) {
                                py.PyErr_SetString(py.PyExc_AttributeError(), "__delattr__ failed");
                            }
                            return -1;
                        }
                    } else {
                        T.__delattr__(self.getData(), attr_name);
                    }
                    return 0;
                }
                return py.PyObject_GenericSetAttr(self_obj, name_obj, value_obj);
            }
        }

        /// Frozen class support - reject all attribute assignment
        pub fn py_frozen_setattro(self_obj: ?*py.PyObject, name_obj: ?*py.PyObject, value_obj: ?*py.PyObject) callconv(.c) c_int {
            _ = self_obj;
            _ = value_obj;

            var size: py.Py_ssize_t = 0;
            const attr_name_ptr: ?[*]const u8 = py.PyUnicode_AsUTF8AndSize(name_obj.?, &size);

            if (attr_name_ptr) |attr_name| {
                var buf: [256]u8 = undefined;
                const msg = std.fmt.bufPrintZ(&buf, "cannot set attribute '{s}' on frozen class '{s}'", .{ attr_name[0..@intCast(size)], name }) catch "cannot modify frozen class";
                py.PyErr_SetString(py.PyExc_AttributeError(), msg.ptr);
            } else {
                py.PyErr_SetString(py.PyExc_AttributeError(), "cannot modify frozen class");
            }
            return -1;
        }
    };
}
