//! Stub Generation Module for PyOZ
//!
//! Generates Python type stub (.pyi) files at comptime from module definitions.
//! This provides IDE autocomplete, type checking with mypy/pyright, and visible
//! function signatures.

const std = @import("std");

// =============================================================================
// Type Mapping: Zig Types -> Python Type Strings
// =============================================================================

/// Map a Zig type to its Python type annotation string
pub fn zigTypeToPython(comptime T: type) []const u8 {
    const info = @typeInfo(T);

    return switch (info) {
        // Integer types -> int
        .int => "int",
        .comptime_int => "int",

        // Float types -> float
        .float => "float",
        .comptime_float => "float",

        // Bool -> bool
        .bool => "bool",

        // Void -> None
        .void => "None",

        // Pointers and slices
        .pointer => |ptr| {
            // String types
            if (ptr.size == .slice and ptr.child == u8) {
                return "str";
            }
            // Null-terminated string
            if (ptr.size == .many and ptr.child == u8) {
                return "str";
            }
            // String literal pointer
            if (ptr.size == .one) {
                const child_info = @typeInfo(ptr.child);
                if (child_info == .array) {
                    const arr = child_info.array;
                    if (arr.child == u8) {
                        return "str";
                    }
                }
            }
            // Pointer to PyObject
            if (ptr.child == @import("python.zig").PyObject) {
                return "Any";
            }
            // Generic slice -> list[T]
            if (ptr.size == .slice) {
                return "list[" ++ zigTypeToPython(ptr.child) ++ "]";
            }
            // Pointer to class type - extract just the type name (strip module prefix)
            return extractTypeName(@typeName(ptr.child));
        },

        // Optional types -> T | None
        .optional => |opt| {
            const inner = zigTypeToPython(opt.child);
            return inner ++ " | None";
        },

        // Error unions - extract payload type
        .error_union => |eu| {
            return zigTypeToPython(eu.payload);
        },

        // Structs - check for known PyOZ types
        .@"struct" => {
            return mapStructType(T);
        },

        // Arrays
        .array => |arr| {
            return "list[" ++ zigTypeToPython(arr.child) ++ "]";
        },

        // Enums
        .@"enum" => extractTypeName(@typeName(T)),

        // Fallback
        else => "Any",
    };
}

/// Map struct types to Python equivalents
fn mapStructType(comptime T: type) []const u8 {
    // Use @hasDecl checks instead of string searching - much faster at comptime

    // Check for PyOZ marker declarations first (fastest checks)
    if (@hasDecl(T, "_is_pyoz_complex")) return "complex";
    if (@hasDecl(T, "_is_pyoz_datetime")) return "datetime.datetime";
    if (@hasDecl(T, "_is_pyoz_timedelta")) return "datetime.timedelta";
    if (@hasDecl(T, "_is_pyoz_date")) return "datetime.date";
    if (@hasDecl(T, "_is_pyoz_time")) return "datetime.time";
    if (@hasDecl(T, "_is_pyoz_bytearray")) return "bytearray";
    if (@hasDecl(T, "_is_pyoz_bytes")) return "bytes";
    if (@hasDecl(T, "_is_pyoz_path")) return "pathlib.Path";
    if (@hasDecl(T, "_is_pyoz_decimal")) return "decimal.Decimal";

    // Collection types - check by declaration pattern
    if (@hasDecl(T, "KeyType") and @hasDecl(T, "ValueType")) {
        // Dict-like type
        return "dict[" ++ zigTypeToPython(T.KeyType) ++ ", " ++ zigTypeToPython(T.ValueType) ++ "]";
    }

    if (@hasDecl(T, "_is_pyoz_frozenset")) {
        if (@hasDecl(T, "ElementType")) {
            return "frozenset[" ++ zigTypeToPython(T.ElementType) ++ "]";
        }
        return "frozenset[Any]";
    }

    if (@hasDecl(T, "_is_pyoz_set")) {
        if (@hasDecl(T, "ElementType")) {
            return "set[" ++ zigTypeToPython(T.ElementType) ++ "]";
        }
        return "set[Any]";
    }

    if (@hasDecl(T, "_is_pyoz_list")) {
        if (@hasDecl(T, "ElementType")) {
            return "list[" ++ zigTypeToPython(T.ElementType) ++ "]";
        }
        return "list[Any]";
    }

    if (@hasDecl(T, "_is_pyoz_iterator")) {
        if (@hasDecl(T, "ElementType")) {
            return "Iterable[" ++ zigTypeToPython(T.ElementType) ++ "]";
        }
        return "Iterable[Any]";
    }

    // Buffer types (numpy arrays)
    if (@hasDecl(T, "_is_pyoz_buffer")) {
        if (@hasDecl(T, "ElementType")) {
            const elem_type = T.ElementType;
            const numpy_dtype = zigTypeToNumpyDtype(elem_type);
            return "numpy.ndarray[Any, numpy.dtype[" ++ numpy_dtype ++ "]]";
        }
        return "numpy.ndarray[Any, Any]";
    }

    // Args wrapper - should be expanded by caller
    if (@hasDecl(T, "is_pyoz_args") and T.is_pyoz_args) {
        return "<<ARGS>>";
    }

    // Tuple structs
    const struct_info = @typeInfo(T).@"struct";
    if (struct_info.is_tuple) {
        var result: []const u8 = "tuple[";
        for (struct_info.fields, 0..) |field, i| {
            if (i > 0) result = result ++ ", ";
            result = result ++ zigTypeToPython(field.type);
        }
        return result ++ "]";
    }

    // Unknown struct - extract just the type name (strip module path)
    return extractTypeName(@typeName(T));
}

/// Extract just the type name from a fully qualified name like "lib.Point" -> "Point"
fn extractTypeName(comptime full_name: []const u8) []const u8 {
    // Find the last '.' and return everything after it
    var last_dot: usize = 0;
    var found_dot = false;
    for (full_name, 0..) |c, i| {
        if (c == '.') {
            last_dot = i;
            found_dot = true;
        }
    }
    if (found_dot) {
        return full_name[last_dot + 1 ..];
    }
    return full_name;
}

/// Map Zig numeric types to numpy dtype names
fn zigTypeToNumpyDtype(comptime T: type) []const u8 {
    return switch (T) {
        f64 => "numpy.float64",
        f32 => "numpy.float32",
        i64 => "numpy.int64",
        i32 => "numpy.int32",
        i16 => "numpy.int16",
        i8 => "numpy.int8",
        u64 => "numpy.uint64",
        u32 => "numpy.uint32",
        u16 => "numpy.uint16",
        u8 => "numpy.uint8",
        else => {
            const type_name = @typeName(T);
            if (std.mem.indexOf(u8, type_name, "Complex") != null) {
                if (std.mem.indexOf(u8, type_name, "Complex32") != null) {
                    return "numpy.complex64";
                }
                return "numpy.complex128";
            }
            return "Any";
        },
    };
}

// =============================================================================
// Stub Writer
// =============================================================================

/// Comptime buffer for building stub content
pub fn StubWriter(comptime max_size: usize) type {
    return struct {
        buffer: [max_size]u8 = undefined,
        pos: usize = 0,

        const Self = @This();

        pub fn write(self: *Self, data: []const u8) void {
            if (self.pos + data.len <= max_size) {
                @memcpy(self.buffer[self.pos..][0..data.len], data);
                self.pos += data.len;
            }
        }

        pub fn writeLine(self: *Self, data: []const u8) void {
            self.write(data);
            self.write("\n");
        }

        pub fn writeIndent(self: *Self, level: usize) void {
            var i: usize = 0;
            while (i < level * 4) : (i += 1) {
                self.write(" ");
            }
        }

        /// Returns a comptime-constant string slice that can be used at runtime
        pub fn getWritten(self: *const Self) *const [self.pos]u8 {
            return self.buffer[0..self.pos];
        }
    };
}

// =============================================================================
// Stub Generation Functions
// =============================================================================

/// Generate the imports section of the stub file
pub fn generateImports(comptime config: anytype) []const u8 {
    @setEvalBranchQuota(100000);
    comptime {
        var result: []const u8 = "\"\"\"Type stubs generated by PyOZ\"\"\"\n\n";
        result = result ++ "from typing import Any, Iterable, overload\n";

        // Check if we need specific imports based on types used
        var needs_datetime = false;
        var needs_decimal = false;
        var needs_pathlib = false;
        var needs_numpy = false;

        // Check functions
        const funcs = config.funcs;
        for (funcs) |f| {
            const func_imports = detectImportsForFunc(@TypeOf(f.func));
            needs_datetime = needs_datetime or func_imports.datetime;
            needs_decimal = needs_decimal or func_imports.decimal;
            needs_pathlib = needs_pathlib or func_imports.pathlib;
            needs_numpy = needs_numpy or func_imports.numpy;
        }

        // Check classes
        if (@hasField(@TypeOf(config), "classes")) {
            const classes = config.classes;
            for (classes) |cls| {
                const class_imports = detectImportsForClass(cls.zig_type);
                needs_datetime = needs_datetime or class_imports.datetime;
                needs_decimal = needs_decimal or class_imports.decimal;
                needs_pathlib = needs_pathlib or class_imports.pathlib;
                needs_numpy = needs_numpy or class_imports.numpy;
            }
        }

        if (needs_datetime) {
            result = result ++ "import datetime\n";
        }
        if (needs_decimal) {
            result = result ++ "import decimal\n";
        }
        if (needs_pathlib) {
            result = result ++ "import pathlib\n";
        }
        if (needs_numpy) {
            result = result ++ "import numpy\n";
        }

        result = result ++ "\n";

        return result;
    }
}

const ImportFlags = struct {
    datetime: bool = false,
    decimal: bool = false,
    pathlib: bool = false,
    numpy: bool = false,
};

fn detectImportsForFunc(comptime Fn: type) ImportFlags {
    const fn_info = @typeInfo(Fn).@"fn";
    var flags = ImportFlags{};

    // Check return type
    if (fn_info.return_type) |ret| {
        const ret_flags = detectImportsForType(ret);
        flags.datetime = flags.datetime or ret_flags.datetime;
        flags.decimal = flags.decimal or ret_flags.decimal;
        flags.pathlib = flags.pathlib or ret_flags.pathlib;
        flags.numpy = flags.numpy or ret_flags.numpy;
    }

    // Check parameters
    for (fn_info.params) |param| {
        if (param.type) |ptype| {
            const param_flags = detectImportsForType(ptype);
            flags.datetime = flags.datetime or param_flags.datetime;
            flags.decimal = flags.decimal or param_flags.decimal;
            flags.pathlib = flags.pathlib or param_flags.pathlib;
            flags.numpy = flags.numpy or param_flags.numpy;
        }
    }

    return flags;
}

fn detectImportsForClass(comptime T: type) ImportFlags {
    const struct_info = @typeInfo(T).@"struct";
    var flags = ImportFlags{};

    // Check fields
    for (struct_info.fields) |field| {
        const field_flags = detectImportsForType(field.type);
        flags.datetime = flags.datetime or field_flags.datetime;
        flags.decimal = flags.decimal or field_flags.decimal;
        flags.pathlib = flags.pathlib or field_flags.pathlib;
        flags.numpy = flags.numpy or field_flags.numpy;
    }

    return flags;
}

fn detectImportsForType(comptime T: type) ImportFlags {
    // Use @hasDecl checks instead of string searching for speed
    const info = @typeInfo(T);

    // Handle optionals and error unions
    if (info == .optional) {
        return detectImportsForType(info.optional.child);
    }
    if (info == .error_union) {
        return detectImportsForType(info.error_union.payload);
    }
    if (info == .pointer) {
        return detectImportsForType(info.pointer.child);
    }

    // Check struct types for PyOZ markers
    if (info == .@"struct") {
        return .{
            .datetime = @hasDecl(T, "_is_pyoz_datetime") or @hasDecl(T, "_is_pyoz_date") or
                @hasDecl(T, "_is_pyoz_time") or @hasDecl(T, "_is_pyoz_timedelta"),
            .decimal = @hasDecl(T, "_is_pyoz_decimal"),
            .pathlib = @hasDecl(T, "_is_pyoz_path"),
            .numpy = @hasDecl(T, "_is_pyoz_buffer"),
        };
    }

    return .{};
}

/// Generate stub for a single function
pub fn generateFunctionStub(
    comptime name: []const u8,
    comptime Fn: type,
    comptime doc: ?[]const u8,
    comptime is_named_kwargs: bool,
) []const u8 {
    comptime {
        var result: []const u8 = "def " ++ name ++ "(";
        const fn_info = @typeInfo(Fn).@"fn";
        const params = fn_info.params;

        if (is_named_kwargs and params.len == 1) {
            // Named kwargs - expand the Args struct
            const ArgsWrapperType = params[0].type.?;
            if (@hasDecl(ArgsWrapperType, "ArgsStruct")) {
                const ArgsStructType = ArgsWrapperType.ArgsStruct;
                const args_fields = @typeInfo(ArgsStructType).@"struct".fields;

                var first = true;
                for (args_fields) |field| {
                    if (!first) {
                        result = result ++ ", ";
                    }
                    first = false;

                    result = result ++ field.name ++ ": ";

                    // Check if optional
                    const field_info = @typeInfo(field.type);
                    if (field_info == .optional) {
                        result = result ++ zigTypeToPython(field_info.optional.child) ++ " | None";
                    } else {
                        result = result ++ zigTypeToPython(field.type);
                    }

                    // Check for default value
                    if (field.default_value_ptr != null) {
                        result = result ++ " = ...";
                    } else if (field_info == .optional) {
                        result = result ++ " = None";
                    }
                }
            }
        } else {
            // Regular positional arguments - use arg0, arg1, etc.
            var arg_idx: usize = 0;
            for (params) |param| {
                if (param.type) |ptype| {
                    if (arg_idx > 0) {
                        result = result ++ ", ";
                    }

                    result = result ++ std.fmt.comptimePrint("arg{d}", .{arg_idx}) ++ ": " ++ zigTypeToPython(ptype);
                    arg_idx += 1;
                }
            }
        }

        result = result ++ ") -> ";

        // Return type
        if (fn_info.return_type) |ret| {
            const ret_info = @typeInfo(ret);
            if (ret_info == .error_union) {
                result = result ++ zigTypeToPython(ret_info.error_union.payload);
            } else {
                result = result ++ zigTypeToPython(ret);
            }
        } else {
            result = result ++ "None";
        }

        result = result ++ ":\n";

        // Docstring
        if (doc) |d| {
            result = result ++ "    \"\"\"" ++ d ++ "\"\"\"\n";
        }

        result = result ++ "    ...\n\n";

        return result;
    }
}

/// Generate stub for a class
pub fn generateClassStub(comptime name: []const u8, comptime T: type) []const u8 {
    comptime {
        var result: []const u8 = "class " ++ name ++ ":\n";
        const struct_info = @typeInfo(T).@"struct";
        const fields = struct_info.fields;

        // Class docstring
        if (@hasDecl(T, "__doc__")) {
            result = result ++ "    \"\"\"...\"\"\"\n";
        }

        // Fields as class-level annotations
        for (fields) |field| {
            result = result ++ "    " ++ field.name ++ ": " ++ zigTypeToPython(field.type) ++ "\n";
        }

        if (fields.len > 0) {
            result = result ++ "\n";
        }

        // __init__ method
        result = result ++ "    def __init__(self";
        for (fields) |field| {
            result = result ++ ", " ++ field.name ++ ": " ++ zigTypeToPython(field.type);
        }
        result = result ++ ") -> None: ...\n\n";

        // Instance methods, static methods, class methods
        for (struct_info.decls) |decl| {
            // Skip private and special declarations
            if (decl.name[0] == '_') continue;
            if (std.mem.startsWith(u8, decl.name, "classattr_")) continue;

            // Skip docstring declarations
            if (std.mem.endsWith(u8, decl.name, "__doc__")) continue;

            const decl_value = @field(T, decl.name);
            const DeclType = @TypeOf(decl_value);

            if (@typeInfo(DeclType) == .@"fn") {
                result = result ++ generateMethodStub(decl.name, DeclType, T);
            }
        }

        // Computed properties (get_X / set_X)
        for (struct_info.decls) |decl| {
            if (std.mem.startsWith(u8, decl.name, "get_")) {
                const prop_name = decl.name[4..];
                // Check if there's a corresponding setter
                const has_setter = @hasDecl(T, "set_" ++ prop_name);

                const getter_fn = @field(T, decl.name);
                const getter_info = @typeInfo(@TypeOf(getter_fn)).@"fn";
                const return_type = if (getter_info.return_type) |ret| zigTypeToPython(ret) else "Any";

                result = result ++ "    @property\n";
                result = result ++ "    def " ++ prop_name ++ "(self) -> " ++ return_type ++ ": ...\n";

                if (has_setter) {
                    result = result ++ "    @" ++ prop_name ++ ".setter\n";
                    result = result ++ "    def " ++ prop_name ++ "(self, value: " ++ return_type ++ ") -> None: ...\n";
                }
                result = result ++ "\n";
            }
        }

        // pyoz.property() declarations
        for (struct_info.decls) |decl| {
            const DeclType = @TypeOf(@field(T, decl.name));
            // Check if this is a type with __pyoz_property__ marker
            if (DeclType == type) {
                const ActualType = @field(T, decl.name);
                if (@hasDecl(ActualType, "__pyoz_property__") and ActualType.__pyoz_property__) {
                    const ConfigType = ActualType.config;
                    // Get return type from the getter function
                    const getter_fn = @field(ConfigType{}, "get");
                    const getter_info = @typeInfo(@TypeOf(getter_fn)).@"fn";
                    const return_type = if (getter_info.return_type) |ret| zigTypeToPython(ret) else "Any";

                    const has_setter = @hasField(ConfigType, "set");

                    result = result ++ "    @property\n";
                    result = result ++ "    def " ++ decl.name ++ "(self) -> " ++ return_type ++ ": ...\n";

                    if (has_setter) {
                        result = result ++ "    @" ++ decl.name ++ ".setter\n";
                        result = result ++ "    def " ++ decl.name ++ "(self, value: " ++ return_type ++ ") -> None: ...\n";
                    }
                    result = result ++ "\n";
                }
            }
        }

        // Magic methods
        for (.{
            .{ "__repr__", "str" },
            .{ "__str__", "str" },
            .{ "__hash__", "int" },
            .{ "__len__", "int" },
            .{ "__bool__", "bool" },
            .{ "__int__", "int" },
            .{ "__float__", "float" },
            .{ "__complex__", "complex" },
            .{ "__index__", "int" },
            .{ "__iter__", "Iterator[Any]" },
            .{ "__next__", "Any" },
            .{ "__call__", "Any" },
            .{ "__enter__", "Any" },
        }) |magic| {
            if (@hasDecl(T, magic[0])) {
                result = result ++ "    def " ++ magic[0] ++ "(self) -> " ++ magic[1] ++ ": ...\n";
            }
        }

        // Comparison methods
        for (.{ "__eq__", "__ne__", "__lt__", "__le__", "__gt__", "__ge__" }) |cmp| {
            if (@hasDecl(T, cmp)) {
                result = result ++ "    def " ++ cmp ++ "(self, other: " ++ name ++ ") -> bool: ...\n";
            }
        }

        // Binary operators
        for (.{
            .{ "__add__", name },
            .{ "__sub__", name },
            .{ "__mul__", name },
            .{ "__truediv__", name },
            .{ "__floordiv__", name },
            .{ "__mod__", name },
            .{ "__pow__", name },
            .{ "__matmul__", name },
            .{ "__and__", name },
            .{ "__or__", name },
            .{ "__xor__", name },
            .{ "__lshift__", name },
            .{ "__rshift__", name },
        }) |op| {
            if (@hasDecl(T, op[0])) {
                result = result ++ "    def " ++ op[0] ++ "(self, other: " ++ op[1] ++ ") -> " ++ name ++ ": ...\n";
            }
        }

        // Unary operators
        for (.{
            .{ "__neg__", name },
            .{ "__pos__", name },
            .{ "__abs__", name },
            .{ "__invert__", name },
        }) |op| {
            if (@hasDecl(T, op[0])) {
                result = result ++ "    def " ++ op[0] ++ "(self) -> " ++ op[1] ++ ": ...\n";
            }
        }

        // Sequence/mapping methods
        if (@hasDecl(T, "__getitem__")) {
            result = result ++ "    def __getitem__(self, key: Any) -> Any: ...\n";
        }
        if (@hasDecl(T, "__setitem__")) {
            result = result ++ "    def __setitem__(self, key: Any, value: Any) -> None: ...\n";
        }
        if (@hasDecl(T, "__delitem__")) {
            result = result ++ "    def __delitem__(self, key: Any) -> None: ...\n";
        }
        if (@hasDecl(T, "__contains__")) {
            result = result ++ "    def __contains__(self, item: Any) -> bool: ...\n";
        }

        // Context manager
        if (@hasDecl(T, "__exit__")) {
            result = result ++ "    def __exit__(self, exc_type: type[BaseException] | None, exc_val: BaseException | None, exc_tb: Any) -> bool | None: ...\n";
        }

        result = result ++ "\n";

        return result;
    }
}

/// Generate stub for a single method
fn generateMethodStub(comptime name: []const u8, comptime Fn: type, comptime ClassType: type) []const u8 {
    comptime {
        var result: []const u8 = "";
        const fn_info = @typeInfo(Fn).@"fn";
        const params = fn_info.params;

        if (params.len == 0) {
            // No parameters - static method
            result = result ++ "    @staticmethod\n    def " ++ name ++ "(";
        } else {
            const first_param = params[0].type.?;
            const first_info = @typeInfo(first_param);

            // Check if first param is self (pointer to class)
            const is_self = first_info == .pointer and
                (first_info.pointer.child == ClassType);

            // Check if first param is cls (comptime type)
            const is_classmethod = first_param == type;

            if (is_classmethod) {
                result = result ++ "    @classmethod\n    def " ++ name ++ "(cls";
            } else if (is_self) {
                result = result ++ "    def " ++ name ++ "(self";
            } else {
                // Static method
                result = result ++ "    @staticmethod\n    def " ++ name ++ "(";
                // First param is not self, include it
                result = result ++ "arg0: " ++ zigTypeToPython(first_param);
            }

            // Rest of parameters - use argN naming with incrementing index
            const start_idx: usize = if (is_self or is_classmethod) 1 else 1;
            var param_idx: usize = if (is_self or is_classmethod) 0 else 1;

            for (params[start_idx..]) |param| {
                if (param.type) |ptype| {
                    result = result ++ ", " ++ std.fmt.comptimePrint("arg{d}", .{param_idx}) ++ ": " ++ zigTypeToPython(ptype);
                    param_idx += 1;
                }
            }
        }

        result = result ++ ") -> ";

        // Return type
        if (fn_info.return_type) |ret| {
            const ret_info = @typeInfo(ret);
            if (ret_info == .error_union) {
                result = result ++ zigTypeToPython(ret_info.error_union.payload);
            } else {
                result = result ++ zigTypeToPython(ret);
            }
        } else {
            result = result ++ "None";
        }

        result = result ++ ": ...\n";

        return result;
    }
}

/// Generate stub for an exception
pub fn generateExceptionStub(comptime name: []const u8, comptime doc: ?[]const u8) []const u8 {
    comptime {
        var result: []const u8 = "class " ++ name ++ "(Exception):\n";
        if (doc) |d| {
            result = result ++ "    \"\"\"" ++ d ++ "\"\"\"\n";
        }
        result = result ++ "    ...\n\n";
        return result;
    }
}

/// Generate stub for a module constant
pub fn generateConstStub(comptime name: []const u8, comptime T: type) []const u8 {
    comptime {
        return name ++ ": " ++ zigTypeToPython(T) ++ "\n";
    }
}

/// Generate stub for an enum
pub fn generateEnumStub(comptime name: []const u8, comptime T: type, comptime is_str_enum: bool) []const u8 {
    comptime {
        var result: []const u8 = "class " ++ name;
        const enum_info = @typeInfo(T).@"enum";

        if (is_str_enum) {
            result = result ++ "(str, Enum):\n";
        } else {
            result = result ++ "(int, Enum):\n";
        }

        // Enum members
        for (enum_info.fields) |field| {
            if (is_str_enum) {
                result = result ++ "    " ++ field.name ++ " = \"" ++ field.name ++ "\"\n";
            } else {
                result = result ++ "    " ++ field.name ++ " = " ++ std.fmt.comptimePrint("{d}", .{field.value}) ++ "\n";
            }
        }

        result = result ++ "\n";

        return result;
    }
}

// =============================================================================
// Main Stub Generator
// =============================================================================

/// Generate complete stub file content for a module
pub fn generateModuleStubs(comptime config: anytype) []const u8 {
    @setEvalBranchQuota(100000);
    comptime {
        // Build result using pure comptime concatenation (no mutable vars)
        var result: []const u8 = "";

        // Imports
        result = result ++ generateImports(config);

        // Check if we have enums - need Enum import
        const has_enums = (@hasField(@TypeOf(config), "enums") and config.enums.len > 0) or
            (@hasField(@TypeOf(config), "str_enums") and config.str_enums.len > 0);
        if (has_enums) {
            // Insert enum import after other imports
            result = result ++ "from enum import Enum\n\n";
        }

        // Exceptions
        if (@hasField(@TypeOf(config), "exceptions")) {
            const exceptions = config.exceptions;
            for (exceptions) |exc| {
                result = result ++ generateExceptionStub(
                    std.mem.span(exc.name),
                    if (exc.doc) |d| std.mem.span(d) else null,
                );
            }
        }

        // Enums (unified - uses is_str_enum field for auto-detection)
        if (@hasField(@TypeOf(config), "enums")) {
            const enums = config.enums;
            for (enums) |e| {
                result = result ++ generateEnumStub(std.mem.span(e.name), e.zig_type, e.is_str_enum);
            }
        }

        // Legacy str_enums support (deprecated)
        if (@hasField(@TypeOf(config), "str_enums")) {
            const str_enums = config.str_enums;
            for (str_enums) |e| {
                // Legacy str_enums always use is_str_enum if available, else default true
                const is_str = if (@hasField(@TypeOf(e), "is_str_enum")) e.is_str_enum else true;
                result = result ++ generateEnumStub(std.mem.span(e.name), e.zig_type, is_str);
            }
        }

        // Classes
        if (@hasField(@TypeOf(config), "classes")) {
            const classes = config.classes;
            for (classes) |cls| {
                result = result ++ generateClassStub(std.mem.span(cls.name), cls.zig_type);
            }
        }

        // Module-level constants
        if (@hasField(@TypeOf(config), "consts")) {
            const consts = config.consts;
            if (consts.len > 0) {
                result = result ++ "# Module constants\n";
                for (consts) |c| {
                    result = result ++ generateConstStub(std.mem.span(c.name), c.value_type);
                }
                result = result ++ "\n";
            }
        }

        // Functions
        const funcs = config.funcs;
        for (funcs) |f| {
            const is_named = @hasField(@TypeOf(f), "is_named_kwargs") and f.is_named_kwargs;
            result = result ++ generateFunctionStub(
                std.mem.span(f.name),
                @TypeOf(f.func),
                if (f.doc) |d| std.mem.span(d) else null,
                is_named,
            );
        }

        return result;
    }
}
