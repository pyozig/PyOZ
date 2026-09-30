//! Object lifecycle functions for class generation
//!
//! Provides py_new, py_init, py_dealloc implementations.
//!
//! Private fields: Fields starting with underscore (_) are considered private
//! and are NOT exposed to Python as __init__ arguments. They are initialized
//! using their default values if provided, zero-initialized if the type supports
//! it, or left undefined (to be set by __new__).

const std = @import("std");
const py = @import("../python.zig");
const conversion = @import("../conversion.zig");
const abi = @import("../abi.zig");
const ref_mod = @import("../ref.zig");

const errors_mod = @import("../errors.zig");
const unwrapSignature = @import("../root.zig").unwrapSignature;
const unwrapSignatureValue = @import("../root.zig").unwrapSignatureValue;

const class_mod = @import("mod.zig");
const wrappers_mod = @import("../wrappers.zig");
const source_parser = @import("../source_parser.zig");
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
        /// The struct field declares a default value: optional in the constructor
        has_default: bool,
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
                    .has_default = pf.default_value_ptr != null,
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
                .has_default = cf.default_value_ptr != null,
            };
            count += 1;
        }

        const final: [count]FlatField(void) = result[0..count].*;
        return &final;
    }
}

/// Build a default value for type T, using field defaults where available,
/// and undefined for private fields that cannot be zero-initialized.
/// This avoids the compile error from std.mem.zeroes on types with
/// non-nullable pointers (e.g. std.heap.ArenaAllocator).
fn initDefault(comptime T: type) T {
    const fields = @typeInfo(T).@"struct".fields;
    var result: T = undefined;
    inline for (fields) |field| {
        if (field.defaultValue()) |default_val| {
            @field(result, field.name) = default_val;
        } else if (comptime canZeroInit(field.type)) {
            @field(result, field.name) = std.mem.zeroes(field.type);
        }
        // else: leave as undefined — __new__ must initialize it
    }
    return result;
}

/// Check at comptime whether a type can be safely zero-initialized via std.mem.zeroes.
/// Returns false for types containing non-nullable, non-allowzero pointers.
fn canZeroInit(comptime T: type) bool {
    return switch (@typeInfo(T)) {
        .pointer => |p| p.is_allowzero,
        .optional => true,
        .@"struct" => |s| {
            for (s.fields) |field| {
                if (!canZeroInit(field.type)) return false;
            }
            return true;
        },
        .@"union" => |u| {
            for (u.fields) |field| {
                if (!canZeroInit(field.type)) return false;
            }
            return true;
        },
        .@"fn" => false,
        else => true,
    };
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

    return struct {
        // Freelist support: if T declares __freelist__ = N, we cache up to N
        // deallocated objects for reuse instead of freeing them.
        const freelist_size = if (@hasDecl(T, "__freelist__")) @field(T, "__freelist__") else 0;
        // Disabled on free-threaded builds: a shared freelist would race, and
        // re-arming a cached object's header needs its owning thread id
        // (ob_tid) and split refcounts, which CPython exposes no public API for.
        // The per-thread mimalloc heaps of free-threaded CPython fill this role.
        const has_freelist = freelist_size > 0 and !py.types.gil_disabled;

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
                self.getData().* = comptime initDefault(T);
                self.setInitialized(false);
                self.initExtra();
                return obj;
            }

            const obj = py.PyType_GenericAlloc(t, 0) orelse return null;
            const self: *PyWrapper = @ptrCast(@alignCast(obj));
            self.getData().* = comptime initDefault(T);
            // _initialized is already 0 from GenericAlloc zero-fill
            self.initExtra();
            return obj;
        }

        /// __init__ - initialize object
        /// Only public fields (not starting with _) are accepted as arguments.
        /// Private fields are initialized in py_new using defaults or undefined.
        /// Name used in constructor error messages ("Point() got ...").
        const display_name: []const u8 = blk: {
            for (class_infos) |info| {
                if (info.zig_type == T) break :blk std.mem.span(info.name);
            }
            const full = @typeName(T);
            break :blk if (std.mem.lastIndexOfScalar(u8, full, '.')) |dot| full[dot + 1 ..] else full;
        };

        const has_new = @hasDecl(T, "__new__");
        const new_params = if (has_new) @typeInfo(@TypeOf(T.__new__)).@"fn".params else &.{};

        /// `__new__(args: pyoz.Args(S))`: names and defaults come from S.
        const new_takes_args = has_new and new_params.len == 1 and wrappers_mod.isArgs(new_params[0].type.?);

        /// Number of positional constructor parameters (not used with pyoz.Args)
        const param_count = if (has_new) new_params.len else flat_fields.len;

        /// Keyword names of the constructor parameters, in positional order:
        /// the public fields, or the parameters of `__new__`. null when
        /// `__new__` takes parameters whose names are unknown (no
        /// `__new____params__` and no source text); keywords are then rejected.
        const param_names: ?[param_count][]const u8 = blk: {
            @setEvalBranchQuota(10000);
            var names: [param_count][]const u8 = undefined;
            if (!has_new) {
                for (flat_fields, 0..) |ff, i| names[i] = ff.name;
                break :blk names;
            }
            if (new_params.len == 0 or new_takes_args) break :blk names;
            const list: []const u8 = if (@hasDecl(T, "__new____params__"))
                std.mem.span(@as([*:0]const u8, T.__new____params__))
            else if (class_mod.lookupParsedSource(class_infos, T)) |src|
                source_parser.getMethodParams(src, display_name, "__new__") orelse break :blk null
            else
                break :blk null;
            var it = std.mem.splitScalar(u8, list, ',');
            for (&names) |*name| {
                name.* = std.mem.trim(u8, it.next() orelse break :blk null, " ");
                if (name.len == 0) break :blk null;
            }
            if (it.next() != null) break :blk null;
            break :blk names;
        };

        /// Whether parameter `i` may be omitted: a field with a default value,
        /// or a `?T` parameter of `__new__`.
        fn paramOptional(comptime i: usize) bool {
            return if (has_new) @typeInfo(new_params[i].type.?) == .optional else flat_fields[i].has_default;
        }

        /// Collect the constructor arguments into one slot per parameter
        /// (borrowed references; null = not given), following Python's rules for
        /// positional and keyword arguments. Returns false with a TypeError set.
        fn collectArgs(items: *[param_count]?*py.PyObject, args: ?*py.PyObject, kwds: ?*py.PyObject) bool {
            const npos: usize = if (args) |a| @intCast(py.PyTuple_Size(a)) else 0;
            if (npos > param_count) {
                _ = py.c.PyErr_Format(py.PyExc_TypeError(), display_name ++ std.fmt.comptimePrint("() takes at most {d} arguments (%zd given)", .{param_count}), @as(py.Py_ssize_t, @intCast(npos)));
                return false;
            }
            for (items[0..npos], 0..) |*item, i| item.* = py.PyTuple_GetItem(args.?, @intCast(i));

            const kw = kwds orelse return true;
            const kw_count = py.PyDict_Size(kw);
            if (kw_count == 0) return true;
            if (comptime param_names == null) {
                py.PyErr_SetString(py.PyExc_TypeError(), display_name ++ "() takes no keyword arguments");
                return false;
            }
            const names = comptime param_names.?;

            var used: py.Py_ssize_t = 0;
            inline for (names, 0..) |name, i| {
                if (py.PyDict_GetItemString(kw, class_mod.comptimeStrZ(name))) |value| {
                    if (i < npos) {
                        py.PyErr_SetString(py.PyExc_TypeError(), display_name ++ "() got multiple values for argument '" ++ name ++ "'");
                        return false;
                    }
                    used += 1;
                    items[i] = value;
                }
            }
            if (used < kw_count) {
                var pos: py.Py_ssize_t = 0;
                var key: ?*py.PyObject = null;
                var value: ?*py.PyObject = null;
                while (py.PyDict_Next(kw, &pos, &key, &value) != 0) {
                    var len: py.Py_ssize_t = 0;
                    const key_str: ?[*]const u8 = py.PyUnicode_AsUTF8AndSize(key.?, &len);
                    if (key_str == null) py.PyErr_Clear();
                    const known = if (key_str) |k| inline for (names) |name| {
                        if (std.mem.eql(u8, name, k[0..@intCast(len)])) break true;
                    } else false else false;
                    if (!known) {
                        _ = py.c.PyErr_Format(py.PyExc_TypeError(), display_name ++ "() got an unexpected keyword argument '%U'", key);
                        return false;
                    }
                }
            }
            return true;
        }

        /// Set the error for a required parameter that was not given.
        fn missingArgument(comptime i: usize) void {
            if (comptime param_names) |names| {
                py.PyErr_SetString(py.PyExc_TypeError(), display_name ++ "() missing required argument '" ++ names[i] ++ "'");
            } else {
                py.PyErr_SetString(py.PyExc_TypeError(), display_name ++ std.fmt.comptimePrint("() missing required argument {d}", .{i + 1}));
            }
        }

        /// Set the error for an argument of the wrong type, unless the
        /// conversion already raised something more specific.
        fn badArgument(comptime i: usize) void {
            if (py.PyErr_Occurred() != null) return;
            if (comptime param_names) |names| {
                py.PyErr_SetString(py.PyExc_TypeError(), display_name ++ "() argument '" ++ names[i] ++ "' has the wrong type");
            } else {
                py.PyErr_SetString(py.PyExc_TypeError(), display_name ++ std.fmt.comptimePrint("() argument {d} has the wrong type", .{i + 1}));
            }
        }

        pub fn py_init(self_obj: ?*py.PyObject, args: ?*py.PyObject, kwds: ?*py.PyObject) callconv(.c) c_int {
            const self: *PyWrapper = @ptrCast(@alignCast(self_obj orelse return -1));
            const Conv = conversion.Converter(class_infos);

            // __new__(args: pyoz.Args(S)): same parsing as keyword functions
            if (comptime new_takes_args) {
                const ArgsWrapper = new_params[0].type.?;
                var parsed = wrappers_mod.parseNamedArgs(ArgsWrapper.ArgsStruct, class_infos, display_name, args, kwds) orelse return -1;
                defer wrappers_mod.releaseNamedArgs(ArgsWrapper.ArgsStruct, &parsed);
                return handleNewReturn(self, T.__new__(.{ .value = parsed }));
            }

            var items: [param_count]?*py.PyObject = @splat(null);
            if (!collectArgs(&items, args, kwds)) return -1;

            if (comptime has_new) {
                var zig_args: NewArgsTuple() = undefined;
                inline for (new_params, 0..) |param, i| {
                    if (items[i]) |item| {
                        zig_args[i] = Conv.fromPy(param.type.?, item) catch {
                            badArgument(i);
                            return -1;
                        };
                    } else if (comptime paramOptional(i)) {
                        zig_args[i] = null;
                    } else {
                        missingArgument(i);
                        return -1;
                    }
                }
                return handleNewReturn(self, @call(.auto, T.__new__, zig_args));
            }

            // Default constructor: one argument per public field (parent
            // fields first for a PyOZ subclass); fields that declare a default
            // value may be omitted.
            const data = self.getData();
            inline for (flat_fields, 0..) |ff, i| {
                const Owner = if (ff.is_parent) ParentZigType else T;
                const field_name = if (ff.is_parent) ff.parent_field_name else ff.name;
                const target = if (ff.is_parent) &@field(data._parent, field_name) else &@field(data.*, field_name);
                if (items[i]) |item| {
                    target.* = Conv.fromPy(ff.field_type, item) catch {
                        badArgument(i);
                        return -1;
                    };
                } else if (comptime ff.has_default) {
                    target.* = comptime std.meta.fieldInfo(Owner, std.meta.stringToEnum(std.meta.FieldEnum(Owner), field_name).?).defaultValue().?;
                } else {
                    missingArgument(i);
                    return -1;
                }
            }

            self.setInitialized(true);
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
                    self.setInitialized(true);
                    return 0;
                } else |err| {
                    if (py.PyErr_Occurred() == null) {
                        const msg = @errorName(err);
                        py.PyErr_SetString(errors_mod.mapWellKnownError(msg), msg.ptr);
                    }
                    return -1;
                }
            } else if (rt_info == .optional) {
                if (result) |value| {
                    self.getData().* = value;
                    self.setInitialized(true);
                    return 0;
                } else {
                    if (py.PyErr_Occurred() == null) {
                        py.PyErr_SetString(py.PyExc_TypeError(), "__new__ returned null, expected an instance");
                    }
                    return -1;
                }
            } else {
                self.getData().* = result;
                self.setInitialized(true);
                return 0;
            }
        }

        /// Argument tuple for calling `__new__` with positional parameters.
        fn NewArgsTuple() type {
            var types: [new_params.len]type = undefined;
            for (new_params, 0..) |param, i| types[i] = param.type.?;
            return std.meta.Tuple(&types);
        }

        /// __del__ - deallocate object
        pub fn py_dealloc(self_obj: ?*py.PyObject) callconv(.c) void {
            const obj = self_obj orelse return;
            const self: *PyWrapper = @ptrCast(@alignCast(obj));

            // Call user's __del__ only if the object was successfully initialized.
            // If __new__ failed (returned error/null), the object was never fully
            // constructed, so __del__ must not run — matching Python semantics.
            if (@hasDecl(T, "__del__") and self.isInitialized()) {
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
