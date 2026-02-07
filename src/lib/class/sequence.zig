//! Sequence protocol for class generation
//!
//! Implements __len__, __getitem__, __setitem__, __delitem__, __contains__

const std = @import("std");
const py = @import("../python.zig");
const conversion = @import("../conversion.zig");
const slots = py.slots;

const class_mod = @import("mod.zig");
const ClassInfo = class_mod.ClassInfo;

/// Build sequence protocol for a given type
pub fn SequenceProtocol(comptime _: [*:0]const u8, comptime T: type, comptime Parent: type, comptime class_infos: []const ClassInfo) type {
    const Conv = conversion.Converter(class_infos);

    return struct {
        pub fn hasSequenceMethods() bool {
            return @hasDecl(T, "__len__") or @hasDecl(T, "__getitem__") or
                @hasDecl(T, "__contains__") or @hasDecl(T, "__reversed__");
        }

        pub var sequence_methods: py.PySequenceMethods = makeSequenceMethods();

        fn makeSequenceMethods() py.PySequenceMethods {
            var sm: py.PySequenceMethods = std.mem.zeroes(py.PySequenceMethods);

            if (@hasDecl(T, "__len__")) sm.sq_length = @ptrCast(&py_sq_length);
            if (@hasDecl(T, "__getitem__")) sm.sq_item = @ptrCast(&py_sq_item);
            if (@hasDecl(T, "__setitem__") or @hasDecl(T, "__delitem__")) sm.sq_ass_item = @ptrCast(&py_sq_ass_item);
            if (@hasDecl(T, "__contains__")) sm.sq_contains = @ptrCast(&py_sq_contains);

            return sm;
        }

        fn py_sq_length(self_obj: ?*py.PyObject) callconv(.c) py.Py_ssize_t {
            const self: *Parent.PyWrapper = @ptrCast(@alignCast(self_obj orelse return -1));
            const LenFn = @TypeOf(T.__len__);
            const LenRetType = @typeInfo(LenFn).@"fn".return_type.?;
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
                        py.PyErr_SetString(py.PyExc_RuntimeError(), "__len__ returned null");
                    }
                    return -1;
                }
            } else {
                const result = T.__len__(self.getDataConst());
                return @intCast(result);
            }
        }

        /// Helper to convert index with Python-style negative wrapping for unsigned types
        fn wrapIndexConst(comptime IndexType: type, index: py.Py_ssize_t, self: *Parent.PyWrapper) ?IndexType {
            if (@typeInfo(IndexType) == .int) {
                const int_info = @typeInfo(IndexType).int;
                if (int_info.signedness == .unsigned and index < 0) {
                    if (@hasDecl(T, "__len__")) {
                        const len: py.Py_ssize_t = @intCast(T.__len__(self.getDataConst()));
                        const wrapped = index + len;
                        if (wrapped < 0) {
                            py.PyErr_SetString(py.PyExc_IndexError(), "index out of range");
                            return null;
                        }
                        return @intCast(wrapped);
                    } else {
                        py.PyErr_SetString(py.PyExc_IndexError(), "negative index not supported");
                        return null;
                    }
                }
            }
            return @intCast(index);
        }

        fn py_sq_item(self_obj: ?*py.PyObject, index: py.Py_ssize_t) callconv(.c) ?*py.PyObject {
            const self: *Parent.PyWrapper = @ptrCast(@alignCast(self_obj orelse return null));
            const GetItemFn = @TypeOf(T.__getitem__);
            const fn_info = @typeInfo(GetItemFn).@"fn";
            const IndexType = fn_info.params[1].type.?;
            const GetItemRetType = fn_info.return_type.?;

            // Wrap negative index for unsigned types
            const idx = wrapIndexConst(IndexType, index, self) orelse return null;

            if (@typeInfo(GetItemRetType) == .error_union) {
                const result = T.__getitem__(self.getDataConst(), idx) catch |err| {
                    if (py.PyErr_Occurred() == null) {
                        const msg = @errorName(err);
                        py.PyErr_SetString(py.PyExc_IndexError(), msg.ptr);
                    }
                    return null;
                };
                return Conv.toPy(@TypeOf(result), result);
            } else if (@typeInfo(GetItemRetType) == .optional) {
                if (T.__getitem__(self.getDataConst(), idx)) |result| {
                    return Conv.toPy(@TypeOf(result), result);
                } else {
                    if (py.PyErr_Occurred() == null) {
                        py.PyErr_SetString(py.PyExc_IndexError(), "index out of range");
                    }
                    return null;
                }
            } else {
                const result = T.__getitem__(self.getDataConst(), idx);
                return Conv.toPy(GetItemRetType, result);
            }
        }

        fn py_sq_contains(self_obj: ?*py.PyObject, value_obj: ?*py.PyObject) callconv(.c) c_int {
            const self: *Parent.PyWrapper = @ptrCast(@alignCast(self_obj orelse return -1));
            const value = value_obj orelse return -1;

            const ContainsFn = @TypeOf(T.__contains__);
            const fn_info = @typeInfo(ContainsFn).@"fn";
            const ElemType = fn_info.params[1].type.?;

            const elem = Conv.fromPy(ElemType, value) catch {
                return 0;
            };

            const ContainsRetType = fn_info.return_type.?;
            if (@typeInfo(ContainsRetType) == .error_union) {
                const result = T.__contains__(self.getDataConst(), elem) catch |err| {
                    if (py.PyErr_Occurred() == null) {
                        const msg = @errorName(err);
                        py.PyErr_SetString(py.PyExc_RuntimeError(), msg.ptr);
                    }
                    return -1;
                };
                return if (result) 1 else 0;
            } else {
                const result = T.__contains__(self.getDataConst(), elem);
                return if (result) 1 else 0;
            }
        }

        fn py_sq_ass_item(self_obj: ?*py.PyObject, index: py.Py_ssize_t, value_obj: ?*py.PyObject) callconv(.c) c_int {
            const self: *Parent.PyWrapper = @ptrCast(@alignCast(self_obj orelse return -1));

            if (value_obj) |value| {
                if (!@hasDecl(T, "__setitem__")) {
                    py.PyErr_SetString(py.PyExc_TypeError(), "object does not support item assignment");
                    return -1;
                }

                const SetItemFn = @TypeOf(T.__setitem__);
                const set_fn_info = @typeInfo(SetItemFn).@"fn";
                const IndexType = set_fn_info.params[1].type.?;
                const ValueType = set_fn_info.params[2].type.?;

                // Wrap negative index for unsigned types
                const idx = wrapIndexConst(IndexType, index, self) orelse return -1;

                const zig_value = Conv.fromPy(ValueType, value) catch {
                    py.PyErr_SetString(py.PyExc_TypeError(), "invalid value type for __setitem__");
                    return -1;
                };

                const SetRetType = set_fn_info.return_type.?;
                if (@typeInfo(SetRetType) == .error_union) {
                    T.__setitem__(self.getData(), idx, zig_value) catch |err| {
                        if (py.PyErr_Occurred() == null) {
                            const msg = @errorName(err);
                            py.PyErr_SetString(py.PyExc_IndexError(), msg.ptr);
                        }
                        return -1;
                    };
                } else if (@typeInfo(SetRetType) == .optional) {
                    if (T.__setitem__(self.getData(), idx, zig_value) == null) {
                        if (py.PyErr_Occurred() == null) {
                            py.PyErr_SetString(py.PyExc_IndexError(), "__setitem__ failed");
                        }
                        return -1;
                    }
                } else {
                    T.__setitem__(self.getData(), idx, zig_value);
                }
                return 0;
            } else {
                if (!@hasDecl(T, "__delitem__")) {
                    py.PyErr_SetString(py.PyExc_TypeError(), "object does not support item deletion");
                    return -1;
                }

                const DelItemFn = @TypeOf(T.__delitem__);
                const del_fn_info = @typeInfo(DelItemFn).@"fn";
                const DelIndexType = del_fn_info.params[1].type.?;

                // Wrap negative index for unsigned types
                const del_idx = wrapIndexConst(DelIndexType, index, self) orelse return -1;

                const DelRetType = del_fn_info.return_type.?;
                if (@typeInfo(DelRetType) == .error_union) {
                    T.__delitem__(self.getData(), del_idx) catch |err| {
                        if (py.PyErr_Occurred() == null) {
                            const msg = @errorName(err);
                            py.PyErr_SetString(py.PyExc_IndexError(), msg.ptr);
                        }
                        return -1;
                    };
                } else if (@typeInfo(DelRetType) == .optional) {
                    if (T.__delitem__(self.getData(), del_idx) == null) {
                        if (py.PyErr_Occurred() == null) {
                            py.PyErr_SetString(py.PyExc_IndexError(), "__delitem__ failed");
                        }
                        return -1;
                    }
                } else {
                    T.__delitem__(self.getData(), del_idx);
                }
                return 0;
            }
        }

        // ====================================================================
        // ABI3 Slot Building
        // ====================================================================

        /// Count how many sequence protocol slots this type needs
        pub fn slotCount() usize {
            var count: usize = 0;
            if (@hasDecl(T, "__len__")) count += 1;
            if (@hasDecl(T, "__getitem__")) count += 1;
            if (@hasDecl(T, "__setitem__") or @hasDecl(T, "__delitem__")) count += 1;
            if (@hasDecl(T, "__contains__")) count += 1;
            return count;
        }

        /// Add sequence protocol slots to a slot array
        /// Returns the number of slots added
        pub fn addSlots(slot_array: []py.PyType_Slot, start_idx: usize) usize {
            var idx = start_idx;

            if (@hasDecl(T, "__len__")) {
                slot_array[idx] = .{ .slot = slots.sq_length, .pfunc = @ptrCast(@constCast(&py_sq_length)) };
                idx += 1;
            }
            if (@hasDecl(T, "__getitem__")) {
                slot_array[idx] = .{ .slot = slots.sq_item, .pfunc = @ptrCast(@constCast(&py_sq_item)) };
                idx += 1;
            }
            if (@hasDecl(T, "__setitem__") or @hasDecl(T, "__delitem__")) {
                slot_array[idx] = .{ .slot = slots.sq_ass_item, .pfunc = @ptrCast(@constCast(&py_sq_ass_item)) };
                idx += 1;
            }
            if (@hasDecl(T, "__contains__")) {
                slot_array[idx] = .{ .slot = slots.sq_contains, .pfunc = @ptrCast(@constCast(&py_sq_contains)) };
                idx += 1;
            }

            return idx - start_idx;
        }
    };
}
