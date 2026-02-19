//! Comparison protocol for class generation
//!
//! Implements __eq__, __ne__, __lt__, __le__, __gt__, __ge__

const py = @import("../python.zig");
const conversion = @import("../conversion.zig");
const class_mod = @import("mod.zig");
const ClassInfo = class_mod.ClassInfo;
const unwrapSignature = @import("../root.zig").unwrapSignature;

// Rich comparison operation codes
pub const Py_LT: c_int = 0;
pub const Py_LE: c_int = 1;
pub const Py_EQ: c_int = 2;
pub const Py_NE: c_int = 3;
pub const Py_GT: c_int = 4;
pub const Py_GE: c_int = 5;

/// Build comparison protocol for a given type
pub fn ComparisonProtocol(comptime T: type, comptime Parent: type, comptime class_infos: []const ClassInfo) type {
    const Conv = conversion.Converter(class_infos);

    return struct {
        pub fn hasComparisonMethods() bool {
            return @hasDecl(T, "__eq__") or @hasDecl(T, "__ne__") or
                @hasDecl(T, "__lt__") or @hasDecl(T, "__le__") or
                @hasDecl(T, "__gt__") or @hasDecl(T, "__ge__");
        }

        /// Get the "other" parameter type from a comparison method's signature.
        /// If the second param is *const T (same type), we use the fast path.
        /// Otherwise, we use the converter to extract the argument.
        fn getOtherParamType(comptime method_name: []const u8) ?type {
            if (!@hasDecl(T, method_name)) return null;
            const func = @field(T, method_name);
            const params = @typeInfo(@TypeOf(func)).@"fn".params;
            if (params.len < 2) return null;
            return params[1].type.?;
        }

        /// Check if a comparison method's "other" param is the same wrapper type (fast path).
        fn otherIsSelf(comptime method_name: []const u8) bool {
            const OtherType = getOtherParamType(method_name) orelse return true;
            return OtherType == *const T;
        }

        /// Convert other_obj to the expected argument type using the converter.
        /// Returns null if conversion fails (returns NotImplemented to caller).
        fn convertOther(comptime OtherType: type, other_obj: *py.PyObject) ?OtherType {
            // Fast path: same type as self
            if (OtherType == *const T) {
                if (!py.PyObject_TypeCheck(other_obj, Parent.getTypeObjectPtr())) {
                    return null;
                }
                const other: *Parent.PyWrapper = @ptrCast(@alignCast(other_obj));
                return other.getDataConst();
            }
            // Use the class-aware converter for cross-class types
            return Conv.fromPy(OtherType, other_obj) catch return null;
        }

        /// Call a comparison method, handling both same-type and cross-class cases.
        /// Supports plain bool, !bool (error union), and ?bool (optional) returns.
        fn callCmp(comptime method_name: []const u8, self_data: *const T, other_obj: *py.PyObject) ?bool {
            const OtherType = getOtherParamType(method_name) orelse return null;
            const other = convertOther(OtherType, other_obj) orelse return null;
            const CmpFn = @TypeOf(@field(T, method_name));
            const CmpRetType = unwrapSignature(@typeInfo(CmpFn).@"fn".return_type.?);
            if (@typeInfo(CmpRetType) == .error_union) {
                const result = @field(T, method_name)(self_data, other) catch |err| {
                    if (py.PyErr_Occurred() == null) {
                        const msg = @errorName(err);
                        py.PyErr_SetString(py.PyExc_RuntimeError(), msg.ptr);
                    }
                    return null;
                };
                return result;
            } else if (@typeInfo(CmpRetType) == .optional) {
                return @field(T, method_name)(self_data, other);
            } else {
                return @field(T, method_name)(self_data, other);
            }
        }

        pub fn py_richcompare(self_obj: ?*py.PyObject, other_obj: ?*py.PyObject, op: c_int) callconv(.c) ?*py.PyObject {
            const self: *Parent.PyWrapper = @ptrCast(@alignCast(self_obj orelse return null));
            const other = other_obj orelse return py.Py_NotImplemented();
            const self_data = self.getDataConst();

            const result: ?bool = switch (op) {
                Py_EQ => if (@hasDecl(T, "__eq__")) callCmp("__eq__", self_data, other) else null,
                Py_NE => if (@hasDecl(T, "__ne__"))
                    callCmp("__ne__", self_data, other)
                else if (@hasDecl(T, "__eq__"))
                    if (callCmp("__eq__", self_data, other)) |eq| !eq else null
                else
                    null,
                Py_LT => if (@hasDecl(T, "__lt__")) callCmp("__lt__", self_data, other) else null,
                Py_LE => if (@hasDecl(T, "__le__"))
                    callCmp("__le__", self_data, other)
                else if (@hasDecl(T, "__lt__") and @hasDecl(T, "__eq__")) blk: {
                    const lt = callCmp("__lt__", self_data, other) orelse break :blk null;
                    const eq = callCmp("__eq__", self_data, other) orelse break :blk null;
                    break :blk lt or eq;
                } else null,
                Py_GT => if (@hasDecl(T, "__gt__"))
                    callCmp("__gt__", self_data, other)
                else if (@hasDecl(T, "__lt__") and otherIsSelf("__lt__")) blk: {
                    // Fallback: a > b  ↔  b < a — only works when other is same type
                    const other_wrapper: *Parent.PyWrapper = @ptrCast(@alignCast(other));
                    if (!py.PyObject_TypeCheck(other, Parent.getTypeObjectPtr())) break :blk null;
                    break :blk T.__lt__(other_wrapper.getDataConst(), self_data);
                } else null,
                Py_GE => if (@hasDecl(T, "__ge__"))
                    callCmp("__ge__", self_data, other)
                else if (@hasDecl(T, "__le__") and otherIsSelf("__le__")) blk: {
                    // Fallback: a >= b  ↔  b <= a — only works when other is same type
                    const other_wrapper: *Parent.PyWrapper = @ptrCast(@alignCast(other));
                    if (!py.PyObject_TypeCheck(other, Parent.getTypeObjectPtr())) break :blk null;
                    break :blk T.__le__(other_wrapper.getDataConst(), self_data);
                } else if (@hasDecl(T, "__gt__") and @hasDecl(T, "__eq__")) blk: {
                    const gt = callCmp("__gt__", self_data, other) orelse break :blk null;
                    const eq = callCmp("__eq__", self_data, other) orelse break :blk null;
                    break :blk gt or eq;
                } else null,
                else => null,
            };

            if (result) |r| {
                return py.Py_RETURN_BOOL(r);
            }
            return py.Py_NotImplemented();
        }
    };
}
