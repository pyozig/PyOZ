//! PyOZ - Python bindings for Zig (like PyO3 for Rust)
//!
//! Write pure Zig functions and structs, PyOZ handles all the Python integration automatically.
//!
//! ## Example Usage - Functions
//!
//! ```zig
//! const pyoz = @import("pyoz");
//!
//! fn add(a: i64, b: i64) i64 {
//!     return a + b;
//! }
//!
//! const MyModule = pyoz.module(.{
//!     .name = "mymodule",
//!     .funcs = &.{ pyoz.func("add", add, "Add two numbers") },
//! });
//!
//! pub export fn PyInit_mymodule() ?*pyoz.PyObject {
//!     return MyModule.init();
//! }
//! ```
//!
//! ## Example Usage - Classes
//!
//! ```zig
//! const Point = struct {
//!     x: f64,
//!     y: f64,
//!
//!     pub fn distance(self: *const Point, other: *const Point) f64 {
//!         const dx = self.x - other.x;
//!         const dy = self.y - other.y;
//!         return @sqrt(dx * dx + dy * dy);
//!     }
//! };
//!
//! const MyModule = pyoz.module(.{
//!     .name = "mymodule",
//!     .classes = &.{ pyoz.class("Point", Point) },
//! });
//! ```

const std = @import("std");

// =============================================================================
// Core imports
// =============================================================================

pub const py = @import("python.zig");
pub const class_mod = @import("class.zig");
pub const module_mod = @import("module.zig");
pub const stubs_mod = @import("stubs.zig");
pub const version = @import("version");
pub const abi = @import("abi.zig");

// =============================================================================
// Python C API types (re-exported for convenience)
// =============================================================================

pub const PyObject = py.PyObject;
pub const PyMethodDef = py.PyMethodDef;
pub const PyModuleDef = py.PyModuleDef;
pub const PyTypeObject = py.PyTypeObject;
pub const Py_ssize_t = py.Py_ssize_t;

// =============================================================================
// Type imports - Complex numbers
// =============================================================================

const complex_types = @import("types/complex.zig");
pub const Complex = complex_types.Complex;
pub const Complex32 = complex_types.Complex32;

// =============================================================================
// Type imports - DateTime
// =============================================================================

const datetime_types = @import("types/datetime.zig");
pub const Date = datetime_types.Date;
pub const Time = datetime_types.Time;
pub const DateTime = datetime_types.DateTime;
pub const TimeDelta = datetime_types.TimeDelta;

/// Initialize the datetime API - call this in module init if using datetime types
pub fn initDatetime() bool {
    return py.PyDateTime_Import();
}

// =============================================================================
// Type imports - Bytes
// =============================================================================

const bytes_types = @import("types/bytes.zig");
pub const Bytes = bytes_types.Bytes;
pub const ByteArray = bytes_types.ByteArray;

// =============================================================================
// Type imports - Path
// =============================================================================

const path_types = @import("types/path.zig");
pub const Path = path_types.Path;

// =============================================================================
// Type imports - Decimal
// =============================================================================

const decimal_mod = @import("types/decimal.zig");
pub const Decimal = decimal_mod.Decimal;
pub const initDecimal = decimal_mod.initDecimal;
pub const PyDecimal_Check = decimal_mod.PyDecimal_Check;
pub const PyDecimal_FromString = decimal_mod.PyDecimal_FromString;
pub const PyDecimal_AsString = decimal_mod.PyDecimal_AsString;

// =============================================================================
// Type imports - Buffer (numpy arrays)
// =============================================================================

const buffer_types = @import("types/buffer.zig");
pub const BufferView = buffer_types.BufferView;
pub const BufferViewMut = buffer_types.BufferViewMut;
pub const BufferInfo = buffer_types.BufferInfo;

// =============================================================================
// Collection imports - Dict
// =============================================================================

const dict_mod = @import("collections/dict.zig");
pub const DictView = dict_mod.DictView;
pub const Dict = dict_mod.Dict;

// =============================================================================
// Collection imports - List
// =============================================================================

const list_mod = @import("collections/list.zig");
pub const ListView = list_mod.ListView;
pub const AllocatedSlice = list_mod.AllocatedSlice;

// =============================================================================
// Collection imports - Set
// =============================================================================

const set_mod = @import("collections/set.zig");
pub const SetView = set_mod.SetView;
pub const Set = set_mod.Set;
pub const FrozenSet = set_mod.FrozenSet;

// =============================================================================
// Collection imports - Iterator
// =============================================================================

const iterator_mod = @import("collections/iterator.zig");
pub const IteratorView = iterator_mod.IteratorView;
pub const Iterator = iterator_mod.Iterator;
pub const LazyIterator = iterator_mod.LazyIterator;

// =============================================================================
// GC Support
// =============================================================================

const gc_mod = @import("gc.zig");
pub const GCVisitor = gc_mod.GCVisitor;

// =============================================================================
// Strong object references
// =============================================================================

const ref_mod = @import("ref.zig");
pub const Ref = ref_mod.Ref;
pub const isRefType = ref_mod.isRefType;

// =============================================================================
// Owned (allocator-backed return values)
// =============================================================================

const owned_mod = @import("types/owned.zig");
pub const Owned = owned_mod.Owned;
pub const owned = owned_mod.owned;

// =============================================================================
// GIL Control
// =============================================================================

const gil_mod = @import("gil.zig");
pub const GILGuard = gil_mod.GILGuard;
pub const GILState = gil_mod.GILState;
pub const releaseGIL = gil_mod.releaseGIL;
pub const acquireGIL = gil_mod.acquireGIL;
pub const allowThreads = gil_mod.allowThreads;
pub const allowThreadsTry = gil_mod.allowThreadsTry;

// =============================================================================
// Signal Handling
// =============================================================================

const signal_mod = @import("signal.zig");
pub const checkSignals = signal_mod.checkSignals;
pub const SignalError = signal_mod.SignalError;

// =============================================================================
// Base types for inheritance
// =============================================================================

const bases_mod = @import("bases.zig");
pub const bases = bases_mod.bases;
pub const object = bases_mod.object;

/// Declare a PyOZ class as the base for inheritance.
/// The child struct must embed its parent as the first field named `_parent`.
///
/// Usage:
///   const Dog = struct {
///       pub const __base__ = pyoz.base(Animal);
///       _parent: Animal,
///       breed: []const u8,
///   };
pub fn base(comptime Parent: type) type {
    return struct {
        pub const _is_pyoz_base = true;
        pub const ParentType = Parent;
    };
}

// =============================================================================
// Conversion
// =============================================================================

const conversion_mod = @import("conversion.zig");
pub const Converter = conversion_mod.Converter;
pub const Conversions = conversion_mod.Conversions;

// =============================================================================
// Callable
// =============================================================================

const callable_wrapper_mod = @import("callable.zig");
pub const Callable = callable_wrapper_mod.Callable;

// =============================================================================
// Exceptions
// =============================================================================

const exceptions_mod = @import("exceptions.zig");
pub const PythonException = exceptions_mod.PythonException;
pub const catchException = exceptions_mod.catchException;
pub const exceptionPending = exceptions_mod.exceptionPending;
pub const clearException = exceptions_mod.clearException;
pub const Null = exceptions_mod.Null;

/// Format a string using Zig's std.fmt, returning a null-terminated pointer.
/// Safe to pass to any function that copies the string immediately (e.g. PyErr_SetString).
/// The buffer lives in the caller's stack frame since this function is inline.
///
/// Usage:
///   return pyoz.raiseValueError(pyoz.fmt("{d} went wrong!", .{42}));
///   const msg = pyoz.fmt("hello {s}", .{"world"});
pub inline fn fmt(comptime format: []const u8, args: anytype) [*:0]const u8 {
    var buf: [4096]u8 = undefined;
    return (std.fmt.bufPrintZ(&buf, format, args) catch "fmt: message too long").ptr;
}

pub const raiseException = exceptions_mod.raiseException;
pub const raiseValueError = exceptions_mod.raiseValueError;
pub const raiseTypeError = exceptions_mod.raiseTypeError;
pub const raiseRuntimeError = exceptions_mod.raiseRuntimeError;
pub const raiseKeyError = exceptions_mod.raiseKeyError;
pub const raiseIndexError = exceptions_mod.raiseIndexError;
pub const raiseAttributeError = exceptions_mod.raiseAttributeError;
pub const raiseMemoryError = exceptions_mod.raiseMemoryError;
pub const raiseOSError = exceptions_mod.raiseOSError;
pub const raiseNotImplementedError = exceptions_mod.raiseNotImplementedError;
pub const raiseOverflowError = exceptions_mod.raiseOverflowError;
pub const raiseZeroDivisionError = exceptions_mod.raiseZeroDivisionError;
pub const raiseFileNotFoundError = exceptions_mod.raiseFileNotFoundError;
pub const raisePermissionError = exceptions_mod.raisePermissionError;
pub const raiseTimeoutError = exceptions_mod.raiseTimeoutError;
pub const raiseConnectionError = exceptions_mod.raiseConnectionError;
pub const raiseEOFError = exceptions_mod.raiseEOFError;
pub const raiseImportError = exceptions_mod.raiseImportError;
pub const raiseStopIteration = exceptions_mod.raiseStopIteration;
pub const raiseSystemError = exceptions_mod.raiseSystemError;
pub const raiseBufferError = exceptions_mod.raiseBufferError;
pub const raiseArithmeticError = exceptions_mod.raiseArithmeticError;
pub const raiseRecursionError = exceptions_mod.raiseRecursionError;
pub const raiseAssertionError = exceptions_mod.raiseAssertionError;
pub const raiseFloatingPointError = exceptions_mod.raiseFloatingPointError;
pub const raiseLookupError = exceptions_mod.raiseLookupError;
pub const raiseNameError = exceptions_mod.raiseNameError;
pub const raiseUnboundLocalError = exceptions_mod.raiseUnboundLocalError;
pub const raiseReferenceError = exceptions_mod.raiseReferenceError;
pub const raiseStopAsyncIteration = exceptions_mod.raiseStopAsyncIteration;
pub const raiseSyntaxError = exceptions_mod.raiseSyntaxError;
pub const raiseUnicodeError = exceptions_mod.raiseUnicodeError;
pub const raiseModuleNotFoundError = exceptions_mod.raiseModuleNotFoundError;
pub const raiseBlockingIOError = exceptions_mod.raiseBlockingIOError;
pub const raiseBrokenPipeError = exceptions_mod.raiseBrokenPipeError;
pub const raiseChildProcessError = exceptions_mod.raiseChildProcessError;
pub const raiseConnectionAbortedError = exceptions_mod.raiseConnectionAbortedError;
pub const raiseConnectionRefusedError = exceptions_mod.raiseConnectionRefusedError;
pub const raiseConnectionResetError = exceptions_mod.raiseConnectionResetError;
pub const raiseFileExistsError = exceptions_mod.raiseFileExistsError;
pub const raiseInterruptedError = exceptions_mod.raiseInterruptedError;
pub const raiseIsADirectoryError = exceptions_mod.raiseIsADirectoryError;
pub const raiseNotADirectoryError = exceptions_mod.raiseNotADirectoryError;
pub const raiseProcessLookupError = exceptions_mod.raiseProcessLookupError;
pub const PyExc = exceptions_mod.PyExc;
pub const ExcBase = exceptions_mod.ExcBase;
pub const ExceptionDef = exceptions_mod.ExceptionDef;
pub const exception = exceptions_mod.exception;
pub const raise = exceptions_mod.raise;

// =============================================================================
// Error mapping
// =============================================================================

const errors_mod = @import("errors.zig");
pub const ErrorMapping = errors_mod.ErrorMapping;
pub const mapError = errors_mod.mapError;
pub const mapErrorMsg = errors_mod.mapErrorMsg;
pub const setErrorFromMapping = errors_mod.setErrorFromMapping;

// =============================================================================
// Enums
// =============================================================================

const enums_mod = @import("enums.zig");
pub const EnumDef = enums_mod.EnumDef;
pub const enumDef = enums_mod.enumDef;
// Legacy aliases (deprecated - use enumDef which auto-detects)
pub const StrEnumDef = enums_mod.StrEnumDef;
pub const strEnumDef = enums_mod.strEnumDef;

// =============================================================================
// Function wrappers
// =============================================================================

const wrappers_mod = @import("wrappers.zig");
pub const wrapFunction = wrappers_mod.wrapFunction;
pub const wrapFunctionWithClasses = wrappers_mod.wrapFunctionWithClasses;
pub const wrapFunctionWithKeywords = wrappers_mod.wrapFunctionWithKeywords;
pub const wrapFunctionWithNamedKeywords = wrappers_mod.wrapFunctionWithNamedKeywords;
pub const wrapFunctionWithErrorMapping = wrappers_mod.wrapFunctionWithErrorMapping;
pub const PyCFunctionWithKeywords = wrappers_mod.PyCFunctionWithKeywords;
pub const FuncDefEntry = wrappers_mod.FuncDefEntry;
pub const func = wrappers_mod.func;
pub const KwFuncDefEntry = wrappers_mod.KwFuncDefEntry;
pub const kwfunc = wrappers_mod.kwfunc;
pub const Args = wrappers_mod.Args;
pub const NamedKwFuncDefEntry = wrappers_mod.NamedKwFuncDefEntry;
pub const kwfunc_named = wrappers_mod.kwfunc_named;

// =============================================================================
// Class definitions
// =============================================================================

/// Class definition for the module
pub const ClassDef = struct {
    name: [*:0]const u8,
    // In ABI3 mode, type_obj is null - we get it from initType() at runtime
    // In non-ABI3 mode, type_obj points to the static type object
    type_obj: if (abi.abi3_enabled) ?*PyTypeObject else *PyTypeObject,
    zig_type: type,
};

/// Create a class definition from a Zig struct
pub fn class(comptime name: [*:0]const u8, comptime T: type) ClassDef {
    return .{
        .name = name,
        .type_obj = if (comptime abi.abi3_enabled) null else &class_mod.getWrapper(T).type_object,
        .zig_type = T,
    };
}

// =============================================================================
// Module builder
// =============================================================================

/// Extract class info (name + type) from class definitions
fn extractClassInfo(comptime classes: anytype) []const class_mod.ClassInfo {
    comptime {
        var infos: [classes.len]class_mod.ClassInfo = undefined;
        for (classes, 0..) |cls, i| {
            // Detect PyOZ parent class via __base__._is_pyoz_base marker
            const parent_type: ?type = blk: {
                if (!@hasDecl(cls.zig_type, "__base__")) break :blk null;
                const BaseDecl = @TypeOf(cls.zig_type.__base__);
                if (BaseDecl != type) break :blk null;
                const BaseType = cls.zig_type.__base__;
                if (!@hasDecl(BaseType, "_is_pyoz_base")) break :blk null;
                break :blk BaseType.ParentType;
            };
            // Validate parent is listed before child
            if (parent_type) |pt| {
                var found = false;
                for (infos[0..i]) |prev| {
                    if (prev.zig_type == pt) {
                        found = true;
                        break;
                    }
                }
                if (!found) {
                    @compileError("PyOZ class inheritance: parent class must be listed before child class in the classes array");
                }
            }

            infos[i] = .{ .name = cls.name, .zig_type = cls.zig_type, .parent_zig_type = parent_type };
        }
        const final = infos;
        return &final;
    }
}

// Helper to check if a type or any of its components uses Decimal
fn usesDecimalType(comptime T: type) bool {
    const info = @typeInfo(T);
    return switch (info) {
        .@"struct" => T == Decimal,
        .optional => |opt| usesDecimalType(opt.child),
        .pointer => |ptr| usesDecimalType(ptr.child),
        else => false,
    };
}

// Helper to check if a type or any of its components uses DateTime types
fn usesDateTimeType(comptime T: type) bool {
    const info = @typeInfo(T);
    return switch (info) {
        .@"struct" => T == DateTime or T == Date or T == Time or T == TimeDelta,
        .optional => |opt| usesDateTimeType(opt.child),
        .pointer => |ptr| usesDateTimeType(ptr.child),
        else => false,
    };
}

// Check if any function in the list uses Decimal types
fn anyFuncUsesDecimal(comptime funcs_list: anytype) bool {
    for (funcs_list) |f| {
        const Fn = @TypeOf(f.func);
        const fn_info = @typeInfo(Fn).@"fn";
        // Check return type
        if (fn_info.return_type) |ret| {
            if (usesDecimalType(ret)) return true;
        }
        // Check parameters
        for (fn_info.params) |param| {
            if (param.type) |ptype| {
                if (usesDecimalType(ptype)) return true;
            }
        }
    }
    return false;
}

// Check if any function in the list uses DateTime types
fn anyFuncUsesDateTime(comptime funcs_list: anytype) bool {
    for (funcs_list) |f| {
        const Fn = @TypeOf(f.func);
        const fn_info = @typeInfo(Fn).@"fn";
        // Check return type
        if (fn_info.return_type) |ret| {
            if (usesDateTimeType(ret)) return true;
        }
        // Check parameters
        for (fn_info.params) |param| {
            if (param.type) |ptype| {
                if (usesDateTimeType(ptype)) return true;
            }
        }
    }
    return false;
}

/// Constant definition for module-level constants
pub const ConstDef = struct {
    name: [*:0]const u8,
    value_type: type,
    value: *const anyopaque,
};

/// Create a constant definition
pub fn constant(comptime name: [*:0]const u8, comptime value: anytype) ConstDef {
    const T = @TypeOf(value);
    const static = struct {
        const val: T = value;
    };
    return .{
        .name = name,
        .value_type = T,
        .value = @ptrCast(&static.val),
    };
}

// =============================================================================
// Test definitions
// =============================================================================

/// A single inline test case definition
pub const TestDef = struct {
    name: []const u8,
    body: []const u8,
    exception: ?[]const u8, // null = assert test, non-null = assertRaises
};

/// Create a test definition (assert-style).
/// The body is Python code that runs inside a unittest method.
pub fn @"test"(comptime name: []const u8, comptime body: []const u8) TestDef {
    return .{ .name = name, .body = body, .exception = null };
}

/// Create a test definition that expects an exception.
/// The body is Python code that should raise the given exception.
pub fn testRaises(comptime name: []const u8, comptime exc: []const u8, comptime body: []const u8) TestDef {
    return .{ .name = name, .body = body, .exception = exc };
}

/// A single inline benchmark definition
pub const BenchDef = struct {
    name: []const u8,
    body: []const u8,
};

/// Create a benchmark definition.
/// The body is Python code to time.
pub fn bench(comptime name: []const u8, comptime body: []const u8) BenchDef {
    return .{ .name = name, .body = body };
}

// =============================================================================
// Property definition
// =============================================================================

/// Property definition struct - use with property() function
/// Example:
/// ```zig
/// pub const length = property(.{
///     .get = fn(self: *const Self) f64 { return @sqrt(self.x * self.x + self.y * self.y); },
///     .set = fn(self: *Self, value: f64) void { ... },
///     .doc = "The length of the vector",
/// });
/// ```
pub fn Property(comptime Config: type) type {
    return struct {
        pub const __pyoz_property__ = true;
        pub const config = Config;

        // Extract types from config
        pub const has_getter = @hasField(Config, "get");
        pub const has_setter = @hasField(Config, "set");
        pub const has_doc = @hasField(Config, "doc");

        pub fn getDoc() ?[*:0]const u8 {
            if (has_doc) {
                return @field(Config, "doc");
            }
            return null;
        }
    };
}

/// Create a property with getter, optional setter, and optional docstring
/// Usage:
/// ```zig
/// const Point = struct {
///     x: f64,
///     y: f64,
///     const Self = @This();
///
///     pub const length = pyoz.property(.{
///         .get = struct {
///             fn get(self: *const Self) f64 {
///                 return @sqrt(self.x * self.x + self.y * self.y);
///             }
///         }.get,
///         .set = struct {
///             fn set(self: *Self, value: f64) void {
///                 const current = @sqrt(self.x * self.x + self.y * self.y);
///                 if (current > 0) {
///                     const factor = value / current;
///                     self.x *= factor;
///                     self.y *= factor;
///                 }
///             }
///         }.set,
///         .doc = "The length (magnitude) of the vector",
///     });
/// };
/// ```
pub fn property(comptime config: anytype) type {
    return Property(@TypeOf(config));
}

// =============================================================================
// Test/Bench content generators (comptime)
// =============================================================================

/// Convert a test name to a valid Python function name.
/// "add returns correct result" -> "add_returns_correct_result"
fn slugify(comptime name: []const u8) []const u8 {
    comptime {
        var result: [name.len]u8 = undefined;
        for (name, 0..) |c, i| {
            if (c == ' ' or c == '-' or c == '.' or c == '/' or c == '\\') {
                result[i] = '_';
            } else if (c >= 'A' and c <= 'Z') {
                result[i] = c + 32; // lowercase
            } else if ((c >= 'a' and c <= 'z') or (c >= '0' and c <= '9') or c == '_') {
                result[i] = c;
            } else {
                result[i] = '_';
            }
        }
        const final = result;
        return &final;
    }
}

/// Capitalize the first letter of a string.
/// "mymod" -> "Mymod"
fn capitalizeFirst(comptime s: []const u8) []const u8 {
    comptime {
        if (s.len == 0) return s;
        var result: [s.len]u8 = undefined;
        result[0] = if (s[0] >= 'a' and s[0] <= 'z') s[0] - 32 else s[0];
        for (s[1..], 1..) |c, i| {
            result[i] = c;
        }
        const final = result;
        return &final;
    }
}

/// Indent each line of a multiline string by the given number of spaces.
fn indentLines(comptime body: []const u8, comptime spaces: usize) []const u8 {
    comptime {
        const indent = " " ** spaces;
        var result: []const u8 = "";
        var start: usize = 0;
        for (body, 0..) |c, i| {
            if (c == '\n') {
                result = result ++ indent ++ body[start..i] ++ "\n";
                start = i + 1;
            }
        }
        // Last line (no trailing newline)
        if (start < body.len) {
            result = result ++ indent ++ body[start..] ++ "\n";
        }
        return result;
    }
}

/// Generate a complete Python unittest file from inline test definitions.
fn generateTestContent(comptime config: anytype) []const u8 {
    comptime {
        const tests_list = if (@hasField(@TypeOf(config), "tests")) config.tests else &[_]TestDef{};
        if (tests_list.len == 0) return "";

        const mod_name: []const u8 = blk: {
            var len: usize = 0;
            while (config.name[len] != 0) : (len += 1) {}
            break :blk config.name[0..len];
        };

        var result: []const u8 =
            "import unittest\n" ++
            "import " ++ mod_name ++ "\n" ++
            "\n" ++
            "\n" ++
            "class Test" ++ capitalizeFirst(mod_name) ++ "(unittest.TestCase):\n";

        for (tests_list) |t| {
            const method_name = "test_" ++ slugify(t.name);
            result = result ++ "    def " ++ method_name ++ "(self):\n";

            if (t.exception) |exc| {
                // assertRaises style
                result = result ++ "        with self.assertRaises(" ++ exc ++ "):\n";
                result = result ++ indentLines(t.body, 12);
            } else {
                // Plain assert style
                result = result ++ indentLines(t.body, 8);
            }
            result = result ++ "\n";
        }

        result = result ++
            "\n" ++
            "if __name__ == \"__main__\":\n" ++
            "    unittest.main()\n";

        return result;
    }
}

/// Generate a complete Python benchmark script from inline benchmark definitions.
fn generateBenchContent(comptime config: anytype) []const u8 {
    comptime {
        const bench_list = if (@hasField(@TypeOf(config), "benchmarks")) config.benchmarks else &[_]BenchDef{};
        if (bench_list.len == 0) return "";

        const mod_name: []const u8 = blk: {
            var len: usize = 0;
            while (config.name[len] != 0) : (len += 1) {}
            break :blk config.name[0..len];
        };

        var result: []const u8 =
            "import timeit\n" ++
            "import " ++ mod_name ++ "\n" ++
            "\n" ++
            "\n" ++
            "def run_benchmarks():\n" ++
            "    results = []\n";

        for (bench_list) |b| {
            const fn_name = "bench_" ++ slugify(b.name);
            result = result ++ "    def " ++ fn_name ++ "():\n";
            result = result ++ indentLines(b.body, 8);
            result = result ++ "    t = timeit.timeit(" ++ fn_name ++ ", number=100000)\n";
            result = result ++ "    results.append((\"" ++ b.name ++ "\", t))\n\n";
        }

        result = result ++
            "    print()\n" ++
            "    print(\"Benchmark Results:\")\n" ++
            "    print(\"-\" * 60)\n" ++
            "    for name, elapsed in results:\n" ++
            "        ops = 100000 / elapsed\n" ++
            "        print(f\"  {name:<40} {ops:>12,.0f} ops/s\")\n" ++
            "    print(\"-\" * 60)\n" ++
            "\n" ++
            "\n" ++
            "if __name__ == \"__main__\":\n" ++
            "    run_benchmarks()\n";

        return result;
    }
}

/// Create a Python module from configuration
pub fn module(comptime config: anytype) type {
    const classes = config.classes;
    const funcs = config.funcs;
    const class_infos = extractClassInfo(classes);
    const exceptions = if (@hasField(@TypeOf(config), "exceptions")) config.exceptions else &[_]ExceptionDef{};
    const num_exceptions = exceptions.len;
    const error_mappings = if (@hasField(@TypeOf(config), "error_mappings")) config.error_mappings else &[_]ErrorMapping{};
    const enums = if (@hasField(@TypeOf(config), "enums")) config.enums else &[_]EnumDef{};
    const num_enums = enums.len;
    // Legacy str_enums support - merge into unified enums list
    const legacy_str_enums = if (@hasField(@TypeOf(config), "str_enums")) config.str_enums else &[_]EnumDef{};
    const num_legacy_str_enums = legacy_str_enums.len;
    const consts = if (@hasField(@TypeOf(config), "consts")) config.consts else &[_]ConstDef{};
    const num_consts = consts.len;
    // Inline test/benchmark definitions (optional)
    _ = if (@hasField(@TypeOf(config), "tests")) config.tests else &[_]TestDef{};
    _ = if (@hasField(@TypeOf(config), "benchmarks")) config.benchmarks else &[_]BenchDef{};

    // Detect at comptime if this module uses Decimal or DateTime types
    const needs_decimal_init = anyFuncUsesDecimal(funcs);
    const needs_datetime_init = anyFuncUsesDateTime(funcs);

    return struct {
        // Generate method definitions array with class-aware wrappers
        var methods: [funcs.len + 1]PyMethodDef = blk: {
            var m: [funcs.len + 1]PyMethodDef = undefined;
            for (funcs, 0..) |f, i| {
                // Check if this is a named keyword-argument function
                const is_named_kwargs = @hasField(@TypeOf(f), "is_named_kwargs") and f.is_named_kwargs;
                // Check if this is a positional keyword-argument function
                const is_kwargs = @hasField(@TypeOf(f), "is_kwargs") and f.is_kwargs;

                if (is_named_kwargs) {
                    m[i] = .{
                        .ml_name = f.name,
                        .ml_meth = @ptrCast(wrapFunctionWithNamedKeywords(f.func, class_infos)),
                        .ml_flags = py.METH_VARARGS | py.METH_KEYWORDS,
                        .ml_doc = f.doc,
                    };
                } else if (is_kwargs) {
                    m[i] = .{
                        .ml_name = f.name,
                        .ml_meth = @ptrCast(wrapFunctionWithKeywords(f.func, class_infos)),
                        .ml_flags = py.METH_VARARGS | py.METH_KEYWORDS,
                        .ml_doc = f.doc,
                    };
                } else {
                    // Use error mapping wrapper if mappings are defined
                    if (error_mappings.len > 0) {
                        m[i] = .{
                            .ml_name = f.name,
                            .ml_meth = wrapFunctionWithErrorMapping(f.func, class_infos, error_mappings),
                            .ml_flags = py.METH_VARARGS,
                            .ml_doc = f.doc,
                        };
                    } else {
                        m[i] = .{
                            .ml_name = f.name,
                            .ml_meth = wrapFunctionWithClasses(f.func, class_infos),
                            .ml_flags = py.METH_VARARGS,
                            .ml_doc = f.doc,
                        };
                    }
                }
            }
            m[funcs.len] = .{
                .ml_name = null,
                .ml_meth = null,
                .ml_flags = 0,
                .ml_doc = null,
            };
            break :blk m;
        };

        // Optional user-provided post-init callback
        const module_init_fn: ?*const fn (*PyObject) callconv(.c) c_int =
            if (@hasField(@TypeOf(config), "module_init")) config.module_init else null;

        // Py_mod_exec slot function — called by Python to populate the module (PEP 489 phase 2)
        fn moduleExec(mod_obj: ?*PyObject) callconv(.c) c_int {
            const mod: *PyObject = mod_obj orelse return -1;

            // Initialize special type APIs at module load time (detected at comptime)
            if (needs_datetime_init) {
                _ = initDatetime();
            }
            if (needs_decimal_init) {
                _ = initDecimal();
            }

            // Add classes to the module
            inline for (classes) |cls| {
                const Wrapper = class_mod.getWrapperWithName(cls.name, cls.zig_type, class_infos);

                // Build qualified name "module.ClassName" so Python derives __module__
                const qualified_name: [*:0]const u8 = comptime blk: {
                    @setEvalBranchQuota(10000);
                    const mod_name: [*:0]const u8 = config.name;
                    const cls_str: [*:0]const u8 = cls.name;
                    // Count lengths
                    var mod_len: usize = 0;
                    while (mod_name[mod_len] != 0) mod_len += 1;
                    var cls_len: usize = 0;
                    while (cls_str[cls_len] != 0) cls_len += 1;
                    // Build "module.ClassName\0"
                    const total = mod_len + 1 + cls_len;
                    var buf: [total:0]u8 = undefined;
                    for (0..mod_len) |i| buf[i] = mod_name[i];
                    buf[mod_len] = '.';
                    for (0..cls_len) |i| buf[mod_len + 1 + i] = cls_str[i];
                    buf[total] = 0;
                    const final = buf;
                    break :blk @ptrCast(&final);
                };

                // Initialize type with qualified name for proper __module__
                const type_obj = Wrapper.initTypeWithName(qualified_name) orelse {
                    return -1;
                };

                // Add __slots__ tuple with field names to the type's __dict__
                // Note: tp_dict access may not work reliably in ABI3 for heap types
                if (!abi.abi3_enabled) {
                    const slots_tuple = class_mod.createSlotsTuple(cls.zig_type);
                    if (slots_tuple) |st| {
                        const type_dict = type_obj.tp_dict;
                        if (type_dict) |dict| {
                            _ = py.PyDict_SetItemString(dict, "__slots__", st);
                        }
                        py.Py_DecRef(st);
                    }

                    // Add class attributes (classattr_NAME declarations)
                    if (type_obj.tp_dict) |type_dict| {
                        if (!class_mod.addClassAttributes(cls.zig_type, type_dict)) {
                            return -1;
                        }
                    }
                } else {
                    // In ABI3 mode, use PyObject_SetAttrString to set class attributes
                    // since tp_dict is not accessible
                    const type_as_obj: *py.PyObject = @ptrCast(@alignCast(type_obj));
                    if (!class_mod.addClassAttributesAbi3(cls.zig_type, type_as_obj)) {
                        return -1;
                    }
                }

                // Add type to module
                // In ABI3 mode, use PyModule_AddObject with the known name
                // since PyModule_AddType may not be available
                if (comptime abi.abi3_enabled) {
                    // PyModule_AddObject steals reference on success
                    const type_as_obj: *py.PyObject = @ptrCast(@alignCast(type_obj));
                    py.Py_IncRef(type_as_obj);
                    if (py.c.PyModule_AddObject(mod, cls.name, type_as_obj) < 0) {
                        py.Py_DecRef(type_as_obj);
                        return -1;
                    }
                } else {
                    if (py.PyModule_AddType(mod, type_obj) < 0) {
                        return -1;
                    }
                }
            }

            // Create and add exceptions to the module
            inline for (0..num_exceptions) |i| {
                const base_exc = exceptions[i].base.toPyObject();
                const exc_type = py.PyErr_NewException(
                    &exception_full_names[i],
                    base_exc,
                    null,
                ) orelse {
                    return -1;
                };
                exception_types[i] = exc_type;

                // Set docstring if provided
                if (exceptions[i].doc) |doc| {
                    const doc_str = py.PyUnicode_FromString(doc);
                    if (doc_str) |ds| {
                        _ = py.PyObject_SetAttrString(exc_type, "__doc__", ds);
                        py.Py_DecRef(ds);
                    }
                }

                // Add to module
                if (py.PyModule_AddObject(mod, exceptions[i].name, exc_type) < 0) {
                    py.Py_DecRef(exc_type);
                    return -1;
                }
            }

            // Create and add enums to the module (unified - auto-detects IntEnum vs StrEnum)
            inline for (0..num_enums) |i| {
                const enum_def = enums[i];
                const enum_type = if (enum_def.is_str_enum)
                    module_mod.createStrEnum(enum_def.zig_type, enum_def.name)
                else
                    module_mod.createEnum(enum_def.zig_type, enum_def.name);

                const enum_obj = enum_type orelse {
                    return -1;
                };

                // Add to module (steals reference on success)
                if (py.PyModule_AddObject(mod, enum_def.name, enum_obj) < 0) {
                    py.Py_DecRef(enum_obj);
                    return -1;
                }
            }

            // Legacy str_enums support (deprecated - use .enums with auto-detection)
            inline for (0..num_legacy_str_enums) |i| {
                const str_enum_def = legacy_str_enums[i];
                const str_enum_type = module_mod.createStrEnum(str_enum_def.zig_type, str_enum_def.name) orelse {
                    return -1;
                };

                // Add to module (steals reference on success)
                if (py.PyModule_AddObject(mod, str_enum_def.name, str_enum_type) < 0) {
                    py.Py_DecRef(str_enum_type);
                    return -1;
                }
            }

            // Add module-level constants
            inline for (0..num_consts) |i| {
                const const_def = consts[i];
                const T = const_def.value_type;
                const value_ptr: *const T = @ptrCast(@alignCast(const_def.value));
                const value = value_ptr.*;

                // Convert to Python object based on type
                const py_value = Conversions.toPy(T, value) orelse {
                    return -1;
                };

                // Add to module (steals reference on success)
                if (py.PyModule_AddObject(mod, const_def.name, py_value) < 0) {
                    py.Py_DecRef(py_value);
                    return -1;
                }
            }

            // Call user-provided post-init callback if present
            if (module_init_fn) |user_init| {
                if (user_init(mod) < 0) return -1;
            }

            return 0;
        }

        // Module slots for multi-phase initialization (PEP 489)
        var module_slots = [_]py.c.PyModuleDef_Slot{
            .{ .slot = py.c.Py_mod_exec, .value = @ptrCast(@constCast(&moduleExec)) },
            .{ .slot = 0, .value = null },
        };

        var module_def: PyModuleDef = .{
            .m_base = py.PyModuleDef_HEAD_INIT,
            .m_name = config.name,
            .m_doc = config.doc,
            .m_size = 0,
            .m_methods = &methods,
            .m_slots = @ptrCast(&module_slots),
            .m_traverse = null,
            .m_clear = null,
            .m_free = null,
        };

        // Generate full exception names at comptime (e.g., "mymodule.MyError")
        const exception_full_names: [num_exceptions][256:0]u8 = blk: {
            var names: [num_exceptions][256:0]u8 = undefined;
            for (exceptions, 0..) |exc, i| {
                var buf: [256:0]u8 = [_:0]u8{0} ** 256;
                // Get module name length by finding null terminator
                var mod_len: usize = 0;
                while (config.name[mod_len] != 0) : (mod_len += 1) {}
                // Get exception name length
                var exc_len: usize = 0;
                while (exc.name[exc_len] != 0) : (exc_len += 1) {}
                // Copy module name
                for (0..mod_len) |j| {
                    buf[j] = config.name[j];
                }
                buf[mod_len] = '.';
                // Copy exception name
                for (0..exc_len) |j| {
                    buf[mod_len + 1 + j] = exc.name[j];
                }
                names[i] = buf;
            }
            break :blk names;
        };

        // Runtime storage for exception types
        var exception_types: [num_exceptions]?*PyObject = [_]?*PyObject{null} ** num_exceptions;

        /// Initialize the module using multi-phase initialization (PEP 489).
        /// Returns a module def object; Python calls moduleExec to populate it.
        pub fn init() ?*PyObject {
            return py.PyModuleDef_Init(&module_def);
        }

        /// Reference to a module exception for raising
        pub const ExceptionRef = struct {
            idx: usize,

            /// Raise this exception with a message
            pub fn raise(self: ExceptionRef, msg: [*:0]const u8) void {
                if (exception_types[self.idx]) |exc_type| {
                    py.PyErr_SetString(exc_type, msg);
                } else {
                    py.PyErr_SetString(py.PyExc_RuntimeError(), msg);
                }
            }
        };

        /// Get an exception reference by index (for use in raise)
        pub fn getException(comptime idx: usize) ExceptionRef {
            return ExceptionRef{ .idx = idx };
        }

        // Expose class types for external use
        pub const registered_classes = class_infos;

        /// Class-aware converter that knows about all registered classes.
        /// Use this instead of pyoz.Conversions when converting registered
        /// class instances (e.g. Module.toPy(Node, my_node)).
        pub const ClassConverter = conversion_mod.Converter(class_infos);
        pub const toPy = ClassConverter.toPy;
        pub const fromPy = ClassConverter.fromPy;

        /// Recover the wrapping PyObject from a `self: *const T` pointer.
        /// Use this to get the PyObject for setting Ref fields:
        ///     node._parser.set(Module.selfObject(GrammarParser, self));
        pub fn selfObject(comptime T: type, ptr: *const T) *PyObject {
            const Wrapper = class_mod.getWrapperWithName(comptime getClassNameForType(T), T, class_infos);
            return Wrapper.objectFromData(ptr);
        }

        fn getClassNameForType(comptime T: type) [*:0]const u8 {
            inline for (class_infos) |info| {
                if (info.zig_type == T) return info.name;
            }
            @compileError("selfObject: type " ++ @typeName(T) ++ " is not a registered class");
        }

        /// Generate Python type stub (.pyi) content for this module
        /// Returns the complete stub file content as a comptime string
        pub fn getStubs() []const u8 {
            return comptime stubs_mod.generateModuleStubs(config);
        }

        /// Stubs data for extraction by pyoz CLI (exported as data symbols)
        const __pyoz_stubs_slice__: []const u8 = blk: {
            @setEvalBranchQuota(100000);
            break :blk stubs_mod.generateModuleStubs(config);
        };
        pub const __pyoz_stubs_ptr__: [*]const u8 = __pyoz_stubs_slice__.ptr;
        pub const __pyoz_stubs_len__: usize = __pyoz_stubs_slice__.len;

        // Export data symbols for the symbol reader to find (works with non-stripped binaries)
        comptime {
            @export(&__pyoz_stubs_ptr__, .{ .name = "__pyoz_stubs_data__" });
            @export(&__pyoz_stubs_len__, .{ .name = "__pyoz_stubs_len__" });
        }

        /// Stubs data in a named section that survives stripping.
        /// Format: 8-byte magic "PYOZSTUB", 8-byte little-endian length, then content.
        /// Section name: ".pyozstub" (ELF/PE), "__DATA,__pyozstub" (Mach-O)
        const builtin = @import("builtin");
        const pyoz_section_name = if (builtin.os.tag == .macos) "__DATA,__pyozstub" else ".pyozstub";
        pub const __pyoz_stubs_section__: [16 + __pyoz_stubs_slice__.len]u8 linksection(pyoz_section_name) = blk: {
            var data: [16 + __pyoz_stubs_slice__.len]u8 = undefined;
            // 8-byte magic header
            @memcpy(data[0..8], "PYOZSTUB");
            // 8-byte little-endian length
            const len = __pyoz_stubs_slice__.len;
            data[8] = @truncate(len);
            data[9] = @truncate(len >> 8);
            data[10] = @truncate(len >> 16);
            data[11] = @truncate(len >> 24);
            data[12] = @truncate(len >> 32);
            data[13] = @truncate(len >> 40);
            data[14] = @truncate(len >> 48);
            data[15] = @truncate(len >> 56);
            // Copy stub content
            @memcpy(data[16..], __pyoz_stubs_slice__);
            break :blk data;
        };

        // Force the section data to be retained by exporting it
        comptime {
            @export(&__pyoz_stubs_section__, .{ .name = "__pyoz_stubs_section__" });
        }

        /// Test data embedded in a named section (same pattern as stubs).
        /// Format: 8-byte magic "PYOZTEST", 8-byte little-endian length, then content.
        const __pyoz_tests_slice__: []const u8 = blk: {
            @setEvalBranchQuota(100000);
            break :blk generateTestContent(config);
        };

        const pyoz_test_section_name = if (builtin.os.tag == .macos) "__DATA,__pyoztest" else ".pyoztest";
        pub const __pyoz_tests_section__: [16 + __pyoz_tests_slice__.len]u8 linksection(pyoz_test_section_name) = blk: {
            var data: [16 + __pyoz_tests_slice__.len]u8 = undefined;
            @memcpy(data[0..8], "PYOZTEST");
            const len = __pyoz_tests_slice__.len;
            data[8] = @truncate(len);
            data[9] = @truncate(len >> 8);
            data[10] = @truncate(len >> 16);
            data[11] = @truncate(len >> 24);
            data[12] = @truncate(len >> 32);
            data[13] = @truncate(len >> 40);
            data[14] = @truncate(len >> 48);
            data[15] = @truncate(len >> 56);
            @memcpy(data[16..], __pyoz_tests_slice__);
            break :blk data;
        };

        comptime {
            @export(&__pyoz_tests_section__, .{ .name = "__pyoz_tests_section__" });
        }

        /// Benchmark data embedded in a named section.
        /// Format: 8-byte magic "PYOZBENC", 8-byte little-endian length, then content.
        const __pyoz_bench_slice__: []const u8 = blk: {
            @setEvalBranchQuota(100000);
            break :blk generateBenchContent(config);
        };

        const pyoz_bench_section_name = if (builtin.os.tag == .macos) "__DATA,__pyozbenc" else ".pyozbenc";
        pub const __pyoz_bench_section__: [16 + __pyoz_bench_slice__.len]u8 linksection(pyoz_bench_section_name) = blk: {
            var data: [16 + __pyoz_bench_slice__.len]u8 = undefined;
            @memcpy(data[0..8], "PYOZBENC");
            const len = __pyoz_bench_slice__.len;
            data[8] = @truncate(len);
            data[9] = @truncate(len >> 8);
            data[10] = @truncate(len >> 16);
            data[11] = @truncate(len >> 24);
            data[12] = @truncate(len >> 32);
            data[13] = @truncate(len >> 40);
            data[14] = @truncate(len >> 48);
            data[15] = @truncate(len >> 56);
            @memcpy(data[16..], __pyoz_bench_slice__);
            break :blk data;
        };

        comptime {
            @export(&__pyoz_bench_section__, .{ .name = "__pyoz_bench_section__" });
        }
    };
}

// =============================================================================
// Error types
// =============================================================================

pub const PyErr = error{
    TypeError,
    ValueError,
    RuntimeError,
    ConversionError,
    MissingArguments,
    WrongArgumentCount,
    InvalidArgument,
};

// =============================================================================
// Submodule Helpers
// =============================================================================

/// Re-export Module from module.zig
pub const Module = @import("module.zig").Module;

/// Create a method definition entry (for use in manual method arrays)
pub fn methodDef(comptime name: [*:0]const u8, comptime func_ptr: *const py.PyCFunction, comptime doc: ?[*:0]const u8) PyMethodDef {
    return .{
        .ml_name = name,
        .ml_meth = func_ptr.*,
        .ml_flags = py.METH_VARARGS,
        .ml_doc = doc,
    };
}

/// Create a sentinel (null terminator) for method arrays
pub fn methodDefSentinel() PyMethodDef {
    return .{
        .ml_name = null,
        .ml_meth = null,
        .ml_flags = 0,
        .ml_doc = null,
    };
}

/// Wrap a Zig function for use in submodule method arrays
pub fn wrapFunc(comptime zig_func: anytype) py.PyCFunction {
    return wrapFunctionWithErrorMapping(zig_func, &[_]class_mod.ClassInfo{}, &[_]ErrorMapping{
        mapError("NegativeValue", .ValueError),
        mapErrorMsg("ValueTooLarge", .ValueError, "Value exceeds maximum"),
        mapError("IndexOutOfBounds", .IndexError),
        mapError("DivisionByZero", .RuntimeError),
    });
}

// =============================================================================
// Python Embedding
// =============================================================================

/// Errors that can occur during Python embedding operations
pub const EmbedError = error{
    InitializationFailed,
    ExecutionFailed,
    ConversionFailed,
    ImportFailed,
    AttributeError,
    CallFailed,
};

/// High-level Python embedding interface.
pub const Python = struct {
    main_dict: *PyObject,

    pub fn init() EmbedError!Python {
        if (!py.Py_IsInitialized()) {
            py.Py_Initialize();
            if (!py.Py_IsInitialized()) {
                return EmbedError.InitializationFailed;
            }
        }

        const main_module = py.PyImport_AddModule("__main__") orelse
            return EmbedError.InitializationFailed;
        const main_dict = py.PyModule_GetDict(main_module) orelse
            return EmbedError.InitializationFailed;

        return .{ .main_dict = main_dict };
    }

    pub fn deinit(self: *Python) void {
        _ = self;
        if (py.Py_IsInitialized()) {
            _ = py.Py_FinalizeEx();
        }
    }

    pub fn exec(self: *Python, code: [*:0]const u8) EmbedError!void {
        const result = py.PyRun_String(code, py.Py_file_input, self.main_dict, self.main_dict);
        if (result) |r| {
            py.Py_DecRef(r);
        } else {
            if (py.PyErr_Occurred() != null) {
                py.PyErr_Print();
            }
            return EmbedError.ExecutionFailed;
        }
    }

    pub fn eval(self: *Python, comptime T: type, expr: [*:0]const u8) EmbedError!T {
        const result = py.PyRun_String(expr, py.Py_eval_input, self.main_dict, self.main_dict);
        if (result) |py_result| {
            defer py.Py_DecRef(py_result);
            return Conversions.fromPy(T, py_result) catch return EmbedError.ConversionFailed;
        } else {
            if (py.PyErr_Occurred() != null) {
                py.PyErr_Print();
            }
            return EmbedError.ExecutionFailed;
        }
    }

    pub fn evalObject(self: *Python, expr: [*:0]const u8) EmbedError!*PyObject {
        const result = py.PyRun_String(expr, py.Py_eval_input, self.main_dict, self.main_dict);
        if (result) |py_result| {
            return py_result;
        } else {
            if (py.PyErr_Occurred() != null) {
                py.PyErr_Print();
            }
            return EmbedError.ExecutionFailed;
        }
    }

    pub fn setGlobal(self: *Python, name: [*:0]const u8, value: anytype) EmbedError!void {
        const py_value = Conversions.toPy(@TypeOf(value), value) orelse
            return EmbedError.ConversionFailed;
        defer py.Py_DecRef(py_value);

        if (py.PyDict_SetItemString(self.main_dict, name, py_value) < 0) {
            return EmbedError.ExecutionFailed;
        }
    }

    pub fn setGlobalObject(self: *Python, name: [*:0]const u8, obj: *PyObject) EmbedError!void {
        if (py.PyDict_SetItemString(self.main_dict, name, obj) < 0) {
            return EmbedError.ExecutionFailed;
        }
    }

    pub fn getGlobal(self: *Python, comptime T: type, name: [*:0]const u8) EmbedError!T {
        const py_value = py.PyDict_GetItemString(self.main_dict, name) orelse
            return EmbedError.AttributeError;
        return Conversions.fromPy(T, py_value) catch return EmbedError.ConversionFailed;
    }

    pub fn getGlobalObject(self: *Python, name: [*:0]const u8) ?*PyObject {
        return py.PyDict_GetItemString(self.main_dict, name);
    }

    pub fn import(self: *Python, module_name: [*:0]const u8) EmbedError!*PyObject {
        _ = self;
        const mod = py.PyImport_ImportModule(module_name) orelse {
            if (py.PyErr_Occurred() != null) {
                py.PyErr_Print();
            }
            return EmbedError.ImportFailed;
        };
        return mod;
    }

    pub fn importAs(self: *Python, module_name: [*:0]const u8, as_name: [*:0]const u8) EmbedError!void {
        const mod = try self.import(module_name);
        defer py.Py_DecRef(mod);
        try self.setGlobalObject(as_name, mod);
    }

    pub fn hasError(self: *Python) bool {
        _ = self;
        return py.PyErr_Occurred() != null;
    }

    pub fn clearError(self: *Python) void {
        _ = self;
        py.PyErr_Clear();
    }

    pub fn printError(self: *Python) void {
        _ = self;
        py.PyErr_Print();
    }

    pub fn isInitialized(self: *Python) bool {
        _ = self;
        return py.Py_IsInitialized();
    }
};

// =============================================================================
// GIL helper functions (withGIL variants)
// =============================================================================

/// Execute a function while holding the GIL.
pub fn withGIL(comptime callback: fn (*Python) anyerror!void) !void {
    const gil = acquireGIL();
    defer gil.release();

    var python = Python.init() catch return error.InitializationFailed;
    _ = &python;

    return callback(&python);
}

/// Execute a function with a return value while holding the GIL.
pub fn withGILReturn(comptime T: type, comptime callback: fn (*Python) anyerror!T) !T {
    const gil = acquireGIL();
    defer gil.release();

    var python = Python.init() catch return error.InitializationFailed;
    _ = &python;

    return callback(&python);
}

/// Execute a function with context while holding the GIL.
pub fn withGILContext(
    comptime Ctx: type,
    ctx: *Ctx,
    comptime callback: fn (*Ctx, *Python) anyerror!void,
) !void {
    const gil = acquireGIL();
    defer gil.release();

    var python = Python.init() catch return error.InitializationFailed;
    _ = &python;

    return callback(ctx, &python);
}

/// Execute a function with context and return value while holding the GIL.
pub fn withGILContextReturn(
    comptime Ctx: type,
    comptime T: type,
    ctx: *Ctx,
    comptime callback: fn (*Ctx, *Python) anyerror!T,
) !T {
    const gil = acquireGIL();
    defer gil.release();

    var python = Python.init() catch return error.InitializationFailed;
    _ = &python;

    return callback(ctx, &python);
}
