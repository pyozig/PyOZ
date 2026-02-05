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
const abi = @import("../abi.zig");
const slots = @import("../python/slots.zig");

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
        // In ABI3 mode, we pass null since type_object is void
        const lifecycle = lifecycle_mod.LifecycleBuilder(
            T,
            PyWrapper,
            if (abi.abi3_enabled) null else &type_object,
            has_dict_support,
            has_weakref_support,
            is_builtin_subclass,
        );
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
            if (comptime abi.abi3_enabled) {
                return heap_type orelse @panic("Type not initialized - call initType() first");
            } else {
                return &type_object;
            }
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
        // Type Object (static) - Non-ABI3 mode only
        // ====================================================================

        // In ABI3 mode, PyTypeObject is opaque so we can't create a static instance.
        // We use a dummy type (void) and rely on PyType_FromSpec for initialization.
        pub var type_object: if (abi.abi3_enabled) void else py.PyTypeObject =
            if (abi.abi3_enabled) {} else makeTypeObject();

        fn makeTypeObject() if (abi.abi3_enabled) void else py.PyTypeObject {
            if (abi.abi3_enabled) return {};

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
        /// Note: In ABI3 mode, this is a no-op since we use PyType_FromSpec.
        pub fn initBase() void {
            if (comptime abi.abi3_enabled) return;

            if (@import("builtin").os.tag == .windows) {
                if (@hasDecl(T, "__base__")) {
                    type_object.tp_base = T.__base__();
                }
            }
        }

        // ====================================================================
        // ABI3 Mode: PyType_FromSpec with Slot Arrays
        // ====================================================================

        /// Count total number of slots needed for this class (ABI3 mode)
        fn countTotalSlots() usize {
            if (!abi.abi3_enabled) return 0;

            var count: usize = 0;

            // Basic type slots
            if (!is_builtin_subclass) {
                count += 3; // tp_new, tp_init, tp_dealloc
            }

            // tp_methods, tp_getset
            count += 2;

            // tp_members for __dict__/__weakref__
            if ((has_dict_support or has_weakref_support) and !is_builtin_subclass) {
                count += 1;
            }

            // tp_doc
            count += 1;

            // tp_repr, tp_str
            count += 1; // tp_repr always present
            if (@hasDecl(T, "__str__")) count += 1;

            // Comparison
            if (@hasDecl(T, "__eq__") or @hasDecl(T, "__ne__") or @hasDecl(T, "__lt__") or
                @hasDecl(T, "__le__") or @hasDecl(T, "__gt__") or @hasDecl(T, "__ge__"))
            {
                count += 1;
            }

            // Hash
            if (@hasDecl(T, "__hash__")) count += 1;

            // Iterator
            if (@hasDecl(T, "__iter__")) count += 1;
            if (@hasDecl(T, "__next__")) count += 1;

            // Descriptor
            if (@hasDecl(T, "__get__")) count += 1;
            if (@hasDecl(T, "__set__") or @hasDecl(T, "__delete__")) count += 1;

            // Callable
            if (@hasDecl(T, "__call__")) count += 1;

            // Attribute access
            if (@hasDecl(T, "__getattr__") or has_dict_support) count += 1;
            if (@hasDecl(T, "__setattr__") or @hasDecl(T, "__delattr__") or has_dict_support or attr.isFrozen()) count += 1;

            // GC
            if (gc.hasGCSupport()) {
                count += 1; // tp_traverse
                if (@hasDecl(T, "__clear__")) count += 1;
            }

            // Protocol slots from sub-modules
            count += num.slotCount();
            count += seq.slotCount();
            count += map.slotCount();

            // Sentinel
            count += 1;

            return count;
        }

        const total_slot_count = countTotalSlots();

        /// Build the slots array for PyType_FromSpec (ABI3 mode)
        pub var type_slots: [total_slot_count]py.PyType_Slot = buildSlots();

        fn buildSlots() [total_slot_count]py.PyType_Slot {
            if (!abi.abi3_enabled) {
                return undefined;
            }

            var slot_array: [total_slot_count]py.PyType_Slot = undefined;
            var idx: usize = 0;

            // Basic lifecycle slots
            if (!is_builtin_subclass) {
                slot_array[idx] = .{ .slot = slots.tp_new, .pfunc = @ptrCast(@constCast(&lifecycle.py_new)) };
                idx += 1;
                slot_array[idx] = .{ .slot = slots.tp_init, .pfunc = @ptrCast(@constCast(&lifecycle.py_init)) };
                idx += 1;
                slot_array[idx] = .{ .slot = slots.tp_dealloc, .pfunc = @ptrCast(@constCast(&lifecycle.py_dealloc)) };
                idx += 1;
            }

            // Methods and properties
            slot_array[idx] = .{ .slot = slots.tp_methods, .pfunc = @ptrCast(@constCast(&meths.methods)) };
            idx += 1;
            slot_array[idx] = .{ .slot = slots.tp_getset, .pfunc = @ptrCast(@constCast(&props.getset)) };
            idx += 1;

            // Members for __dict__/__weakref__
            if ((has_dict_support or has_weakref_support) and !is_builtin_subclass) {
                slot_array[idx] = .{ .slot = slots.tp_members, .pfunc = @ptrCast(@constCast(&feature_members)) };
                idx += 1;
            }

            // Documentation
            const doc_ptr: [*:0]const u8 = if (@hasDecl(T, "__doc__")) blk: {
                const DocType = @TypeOf(T.__doc__);
                if (DocType != [*:0]const u8) {
                    @compileError("__doc__ must be declared as [*:0]const u8");
                }
                break :blk T.__doc__;
            } else name;
            slot_array[idx] = .{ .slot = slots.tp_doc, .pfunc = @ptrCast(@constCast(doc_ptr)) };
            idx += 1;

            // Repr protocol
            if (@hasDecl(T, "__repr__")) {
                slot_array[idx] = .{ .slot = slots.tp_repr, .pfunc = @ptrCast(@constCast(&repr.py_magic_repr)) };
            } else {
                slot_array[idx] = .{ .slot = slots.tp_repr, .pfunc = @ptrCast(@constCast(&repr.py_repr)) };
            }
            idx += 1;

            if (@hasDecl(T, "__str__")) {
                slot_array[idx] = .{ .slot = slots.tp_str, .pfunc = @ptrCast(@constCast(&repr.py_magic_str)) };
                idx += 1;
            }

            // Comparison protocol
            if (@hasDecl(T, "__eq__") or @hasDecl(T, "__ne__") or @hasDecl(T, "__lt__") or
                @hasDecl(T, "__le__") or @hasDecl(T, "__gt__") or @hasDecl(T, "__ge__"))
            {
                slot_array[idx] = .{ .slot = slots.tp_richcompare, .pfunc = @ptrCast(@constCast(&cmp.py_richcompare)) };
                idx += 1;
            }

            // Hash
            if (@hasDecl(T, "__hash__")) {
                slot_array[idx] = .{ .slot = slots.tp_hash, .pfunc = @ptrCast(@constCast(&repr.py_hash)) };
                idx += 1;
            }

            // Iterator protocol
            if (@hasDecl(T, "__iter__")) {
                slot_array[idx] = .{ .slot = slots.tp_iter, .pfunc = @ptrCast(@constCast(&iter.py_iter)) };
                idx += 1;
            }
            if (@hasDecl(T, "__next__")) {
                slot_array[idx] = .{ .slot = slots.tp_iternext, .pfunc = @ptrCast(@constCast(&iter.py_iternext)) };
                idx += 1;
            }

            // Descriptor protocol
            if (@hasDecl(T, "__get__")) {
                slot_array[idx] = .{ .slot = slots.tp_descr_get, .pfunc = @ptrCast(@constCast(&desc.py_descr_get)) };
                idx += 1;
            }
            if (@hasDecl(T, "__set__") or @hasDecl(T, "__delete__")) {
                slot_array[idx] = .{ .slot = slots.tp_descr_set, .pfunc = @ptrCast(@constCast(&desc.py_descr_set)) };
                idx += 1;
            }

            // Callable protocol
            if (@hasDecl(T, "__call__")) {
                slot_array[idx] = .{ .slot = slots.tp_call, .pfunc = @ptrCast(@constCast(&call.py_call)) };
                idx += 1;
            }

            // Attribute access
            if (@hasDecl(T, "__getattr__")) {
                slot_array[idx] = .{ .slot = slots.tp_getattro, .pfunc = @ptrCast(@constCast(&attr.py_getattro)) };
                idx += 1;
            } else if (has_dict_support) {
                slot_array[idx] = .{ .slot = slots.tp_getattro, .pfunc = @ptrCast(py.c.PyObject_GenericGetAttr) };
                idx += 1;
            }

            if (attr.isFrozen()) {
                slot_array[idx] = .{ .slot = slots.tp_setattro, .pfunc = @ptrCast(@constCast(&attr.py_frozen_setattro)) };
                idx += 1;
            } else if (@hasDecl(T, "__setattr__") or @hasDecl(T, "__delattr__")) {
                slot_array[idx] = .{ .slot = slots.tp_setattro, .pfunc = @ptrCast(@constCast(&attr.py_setattro)) };
                idx += 1;
            } else if (has_dict_support) {
                slot_array[idx] = .{ .slot = slots.tp_setattro, .pfunc = @ptrCast(py.c.PyObject_GenericSetAttr) };
                idx += 1;
            }

            // GC support
            if (gc.hasGCSupport()) {
                slot_array[idx] = .{ .slot = slots.tp_traverse, .pfunc = @ptrCast(@constCast(&gc.py_traverse)) };
                idx += 1;
                if (@hasDecl(T, "__clear__")) {
                    slot_array[idx] = .{ .slot = slots.tp_clear, .pfunc = @ptrCast(@constCast(&gc.py_clear)) };
                    idx += 1;
                }
            }

            // Protocol slots from sub-modules
            idx += num.addSlots(&slot_array, idx);
            idx += seq.addSlots(&slot_array, idx);
            idx += map.addSlots(&slot_array, idx);

            // Sentinel
            slot_array[idx] = .{ .slot = 0, .pfunc = null };

            return slot_array;
        }

        /// PyType_Spec for ABI3 mode
        pub var type_spec: py.PyType_Spec = makeTypeSpec();

        fn makeTypeSpec() py.PyType_Spec {
            if (!abi.abi3_enabled) {
                return undefined;
            }

            return .{
                .name = name,
                .basicsize = if (is_builtin_subclass) 0 else @sizeOf(PyWrapper),
                .itemsize = 0,
                .flags = @as(c_uint, py.Py_TPFLAGS_DEFAULT | py.Py_TPFLAGS_BASETYPE |
                    (if (gc.hasGCSupport()) py.Py_TPFLAGS_HAVE_GC else 0)),
                .slots = @ptrCast(&type_slots),
            };
        }

        /// Storage for heap type pointer in ABI3 mode
        pub var heap_type: ?*py.PyTypeObject = null;

        /// Initialize type - call PyType_Ready (non-ABI3) or PyType_FromSpec (ABI3)
        /// Returns the type object pointer on success, null on failure
        pub fn initType() ?*py.PyTypeObject {
            return initTypeWithName(name);
        }

        /// Initialize type with a custom name override
        /// This is used when registering classes with pyoz.class("CustomName", T)
        /// to ensure the Python-visible name matches the registered name
        pub fn initTypeWithName(custom_name: [*:0]const u8) ?*py.PyTypeObject {
            if (comptime abi.abi3_enabled) {
                // ABI3 mode: use PyType_FromSpec to create heap type
                // Create a spec with the custom name
                var spec_with_name = type_spec;
                spec_with_name.name = custom_name;
                const type_obj = py.c.PyType_FromSpec(&spec_with_name);
                if (type_obj == null) {
                    return null;
                }
                heap_type = @ptrCast(@alignCast(type_obj));
                return heap_type;
            } else {
                // Non-ABI3 mode: use static type object with PyType_Ready
                // Override the tp_name with the custom name
                type_object.tp_name = custom_name;
                initBase();
                if (py.c.PyType_Ready(&type_object) < 0) {
                    return null;
                }
                return &type_object;
            }
        }

        /// Get the type object pointer (works in both modes)
        pub fn getType() *py.PyTypeObject {
            if (comptime abi.abi3_enabled) {
                return heap_type orelse @panic("Type not initialized - call initType() first");
            } else {
                return &type_object;
            }
        }

        // ====================================================================
        // Helper to extract Zig data from a Python object
        // ====================================================================

        pub fn unwrap(obj: *py.PyObject) ?*T {
            const type_ptr = getType();
            if (!py.PyObject_TypeCheck(obj, type_ptr)) {
                return null;
            }
            const wrapper_ptr: *PyWrapper = @ptrCast(@alignCast(obj));
            return wrapper_ptr.getData();
        }

        pub fn unwrapConst(obj: *py.PyObject) ?*const T {
            const type_ptr = getType();
            if (!py.PyObject_TypeCheck(obj, type_ptr)) {
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

/// Add class attributes in ABI3 mode using PyObject_SetAttrString
/// since tp_dict is not accessible in stable ABI
pub fn addClassAttributesAbi3(comptime T: type, type_obj: *py.PyObject) bool {
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

            if (py.PyObject_SetAttrString(type_obj, attr_name.ptr, py_value) < 0) {
                py.Py_DecRef(py_value);
                return false;
            }
            py.Py_DecRef(py_value);
        }
    }

    return true;
}
