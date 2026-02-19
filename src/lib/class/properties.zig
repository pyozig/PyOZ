//! Properties (getset) generation for class generation
//!
//! Generates getters and setters for struct fields and computed properties
//! Supports both get_X/set_X naming convention and pyoz.property() declarations
//!
//! Private fields: Fields starting with underscore (_) are considered private
//! and are NOT exposed to Python as properties or __init__ arguments.

const std = @import("std");
const py = @import("../python.zig");
const conversion = @import("../conversion.zig");
const ref_mod = @import("../ref.zig");

const unwrapSignature = @import("../root.zig").unwrapSignature;

const class_mod = @import("mod.zig");
const ClassInfo = class_mod.ClassInfo;

/// Check if a field name indicates a private field (starts with underscore)
/// Private fields are not exposed to Python as properties or __init__ arguments
fn isPrivateField(comptime name: []const u8) bool {
    return name.len > 0 and name[0] == '_';
}

/// Check if a declaration is a pyoz.property (checks the actual type value, not metatype)
fn isPyozPropertyDecl(comptime T: type, comptime decl_name: []const u8) bool {
    const DeclType = @TypeOf(@field(T, decl_name));
    // If this declaration is a type (e.g., pub const foo = SomeType)
    if (DeclType == type) {
        const ActualType = @field(T, decl_name);
        if (@hasDecl(ActualType, "__pyoz_property__")) {
            return ActualType.__pyoz_property__;
        }
    }
    return false;
}

/// Build properties for a given type
pub fn PropertiesBuilder(comptime T: type, comptime Parent: type, comptime class_infos: []const ClassInfo) type {
    const struct_info = @typeInfo(T).@"struct";
    const fields = struct_info.fields;

    return struct {
        // Check if struct has custom getter or setter
        pub fn hasCustomGetter(comptime field_name: []const u8) bool {
            const getter_name = "get_" ++ field_name;
            return @hasDecl(T, getter_name);
        }

        pub fn hasCustomSetter(comptime field_name: []const u8) bool {
            const setter_name = "set_" ++ field_name;
            return @hasDecl(T, setter_name);
        }

        // Count computed properties (get_X style)
        fn countComputedProperties() usize {
            const type_decls = @typeInfo(T).@"struct".decls;
            var count: usize = 0;
            for (type_decls) |decl| {
                if (decl.name.len > 4 and std.mem.startsWith(u8, decl.name, "get_")) {
                    // Must be a function, not a constant (e.g. get_error__doc__)
                    if (@typeInfo(@TypeOf(@field(T, decl.name))) != .@"fn") continue;
                    const prop_name = decl.name[4..];
                    var is_field = false;
                    for (fields) |field| {
                        if (std.mem.eql(u8, field.name, prop_name)) {
                            is_field = true;
                            break;
                        }
                    }
                    if (!is_field) {
                        count += 1;
                    }
                }
            }
            return count;
        }

        // Count pyoz.property() declarations
        fn countPyozProperties() usize {
            const type_decls = @typeInfo(T).@"struct".decls;
            var count: usize = 0;
            for (type_decls) |decl| {
                if (isPyozPropertyDecl(T, decl.name)) {
                    count += 1;
                }
            }
            return count;
        }

        // Count public fields (excluding private fields starting with _ and Ref fields)
        fn countPublicFields() usize {
            var count: usize = 0;
            for (fields) |field| {
                if (isPrivateField(field.name)) continue;
                if (ref_mod.isRefType(field.type)) continue;
                count += 1;
            }
            return count;
        }

        pub const public_fields_count = countPublicFields();
        pub const computed_props_count = countComputedProperties();
        pub const pyoz_props_count = countPyozProperties();
        pub const total_getset_count = public_fields_count + computed_props_count + pyoz_props_count + 1;

        /// Check if class is frozen
        pub fn isFrozen() bool {
            if (@hasDecl(T, "__frozen__")) {
                const FrozenType = @TypeOf(T.__frozen__);
                if (FrozenType == bool) {
                    return T.__frozen__;
                }
            }
            return false;
        }

        /// Get property docstring
        pub fn getPropertyDoc(comptime prop_name: []const u8) ?[*:0]const u8 {
            const doc_name = prop_name ++ "__doc__";
            if (@hasDecl(T, doc_name)) {
                const DocType = @TypeOf(@field(T, doc_name));
                if (DocType != [*:0]const u8) {
                    @compileError(doc_name ++ " must be declared as [*:0]const u8");
                }
                return @field(T, doc_name);
            }
            return null;
        }

        pub var getset: [total_getset_count]py.PyGetSetDef = blk: {
            var gs: [total_getset_count]py.PyGetSetDef = undefined;

            // Field-based getters/setters (skip private fields starting with _ and Ref fields)
            var field_idx: usize = 0;
            for (fields) |field| {
                // Skip private fields
                if (isPrivateField(field.name)) continue;
                // Skip Ref fields - they are internal references, not Python properties
                if (ref_mod.isRefType(field.type)) continue;

                gs[field_idx] = .{
                    .name = @ptrCast(field.name.ptr),
                    .get = @ptrCast(generateGetter(field.name, field.type)),
                    .set = if (isFrozen()) null else @ptrCast(generateSetter(field.name, field.type)),
                    .doc = getPropertyDoc(field.name),
                    .closure = null,
                };
                field_idx += 1;
            }

            // Computed properties (get_X/set_X style)
            var comp_idx: usize = public_fields_count;
            const type_decls = @typeInfo(T).@"struct".decls;
            for (type_decls) |decl| {
                if (decl.name.len > 4 and std.mem.startsWith(u8, decl.name, "get_")) {
                    // Must be a function, not a constant (e.g. get_error__doc__)
                    if (@typeInfo(@TypeOf(@field(T, decl.name))) != .@"fn") continue;
                    const prop_name = decl.name[4..];
                    var is_field = false;
                    for (fields) |field| {
                        if (std.mem.eql(u8, field.name, prop_name)) {
                            is_field = true;
                            break;
                        }
                    }
                    if (!is_field) {
                        gs[comp_idx] = .{
                            .name = @ptrCast(prop_name.ptr),
                            .get = @ptrCast(generateComputedGetter(prop_name)),
                            .set = if (isFrozen()) null else @ptrCast(generateComputedSetter(prop_name)),
                            .doc = getPropertyDoc(prop_name),
                            .closure = null,
                        };
                        comp_idx += 1;
                    }
                }
            }

            // pyoz.property() declarations
            for (type_decls) |decl| {
                if (isPyozPropertyDecl(T, decl.name)) {
                    gs[comp_idx] = .{
                        .name = @ptrCast(decl.name.ptr),
                        .get = @ptrCast(generatePyozPropertyGetter(decl.name)),
                        .set = if (isFrozen()) null else @ptrCast(generatePyozPropertySetter(decl.name)),
                        .doc = getPyozPropertyDoc(decl.name),
                        .closure = null,
                    };
                    comp_idx += 1;
                }
            }

            // Sentinel
            gs[total_getset_count - 1] = .{
                .name = null,
                .get = null,
                .set = null,
                .doc = null,
                .closure = null,
            };

            break :blk gs;
        };

        fn generateGetter(comptime field_name: []const u8, comptime FieldType: type) *const fn (?*py.PyObject, ?*anyopaque) callconv(.c) ?*py.PyObject {
            if (comptime hasCustomGetter(field_name)) {
                return struct {
                    fn get(self_obj: ?*py.PyObject, closure: ?*anyopaque) callconv(.c) ?*py.PyObject {
                        _ = closure;
                        const self: *Parent.PyWrapper = @ptrCast(@alignCast(self_obj orelse return null));
                        const custom_getter = @field(T, "get_" ++ field_name);
                        const result = custom_getter(self.getDataConst());
                        const py_result = conversion.Converter(class_infos).toPy(@TypeOf(result), result);
                        // Ensure an exception is set if conversion failed
                        if (py_result == null and py.PyErr_Occurred() == null) {
                            py.PyErr_SetString(py.PyExc_TypeError(), "Cannot convert field '" ++ field_name ++ "' to Python object");
                        }
                        return py_result;
                    }
                }.get;
            }
            return struct {
                fn get(self_obj: ?*py.PyObject, closure: ?*anyopaque) callconv(.c) ?*py.PyObject {
                    _ = closure;
                    const self: *Parent.PyWrapper = @ptrCast(@alignCast(self_obj orelse return null));
                    const value = @field(self.getDataConst().*, field_name);
                    const py_result = conversion.Converter(class_infos).toPy(FieldType, value);
                    // Ensure an exception is set if conversion failed
                    if (py_result == null and py.PyErr_Occurred() == null) {
                        py.PyErr_SetString(py.PyExc_TypeError(), "Cannot convert field '" ++ field_name ++ "' to Python object");
                    }
                    return py_result;
                }
            }.get;
        }

        fn generateSetter(comptime field_name: []const u8, comptime FieldType: type) *const fn (?*py.PyObject, ?*py.PyObject, ?*anyopaque) callconv(.c) c_int {
            if (comptime hasCustomSetter(field_name)) {
                return struct {
                    fn set(self_obj: ?*py.PyObject, value: ?*py.PyObject, closure: ?*anyopaque) callconv(.c) c_int {
                        _ = closure;
                        const self: *Parent.PyWrapper = @ptrCast(@alignCast(self_obj orelse return -1));
                        const py_value = value orelse {
                            py.PyErr_SetString(py.PyExc_AttributeError(), "Cannot delete attribute");
                            return -1;
                        };
                        const custom_setter = @field(T, "set_" ++ field_name);
                        const SetterType = @TypeOf(custom_setter);
                        const setter_info = @typeInfo(SetterType).@"fn";
                        const ValueType = setter_info.params[1].type.?;
                        const converted = conversion.Converter(class_infos).fromPy(ValueType, py_value) catch {
                            py.PyErr_SetString(py.PyExc_TypeError(), "Failed to convert value for: " ++ field_name);
                            return -1;
                        };
                        const RetType = unwrapSignature(setter_info.return_type orelse void);
                        if (@typeInfo(RetType) == .error_union) {
                            custom_setter(self.getData(), converted) catch |err| {
                                if (py.PyErr_Occurred() == null) {
                                    const msg = @errorName(err);
                                    py.PyErr_SetString(py.PyExc_ValueError(), msg.ptr);
                                }
                                return -1;
                            };
                        } else if (@typeInfo(RetType) == .optional) {
                            if (custom_setter(self.getData(), converted) == null) {
                                if (py.PyErr_Occurred() == null) {
                                    py.PyErr_SetString(py.PyExc_ValueError(), "setter failed for: " ++ field_name);
                                }
                                return -1;
                            }
                        } else {
                            custom_setter(self.getData(), converted);
                        }
                        return 0;
                    }
                }.set;
            }
            return struct {
                fn set(self_obj: ?*py.PyObject, value: ?*py.PyObject, closure: ?*anyopaque) callconv(.c) c_int {
                    _ = closure;
                    const self: *Parent.PyWrapper = @ptrCast(@alignCast(self_obj orelse return -1));
                    const py_value = value orelse {
                        py.PyErr_SetString(py.PyExc_AttributeError(), "Cannot delete attribute");
                        return -1;
                    };
                    @field(self.getData().*, field_name) = conversion.Converter(class_infos).fromPy(FieldType, py_value) catch {
                        py.PyErr_SetString(py.PyExc_TypeError(), "Failed to convert value for: " ++ field_name);
                        return -1;
                    };
                    return 0;
                }
            }.set;
        }

        fn generateComputedGetter(comptime prop_name: []const u8) *const fn (?*py.PyObject, ?*anyopaque) callconv(.c) ?*py.PyObject {
            const getter_name = "get_" ++ prop_name;
            return struct {
                fn get(self_obj: ?*py.PyObject, closure: ?*anyopaque) callconv(.c) ?*py.PyObject {
                    _ = closure;
                    const self: *Parent.PyWrapper = @ptrCast(@alignCast(self_obj orelse return null));
                    const getter = @field(T, getter_name);
                    const result = getter(self.getDataConst());
                    return conversion.Converter(class_infos).toPy(@TypeOf(result), result);
                }
            }.get;
        }

        fn generateComputedSetter(comptime prop_name: []const u8) ?*const fn (?*py.PyObject, ?*py.PyObject, ?*anyopaque) callconv(.c) c_int {
            const setter_name = "set_" ++ prop_name;
            if (!@hasDecl(T, setter_name)) {
                return null;
            }
            return struct {
                fn set(self_obj: ?*py.PyObject, value: ?*py.PyObject, closure: ?*anyopaque) callconv(.c) c_int {
                    _ = closure;
                    const self: *Parent.PyWrapper = @ptrCast(@alignCast(self_obj orelse return -1));
                    const py_value = value orelse {
                        py.PyErr_SetString(py.PyExc_AttributeError(), "Cannot delete property: " ++ prop_name);
                        return -1;
                    };
                    const setter = @field(T, setter_name);
                    const SetterType = @TypeOf(setter);
                    const setter_info = @typeInfo(SetterType).@"fn";
                    const ValueType = setter_info.params[1].type.?;
                    const converted = conversion.Converter(class_infos).fromPy(ValueType, py_value) catch {
                        py.PyErr_SetString(py.PyExc_TypeError(), "Failed to convert value for property: " ++ prop_name);
                        return -1;
                    };
                    const RetType = unwrapSignature(setter_info.return_type orelse void);
                    if (@typeInfo(RetType) == .error_union) {
                        setter(self.getData(), converted) catch |err| {
                            if (py.PyErr_Occurred() == null) {
                                const msg = @errorName(err);
                                py.PyErr_SetString(py.PyExc_ValueError(), msg.ptr);
                            }
                            return -1;
                        };
                    } else if (@typeInfo(RetType) == .optional) {
                        if (setter(self.getData(), converted) == null) {
                            if (py.PyErr_Occurred() == null) {
                                py.PyErr_SetString(py.PyExc_ValueError(), "setter failed for property: " ++ prop_name);
                            }
                            return -1;
                        }
                    } else {
                        setter(self.getData(), converted);
                    }
                    return 0;
                }
            }.set;
        }

        /// Get docstring for a pyoz.property() declaration
        fn getPyozPropertyDoc(comptime prop_name: []const u8) ?[*:0]const u8 {
            const PropType = @field(T, prop_name);
            const ConfigType = PropType.config;
            if (@hasField(ConfigType, "doc")) {
                const doc_field = @field(ConfigType{}, "doc");
                return doc_field;
            }
            return null;
        }

        /// Generate getter for a pyoz.property() declaration
        fn generatePyozPropertyGetter(comptime prop_name: []const u8) *const fn (?*py.PyObject, ?*anyopaque) callconv(.c) ?*py.PyObject {
            const PropType = @field(T, prop_name);
            const ConfigType = PropType.config;

            if (!@hasField(ConfigType, "get")) {
                @compileError("pyoz.property '" ++ prop_name ++ "' must have a 'get' field");
            }

            return struct {
                fn get(self_obj: ?*py.PyObject, closure: ?*anyopaque) callconv(.c) ?*py.PyObject {
                    _ = closure;
                    const self: *Parent.PyWrapper = @ptrCast(@alignCast(self_obj orelse return null));
                    const config = ConfigType{};
                    const getter = config.get;
                    const result = getter(self.getDataConst());
                    return conversion.Converter(class_infos).toPy(@TypeOf(result), result);
                }
            }.get;
        }

        /// Generate setter for a pyoz.property() declaration (or null if no setter)
        fn generatePyozPropertySetter(comptime prop_name: []const u8) ?*const fn (?*py.PyObject, ?*py.PyObject, ?*anyopaque) callconv(.c) c_int {
            const PropType = @field(T, prop_name);
            const ConfigType = PropType.config;

            if (!@hasField(ConfigType, "set")) {
                return null;
            }

            return struct {
                fn set(self_obj: ?*py.PyObject, value: ?*py.PyObject, closure: ?*anyopaque) callconv(.c) c_int {
                    _ = closure;
                    const self: *Parent.PyWrapper = @ptrCast(@alignCast(self_obj orelse return -1));
                    const py_value = value orelse {
                        py.PyErr_SetString(py.PyExc_AttributeError(), "Cannot delete property: " ++ prop_name);
                        return -1;
                    };
                    const config = ConfigType{};
                    const setter = config.set;
                    const SetterType = @TypeOf(setter);
                    const setter_info = @typeInfo(SetterType).@"fn";
                    const ValueType = setter_info.params[1].type.?;
                    const converted = conversion.Converter(class_infos).fromPy(ValueType, py_value) catch {
                        py.PyErr_SetString(py.PyExc_TypeError(), "Failed to convert value for property: " ++ prop_name);
                        return -1;
                    };
                    const RetType = unwrapSignature(setter_info.return_type orelse void);
                    if (@typeInfo(RetType) == .error_union) {
                        setter(self.getData(), converted) catch |err| {
                            if (py.PyErr_Occurred() == null) {
                                const msg = @errorName(err);
                                py.PyErr_SetString(py.PyExc_ValueError(), msg.ptr);
                            }
                            return -1;
                        };
                    } else if (@typeInfo(RetType) == .optional) {
                        if (setter(self.getData(), converted) == null) {
                            if (py.PyErr_Occurred() == null) {
                                py.PyErr_SetString(py.PyExc_ValueError(), "setter failed for property: " ++ prop_name);
                            }
                            return -1;
                        }
                    } else {
                        setter(self.getData(), converted);
                    }
                    return 0;
                }
            }.set;
        }
    };
}
