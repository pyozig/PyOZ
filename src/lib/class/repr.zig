//! Repr/str/hash protocol for class generation
//!
//! Implements __repr__, __str__, __hash__

const std = @import("std");
const py = @import("../python.zig");
const conversion = @import("../conversion.zig");

const class_mod = @import("mod.zig");
const ClassInfo = class_mod.ClassInfo;

/// Check if a field name indicates a private field (starts with underscore)
fn isPrivateField(comptime field_name: []const u8) bool {
    return field_name.len > 0 and field_name[0] == '_';
}

/// Build repr protocol for a given type
pub fn ReprProtocol(comptime name: [*:0]const u8, comptime T: type, comptime Parent: type, comptime class_infos: []const ClassInfo) type {
    const struct_info = @typeInfo(T).@"struct";
    const fields = struct_info.fields;

    // Pre-compute the opening "ClassName(" string at comptime as a null-terminated literal
    const name_open: [*:0]const u8 = comptime blk: {
        const s = std.mem.span(name) ++ "(";
        const with_sentinel: *const [s.len:0]u8 = @ptrCast(s.ptr);
        break :blk with_sentinel;
    };

    return struct {
        /// Default __repr__ - builds "ClassName(field1=val1, field2=val2)"
        pub fn py_repr(self_obj: ?*py.PyObject) callconv(.c) ?*py.PyObject {
            const self: *Parent.PyWrapper = @ptrCast(@alignCast(self_obj orelse return null));
            const data = self.getDataConst();

            // Start with "ClassName("
            var result: ?*py.PyObject = py.PyUnicode_FromString(name_open);
            if (result == null) return null;

            comptime var is_first = true;
            inline for (fields) |field| {
                // Skip private fields
                if (comptime isPrivateField(field.name)) continue;

                // Add separator
                if (comptime !is_first) {
                    const sep = py.PyUnicode_FromString(", ") orelse {
                        py.Py_DecRef(result.?);
                        return null;
                    };
                    const new_result = py.PyUnicode_Concat(result.?, sep);
                    py.Py_DecRef(sep);
                    py.Py_DecRef(result.?);
                    result = new_result;
                    if (result == null) return null;
                }
                is_first = false;

                // Add "field_name="
                const field_label = py.PyUnicode_FromString(field.name ++ "=") orelse {
                    py.Py_DecRef(result.?);
                    return null;
                };
                const with_label = py.PyUnicode_Concat(result.?, field_label);
                py.Py_DecRef(field_label);
                py.Py_DecRef(result.?);
                result = with_label;
                if (result == null) return null;

                // Get field value, repr it, and append
                const value = @field(data.*, field.name);
                const val_str: ?*py.PyObject = blk: {
                    const py_value = conversion.Converter(class_infos).toPy(field.type, value) orelse break :blk null;
                    const repr_obj = py.PyObject_Repr(py_value);
                    py.Py_DecRef(py_value);
                    break :blk repr_obj;
                };
                const val_repr = val_str orelse (py.PyUnicode_FromString("?") orelse {
                    py.Py_DecRef(result.?);
                    return null;
                });

                const with_val = py.PyUnicode_Concat(result.?, val_repr);
                py.Py_DecRef(val_repr);
                py.Py_DecRef(result.?);
                result = with_val;
                if (result == null) return null;
            }

            // Close with ")"
            const closing = py.PyUnicode_FromString(")") orelse {
                py.Py_DecRef(result.?);
                return null;
            };
            const final_result = py.PyUnicode_Concat(result.?, closing);
            py.Py_DecRef(closing);
            py.Py_DecRef(result.?);
            return final_result;
        }

        /// Custom __repr__ - calls T.__repr__
        pub fn py_magic_repr(self_obj: ?*py.PyObject) callconv(.c) ?*py.PyObject {
            const self: *Parent.PyWrapper = @ptrCast(@alignCast(self_obj orelse return null));
            const result = T.__repr__(self.getDataConst());
            return conversion.Converter(class_infos).toPy(@TypeOf(result), result);
        }

        /// Custom __str__ - calls T.__str__
        pub fn py_magic_str(self_obj: ?*py.PyObject) callconv(.c) ?*py.PyObject {
            const self: *Parent.PyWrapper = @ptrCast(@alignCast(self_obj orelse return null));
            const result = T.__str__(self.getDataConst());
            return conversion.Converter(class_infos).toPy(@TypeOf(result), result);
        }

        /// Custom __hash__ - calls T.__hash__
        pub fn py_hash(self_obj: ?*py.PyObject) callconv(.c) py.c.Py_hash_t {
            const self: *Parent.PyWrapper = @ptrCast(@alignCast(self_obj orelse return -1));
            return @intCast(T.__hash__(self.getDataConst()));
        }
    };
}
