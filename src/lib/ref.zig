//! Strong Python object references for cross-object lifetime management.
//!
//! `Ref(T)` allows one PyOZ-managed struct to hold a strong reference to another,
//! preventing the referenced object from being garbage collected while the reference exists.
//!
//! Usage:
//! ```zig
//! const Node = struct {
//!     _parser: pyoz.Ref(GrammarParser),
//!     _index: u32,
//!
//!     pub fn text(self: *const Node) []const u8 {
//!         const parser = self._parser.get().?;
//!         // ... safely use parser data ...
//!     }
//! };
//! ```

const py = @import("python.zig");
const class_mod = @import("class.zig");

/// A strong reference to a Python-managed Zig object of type `T`.
///
/// Stores a `?*PyObject` internally and manages INCREF/DECREF automatically.
/// PyOZ's class machinery calls `clear()` on deallocation (including freelist eviction).
///
/// Default value is null (no reference held). Fields should be declared as:
///     _parser: pyoz.Ref(GrammarParser) = .{},
/// or simply:
///     _parser: pyoz.Ref(GrammarParser),
/// (zero-init in py_new handles the default)
pub fn Ref(comptime T: type) type {
    return extern struct {
        const Self = @This();

        /// Comptime marker for detection by lifecycle/properties/stubs.
        pub const __pyoz_ref__ = true;

        /// The referenced Zig type.
        pub const RefType = T;

        /// The underlying Python object pointer (null = no reference held).
        _py_obj: ?*py.PyObject = null,

        /// Store a reference to a Python object. INCREFs the new object
        /// and DECREFs any previously held reference.
        pub fn set(self: *Self, obj: *py.PyObject) void {
            const old = self._py_obj;
            py.Py_IncRef(obj);
            self._py_obj = obj;
            if (old) |o| py.Py_DecRef(o);
        }

        /// Get an immutable pointer to the referenced Zig data, or null if no reference is held.
        pub fn get(self: *const Self, comptime class_infos: []const class_mod.ClassInfo) ?*const T {
            const obj = self._py_obj orelse return null;
            const Wrapper = class_mod.getWrapperWithName(comptime getClassName(class_infos), T, class_infos);
            return Wrapper.unwrapConst(obj);
        }

        /// Get a mutable pointer to the referenced Zig data, or null if no reference is held.
        pub fn getMut(self: *Self, comptime class_infos: []const class_mod.ClassInfo) ?*T {
            const obj = self._py_obj orelse return null;
            const Wrapper = class_mod.getWrapperWithName(comptime getClassName(class_infos), T, class_infos);
            return Wrapper.unwrap(obj);
        }

        /// Get the raw PyObject pointer (borrowed reference).
        pub fn object(self: *const Self) ?*py.PyObject {
            return self._py_obj;
        }

        /// Release the held reference (DECREF) and set to null.
        pub fn clear(self: *Self) void {
            if (self._py_obj) |obj| {
                self._py_obj = null;
                py.Py_DecRef(obj);
            }
        }

        /// Look up the class name for T in class_infos at comptime.
        fn getClassName(comptime class_infos: []const class_mod.ClassInfo) [*:0]const u8 {
            inline for (class_infos) |info| {
                if (info.zig_type == T) return info.name;
            }
            @compileError("Ref(" ++ @typeName(T) ++ "): type is not a registered class");
        }
    };
}

/// Check at comptime whether a type is a `Ref(T)`.
pub fn isRefType(comptime FieldType: type) bool {
    return @typeInfo(FieldType) == .@"struct" and @hasDecl(FieldType, "__pyoz_ref__");
}
