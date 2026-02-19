//! Iterator protocol for class generation
//!
//! Implements __iter__, __next__

const py = @import("../python.zig");
const conversion = @import("../conversion.zig");

const unwrapSignature = @import("../root.zig").unwrapSignature;

const class_mod = @import("mod.zig");
const ClassInfo = class_mod.ClassInfo;

/// Build iterator protocol for a given type
pub fn IteratorProtocol(comptime _: [*:0]const u8, comptime T: type, comptime Parent: type, comptime class_infos: []const ClassInfo) type {
    const Conv = conversion.Converter(class_infos);

    return struct {
        pub fn py_iter(self_obj: ?*py.PyObject) callconv(.c) ?*py.PyObject {
            const self: *Parent.PyWrapper = @ptrCast(@alignCast(self_obj orelse return null));
            const IterFn = @TypeOf(T.__iter__);
            const IterRetType = unwrapSignature(@typeInfo(IterFn).@"fn".return_type.?);
            const iter_rt_info = @typeInfo(IterRetType);

            if (iter_rt_info == .error_union) {
                const result = T.__iter__(self.getData()) catch |err| {
                    if (py.PyErr_Occurred() == null) {
                        const msg = @errorName(err);
                        py.PyErr_SetString(py.PyExc_RuntimeError(), msg.ptr);
                    }
                    return null;
                };
                const ResultType = @TypeOf(result);
                const result_info = @typeInfo(ResultType);
                if (result_info == .pointer and result_info.pointer.size == .one and result_info.pointer.child == T) {
                    py.Py_IncRef(self_obj);
                    return self_obj;
                } else {
                    return Conv.toPy(ResultType, result);
                }
            } else if (iter_rt_info == .optional) {
                if (T.__iter__(self.getData())) |result| {
                    const ResultType = @TypeOf(result);
                    const result_info = @typeInfo(ResultType);
                    if (result_info == .pointer and result_info.pointer.size == .one and result_info.pointer.child == T) {
                        py.Py_IncRef(self_obj);
                        return self_obj;
                    } else {
                        return Conv.toPy(ResultType, result);
                    }
                } else {
                    if (py.PyErr_Occurred() != null) return null;
                    return py.Py_RETURN_NONE();
                }
            } else {
                const result = T.__iter__(self.getData());
                const ResultType = @TypeOf(result);
                const result_info = @typeInfo(ResultType);
                if (result_info == .pointer and result_info.pointer.size == .one and result_info.pointer.child == T) {
                    py.Py_IncRef(self_obj);
                    return self_obj;
                } else {
                    return Conv.toPy(ResultType, result);
                }
            }
        }

        pub fn py_iternext(self_obj: ?*py.PyObject) callconv(.c) ?*py.PyObject {
            const self: *Parent.PyWrapper = @ptrCast(@alignCast(self_obj orelse return null));
            const NextFn = @TypeOf(T.__next__);
            const NextRetType = unwrapSignature(@typeInfo(NextFn).@"fn".return_type.?);

            if (@typeInfo(NextRetType) == .error_union) {
                const result = T.__next__(self.getData()) catch |err| {
                    if (py.PyErr_Occurred() == null) {
                        const msg = @errorName(err);
                        py.PyErr_SetString(py.PyExc_RuntimeError(), msg.ptr);
                    }
                    return null;
                };
                // Result is the payload of the error union, which should be optional
                if (@typeInfo(@TypeOf(result)) == .optional) {
                    if (result) |value| {
                        return Conv.toPy(@TypeOf(value), value);
                    } else {
                        return null; // StopIteration
                    }
                } else {
                    return Conv.toPy(@TypeOf(result), result);
                }
            } else {
                // Original behavior: __next__ returns ?T
                const result = T.__next__(self.getData());
                if (result) |value| {
                    return Conv.toPy(@TypeOf(value), value);
                } else {
                    return null;
                }
            }
        }
    };
}
