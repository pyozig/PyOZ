//! Iterator protocol for class generation
//!
//! Implements __iter__, __next__

const py = @import("../python.zig");
const conversion = @import("../conversion.zig");

const class_mod = @import("mod.zig");
const ClassInfo = class_mod.ClassInfo;

/// Build iterator protocol for a given type
pub fn IteratorProtocol(comptime _: [*:0]const u8, comptime T: type, comptime Parent: type, comptime class_infos: []const ClassInfo) type {
    const Conv = conversion.Converter(class_infos);

    return struct {
        pub fn py_iter(self_obj: ?*py.PyObject) callconv(.c) ?*py.PyObject {
            const self: *Parent.PyWrapper = @ptrCast(@alignCast(self_obj orelse return null));
            const result = T.__iter__(self.getData());
            const ResultType = @TypeOf(result);

            const result_info = @typeInfo(ResultType);
            if (result_info == .pointer and result_info.pointer.child == T) {
                py.Py_IncRef(self_obj);
                return self_obj;
            } else {
                return Conv.toPy(ResultType, result);
            }
        }

        pub fn py_iternext(self_obj: ?*py.PyObject) callconv(.c) ?*py.PyObject {
            const self: *Parent.PyWrapper = @ptrCast(@alignCast(self_obj orelse return null));
            const result = T.__next__(self.getData());
            if (result) |value| {
                return Conv.toPy(@TypeOf(value), value);
            } else {
                return null;
            }
        }
    };
}
