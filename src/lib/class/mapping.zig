//! Mapping protocol for class generation
//!
//! Implements __getitem__, __setitem__, __delitem__ for dict-like access

const std = @import("std");
const py = @import("../python.zig");
const conversion = @import("../conversion.zig");
const slots = @import("../python/slots.zig");
const abi = @import("../abi.zig");

const unwrapSignature = @import("../root.zig").unwrapSignature;

const class_mod = @import("mod.zig");
const ClassInfo = class_mod.ClassInfo;

/// Build mapping protocol for a given type
pub fn MappingProtocol(comptime _: [*:0]const u8, comptime T: type, comptime Parent: type, comptime class_infos: []const ClassInfo) type {
    const Conv = conversion.Converter(class_infos);

    return struct {
        pub fn hasMappingMethods() bool {
            return @hasDecl(T, "__getitem__");
        }

        pub var mapping_methods: py.PyMappingMethods = makeMappingMethods();

        fn makeMappingMethods() py.PyMappingMethods {
            var mm: py.PyMappingMethods = std.mem.zeroes(py.PyMappingMethods);

            if (@hasDecl(T, "__len__")) mm.mp_length = @ptrCast(&py_mp_length);
            if (@hasDecl(T, "__getitem__")) mm.mp_subscript = @ptrCast(&py_mp_subscript);
            if (@hasDecl(T, "__setitem__") or @hasDecl(T, "__delitem__")) mm.mp_ass_subscript = @ptrCast(&py_mp_ass_subscript);

            return mm;
        }

        fn py_mp_length(self_obj: ?*py.PyObject) callconv(.c) py.Py_ssize_t {
            const self: *Parent.PyWrapper = @ptrCast(@alignCast(self_obj orelse return -1));
            const LenFn = @TypeOf(T.__len__);
            const LenRetType = unwrapSignature(@typeInfo(LenFn).@"fn".return_type.?);
            if (@typeInfo(LenRetType) == .error_union) {
                const result = T.__len__(self.getDataConst()) catch |err| {
                    if (py.PyErr_Occurred() == null) {
                        const msg = @errorName(err);
                        py.PyErr_SetString(py.PyExc_RuntimeError(), msg.ptr);
                    }
                    return -1;
                };
                return @intCast(result);
            } else if (@typeInfo(LenRetType) == .optional) {
                if (T.__len__(self.getDataConst())) |result| {
                    return @intCast(result);
                } else {
                    if (py.PyErr_Occurred() == null) {
                        py.PyErr_SetString(py.PyExc_TypeError(), "__len__ returned null, expected an integer");
                    }
                    return -1;
                }
            } else {
                const result = T.__len__(self.getDataConst());
                return @intCast(result);
            }
        }

        fn py_mp_subscript(self_obj: ?*py.PyObject, key_obj: ?*py.PyObject) callconv(.c) ?*py.PyObject {
            const self: *Parent.PyWrapper = @ptrCast(@alignCast(self_obj orelse return null));
            const key = key_obj orelse return null;

            const GetItemFn = @TypeOf(T.__getitem__);
            const fn_info = @typeInfo(GetItemFn).@"fn";
            const KeyType = fn_info.params[1].type.?;

            const is_integer_key = comptime blk: {
                const key_info = @typeInfo(KeyType);
                break :blk key_info == .int or key_info == .comptime_int;
            };

            const zig_key = Conv.fromPy(KeyType, key) catch {
                if (is_integer_key) {
                    py.PyErr_SetString(py.PyExc_IndexError(), "Invalid index type");
                } else {
                    py.PyErr_SetString(py.PyExc_KeyError(), "Invalid key type");
                }
                return null;
            };

            const GetItemRetType = unwrapSignature(fn_info.return_type.?);
            if (@typeInfo(GetItemRetType) == .error_union) {
                const result = T.__getitem__(self.getDataConst(), zig_key) catch |err| {
                    if (py.PyErr_Occurred() == null) {
                        const msg = @errorName(err);
                        if (is_integer_key) {
                            py.PyErr_SetString(py.PyExc_IndexError(), msg.ptr);
                        } else {
                            py.PyErr_SetString(py.PyExc_KeyError(), msg.ptr);
                        }
                    }
                    return null;
                };
                return Conv.toPy(@TypeOf(result), result);
            } else if (@typeInfo(GetItemRetType) == .optional) {
                if (T.__getitem__(self.getDataConst(), zig_key)) |result| {
                    return Conv.toPy(@TypeOf(result), result);
                } else {
                    if (py.PyErr_Occurred() == null) {
                        if (is_integer_key) {
                            py.PyErr_SetString(py.PyExc_IndexError(), "index out of range");
                        } else {
                            py.PyErr_SetString(py.PyExc_KeyError(), "key not found");
                        }
                    }
                    return null;
                }
            } else {
                const result = T.__getitem__(self.getDataConst(), zig_key);
                return Conv.toPy(GetItemRetType, result);
            }
        }

        fn py_mp_ass_subscript(self_obj: ?*py.PyObject, key_obj: ?*py.PyObject, value_obj: ?*py.PyObject) callconv(.c) c_int {
            const self: *Parent.PyWrapper = @ptrCast(@alignCast(self_obj orelse return -1));
            const key = key_obj orelse return -1;

            if (value_obj) |value| {
                if (!@hasDecl(T, "__setitem__")) {
                    py.PyErr_SetString(py.PyExc_TypeError(), "object does not support item assignment");
                    return -1;
                }

                const SetItemFn = @TypeOf(T.__setitem__);
                const set_fn_info = @typeInfo(SetItemFn).@"fn";
                const KeyType = set_fn_info.params[1].type.?;
                const ValueType = set_fn_info.params[2].type.?;

                const is_integer_key = comptime blk: {
                    const key_info = @typeInfo(KeyType);
                    break :blk key_info == .int or key_info == .comptime_int;
                };

                const zig_key = Conv.fromPy(KeyType, key) catch {
                    if (is_integer_key) {
                        py.PyErr_SetString(py.PyExc_IndexError(), "Invalid index type");
                    } else {
                        py.PyErr_SetString(py.PyExc_KeyError(), "Invalid key type");
                    }
                    return -1;
                };

                const zig_value = Conv.fromPy(ValueType, value) catch {
                    py.PyErr_SetString(py.PyExc_TypeError(), "invalid value type for __setitem__");
                    return -1;
                };

                const SetRetType = unwrapSignature(set_fn_info.return_type.?);
                if (@typeInfo(SetRetType) == .error_union) {
                    T.__setitem__(self.getData(), zig_key, zig_value) catch |err| {
                        if (py.PyErr_Occurred() == null) {
                            const msg = @errorName(err);
                            if (is_integer_key) {
                                py.PyErr_SetString(py.PyExc_IndexError(), msg.ptr);
                            } else {
                                py.PyErr_SetString(py.PyExc_KeyError(), msg.ptr);
                            }
                        }
                        return -1;
                    };
                } else if (@typeInfo(SetRetType) == .optional) {
                    if (T.__setitem__(self.getData(), zig_key, zig_value) == null) {
                        if (py.PyErr_Occurred() == null) {
                            py.PyErr_SetString(py.PyExc_RuntimeError(), "__setitem__ failed");
                        }
                        return -1;
                    }
                } else {
                    T.__setitem__(self.getData(), zig_key, zig_value);
                }
                return 0;
            } else {
                if (!@hasDecl(T, "__delitem__")) {
                    py.PyErr_SetString(py.PyExc_TypeError(), "object does not support item deletion");
                    return -1;
                }

                const DelItemFn = @TypeOf(T.__delitem__);
                const del_fn_info = @typeInfo(DelItemFn).@"fn";
                const KeyType = del_fn_info.params[1].type.?;

                const is_integer_key = comptime blk: {
                    const key_info = @typeInfo(KeyType);
                    break :blk key_info == .int or key_info == .comptime_int;
                };

                const zig_key = Conv.fromPy(KeyType, key) catch {
                    if (is_integer_key) {
                        py.PyErr_SetString(py.PyExc_IndexError(), "Invalid index type");
                    } else {
                        py.PyErr_SetString(py.PyExc_KeyError(), "Invalid key type");
                    }
                    return -1;
                };

                const DelRetType = unwrapSignature(del_fn_info.return_type.?);
                if (@typeInfo(DelRetType) == .error_union) {
                    T.__delitem__(self.getData(), zig_key) catch |err| {
                        if (py.PyErr_Occurred() == null) {
                            const msg = @errorName(err);
                            if (is_integer_key) {
                                py.PyErr_SetString(py.PyExc_IndexError(), msg.ptr);
                            } else {
                                py.PyErr_SetString(py.PyExc_KeyError(), msg.ptr);
                            }
                        }
                        return -1;
                    };
                } else if (@typeInfo(DelRetType) == .optional) {
                    if (T.__delitem__(self.getData(), zig_key) == null) {
                        if (py.PyErr_Occurred() == null) {
                            py.PyErr_SetString(py.PyExc_RuntimeError(), "__delitem__ failed");
                        }
                        return -1;
                    }
                } else {
                    T.__delitem__(self.getData(), zig_key);
                }
                return 0;
            }
        }

        // =====================================================================
        // ABI3 Slot Building Functions
        // =====================================================================

        /// Count how many slots are needed for mapping protocol (ABI3)
        pub fn slotCount() usize {
            if (!abi.abi3_enabled) return 0;

            var count: usize = 0;
            if (@hasDecl(T, "__len__")) count += 1;
            if (@hasDecl(T, "__getitem__")) count += 1;
            if (@hasDecl(T, "__setitem__") or @hasDecl(T, "__delitem__")) count += 1;
            return count;
        }

        /// Add mapping protocol slots to a slot array (ABI3)
        /// Returns the number of slots added
        pub fn addSlots(slot_array: []py.PyType_Slot, start_idx: usize) usize {
            if (!abi.abi3_enabled) return 0;

            var idx = start_idx;

            if (@hasDecl(T, "__len__")) {
                slot_array[idx] = .{ .slot = slots.mp_length, .pfunc = @ptrCast(@constCast(&py_mp_length)) };
                idx += 1;
            }
            if (@hasDecl(T, "__getitem__")) {
                slot_array[idx] = .{ .slot = slots.mp_subscript, .pfunc = @ptrCast(@constCast(&py_mp_subscript)) };
                idx += 1;
            }
            if (@hasDecl(T, "__setitem__") or @hasDecl(T, "__delitem__")) {
                slot_array[idx] = .{ .slot = slots.mp_ass_subscript, .pfunc = @ptrCast(@constCast(&py_mp_ass_subscript)) };
                idx += 1;
            }

            return idx - start_idx;
        }
    };
}
