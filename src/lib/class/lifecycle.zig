//! Object lifecycle functions for class generation
//!
//! Provides py_new, py_init, py_dealloc implementations.
//!
//! Private fields: Fields starting with underscore (_) are considered private
//! and are NOT exposed to Python as __init__ arguments. They are zero-initialized.

const std = @import("std");
const py = @import("../python.zig");
const conversion = @import("../conversion.zig");
const abi = @import("../abi.zig");
const ref_mod = @import("../ref.zig");

const unwrapSignature = @import("../root.zig").unwrapSignature;
const unwrapSignatureValue = @import("../root.zig").unwrapSignatureValue;

const class_mod = @import("mod.zig");
const ClassInfo = class_mod.ClassInfo;

/// Check if a field name indicates a private field (starts with underscore)
/// Private fields are not exposed to Python as properties or __init__ arguments
fn isPrivateField(comptime name: []const u8) bool {
    return name.len > 0 and name[0] == '_';
}

/// Comptime helper: build a flattened list of (field_name, field_type, is_parent)
/// for the Python __init__ constructor of a PyOZ subclass.
/// Parent's public fields come first, then child's own public fields (excluding _parent).
fn FlatField(comptime dummy: type) type {
    _ = dummy;
    return struct {
        name: []const u8,
        field_type: type,
        is_parent: bool,
        parent_field_name: []const u8, // parent field name within _parent, or "" for child fields
    };
}

fn flattenInitFields(comptime T: type, comptime is_pyoz_sub: bool, comptime ParentType: type) []const FlatField(void) {
    comptime {
        var result: [64]FlatField(void) = undefined;
        var count: usize = 0;

        if (is_pyoz_sub) {
            // First: parent's public fields
            const parent_fields = @typeInfo(ParentType).@"struct".fields;
            for (parent_fields) |pf| {
                if (isPrivateField(pf.name)) continue;
                if (ref_mod.isRefType(pf.type)) continue;
                result[count] = .{
                    .name = pf.name,
                    .field_type = pf.type,
                    .is_parent = true,
                    .parent_field_name = pf.name,
                };
                count += 1;
            }
        }

        // Then: child's own public fields
        const child_fields = @typeInfo(T).@"struct".fields;
        for (child_fields) |cf| {
            if (isPrivateField(cf.name)) continue;
            if (ref_mod.isRefType(cf.type)) continue;
            result[count] = .{
                .name = cf.name,
                .field_type = cf.type,
                .is_parent = false,
                .parent_field_name = "",
            };
            count += 1;
        }

        const final: [count]FlatField(void) = result[0..count].*;
        return &final;
    }
}

/// Build lifecycle functions for a given type
/// In ABI3 mode, type_object_ptr is not used (we get the type from heap_type at runtime)
pub fn LifecycleBuilder(
    comptime T: type,
    comptime PyWrapper: type,
    comptime type_object_ptr: if (abi.abi3_enabled) ?*anyopaque else *py.PyTypeObject,
    comptime has_dict_support: bool,
    comptime has_weakref_support: bool,
    comptime is_builtin_subclass: bool,
    comptime class_infos: []const ClassInfo,
    comptime is_pyoz_subclass: bool,
    comptime ParentZigType: type,
) type {
    const struct_info = @typeInfo(T).@"struct";
    const fields = struct_info.fields;

    // Flattened init fields for PyOZ subclasses (parent public fields + child public fields)
    const flat_fields = flattenInitFields(T, is_pyoz_subclass, ParentZigType);

    // Count public fields (excluding private fields starting with _ and Ref fields)
    const public_field_count = comptime blk: {
        if (is_pyoz_subclass) break :blk flat_fields.len;
        var count: usize = 0;
        for (fields) |field| {
            if (isPrivateField(field.name)) continue;
            if (ref_mod.isRefType(field.type)) continue;
            count += 1;
        }
        break :blk count;
    };

    return struct {
        // Freelist support: if T declares __freelist__ = N, we cache up to N
        // deallocated objects for reuse instead of freeing them.
        const freelist_size = if (@hasDecl(T, "__freelist__")) @field(T, "__freelist__") else 0;
        const has_freelist = freelist_size > 0;

        var freelist: [freelist_size]?*py.PyObject = [_]?*py.PyObject{null} ** freelist_size;
        var freelist_count: usize = 0;

        /// __new__ - allocate object (checks freelist first)
        pub fn py_new(type_obj: ?*py.PyTypeObject, args: ?*py.PyObject, kwds: ?*py.PyObject) callconv(.c) ?*py.PyObject {
            _ = args;
            _ = kwds;
            const t = type_obj orelse return null;

            // Try to reuse from freelist
            if (has_freelist and freelist_count > 0) {
                freelist_count -= 1;
                const obj = freelist[freelist_count].?;
                freelist[freelist_count] = null;

                // Re-initialize the object
                if (comptime @hasField(py.c.PyObject, "ob_refcnt")) {
                    const base: *py.c.PyObject = @ptrCast(@alignCast(obj));
                    base.ob_refcnt = 1;
                } else {
                    const ob_ptr: *py.Py_ssize_t = @ptrCast(@alignCast(obj));
                    ob_ptr.* = 1;
                }

                const self: *PyWrapper = @ptrCast(@alignCast(obj));
                self.getData().* = std.mem.zeroes(T);
                self.initExtra();
                return obj;
            }

            const obj = py.PyType_GenericAlloc(t, 0) orelse return null;
            const self: *PyWrapper = @ptrCast(@alignCast(obj));
            self.getData().* = std.mem.zeroes(T);
            self.initExtra();
            return obj;
        }

        /// __init__ - initialize object
        /// Only public fields (not starting with _) are accepted as arguments.
        /// Private fields are zero-initialized in py_new.
        pub fn py_init(self_obj: ?*py.PyObject, args: ?*py.PyObject, kwds: ?*py.PyObject) callconv(.c) c_int {
            _ = kwds;
            const self: *PyWrapper = @ptrCast(@alignCast(self_obj orelse return -1));
            const py_args = args orelse {
                if (@hasDecl(T, "__new__")) {
                    const NewFn = @TypeOf(T.__new__);
                    const new_params = @typeInfo(NewFn).@"fn".params;
                    if (new_params.len == 0) {
                        return handleNewReturn(self, T.__new__());
                    }
                }
                if (public_field_count == 0) return 0;
                py.PyErr_SetString(py.PyExc_TypeError(), "Wrong number of arguments to __init__");
                return -1;
            };

            const arg_count = py.PyTuple_Size(py_args);

            if (@hasDecl(T, "__new__")) {
                const NewFn = @TypeOf(T.__new__);
                const new_fn_info = @typeInfo(NewFn).@"fn";
                const new_params = new_fn_info.params;

                // Count required params (non-optional) vs total
                const required_count = comptime blk: {
                    var count: usize = 0;
                    for (new_params) |p| {
                        const PT = p.type.?;
                        if (@typeInfo(PT) != .optional) count += 1;
                    }
                    break :blk count;
                };

                if (arg_count < required_count or arg_count > new_params.len) {
                    py.PyErr_SetString(py.PyExc_TypeError(), "Wrong number of arguments to __init__");
                    return -1;
                }

                const zig_args = parseNewArgs(py_args, @intCast(arg_count)) catch {
                    py.PyErr_SetString(py.PyExc_TypeError(), "Failed to convert arguments");
                    return -1;
                };

                return handleNewReturn(self, @call(.auto, T.__new__, zig_args));
            }

            if (arg_count != public_field_count) {
                py.PyErr_SetString(py.PyExc_TypeError(), "Wrong number of arguments to __init__");
                return -1;
            }

            const data = self.getData();

            if (comptime is_pyoz_subclass) {
                // Flattened init: parent public fields first, then child's own public fields
                inline for (flat_fields, 0..) |ff, i| {
                    const item = py.PyTuple_GetItem(py_args, @intCast(i)) orelse {
                        py.PyErr_SetString(py.PyExc_TypeError(), "Failed to get argument");
                        return -1;
                    };
                    const value = conversion.Converter(class_infos).fromPy(ff.field_type, item) catch {
                        py.PyErr_SetString(py.PyExc_TypeError(), "Failed to convert argument: " ++ ff.name);
                        return -1;
                    };
                    if (ff.is_parent) {
                        @field(data._parent, ff.parent_field_name) = value;
                    } else {
                        @field(data.*, ff.name) = value;
                    }
                }
            } else {
                comptime var i: usize = 0;
                inline for (fields) |field| {
                    // Skip private fields - they remain zero-initialized from py_new
                    if (comptime isPrivateField(field.name)) continue;
                    // Skip Ref fields - they are managed internally, not via __init__
                    if (comptime ref_mod.isRefType(field.type)) continue;

                    const item = py.PyTuple_GetItem(py_args, @intCast(i)) orelse {
                        py.PyErr_SetString(py.PyExc_TypeError(), "Failed to get argument");
                        return -1;
                    };
                    @field(data.*, field.name) = conversion.Converter(class_infos).fromPy(field.type, item) catch {
                        py.PyErr_SetString(py.PyExc_TypeError(), "Failed to convert argument: " ++ field.name);
                        return -1;
                    };
                    i += 1;
                }
            }

            return 0;
        }

        /// Handle the return value of a user-defined __new__ function.
        /// Supports three return conventions:
        ///   - `T`  — plain struct (always succeeds)
        ///   - `!T` — error union (error → RuntimeError, or user already set an exception)
        ///   - `?T` — optional (null → TypeError, or user already set an exception via raise*)
        fn handleNewReturn(self: *PyWrapper, raw: anytype) c_int {
            const RawRT = @TypeOf(raw);
            const result = unwrapSignatureValue(RawRT, raw);
            const RT = unwrapSignature(RawRT);
            const rt_info = @typeInfo(RT);

            if (rt_info == .error_union) {
                if (result) |value| {
                    self.getData().* = value;
                    return 0;
                } else |err| {
                    if (py.PyErr_Occurred() == null) {
                        const msg = @errorName(err);
                        py.PyErr_SetString(py.PyExc_RuntimeError(), msg.ptr);
                    }
                    return -1;
                }
            } else if (rt_info == .optional) {
                if (result) |value| {
                    self.getData().* = value;
                    return 0;
                } else {
                    if (py.PyErr_Occurred() == null) {
                        py.PyErr_SetString(py.PyExc_TypeError(), "__new__ returned null, expected an instance");
                    }
                    return -1;
                }
            } else {
                self.getData().* = result;
                return 0;
            }
        }

        fn parseNewArgs(py_args: *py.PyObject, actual_count: usize) !NewArgsTuple() {
            if (!@hasDecl(T, "__new__")) {
                return error.NoNewFunction;
            }
            const NewFn = @TypeOf(T.__new__);
            const new_params = @typeInfo(NewFn).@"fn".params;

            var result: NewArgsTuple() = undefined;
            inline for (0..new_params.len) |i| {
                const ParamType = new_params[i].type.?;
                if (i < actual_count) {
                    const item = py.PyTuple_GetItem(py_args, @intCast(i)) orelse return error.InvalidArgument;
                    result[i] = try conversion.Converter(class_infos).fromPy(ParamType, item);
                } else {
                    // Missing arg — must be optional, fill with null
                    if (@typeInfo(ParamType) == .optional) {
                        result[i] = null;
                    } else {
                        return error.MissingArgument;
                    }
                }
            }
            return result;
        }

        fn NewArgsTuple() type {
            if (!@hasDecl(T, "__new__")) {
                return std.meta.Tuple(&[_]type{});
            }
            const NewFn = @TypeOf(T.__new__);
            const new_params = @typeInfo(NewFn).@"fn".params;
            var types: [new_params.len]type = undefined;
            for (0..new_params.len) |i| {
                types[i] = new_params[i].type.?;
            }
            return std.meta.Tuple(&types);
        }

        /// __del__ - deallocate object
        pub fn py_dealloc(self_obj: ?*py.PyObject) callconv(.c) void {
            const obj = self_obj orelse return;
            const self: *PyWrapper = @ptrCast(@alignCast(obj));

            // Call user's __del__ if defined (before any cleanup)
            if (@hasDecl(T, "__del__")) {
                T.__del__(self.getData());
            }

            const obj_type = py.Py_TYPE(obj);

            if (has_weakref_support) {
                if (self.getWeakRefList()) |_| {
                    py.PyObject_ClearWeakRefs(obj);
                }
            }

            if (has_dict_support) {
                if (self.getDict()) |dict| {
                    py.Py_DecRef(dict);
                    self.setDict(null);
                }
            }

            // Release all Ref(T) fields before freelist push or object free
            inline for (fields) |field| {
                if (comptime ref_mod.isRefType(field.type)) {
                    @field(self.getData().*, field.name).clear();
                }
            }

            // Try to cache in freelist instead of freeing
            // Only for non-subclass, non-dict, non-weakref types (simple objects)
            if (has_freelist and !has_dict_support and !has_weakref_support and !is_builtin_subclass) {
                if (freelist_count < freelist_size) {
                    freelist[freelist_count] = obj;
                    freelist_count += 1;
                    return;
                }
            }

            // In ABI3 mode, PyTypeObject is opaque so we can't access tp_flags or tp_free
            // All types created via PyType_FromSpec are heap types
            if (comptime abi.abi3_enabled) {
                // Free the object
                py.PyObject_Del(self_obj);
                // Decref the type (heap types need this)
                if (obj_type) |t| {
                    py.Py_DecRef(@ptrCast(@alignCast(t)));
                }
            } else {
                const tp: ?*py.PyTypeObject = obj_type;
                const is_heaptype = if (tp) |t| (t.tp_flags & py.Py_TPFLAGS_HEAPTYPE) != 0 else false;

                if (obj_type) |t| {
                    if (t.tp_free) |free_fn| {
                        free_fn(self_obj);
                    } else {
                        py.PyObject_Del(self_obj);
                    }
                } else {
                    py.PyObject_Del(self_obj);
                }

                if (is_heaptype) {
                    if (tp) |t| {
                        py.Py_DecRef(@ptrCast(t));
                    }
                }
            }
        }

        // Expose whether this is a builtin subclass
        pub const is_builtin = is_builtin_subclass;

        // Reference to type object for other modules
        // Note: In ABI3 mode, this will panic - use Parent.getType() instead
        pub fn getTypeObject() *py.PyTypeObject {
            if (comptime abi.abi3_enabled) {
                @panic("getTypeObject not available in ABI3 mode - use Parent.getType() instead");
            } else {
                return type_object_ptr;
            }
        }
    };
}
