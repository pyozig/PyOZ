//! Class wrapper module for PyOZ
//!
//! This module provides comptime generation of Python classes from Zig structs.
//! It automatically:
//! - Generates __init__ from struct fields
//! - Creates getters/setters for each field
//! - Wraps pub fn methods as Python methods

const std = @import("std");
const py = @import("../python.zig");
const conversion = @import("../conversion.zig");

// Sub-modules
const wrapper_mod = @import("wrapper.zig");
const lifecycle_mod = @import("lifecycle.zig");
const number_mod = @import("number.zig");
const sequence_mod = @import("sequence.zig");
const mapping_mod = @import("mapping.zig");
const comparison_mod = @import("comparison.zig");
const repr_mod = @import("repr.zig");
const iterator_mod = @import("iterator.zig");
const buffer_mod = @import("buffer.zig");
const descriptor_mod = @import("descriptor.zig");
const attributes_mod = @import("attributes.zig");
const callable_mod = @import("callable.zig");
const properties_mod = @import("properties.zig");
const methods_mod = @import("methods.zig");
const gc_protocol = @import("gc.zig");

// Forward declaration - we'll use basic conversions within class methods
fn getConversions() type {
    return conversion.Conversions;
}

/// Configuration for a class definition
pub const ClassDef = struct {
    name: [*:0]const u8,
    type_obj: *py.PyTypeObject,
};

/// Get the wrapper type for a Zig struct (for use in conversions)
pub fn getWrapper(comptime T: type) type {
    // We need a default name - use the type name
    return generateClass(@typeName(T), T);
}

/// Generate a Python class wrapper for a Zig struct
pub fn class(comptime name: [*:0]const u8, comptime T: type) ClassDef {
    const Generated = generateClass(name, T);
    return .{
        .name = name,
        .type_obj = &Generated.type_object,
    };
}

/// Generate all the wrapper code for a Zig struct
fn generateClass(comptime name: [*:0]const u8, comptime T: type) type {
    const struct_info = @typeInfo(T).@"struct";
    const fields = struct_info.fields;

    // Check if this is a "mixin" class that inherits from a Python built-in type
    const is_builtin_subclass = comptime blk: {
        if (!@hasDecl(T, "__base__")) break :blk false;
        for (fields) |_| {
            break :blk false;
        }
        break :blk true;
    };

    return struct {
        const Self = @This();

        // Feature detection
        const has_dict_support = blk: {
            if (@hasDecl(T, "__features__")) {
                const features = T.__features__;
                if (@hasField(@TypeOf(features), "dict")) {
                    break :blk features.dict;
                }
            }
            break :blk false;
        };

        const has_weakref_support = blk: {
            if (@hasDecl(T, "__features__")) {
                const features = T.__features__;
                if (@hasField(@TypeOf(features), "weakref")) {
                    break :blk features.weakref;
                }
            }
            break :blk false;
        };

        // Build the wrapper struct using the wrapper module
        const WrapperResult = wrapper_mod.WrapperBuilder(T, is_builtin_subclass, has_dict_support, has_weakref_support);
        pub const PyWrapper = WrapperResult.PyWrapper;
        const dict_struct_offset = WrapperResult.dict_struct_offset;
        const weakref_struct_offset = WrapperResult.weakref_struct_offset;

        // Build protocol handlers
        const lifecycle = lifecycle_mod.LifecycleBuilder(T, PyWrapper, &type_object, has_dict_support, has_weakref_support, is_builtin_subclass);
        const num = number_mod.NumberProtocol(T, Self);
        const seq = sequence_mod.SequenceProtocol(T, Self);
        const map = mapping_mod.MappingProtocol(T, Self);
        const cmp = comparison_mod.ComparisonProtocol(T, Self);
        const repr = repr_mod.ReprProtocol(T, Self, name);
        const iter = iterator_mod.IteratorProtocol(T, Self);
        const buf = buffer_mod.BufferProtocol(T, Self);
        const desc = descriptor_mod.DescriptorProtocol(T, Self);
        const attr = attributes_mod.AttributeProtocol(T, Self, name);
        const call = callable_mod.CallableProtocol(T, Self);
        const props = properties_mod.PropertiesBuilder(T, Self);
        const meths = methods_mod.MethodBuilder(T, PyWrapper);
        const gc = gc_protocol.GCBuilder(T, PyWrapper);

        // Helper function to get type object pointer (for protocols that need it)
        pub fn getTypeObjectPtr() *py.PyTypeObject {
            return &type_object;
        }

        // ====================================================================
        // Members for __dict__ and __weakref__ support
        // ====================================================================

        const ptr_size = @sizeOf(?*py.PyObject);
        const dict_size = if (has_dict_support) ptr_size else 0;
        const weakref_size = if (has_weakref_support) ptr_size else 0;

        const member_count = (if (has_dict_support) @as(usize, 1) else 0) +
            (if (has_weakref_support) @as(usize, 1) else 0) + 1;

        var feature_members: [member_count]py.PyMemberDef = blk: {
            var members: [member_count]py.PyMemberDef = undefined;
            var idx: usize = 0;

            if (has_dict_support) {
                members[idx] = .{
                    .name = "__dict__",
                    .type = py.c.T_OBJECT_EX,
                    .offset = dict_struct_offset,
                    .flags = 0,
                    .doc = null,
                };
                idx += 1;
            }

            if (has_weakref_support) {
                members[idx] = .{
                    .name = "__weakref__",
                    .type = py.c.T_OBJECT_EX,
                    .offset = weakref_struct_offset,
                    .flags = py.c.READONLY,
                    .doc = null,
                };
                idx += 1;
            }

            // Sentinel
            members[idx] = .{
                .name = null,
                .type = 0,
                .offset = 0,
                .flags = 0,
                .doc = null,
            };

            break :blk members;
        };

        // ====================================================================
        // Type Object (static)
        // ====================================================================

        pub var type_object: py.PyTypeObject = makeTypeObject();

        fn makeTypeObject() py.PyTypeObject {
            var obj: py.PyTypeObject = std.mem.zeroes(py.PyTypeObject);

            // Basic setup
            if (comptime @hasField(py.c.PyObject, "ob_refcnt")) {
                obj.ob_base.ob_base.ob_refcnt = 1;
            } else {
                const ob_ptr: *py.Py_ssize_t = @ptrCast(&obj.ob_base.ob_base);
                ob_ptr.* = 1;
            }
            obj.ob_base.ob_base.ob_type = null;
            obj.tp_name = name;
            obj.tp_basicsize = if (is_builtin_subclass) 0 else @sizeOf(PyWrapper);
            obj.tp_itemsize = 0;
            obj.tp_flags = py.Py_TPFLAGS_DEFAULT | py.Py_TPFLAGS_BASETYPE |
                (if (gc.hasGCSupport()) py.Py_TPFLAGS_HAVE_GC else 0);

            // Set tp_dictoffset for __dict__ support
            if (has_dict_support and !is_builtin_subclass) {
                obj.tp_dictoffset = dict_struct_offset;
            }

            // Set tp_weaklistoffset for weak reference support
            if (has_weakref_support and !is_builtin_subclass) {
                obj.tp_weaklistoffset = weakref_struct_offset;
            }

            // Inheritance
            // On Windows, DLL data imports (like PyList_Type) require runtime
            // address resolution. At comptime, we'd get the import thunk address
            // instead of the actual type object. On Unix, comptime works fine.
            if (@hasDecl(T, "__base__")) {
                if (@import("builtin").os.tag != .windows) {
                    obj.tp_base = T.__base__();
                }
                // On Windows, tp_base is set via initBase() at runtime
            }

            // Documentation
            obj.tp_doc = if (@hasDecl(T, "__doc__")) blk: {
                const DocType = @TypeOf(T.__doc__);
                if (DocType != [*:0]const u8) {
                    @compileError("__doc__ must be declared as [*:0]const u8");
                }
                break :blk T.__doc__;
            } else name;

            // Lifecycle slots
            if (!is_builtin_subclass) {
                obj.tp_new = @ptrCast(&lifecycle.py_new);
                obj.tp_init = @ptrCast(&lifecycle.py_init);
                obj.tp_dealloc = @ptrCast(&lifecycle.py_dealloc);
            }

            // Methods and properties
            obj.tp_methods = @ptrCast(&meths.methods);
            obj.tp_getset = @ptrCast(&props.getset);

            // Members for __dict__ and __weakref__
            if ((has_dict_support or has_weakref_support) and !is_builtin_subclass) {
                obj.tp_members = @ptrCast(&feature_members);
            }

            // Repr protocol
            if (@hasDecl(T, "__repr__")) {
                obj.tp_repr = @ptrCast(&repr.py_magic_repr);
            } else {
                obj.tp_repr = @ptrCast(&repr.py_repr);
            }

            if (@hasDecl(T, "__str__")) {
                obj.tp_str = @ptrCast(&repr.py_magic_str);
            }

            // Comparison protocol
            if (@hasDecl(T, "__eq__") or @hasDecl(T, "__ne__") or @hasDecl(T, "__lt__") or
                @hasDecl(T, "__le__") or @hasDecl(T, "__gt__") or @hasDecl(T, "__ge__"))
            {
                obj.tp_richcompare = @ptrCast(&cmp.py_richcompare);
            }

            // Hash
            if (@hasDecl(T, "__hash__")) {
                obj.tp_hash = @ptrCast(&repr.py_hash);
            }

            // Number protocol
            if (num.hasNumberMethods()) {
                obj.tp_as_number = &num.number_methods;
            }

            // Sequence protocol
            if (seq.hasSequenceMethods()) {
                obj.tp_as_sequence = &seq.sequence_methods;
            }

            // Mapping protocol
            if (map.hasMappingMethods()) {
                obj.tp_as_mapping = &map.mapping_methods;
            }

            // Iterator protocol
            if (@hasDecl(T, "__iter__")) {
                obj.tp_iter = @ptrCast(&iter.py_iter);
            }

            if (@hasDecl(T, "__next__")) {
                obj.tp_iternext = @ptrCast(&iter.py_iternext);
            }

            // Buffer protocol
            if (buf.hasBufferProtocol()) {
                obj.tp_as_buffer = &buf.buffer_procs;
            }

            // Descriptor protocol
            if (@hasDecl(T, "__get__")) {
                obj.tp_descr_get = @ptrCast(&desc.py_descr_get);
            }
            if (@hasDecl(T, "__set__") or @hasDecl(T, "__delete__")) {
                obj.tp_descr_set = @ptrCast(&desc.py_descr_set);
            }

            // Callable protocol
            if (@hasDecl(T, "__call__")) {
                obj.tp_call = @ptrCast(&call.py_call);
            }

            // Attribute access
            if (@hasDecl(T, "__getattr__")) {
                obj.tp_getattro = @ptrCast(&attr.py_getattro);
            } else if (has_dict_support) {
                obj.tp_getattro = py.c.PyObject_GenericGetAttr;
            }

            if (@hasDecl(T, "__setattr__") or @hasDecl(T, "__delattr__")) {
                obj.tp_setattro = @ptrCast(&attr.py_setattro);
            } else if (has_dict_support) {
                obj.tp_setattro = py.c.PyObject_GenericSetAttr;
            }

            // Frozen classes
            if (attr.isFrozen()) {
                obj.tp_setattro = @ptrCast(&attr.py_frozen_setattro);
            }

            // GC support
            if (gc.hasGCSupport()) {
                obj.tp_traverse = @ptrCast(&gc.py_traverse);
                if (@hasDecl(T, "__clear__")) {
                    obj.tp_clear = @ptrCast(&gc.py_clear);
                }
            }

            return obj;
        }

        /// Initialize base type at runtime (required on Windows for DLL imports)
        /// On Windows, DLL data symbols like PyList_Type need runtime address
        /// resolution. This function must be called before PyType_Ready().
        pub fn initBase() void {
            if (@import("builtin").os.tag == .windows) {
                if (@hasDecl(T, "__base__")) {
                    type_object.tp_base = T.__base__();
                }
            }
        }

        // ====================================================================
        // Helper to extract Zig data from a Python object
        // ====================================================================

        pub fn unwrap(obj: *py.PyObject) ?*T {
            if (!py.PyObject_TypeCheck(obj, &type_object)) {
                return null;
            }
            const wrapper_ptr: *PyWrapper = @ptrCast(@alignCast(obj));
            return wrapper_ptr.getData();
        }

        pub fn unwrapConst(obj: *py.PyObject) ?*const T {
            if (!py.PyObject_TypeCheck(obj, &type_object)) {
                return null;
            }
            const wrapper_ptr: *const PyWrapper = @ptrCast(@alignCast(obj));
            return wrapper_ptr.getDataConst();
        }
    };
}

/// Extract a Zig value from a Python object if it's a wrapped class
pub fn unwrap(comptime T: type, obj: *py.PyObject) ?*T {
    _ = obj;
    return null;
}

/// Create a Python tuple containing the field names of a Zig struct (for __slots__)
pub fn createSlotsTuple(comptime T: type) ?*py.PyObject {
    const info = @typeInfo(T);
    if (info != .@"struct") return null;

    const type_fields = info.@"struct".fields;
    const tuple = py.PyTuple_New(@intCast(type_fields.len)) orelse return null;

    inline for (type_fields, 0..) |field, i| {
        const name_str = py.PyUnicode_FromString(@ptrCast(field.name.ptr)) orelse {
            py.Py_DecRef(tuple);
            return null;
        };
        if (py.PyTuple_SetItem(tuple, @intCast(i), name_str) < 0) {
            py.Py_DecRef(tuple);
            return null;
        }
    }

    return tuple;
}

/// Add class attributes (declarations starting with "classattr_") to the type's dict
pub fn addClassAttributes(comptime T: type, type_dict: *py.PyObject) bool {
    const info = @typeInfo(T);
    if (info != .@"struct") return true;

    const decls = info.@"struct".decls;
    const Conv = conversion.Conversions;

    inline for (decls) |decl| {
        const prefix = "classattr_";
        if (decl.name.len > prefix.len and std.mem.startsWith(u8, decl.name, prefix)) {
            const attr_name = decl.name[prefix.len..];
            const value = @field(T, decl.name);
            const ValueType = @TypeOf(value);

            const py_value = Conv.toPy(ValueType, value) orelse {
                return false;
            };

            if (py.PyDict_SetItemString(type_dict, attr_name.ptr, py_value) < 0) {
                py.Py_DecRef(py_value);
                return false;
            }
            py.Py_DecRef(py_value);
        }
    }

    return true;
}
