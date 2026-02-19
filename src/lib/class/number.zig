//! Number protocol for class generation
//!
//! Implements __add__, __sub__, __mul__, __neg__, __truediv__, etc.

const std = @import("std");
const py = @import("../python.zig");
const conversion = @import("../conversion.zig");
const slots = py.slots;

const unwrapSignature = @import("../root.zig").unwrapSignature;
const class_mod = @import("mod.zig");
const ClassInfo = class_mod.ClassInfo;

/// Build number protocol for a given type
pub fn NumberProtocol(comptime _: [*:0]const u8, comptime T: type, comptime Parent: type, comptime class_infos: []const ClassInfo) type {
    const Conv = conversion.Converter(class_infos);

    return struct {
        pub fn hasNumberMethods() bool {
            return @hasDecl(T, "__add__") or @hasDecl(T, "__sub__") or
                @hasDecl(T, "__mul__") or @hasDecl(T, "__neg__") or
                @hasDecl(T, "__bool__") or @hasDecl(T, "__truediv__") or
                @hasDecl(T, "__floordiv__") or @hasDecl(T, "__mod__") or
                @hasDecl(T, "__divmod__") or
                @hasDecl(T, "__pow__") or @hasDecl(T, "__pos__") or
                @hasDecl(T, "__abs__") or @hasDecl(T, "__invert__") or
                @hasDecl(T, "__lshift__") or @hasDecl(T, "__rshift__") or
                @hasDecl(T, "__and__") or @hasDecl(T, "__or__") or
                @hasDecl(T, "__xor__") or @hasDecl(T, "__matmul__") or
                @hasDecl(T, "__int__") or @hasDecl(T, "__float__") or
                @hasDecl(T, "__complex__") or @hasDecl(T, "__index__") or
                @hasDecl(T, "__iadd__") or @hasDecl(T, "__isub__") or
                @hasDecl(T, "__imul__") or @hasDecl(T, "__itruediv__") or
                @hasDecl(T, "__ifloordiv__") or @hasDecl(T, "__imod__") or
                @hasDecl(T, "__ipow__") or @hasDecl(T, "__ilshift__") or
                @hasDecl(T, "__irshift__") or @hasDecl(T, "__iand__") or
                @hasDecl(T, "__ior__") or @hasDecl(T, "__ixor__") or
                @hasDecl(T, "__imatmul__") or
                @hasDecl(T, "__radd__") or @hasDecl(T, "__rsub__") or
                @hasDecl(T, "__rmul__") or @hasDecl(T, "__rtruediv__") or
                @hasDecl(T, "__rfloordiv__") or @hasDecl(T, "__rmod__") or
                @hasDecl(T, "__rdivmod__") or
                @hasDecl(T, "__rpow__") or @hasDecl(T, "__rlshift__") or
                @hasDecl(T, "__rrshift__") or @hasDecl(T, "__rand__") or
                @hasDecl(T, "__ror__") or @hasDecl(T, "__rxor__") or
                @hasDecl(T, "__rmatmul__");
        }

        pub var number_methods: py.c.PyNumberMethods = makeNumberMethods();

        fn makeNumberMethods() py.c.PyNumberMethods {
            var nm: py.c.PyNumberMethods = std.mem.zeroes(py.c.PyNumberMethods);

            if (@hasDecl(T, "__add__")) nm.nb_add = @ptrCast(&py_nb_add);
            if (@hasDecl(T, "__sub__")) nm.nb_subtract = @ptrCast(&py_nb_sub);
            if (@hasDecl(T, "__mul__")) nm.nb_multiply = @ptrCast(&py_nb_mul);
            if (@hasDecl(T, "__neg__")) nm.nb_negative = @ptrCast(&py_nb_neg);
            if (@hasDecl(T, "__truediv__")) nm.nb_true_divide = @ptrCast(&py_nb_truediv);
            if (@hasDecl(T, "__floordiv__")) nm.nb_floor_divide = @ptrCast(&py_nb_floordiv);
            if (@hasDecl(T, "__mod__")) nm.nb_remainder = @ptrCast(&py_nb_mod);
            if (@hasDecl(T, "__divmod__")) nm.nb_divmod = @ptrCast(&py_nb_divmod);
            if (@hasDecl(T, "__bool__")) nm.nb_bool = @ptrCast(&py_nb_bool);
            if (@hasDecl(T, "__pow__")) nm.nb_power = @ptrCast(&py_nb_pow);
            if (@hasDecl(T, "__pos__")) nm.nb_positive = @ptrCast(&py_nb_pos);
            if (@hasDecl(T, "__abs__")) nm.nb_absolute = @ptrCast(&py_nb_abs);
            if (@hasDecl(T, "__invert__")) nm.nb_invert = @ptrCast(&py_nb_invert);
            if (@hasDecl(T, "__lshift__")) nm.nb_lshift = @ptrCast(&py_nb_lshift);
            if (@hasDecl(T, "__rshift__")) nm.nb_rshift = @ptrCast(&py_nb_rshift);
            if (@hasDecl(T, "__and__")) nm.nb_and = @ptrCast(&py_nb_and);
            if (@hasDecl(T, "__or__")) nm.nb_or = @ptrCast(&py_nb_or);
            if (@hasDecl(T, "__xor__")) nm.nb_xor = @ptrCast(&py_nb_xor);
            if (@hasDecl(T, "__matmul__")) nm.nb_matrix_multiply = @ptrCast(&py_nb_matmul);
            if (@hasDecl(T, "__int__")) nm.nb_int = @ptrCast(&py_nb_int);
            if (@hasDecl(T, "__float__")) nm.nb_float = @ptrCast(&py_nb_float);
            if (@hasDecl(T, "__index__")) nm.nb_index = @ptrCast(&py_nb_index);
            // In-place operators
            if (@hasDecl(T, "__iadd__")) nm.nb_inplace_add = @ptrCast(&py_nb_iadd);
            if (@hasDecl(T, "__isub__")) nm.nb_inplace_subtract = @ptrCast(&py_nb_isub);
            if (@hasDecl(T, "__imul__")) nm.nb_inplace_multiply = @ptrCast(&py_nb_imul);
            if (@hasDecl(T, "__itruediv__")) nm.nb_inplace_true_divide = @ptrCast(&py_nb_itruediv);
            if (@hasDecl(T, "__ifloordiv__")) nm.nb_inplace_floor_divide = @ptrCast(&py_nb_ifloordiv);
            if (@hasDecl(T, "__imod__")) nm.nb_inplace_remainder = @ptrCast(&py_nb_imod);
            if (@hasDecl(T, "__ipow__")) nm.nb_inplace_power = @ptrCast(&py_nb_ipow);
            if (@hasDecl(T, "__ilshift__")) nm.nb_inplace_lshift = @ptrCast(&py_nb_ilshift);
            if (@hasDecl(T, "__irshift__")) nm.nb_inplace_rshift = @ptrCast(&py_nb_irshift);
            if (@hasDecl(T, "__iand__")) nm.nb_inplace_and = @ptrCast(&py_nb_iand);
            if (@hasDecl(T, "__ior__")) nm.nb_inplace_or = @ptrCast(&py_nb_ior);
            if (@hasDecl(T, "__ixor__")) nm.nb_inplace_xor = @ptrCast(&py_nb_ixor);
            if (@hasDecl(T, "__imatmul__")) nm.nb_inplace_matrix_multiply = @ptrCast(&py_nb_imatmul);

            return nm;
        }

        /// Handle return value from a number protocol method.
        /// Supports plain T, !T (error union), and ?T (optional).
        fn handleNumberReturn(comptime RetType: type, result: RetType, default_exc: *py.PyObject) ?*py.PyObject {
            const rt_info = @typeInfo(RetType);
            if (rt_info == .error_union) {
                if (result) |value| {
                    return Conv.toPy(@TypeOf(value), value);
                } else |err| {
                    if (py.PyErr_Occurred() == null) {
                        const msg = @errorName(err);
                        py.PyErr_SetString(default_exc, msg.ptr);
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

        /// Handle return value from an in-place number protocol method.
        /// In-place ops return void, !void, or ?@TypeOf(null).
        fn handleInplaceReturn(comptime RetType: type, result: RetType, self_obj: ?*py.PyObject) ?*py.PyObject {
            const rt_info = @typeInfo(RetType);
            if (rt_info == .error_union) {
                _ = result catch |err| {
                    if (py.PyErr_Occurred() == null) {
                        const msg = @errorName(err);
                        py.PyErr_SetString(py.PyExc_RuntimeError(), msg.ptr);
                    }
                    return null;
                };
                py.Py_IncRef(self_obj);
                return self_obj;
            } else if (rt_info == .optional) {
                if (result == null) {
                    if (py.PyErr_Occurred() == null) {
                        py.PyErr_SetString(py.PyExc_RuntimeError(), "in-place operation failed");
                    }
                    return null;
                }
                py.Py_IncRef(self_obj);
                return self_obj;
            } else {
                py.Py_IncRef(self_obj);
                return self_obj;
            }
        }

        /// Generic binary op helper: handles forward, reverse, and mixed-type dispatch.
        fn binop(comptime forward: []const u8, comptime reverse: []const u8, exc: *py.PyObject, self_obj: ?*py.PyObject, other_obj: ?*py.PyObject) ?*py.PyObject {
            const self_is_T = py.PyObject_TypeCheck(self_obj.?, Parent.getTypeObjectPtr());
            const other_is_T = py.PyObject_TypeCheck(other_obj.?, Parent.getTypeObjectPtr());

            if (self_is_T and other_is_T) {
                if (@hasDecl(T, forward)) {
                    const self: *Parent.PyWrapper = @ptrCast(@alignCast(self_obj orelse return null));
                    const other: *Parent.PyWrapper = @ptrCast(@alignCast(other_obj orelse return null));
                    const Fn = @TypeOf(@field(T, forward));
                    const RetType = unwrapSignature(@typeInfo(Fn).@"fn".return_type.?);
                    return handleNumberReturn(RetType, @field(T, forward)(self.getDataConst(), other.getDataConst()), exc);
                }
            }

            if (!self_is_T and other_is_T) {
                if (@hasDecl(T, reverse)) {
                    const other: *Parent.PyWrapper = @ptrCast(@alignCast(other_obj orelse return null));
                    const RFn = @TypeOf(@field(T, reverse));
                    const RRetType = unwrapSignature(@typeInfo(RFn).@"fn".return_type.?);
                    return handleNumberReturn(RRetType, @field(T, reverse)(other.getDataConst(), self_obj.?), exc);
                }
            }

            if (self_is_T and !other_is_T) {
                if (@hasDecl(T, forward)) {
                    const Fn = @TypeOf(@field(T, forward));
                    const fwd_params = @typeInfo(Fn).@"fn".params;
                    if (fwd_params.len >= 2) {
                        const OtherType = fwd_params[1].type.?;
                        if (OtherType == ?*py.PyObject or OtherType == *py.PyObject) {
                            const self: *Parent.PyWrapper = @ptrCast(@alignCast(self_obj orelse return null));
                            const RetType = unwrapSignature(@typeInfo(Fn).@"fn".return_type.?);
                            return handleNumberReturn(RetType, @field(T, forward)(self.getDataConst(), other_obj.?), exc);
                        }
                    }
                }
            }

            return py.Py_NotImplemented();
        }

        /// Generic inplace op helper.
        fn inplace_op(comptime method: []const u8, self_obj: ?*py.PyObject, other_obj: ?*py.PyObject) ?*py.PyObject {
            const self: *Parent.PyWrapper = @ptrCast(@alignCast(self_obj orelse return null));
            const other: *Parent.PyWrapper = @ptrCast(@alignCast(other_obj orelse return null));
            if (!py.PyObject_TypeCheck(other_obj.?, Parent.getTypeObjectPtr())) {
                return py.Py_NotImplemented();
            }
            const Fn = @TypeOf(@field(T, method));
            const RetType = unwrapSignature(@typeInfo(Fn).@"fn".return_type.?);
            return handleInplaceReturn(RetType, @field(T, method)(self.getData(), other.getDataConst()), self_obj);
        }

        fn py_nb_add(self_obj: ?*py.PyObject, other_obj: ?*py.PyObject) callconv(.c) ?*py.PyObject {
            return binop("__add__", "__radd__", py.PyExc_RuntimeError(), self_obj, other_obj);
        }

        fn py_nb_sub(self_obj: ?*py.PyObject, other_obj: ?*py.PyObject) callconv(.c) ?*py.PyObject {
            return binop("__sub__", "__rsub__", py.PyExc_RuntimeError(), self_obj, other_obj);
        }

        fn py_nb_mul(self_obj: ?*py.PyObject, other_obj: ?*py.PyObject) callconv(.c) ?*py.PyObject {
            return binop("__mul__", "__rmul__", py.PyExc_RuntimeError(), self_obj, other_obj);
        }

        fn py_nb_neg(self_obj: ?*py.PyObject) callconv(.c) ?*py.PyObject {
            const self: *Parent.PyWrapper = @ptrCast(@alignCast(self_obj orelse return null));
            const Fn = @TypeOf(T.__neg__);
            const RetType = unwrapSignature(@typeInfo(Fn).@"fn".return_type.?);
            return handleNumberReturn(RetType, T.__neg__(self.getDataConst()), py.PyExc_RuntimeError());
        }

        fn py_nb_truediv(self_obj: ?*py.PyObject, other_obj: ?*py.PyObject) callconv(.c) ?*py.PyObject {
            return binop("__truediv__", "__rtruediv__", py.PyExc_ZeroDivisionError(), self_obj, other_obj);
        }

        fn py_nb_floordiv(self_obj: ?*py.PyObject, other_obj: ?*py.PyObject) callconv(.c) ?*py.PyObject {
            return binop("__floordiv__", "__rfloordiv__", py.PyExc_ZeroDivisionError(), self_obj, other_obj);
        }

        fn py_nb_mod(self_obj: ?*py.PyObject, other_obj: ?*py.PyObject) callconv(.c) ?*py.PyObject {
            return binop("__mod__", "__rmod__", py.PyExc_ZeroDivisionError(), self_obj, other_obj);
        }

        fn py_nb_divmod(self_obj: ?*py.PyObject, other_obj: ?*py.PyObject) callconv(.c) ?*py.PyObject {
            return binop("__divmod__", "__rdivmod__", py.PyExc_ZeroDivisionError(), self_obj, other_obj);
        }

        fn py_nb_bool(self_obj: ?*py.PyObject) callconv(.c) c_int {
            const self: *Parent.PyWrapper = @ptrCast(@alignCast(self_obj orelse return -1));
            const BoolFn = @TypeOf(T.__bool__);
            const BoolRetType = unwrapSignature(@typeInfo(BoolFn).@"fn".return_type.?);
            if (@typeInfo(BoolRetType) == .error_union) {
                const result = T.__bool__(self.getDataConst()) catch |err| {
                    if (py.PyErr_Occurred() == null) {
                        const msg = @errorName(err);
                        py.PyErr_SetString(py.PyExc_RuntimeError(), msg.ptr);
                    }
                    return -1;
                };
                return if (result) 1 else 0;
            } else {
                const result = T.__bool__(self.getDataConst());
                return if (result) 1 else 0;
            }
        }

        fn py_nb_pow(self_obj: ?*py.PyObject, other_obj: ?*py.PyObject, mod_obj: ?*py.PyObject) callconv(.c) ?*py.PyObject {
            _ = mod_obj;
            return binop("__pow__", "__rpow__", py.PyExc_ValueError(), self_obj, other_obj);
        }

        fn py_nb_pos(self_obj: ?*py.PyObject) callconv(.c) ?*py.PyObject {
            const self: *Parent.PyWrapper = @ptrCast(@alignCast(self_obj orelse return null));
            const Fn = @TypeOf(T.__pos__);
            const RetType = unwrapSignature(@typeInfo(Fn).@"fn".return_type.?);
            return handleNumberReturn(RetType, T.__pos__(self.getDataConst()), py.PyExc_RuntimeError());
        }

        fn py_nb_abs(self_obj: ?*py.PyObject) callconv(.c) ?*py.PyObject {
            const self: *Parent.PyWrapper = @ptrCast(@alignCast(self_obj orelse return null));
            const Fn = @TypeOf(T.__abs__);
            const RetType = unwrapSignature(@typeInfo(Fn).@"fn".return_type.?);
            return handleNumberReturn(RetType, T.__abs__(self.getDataConst()), py.PyExc_RuntimeError());
        }

        fn py_nb_invert(self_obj: ?*py.PyObject) callconv(.c) ?*py.PyObject {
            const self: *Parent.PyWrapper = @ptrCast(@alignCast(self_obj orelse return null));
            const Fn = @TypeOf(T.__invert__);
            const RetType = unwrapSignature(@typeInfo(Fn).@"fn".return_type.?);
            return handleNumberReturn(RetType, T.__invert__(self.getDataConst()), py.PyExc_RuntimeError());
        }

        fn py_nb_lshift(self_obj: ?*py.PyObject, other_obj: ?*py.PyObject) callconv(.c) ?*py.PyObject {
            return binop("__lshift__", "__rlshift__", py.PyExc_RuntimeError(), self_obj, other_obj);
        }

        fn py_nb_rshift(self_obj: ?*py.PyObject, other_obj: ?*py.PyObject) callconv(.c) ?*py.PyObject {
            return binop("__rshift__", "__rrshift__", py.PyExc_RuntimeError(), self_obj, other_obj);
        }

        fn py_nb_and(self_obj: ?*py.PyObject, other_obj: ?*py.PyObject) callconv(.c) ?*py.PyObject {
            return binop("__and__", "__rand__", py.PyExc_RuntimeError(), self_obj, other_obj);
        }

        fn py_nb_or(self_obj: ?*py.PyObject, other_obj: ?*py.PyObject) callconv(.c) ?*py.PyObject {
            return binop("__or__", "__ror__", py.PyExc_RuntimeError(), self_obj, other_obj);
        }

        fn py_nb_xor(self_obj: ?*py.PyObject, other_obj: ?*py.PyObject) callconv(.c) ?*py.PyObject {
            return binop("__xor__", "__rxor__", py.PyExc_RuntimeError(), self_obj, other_obj);
        }

        fn py_nb_matmul(self_obj: ?*py.PyObject, other_obj: ?*py.PyObject) callconv(.c) ?*py.PyObject {
            return binop("__matmul__", "__rmatmul__", py.PyExc_RuntimeError(), self_obj, other_obj);
        }

        fn py_nb_int(self_obj: ?*py.PyObject) callconv(.c) ?*py.PyObject {
            const self: *Parent.PyWrapper = @ptrCast(@alignCast(self_obj orelse return null));
            const Fn = @TypeOf(T.__int__);
            const RetType = unwrapSignature(@typeInfo(Fn).@"fn".return_type.?);
            return handleNumberReturn(RetType, T.__int__(self.getDataConst()), py.PyExc_RuntimeError());
        }

        fn py_nb_float(self_obj: ?*py.PyObject) callconv(.c) ?*py.PyObject {
            const self: *Parent.PyWrapper = @ptrCast(@alignCast(self_obj orelse return null));
            const Fn = @TypeOf(T.__float__);
            const RetType = unwrapSignature(@typeInfo(Fn).@"fn".return_type.?);
            return handleNumberReturn(RetType, T.__float__(self.getDataConst()), py.PyExc_RuntimeError());
        }

        fn py_nb_index(self_obj: ?*py.PyObject) callconv(.c) ?*py.PyObject {
            const self: *Parent.PyWrapper = @ptrCast(@alignCast(self_obj orelse return null));
            const Fn = @TypeOf(T.__index__);
            const RetType = unwrapSignature(@typeInfo(Fn).@"fn".return_type.?);
            return handleNumberReturn(RetType, T.__index__(self.getDataConst()), py.PyExc_RuntimeError());
        }

        // In-place operators
        fn py_nb_iadd(self_obj: ?*py.PyObject, other_obj: ?*py.PyObject) callconv(.c) ?*py.PyObject {
            return inplace_op("__iadd__", self_obj, other_obj);
        }

        fn py_nb_isub(self_obj: ?*py.PyObject, other_obj: ?*py.PyObject) callconv(.c) ?*py.PyObject {
            return inplace_op("__isub__", self_obj, other_obj);
        }

        fn py_nb_imul(self_obj: ?*py.PyObject, other_obj: ?*py.PyObject) callconv(.c) ?*py.PyObject {
            return inplace_op("__imul__", self_obj, other_obj);
        }

        fn py_nb_itruediv(self_obj: ?*py.PyObject, other_obj: ?*py.PyObject) callconv(.c) ?*py.PyObject {
            return inplace_op("__itruediv__", self_obj, other_obj);
        }

        fn py_nb_ifloordiv(self_obj: ?*py.PyObject, other_obj: ?*py.PyObject) callconv(.c) ?*py.PyObject {
            return inplace_op("__ifloordiv__", self_obj, other_obj);
        }

        fn py_nb_imod(self_obj: ?*py.PyObject, other_obj: ?*py.PyObject) callconv(.c) ?*py.PyObject {
            return inplace_op("__imod__", self_obj, other_obj);
        }

        fn py_nb_ipow(self_obj: ?*py.PyObject, other_obj: ?*py.PyObject, mod_obj: ?*py.PyObject) callconv(.c) ?*py.PyObject {
            _ = mod_obj;
            return inplace_op("__ipow__", self_obj, other_obj);
        }

        fn py_nb_ilshift(self_obj: ?*py.PyObject, other_obj: ?*py.PyObject) callconv(.c) ?*py.PyObject {
            return inplace_op("__ilshift__", self_obj, other_obj);
        }

        fn py_nb_irshift(self_obj: ?*py.PyObject, other_obj: ?*py.PyObject) callconv(.c) ?*py.PyObject {
            return inplace_op("__irshift__", self_obj, other_obj);
        }

        fn py_nb_iand(self_obj: ?*py.PyObject, other_obj: ?*py.PyObject) callconv(.c) ?*py.PyObject {
            return inplace_op("__iand__", self_obj, other_obj);
        }

        fn py_nb_ior(self_obj: ?*py.PyObject, other_obj: ?*py.PyObject) callconv(.c) ?*py.PyObject {
            return inplace_op("__ior__", self_obj, other_obj);
        }

        fn py_nb_ixor(self_obj: ?*py.PyObject, other_obj: ?*py.PyObject) callconv(.c) ?*py.PyObject {
            return inplace_op("__ixor__", self_obj, other_obj);
        }

        fn py_nb_imatmul(self_obj: ?*py.PyObject, other_obj: ?*py.PyObject) callconv(.c) ?*py.PyObject {
            return inplace_op("__imatmul__", self_obj, other_obj);
        }

        // ====================================================================
        // ABI3 Slot Building
        // ====================================================================

        /// Count how many number protocol slots this type needs
        pub fn slotCount() usize {
            var count: usize = 0;
            if (@hasDecl(T, "__add__")) count += 1;
            if (@hasDecl(T, "__sub__")) count += 1;
            if (@hasDecl(T, "__mul__")) count += 1;
            if (@hasDecl(T, "__neg__")) count += 1;
            if (@hasDecl(T, "__truediv__")) count += 1;
            if (@hasDecl(T, "__floordiv__")) count += 1;
            if (@hasDecl(T, "__mod__")) count += 1;
            if (@hasDecl(T, "__divmod__")) count += 1;
            if (@hasDecl(T, "__bool__")) count += 1;
            if (@hasDecl(T, "__pow__")) count += 1;
            if (@hasDecl(T, "__pos__")) count += 1;
            if (@hasDecl(T, "__abs__")) count += 1;
            if (@hasDecl(T, "__invert__")) count += 1;
            if (@hasDecl(T, "__lshift__")) count += 1;
            if (@hasDecl(T, "__rshift__")) count += 1;
            if (@hasDecl(T, "__and__")) count += 1;
            if (@hasDecl(T, "__or__")) count += 1;
            if (@hasDecl(T, "__xor__")) count += 1;
            if (@hasDecl(T, "__matmul__")) count += 1;
            if (@hasDecl(T, "__int__")) count += 1;
            if (@hasDecl(T, "__float__")) count += 1;
            if (@hasDecl(T, "__index__")) count += 1;
            if (@hasDecl(T, "__iadd__")) count += 1;
            if (@hasDecl(T, "__isub__")) count += 1;
            if (@hasDecl(T, "__imul__")) count += 1;
            if (@hasDecl(T, "__itruediv__")) count += 1;
            if (@hasDecl(T, "__ifloordiv__")) count += 1;
            if (@hasDecl(T, "__imod__")) count += 1;
            if (@hasDecl(T, "__ipow__")) count += 1;
            if (@hasDecl(T, "__ilshift__")) count += 1;
            if (@hasDecl(T, "__irshift__")) count += 1;
            if (@hasDecl(T, "__iand__")) count += 1;
            if (@hasDecl(T, "__ior__")) count += 1;
            if (@hasDecl(T, "__ixor__")) count += 1;
            if (@hasDecl(T, "__imatmul__")) count += 1;
            return count;
        }

        /// Add number protocol slots to a slot array
        /// Returns the number of slots added
        pub fn addSlots(slot_array: []py.PyType_Slot, start_idx: usize) usize {
            var idx = start_idx;

            if (@hasDecl(T, "__add__")) {
                slot_array[idx] = .{ .slot = slots.nb_add, .pfunc = @ptrCast(@constCast(&py_nb_add)) };
                idx += 1;
            }
            if (@hasDecl(T, "__sub__")) {
                slot_array[idx] = .{ .slot = slots.nb_subtract, .pfunc = @ptrCast(@constCast(&py_nb_sub)) };
                idx += 1;
            }
            if (@hasDecl(T, "__mul__")) {
                slot_array[idx] = .{ .slot = slots.nb_multiply, .pfunc = @ptrCast(@constCast(&py_nb_mul)) };
                idx += 1;
            }
            if (@hasDecl(T, "__neg__")) {
                slot_array[idx] = .{ .slot = slots.nb_negative, .pfunc = @ptrCast(@constCast(&py_nb_neg)) };
                idx += 1;
            }
            if (@hasDecl(T, "__truediv__")) {
                slot_array[idx] = .{ .slot = slots.nb_true_divide, .pfunc = @ptrCast(@constCast(&py_nb_truediv)) };
                idx += 1;
            }
            if (@hasDecl(T, "__floordiv__")) {
                slot_array[idx] = .{ .slot = slots.nb_floor_divide, .pfunc = @ptrCast(@constCast(&py_nb_floordiv)) };
                idx += 1;
            }
            if (@hasDecl(T, "__mod__")) {
                slot_array[idx] = .{ .slot = slots.nb_remainder, .pfunc = @ptrCast(@constCast(&py_nb_mod)) };
                idx += 1;
            }
            if (@hasDecl(T, "__divmod__")) {
                slot_array[idx] = .{ .slot = slots.nb_divmod, .pfunc = @ptrCast(@constCast(&py_nb_divmod)) };
                idx += 1;
            }
            if (@hasDecl(T, "__bool__")) {
                slot_array[idx] = .{ .slot = slots.nb_bool, .pfunc = @ptrCast(@constCast(&py_nb_bool)) };
                idx += 1;
            }
            if (@hasDecl(T, "__pow__")) {
                slot_array[idx] = .{ .slot = slots.nb_power, .pfunc = @ptrCast(@constCast(&py_nb_pow)) };
                idx += 1;
            }
            if (@hasDecl(T, "__pos__")) {
                slot_array[idx] = .{ .slot = slots.nb_positive, .pfunc = @ptrCast(@constCast(&py_nb_pos)) };
                idx += 1;
            }
            if (@hasDecl(T, "__abs__")) {
                slot_array[idx] = .{ .slot = slots.nb_absolute, .pfunc = @ptrCast(@constCast(&py_nb_abs)) };
                idx += 1;
            }
            if (@hasDecl(T, "__invert__")) {
                slot_array[idx] = .{ .slot = slots.nb_invert, .pfunc = @ptrCast(@constCast(&py_nb_invert)) };
                idx += 1;
            }
            if (@hasDecl(T, "__lshift__")) {
                slot_array[idx] = .{ .slot = slots.nb_lshift, .pfunc = @ptrCast(@constCast(&py_nb_lshift)) };
                idx += 1;
            }
            if (@hasDecl(T, "__rshift__")) {
                slot_array[idx] = .{ .slot = slots.nb_rshift, .pfunc = @ptrCast(@constCast(&py_nb_rshift)) };
                idx += 1;
            }
            if (@hasDecl(T, "__and__")) {
                slot_array[idx] = .{ .slot = slots.nb_and, .pfunc = @ptrCast(@constCast(&py_nb_and)) };
                idx += 1;
            }
            if (@hasDecl(T, "__or__")) {
                slot_array[idx] = .{ .slot = slots.nb_or, .pfunc = @ptrCast(@constCast(&py_nb_or)) };
                idx += 1;
            }
            if (@hasDecl(T, "__xor__")) {
                slot_array[idx] = .{ .slot = slots.nb_xor, .pfunc = @ptrCast(@constCast(&py_nb_xor)) };
                idx += 1;
            }
            if (@hasDecl(T, "__matmul__")) {
                slot_array[idx] = .{ .slot = slots.nb_matrix_multiply, .pfunc = @ptrCast(@constCast(&py_nb_matmul)) };
                idx += 1;
            }
            if (@hasDecl(T, "__int__")) {
                slot_array[idx] = .{ .slot = slots.nb_int, .pfunc = @ptrCast(@constCast(&py_nb_int)) };
                idx += 1;
            }
            if (@hasDecl(T, "__float__")) {
                slot_array[idx] = .{ .slot = slots.nb_float, .pfunc = @ptrCast(@constCast(&py_nb_float)) };
                idx += 1;
            }
            if (@hasDecl(T, "__index__")) {
                slot_array[idx] = .{ .slot = slots.nb_index, .pfunc = @ptrCast(@constCast(&py_nb_index)) };
                idx += 1;
            }
            // In-place operators
            if (@hasDecl(T, "__iadd__")) {
                slot_array[idx] = .{ .slot = slots.nb_inplace_add, .pfunc = @ptrCast(@constCast(&py_nb_iadd)) };
                idx += 1;
            }
            if (@hasDecl(T, "__isub__")) {
                slot_array[idx] = .{ .slot = slots.nb_inplace_subtract, .pfunc = @ptrCast(@constCast(&py_nb_isub)) };
                idx += 1;
            }
            if (@hasDecl(T, "__imul__")) {
                slot_array[idx] = .{ .slot = slots.nb_inplace_multiply, .pfunc = @ptrCast(@constCast(&py_nb_imul)) };
                idx += 1;
            }
            if (@hasDecl(T, "__itruediv__")) {
                slot_array[idx] = .{ .slot = slots.nb_inplace_true_divide, .pfunc = @ptrCast(@constCast(&py_nb_itruediv)) };
                idx += 1;
            }
            if (@hasDecl(T, "__ifloordiv__")) {
                slot_array[idx] = .{ .slot = slots.nb_inplace_floor_divide, .pfunc = @ptrCast(@constCast(&py_nb_ifloordiv)) };
                idx += 1;
            }
            if (@hasDecl(T, "__imod__")) {
                slot_array[idx] = .{ .slot = slots.nb_inplace_remainder, .pfunc = @ptrCast(@constCast(&py_nb_imod)) };
                idx += 1;
            }
            if (@hasDecl(T, "__ipow__")) {
                slot_array[idx] = .{ .slot = slots.nb_inplace_power, .pfunc = @ptrCast(@constCast(&py_nb_ipow)) };
                idx += 1;
            }
            if (@hasDecl(T, "__ilshift__")) {
                slot_array[idx] = .{ .slot = slots.nb_inplace_lshift, .pfunc = @ptrCast(@constCast(&py_nb_ilshift)) };
                idx += 1;
            }
            if (@hasDecl(T, "__irshift__")) {
                slot_array[idx] = .{ .slot = slots.nb_inplace_rshift, .pfunc = @ptrCast(@constCast(&py_nb_irshift)) };
                idx += 1;
            }
            if (@hasDecl(T, "__iand__")) {
                slot_array[idx] = .{ .slot = slots.nb_inplace_and, .pfunc = @ptrCast(@constCast(&py_nb_iand)) };
                idx += 1;
            }
            if (@hasDecl(T, "__ior__")) {
                slot_array[idx] = .{ .slot = slots.nb_inplace_or, .pfunc = @ptrCast(@constCast(&py_nb_ior)) };
                idx += 1;
            }
            if (@hasDecl(T, "__ixor__")) {
                slot_array[idx] = .{ .slot = slots.nb_inplace_xor, .pfunc = @ptrCast(@constCast(&py_nb_ixor)) };
                idx += 1;
            }
            if (@hasDecl(T, "__imatmul__")) {
                slot_array[idx] = .{ .slot = slots.nb_inplace_matrix_multiply, .pfunc = @ptrCast(@constCast(&py_nb_imatmul)) };
                idx += 1;
            }

            return idx - start_idx;
        }
    };
}
