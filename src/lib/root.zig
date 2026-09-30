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
pub const MemoryView = bytes_types.MemoryView;
pub const BytesLike = bytes_types.BytesLike;

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
// Signature (stub return type override)
// =============================================================================

/// Override the Python type stub annotation for a function's return type.
///
/// `Signature(T, "python_type")` behaves identically to `T` at runtime, but
/// the stub generator emits the provided string instead of inferring from `T`.
///
/// Use this when the Zig return type doesn't map cleanly to the Python type,
/// most commonly when `?T` is used for exception signaling (not `None` returns):
///
/// ```zig
/// // Without Signature: generates `def probe() -> dict[str, bool] | None`
/// fn probe() ?Dict([]const u8, bool) { ... }
///
/// // With Signature: generates `def probe() -> dict[str, bool]`
/// fn probe() pyoz.Signature(?Dict([]const u8, bool), "dict[str, bool]") { ... }
///
/// // For functions that only raise: generates `def fail() -> Never`
/// fn fail() pyoz.Signature(?void, "Never") { ... }
/// ```
///
/// Works on both module-level functions and class methods.
pub fn Signature(comptime Inner: type, comptime stub: []const u8) type {
    return struct {
        pub const _is_pyoz_signature = true;
        pub const inner_type = Inner;
        pub const stub_type = stub;
        value: Inner,
    };
}

/// Unwrap a `Signature(T, ...)` to its inner type `T`.
/// If `T` is not a Signature wrapper, returns `T` unchanged.
/// Use this everywhere return types are introspected at comptime.
pub fn unwrapSignature(comptime T: type) type {
    if (@typeInfo(T) == .@"struct" and @hasDecl(T, "_is_pyoz_signature")) {
        return T.inner_type;
    }
    return T;
}

/// If the raw return value is a Signature wrapper, extract the inner `.value`.
/// Otherwise return the value unchanged.
/// Use this at runtime to unwrap the actual result of a function call.
pub fn unwrapSignatureValue(comptime RawReturnType: type, raw: RawReturnType) unwrapSignature(RawReturnType) {
    if (@typeInfo(RawReturnType) == .@"struct" and @hasDecl(RawReturnType, "_is_pyoz_signature")) {
        return raw.value;
    }
    return raw;
}

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

const fmt_mod = @import("fmt.zig");
/// Lazily formatted message; see src/lib/fmt.zig. Accepted by every `raise*`
/// helper and convertible to `str` wherever PyOZ converts return values.
pub const fmt = fmt_mod.fmt;
pub const Formatted = fmt_mod.Formatted;

const aio_mod = @import("aio.zig");
/// Wrap a Zig function as a Python function returning an `asyncio.Future`;
/// see src/lib/aio.zig.
pub const asyncFn = aio_mod.asyncFn;
/// Async instance method; see aio.asyncMethod for the `self` contract.
pub const asyncMethod = aio_mod.asyncMethod;
/// Result type of calling `asyncFn(f)` from Zig (e.g. inside `__anext__`).
pub const Future = aio_mod.Future;
/// The process-wide `std.Io` runtime used by async functions.
pub const io = aio_mod.io;
/// Number of async jobs not yet fully cleaned up (diagnostics / leak checks).
pub const asyncLiveJobs = aio_mod.liveJobs;
/// Set the maximum number of concurrently running async jobs (default 256).
pub const setAsyncConcurrency = aio_mod.setConcurrency;

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
pub const wrapFunctionWithNamedKeywords = wrappers_mod.wrapFunctionWithNamedKeywords;
pub const wrapFunctionWithErrorMapping = wrappers_mod.wrapFunctionWithErrorMapping;
pub const wrapAutoKeywordFunction = wrappers_mod.wrapAutoKeywordFunction;
pub const PyCFunctionWithKeywords = wrappers_mod.PyCFunctionWithKeywords;
pub const FuncDefEntry = wrappers_mod.FuncDefEntry;
pub const func = wrappers_mod.func;
pub const KwFuncDefEntry = wrappers_mod.KwFuncDefEntry;
pub const kwfunc = wrappers_mod.kwfunc;
pub const Args = wrappers_mod.Args;

// =============================================================================
// `.from` auto-scan API
// =============================================================================

const from_mod = @import("from.zig");
pub const source = from_mod.source;
pub const sub = from_mod.sub;
pub const withSource = from_mod.withSource;
pub const Exception = from_mod.Exception;
pub const ErrorMap = from_mod.ErrorMapType;

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
        .@"struct" => if (@hasDecl(T, "_is_pyoz_signature")) usesDecimalType(T.inner_type) else T == Decimal,
        .optional => |opt| usesDecimalType(opt.child),
        .pointer => |ptr| usesDecimalType(ptr.child),
        else => false,
    };
}

// Helper to check if a type or any of its components uses DateTime types
fn usesDateTimeType(comptime T: type) bool {
    const info = @typeInfo(T);
    return switch (info) {
        .@"struct" => if (@hasDecl(T, "_is_pyoz_signature")) usesDateTimeType(T.inner_type) else T == DateTime or T == Date or T == Time or T == TimeDelta,
        .optional => |opt| usesDateTimeType(opt.child),
        .pointer => |ptr| usesDateTimeType(ptr.child),
        else => false,
    };
}

// Check if any function in the list uses Decimal types
fn anyFuncUsesDecimal(comptime funcs_list: anytype) bool {
    @setEvalBranchQuota(std.math.maxInt(u32));
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
    @setEvalBranchQuota(std.math.maxInt(u32));
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
/// Merges explicit .tests with __tests__ from .from namespaces.
fn generateTestContent(comptime config: anytype) []const u8 {
    comptime {
        const tests_list = if (@hasField(@TypeOf(config), "tests")) config.tests else &[_]TestDef{};

        // Count .from tests
        const has_from = @hasField(@TypeOf(config), "from");
        const from_entries = if (has_from) config.from else &.{};
        var from_test_count: usize = 0;
        if (has_from) {
            for (from_entries) |entry| {
                if (from_mod.isSub(entry)) continue;
                const ns = from_mod.resolveNamespace(entry);
                if (from_mod.hasTests(ns)) {
                    from_test_count += @field(ns, "__tests__").len;
                }
            }
        }

        if (tests_list.len == 0 and from_test_count == 0) return "";

        const mod_name: []const u8 = blk: {
            var len: usize = 0;
            while (config.name[len] != 0) : (len += 1) {}
            break :blk config.name[0..len];
        };

        // In package mode (module name starts with '_'), also import the package name
        // so users can write `assert ravn.add(2, 3) == 5` instead of `assert _ravn.add(2, 3) == 5`
        const pkg_import: []const u8 = if (mod_name.len > 1 and mod_name[0] == '_')
            "import " ++ mod_name[1..] ++ "\n"
        else
            "";

        var result: []const u8 =
            "import unittest\n" ++
            "import " ++ mod_name ++ "\n" ++
            pkg_import ++
            "\n" ++
            "\n" ++
            "class Test" ++ capitalizeFirst(mod_name) ++ "(unittest.TestCase):\n";

        // Explicit tests
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

        // .from tests
        if (has_from) {
            for (from_entries) |entry| {
                if (from_mod.isSub(entry)) continue;
                const ns = from_mod.resolveNamespace(entry);
                if (from_mod.hasTests(ns)) {
                    for (@field(ns, "__tests__")) |t| {
                        const method_name = "test_" ++ slugify(t.name);
                        result = result ++ "    def " ++ method_name ++ "(self):\n";

                        if (t.exception) |exc| {
                            result = result ++ "        with self.assertRaises(" ++ exc ++ "):\n";
                            result = result ++ indentLines(t.body, 12);
                        } else {
                            result = result ++ indentLines(t.body, 8);
                        }
                        result = result ++ "\n";
                    }
                }
            }
        }

        result = result ++
            "\n" ++
            "if __name__ == \"__main__\":\n" ++
            "    unittest.main()\n";

        return result;
    }
}

/// Generate a complete Python benchmark script from inline benchmark definitions.
/// Merges explicit .benchmarks with __benchmarks__ from .from namespaces.
fn generateBenchContent(comptime config: anytype) []const u8 {
    comptime {
        const bench_list = if (@hasField(@TypeOf(config), "benchmarks")) config.benchmarks else &[_]BenchDef{};

        // Count .from benchmarks
        const has_from = @hasField(@TypeOf(config), "from");
        const from_entries = if (has_from) config.from else &.{};
        var from_bench_count: usize = 0;
        if (has_from) {
            for (from_entries) |entry| {
                if (from_mod.isSub(entry)) continue;
                const ns = from_mod.resolveNamespace(entry);
                if (from_mod.hasBenchmarks(ns)) {
                    from_bench_count += @field(ns, "__benchmarks__").len;
                }
            }
        }

        if (bench_list.len == 0 and from_bench_count == 0) return "";

        const mod_name: []const u8 = blk: {
            var len: usize = 0;
            while (config.name[len] != 0) : (len += 1) {}
            break :blk config.name[0..len];
        };

        const bench_pkg_import: []const u8 = if (mod_name.len > 1 and mod_name[0] == '_')
            "import " ++ mod_name[1..] ++ "\n"
        else
            "";

        var result: []const u8 =
            "import timeit\n" ++
            "import " ++ mod_name ++ "\n" ++
            bench_pkg_import ++
            "\n" ++
            "\n" ++
            "def run_benchmarks():\n" ++
            "    results = []\n";

        // Explicit benchmarks
        for (bench_list) |b| {
            const fn_name = "bench_" ++ slugify(b.name);
            result = result ++ "    def " ++ fn_name ++ "():\n";
            result = result ++ indentLines(b.body, 8);
            result = result ++ "    t = timeit.timeit(" ++ fn_name ++ ", number=100000)\n";
            result = result ++ "    results.append((\"" ++ b.name ++ "\", t))\n\n";
        }

        // .from benchmarks
        if (has_from) {
            for (from_entries) |entry| {
                if (from_mod.isSub(entry)) continue;
                const ns = from_mod.resolveNamespace(entry);
                if (from_mod.hasBenchmarks(ns)) {
                    for (@field(ns, "__benchmarks__")) |b| {
                        const fn_name = "bench_" ++ slugify(b.name);
                        result = result ++ "    def " ++ fn_name ++ "():\n";
                        result = result ++ indentLines(b.body, 8);
                        result = result ++ "    t = timeit.timeit(" ++ fn_name ++ ", number=100000)\n";
                        result = result ++ "    results.append((\"" ++ b.name ++ "\", t))\n\n";
                    }
                }
            }
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

/// Extract class info from both explicit classes AND .from namespace classes.
fn extractClassInfoWithFrom(
    comptime classes: anytype,
    comptime from_entries: anytype,
    comptime explicit_names_list: []const []const u8,
) []const class_mod.ClassInfo {
    comptime {
        @setEvalBranchQuota(std.math.maxInt(u32));

        // Count .from classes
        const from_count = from_mod.countAllFromClasses(from_entries, explicit_names_list);
        const total = classes.len + from_count;

        var infos: [total]class_mod.ClassInfo = undefined;

        // Explicit classes (same as extractClassInfo)
        for (classes, 0..) |cls, i| {
            const parent_type: ?type = blk: {
                if (!@hasDecl(cls.zig_type, "__base__")) break :blk null;
                const BaseDecl = @TypeOf(cls.zig_type.__base__);
                if (BaseDecl != type) break :blk null;
                const BaseType = cls.zig_type.__base__;
                if (!@hasDecl(BaseType, "_is_pyoz_base")) break :blk null;
                break :blk BaseType.ParentType;
            };
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

        // .from classes
        var from_idx: usize = classes.len;
        for (from_entries) |entry| {
            if (from_mod.isSub(entry)) continue;
            const ns = from_mod.resolveNamespace(entry);
            const opts = from_mod.getSourceOptions(entry);
            const decls = @typeInfo(ns).@"struct".decls;
            for (decls) |d| {
                if (from_mod.shouldExportAsClass(ns, d.name, opts, explicit_names_list)) {
                    const ClassType = @field(ns, d.name);
                    const parent_type: ?type = pblk: {
                        if (!@hasDecl(ClassType, "__base__")) break :pblk null;
                        const BaseDecl2 = @TypeOf(ClassType.__base__);
                        if (BaseDecl2 != type) break :pblk null;
                        const BaseType2 = ClassType.__base__;
                        if (!@hasDecl(BaseType2, "_is_pyoz_base")) break :pblk null;
                        break :pblk BaseType2.ParentType;
                    };
                    infos[from_idx] = .{
                        .name = from_mod.comptimeStrZ(d.name),
                        .zig_type = ClassType,
                        .parent_zig_type = parent_type,
                        .parsed_source = from_mod.resolveParsedSource(entry),
                    };
                    from_idx += 1;
                }
            }
        }

        const final = infos;
        return &final;
    }
}

// Check if any .from function uses Decimal types
fn anyFromFuncUsesDecimal(comptime from_entries: anytype, comptime explicit_names_list: []const []const u8) bool {
    @setEvalBranchQuota(std.math.maxInt(u32));
    for (from_entries) |entry| {
        if (from_mod.isSub(entry)) continue;
        const ns = from_mod.resolveNamespace(entry);
        const opts = from_mod.getSourceOptions(entry);
        const decls = @typeInfo(ns).@"struct".decls;
        for (decls) |d| {
            if (from_mod.shouldExportAsFunction(ns, d.name, opts, explicit_names_list)) {
                const func_val = @field(ns, d.name);
                const Fn = @TypeOf(func_val);
                const fn_info = @typeInfo(Fn).@"fn";
                if (fn_info.return_type) |ret| {
                    if (usesDecimalType(ret)) return true;
                }
                for (fn_info.params) |param| {
                    if (param.type) |ptype| {
                        if (usesDecimalType(ptype)) return true;
                    }
                }
            }
        }
    }
    return false;
}

// Check if any .from function uses DateTime types
fn anyFromFuncUsesDateTime(comptime from_entries: anytype, comptime explicit_names_list: []const []const u8) bool {
    @setEvalBranchQuota(std.math.maxInt(u32));
    for (from_entries) |entry| {
        if (from_mod.isSub(entry)) continue;
        const ns = from_mod.resolveNamespace(entry);
        const opts = from_mod.getSourceOptions(entry);
        const decls = @typeInfo(ns).@"struct".decls;
        for (decls) |d| {
            if (from_mod.shouldExportAsFunction(ns, d.name, opts, explicit_names_list)) {
                const func_val = @field(ns, d.name);
                const Fn = @TypeOf(func_val);
                const fn_info = @typeInfo(Fn).@"fn";
                if (fn_info.return_type) |ret| {
                    if (usesDateTimeType(ret)) return true;
                }
                for (fn_info.params) |param| {
                    if (param.type) |ptype| {
                        if (usesDateTimeType(ptype)) return true;
                    }
                }
            }
        }
    }
    return false;
}

/// Create a Python module from configuration
pub fn module(comptime config: anytype) type {
    @setEvalBranchQuota(std.math.maxInt(u32));
    const classes = if (@hasField(@TypeOf(config), "classes")) config.classes else &[_]ClassDef{};
    const funcs = if (@hasField(@TypeOf(config), "funcs")) config.funcs else &.{};
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

    // === .from auto-scan processing ===
    const has_from = @hasField(@TypeOf(config), "from");
    const from_entries = if (has_from) config.from else &.{};

    // Validate no duplicates across .from entries
    if (has_from) {
        from_mod.checkFromDuplicates(from_entries);
    }

    // Build explicit name set for deduplication (explicit wins over .from)
    const explicit_names = from_mod.buildExplicitNameSet(config);

    // Count .from items for array sizing
    const from_func_count = if (has_from) from_mod.countAllFromFunctions(from_entries, explicit_names) else 0;
    const from_exc_count = if (has_from) from_mod.countAllFromExceptions(from_entries, explicit_names) else 0;

    // Build combined class_infos (explicit + .from classes)
    const class_infos = extractClassInfoWithFrom(classes, from_entries, explicit_names);

    // Total exception count (explicit + .from)
    const num_all_exceptions = num_exceptions + from_exc_count;

    // Detect at comptime if this module uses Decimal or DateTime types
    const needs_decimal_init = anyFuncUsesDecimal(funcs) or
        (has_from and anyFromFuncUsesDecimal(from_entries, explicit_names));
    const needs_datetime_init = anyFuncUsesDateTime(funcs) or
        (has_from and anyFromFuncUsesDateTime(from_entries, explicit_names));

    // Total error mappings (explicit + .from)
    const all_error_mappings = comptime blk: {
        const total = error_mappings.len + from_mod.countAllFromErrorMappings(from_entries);
        if (total == 0) break :blk &[_]ErrorMapping{};
        var mappings: [total]ErrorMapping = undefined;
        // Copy explicit mappings
        for (error_mappings, 0..) |m, i| {
            mappings[i] = m;
        }
        // Append .from error mappings
        var idx: usize = error_mappings.len;
        for (from_entries) |entry| {
            if (from_mod.isSub(entry)) continue;
            const ns = from_mod.resolveNamespace(entry);
            const decls = @typeInfo(ns).@"struct".decls;
            for (decls) |d| {
                if (from_mod.isErrorMapDecl(ns, d.name)) {
                    const ErrMap = @field(ns, d.name);
                    const err_mappings_data = ErrMap._error_mappings;
                    for (err_mappings_data) |em| {
                        mappings[idx] = .{
                            .error_name = em[0],
                            .exc_type = em[1],
                            .message = if (em.len > 2) em[2] else null,
                        };
                        idx += 1;
                    }
                }
            }
        }
        const final = mappings;
        break :blk &final;
    };

    return struct {
        // Generate method definitions array with class-aware wrappers
        // Size = explicit funcs + .from funcs + sentinel
        var methods: [funcs.len + from_func_count + 1]PyMethodDef = blk: {
            @setEvalBranchQuota(std.math.maxInt(u32));
            var m: [funcs.len + from_func_count + 1]PyMethodDef = undefined;

            // Explicit funcs
            for (funcs, 0..) |f, i| {
                // Check if this is a keyword-argument function using Args(T)
                // pyoz.kwfunc, or pyoz.func given a function taking pyoz.Args(T)
                const is_named_kwargs = (@hasField(@TypeOf(f), "is_named_kwargs") and f.is_named_kwargs) or
                    from_mod.isNamedKwargsFunc(@TypeOf(f.func));
                const kwargs_mode: stubs_mod.KwargsMode = if (is_named_kwargs) .args_struct else .positional;
                const ml_doc = stubs_mod.buildMlDoc(
                    std.mem.span(f.name),
                    @TypeOf(f.func),
                    .module_func,
                    kwargs_mode,
                    f.doc,
                    if (@hasField(@TypeOf(f), "params")) f.params else null,
                );

                if (is_named_kwargs) {
                    m[i] = .{
                        .ml_name = f.name,
                        .ml_meth = @ptrCast(wrappers_mod.wrapFunctionWithNamedKeywordsAndErrorMapping(f.func, class_infos, all_error_mappings)),
                        .ml_flags = py.METH_VARARGS | py.METH_KEYWORDS,
                        .ml_doc = ml_doc,
                    };
                } else {
                    // Use error mapping wrapper if mappings are defined
                    if (all_error_mappings.len > 0) {
                        m[i] = .{
                            .ml_name = f.name,
                            .ml_meth = wrapFunctionWithErrorMapping(f.func, class_infos, all_error_mappings),
                            .ml_flags = py.METH_VARARGS,
                            .ml_doc = ml_doc,
                        };
                    } else {
                        m[i] = .{
                            .ml_name = f.name,
                            .ml_meth = wrapFunctionWithClasses(f.func, class_infos),
                            .ml_flags = py.METH_VARARGS,
                            .ml_doc = ml_doc,
                        };
                    }
                }
            }

            // .from funcs
            var from_idx: usize = funcs.len;
            for (from_entries) |entry| {
                if (from_mod.isSub(entry)) continue;
                const ns = from_mod.resolveNamespace(entry);
                const opts = from_mod.getSourceOptions(entry);
                const decls = @typeInfo(ns).@"struct".decls;
                for (decls) |d| {
                    if (from_mod.shouldExportAsFunction(ns, d.name, opts, explicit_names)) {
                        const func_val = @field(ns, d.name);
                        const doc = from_mod.getDocstring(entry, d.name);
                        const FnType = @TypeOf(func_val);
                        const is_named = from_mod.isNamedKwargsFunc(FnType);
                        const param_names = from_mod.getParamNames(entry, d.name);
                        const has_optional = !is_named and from_mod.hasOptionalParams(FnType);
                        const is_auto_kwargs = has_optional and param_names != null;
                        if (has_optional and param_names == null) {
                            @compileLog("PyOZ .from: function '" ++ d.name ++ "' has ?T optional params but no source text for param names — kwargs won't work. Use pyoz.withSource() or add __source__() / " ++ d.name ++ "__params__ to the namespace.");
                        }
                        const kwargs_mode: stubs_mod.KwargsMode = if (is_named) .args_struct else if (is_auto_kwargs) .auto_kwargs else .positional;
                        const ml_doc = stubs_mod.buildMlDoc(
                            d.name,
                            FnType,
                            .module_func,
                            kwargs_mode,
                            doc,
                            param_names,
                        );

                        if (is_named) {
                            m[from_idx] = .{
                                .ml_name = from_mod.comptimeStrZ(d.name),
                                .ml_meth = @ptrCast(wrappers_mod.wrapFunctionWithNamedKeywordsAndErrorMapping(func_val, class_infos, all_error_mappings)),
                                .ml_flags = py.METH_VARARGS | py.METH_KEYWORDS,
                                .ml_doc = ml_doc,
                            };
                        } else if (is_auto_kwargs) {
                            m[from_idx] = .{
                                .ml_name = from_mod.comptimeStrZ(d.name),
                                .ml_meth = @ptrCast(wrappers_mod.wrapAutoKeywordFunctionWithErrorMapping(func_val, class_infos, param_names.?, all_error_mappings)),
                                .ml_flags = py.METH_VARARGS | py.METH_KEYWORDS,
                                .ml_doc = ml_doc,
                            };
                        } else {
                            if (all_error_mappings.len > 0) {
                                m[from_idx] = .{
                                    .ml_name = from_mod.comptimeStrZ(d.name),
                                    .ml_meth = wrapFunctionWithErrorMapping(func_val, class_infos, all_error_mappings),
                                    .ml_flags = py.METH_VARARGS,
                                    .ml_doc = ml_doc,
                                };
                            } else {
                                m[from_idx] = .{
                                    .ml_name = from_mod.comptimeStrZ(d.name),
                                    .ml_meth = wrapFunctionWithClasses(func_val, class_infos),
                                    .ml_flags = py.METH_VARARGS,
                                    .ml_doc = ml_doc,
                                };
                            }
                        }
                        from_idx += 1;
                    }
                }
            }

            // Sentinel (null terminator)
            m[funcs.len + from_func_count] = .{
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
            @setEvalBranchQuota(std.math.maxInt(u32));
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
                    @setEvalBranchQuota(std.math.maxInt(u32));
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

            // === .from: Register classes ===
            if (has_from) {
                inline for (from_entries) |entry| {
                    if (comptime !from_mod.isSub(entry)) {
                        const ns = from_mod.resolveNamespace(entry);
                        const opts = comptime from_mod.getSourceOptions(entry);
                        const decls = @typeInfo(ns).@"struct".decls;
                        inline for (decls) |d| {
                            if (comptime from_mod.shouldExportAsClass(ns, d.name, opts, explicit_names)) {
                                const ClassType = @field(ns, d.name);
                                const cls_name_z = comptime from_mod.comptimeStrZ(d.name);
                                const FromWrapper = class_mod.getWrapperWithName(cls_name_z, ClassType, class_infos);

                                const from_qualified: [*:0]const u8 = comptime qblk: {
                                    @setEvalBranchQuota(std.math.maxInt(u32));
                                    const mn: [*:0]const u8 = config.name;
                                    var ml: usize = 0;
                                    while (mn[ml] != 0) ml += 1;
                                    const cn = d.name;
                                    const tot = ml + 1 + cn.len;
                                    var qbuf: [tot:0]u8 = undefined;
                                    for (0..ml) |qi| qbuf[qi] = mn[qi];
                                    qbuf[ml] = '.';
                                    for (0..cn.len) |qi| qbuf[ml + 1 + qi] = cn[qi];
                                    qbuf[tot] = 0;
                                    const qfin = qbuf;
                                    break :qblk @ptrCast(&qfin);
                                };

                                const from_type_obj = FromWrapper.initTypeWithName(from_qualified) orelse {
                                    return -1;
                                };

                                // Set class tp_doc from source if no explicit __doc__
                                if (comptime !@hasDecl(ClassType, "__doc__")) {
                                    if (comptime from_mod.getClassDoc(entry, d.name)) |src_class_doc| {
                                        from_type_obj.tp_doc = src_class_doc;
                                    }
                                }

                                if (!abi.abi3_enabled) {
                                    const from_slots_tuple = class_mod.createSlotsTuple(ClassType);
                                    if (from_slots_tuple) |fst| {
                                        if (from_type_obj.tp_dict) |fdict| {
                                            _ = py.PyDict_SetItemString(fdict, "__slots__", fst);
                                        }
                                        py.Py_DecRef(fst);
                                    }
                                    if (from_type_obj.tp_dict) |ftype_dict| {
                                        if (!class_mod.addClassAttributes(ClassType, ftype_dict)) {
                                            return -1;
                                        }
                                    }
                                } else {
                                    const ftype_as_obj: *py.PyObject = @ptrCast(@alignCast(from_type_obj));
                                    if (!class_mod.addClassAttributesAbi3(ClassType, ftype_as_obj)) {
                                        return -1;
                                    }
                                }

                                if (comptime abi.abi3_enabled) {
                                    const ftype_as_obj: *py.PyObject = @ptrCast(@alignCast(from_type_obj));
                                    py.Py_IncRef(ftype_as_obj);
                                    if (py.c.PyModule_AddObject(mod, cls_name_z, ftype_as_obj) < 0) {
                                        py.Py_DecRef(ftype_as_obj);
                                        return -1;
                                    }
                                } else {
                                    if (py.PyModule_AddType(mod, from_type_obj) < 0) {
                                        return -1;
                                    }
                                }
                            }
                        }
                    }
                }
            }

            // === .from: Register exceptions ===
            if (has_from) {
                comptime var from_exc_idx: usize = num_exceptions;
                inline for (from_entries) |entry| {
                    if (comptime !from_mod.isSub(entry)) {
                        const ns = from_mod.resolveNamespace(entry);
                        const opts = comptime from_mod.getSourceOptions(entry);
                        const decls = @typeInfo(ns).@"struct".decls;
                        inline for (decls) |d| {
                            if (comptime from_mod.shouldExportAsException(ns, d.name, opts, explicit_names)) {
                                const ExcMarker = @field(ns, d.name);
                                const base_exc_from = ExcMarker._exc_base.toPyObject();
                                const exc_type_from = py.PyErr_NewException(
                                    &exception_full_names[from_exc_idx],
                                    base_exc_from,
                                    null,
                                ) orelse {
                                    return -1;
                                };
                                exception_types[from_exc_idx] = exc_type_from;

                                if (ExcMarker._exc_doc) |exc_doc| {
                                    const exc_doc_str = py.PyUnicode_FromString(exc_doc);
                                    if (exc_doc_str) |eds| {
                                        _ = py.PyObject_SetAttrString(exc_type_from, "__doc__", eds);
                                        py.Py_DecRef(eds);
                                    }
                                }

                                if (py.PyModule_AddObject(mod, from_mod.comptimeStrZ(d.name), exc_type_from) < 0) {
                                    py.Py_DecRef(exc_type_from);
                                    return -1;
                                }

                                from_exc_idx += 1;
                            }
                        }
                    }
                }
            }

            // === .from: Register enums ===
            if (has_from) {
                inline for (from_entries) |entry| {
                    if (comptime !from_mod.isSub(entry)) {
                        const ns = from_mod.resolveNamespace(entry);
                        const opts = comptime from_mod.getSourceOptions(entry);
                        const decls = @typeInfo(ns).@"struct".decls;
                        inline for (decls) |d| {
                            if (comptime from_mod.shouldExportAsEnum(ns, d.name, opts, explicit_names)) {
                                const EnumType = @field(ns, d.name);
                                const is_str = comptime !from_mod.isIntEnum(EnumType);
                                const enum_name_z = comptime from_mod.comptimeStrZ(d.name);
                                const from_enum_obj = (if (comptime is_str)
                                    module_mod.createStrEnum(EnumType, enum_name_z)
                                else
                                    module_mod.createEnum(EnumType, enum_name_z)) orelse {
                                    return -1;
                                };

                                if (py.PyModule_AddObject(mod, enum_name_z, from_enum_obj) < 0) {
                                    py.Py_DecRef(from_enum_obj);
                                    return -1;
                                }
                            }
                        }
                    }
                }
            }

            // === .from: Register constants ===
            if (has_from) {
                inline for (from_entries) |entry| {
                    if (comptime !from_mod.isSub(entry)) {
                        const ns = from_mod.resolveNamespace(entry);
                        const opts = comptime from_mod.getSourceOptions(entry);
                        const decls = @typeInfo(ns).@"struct".decls;
                        inline for (decls) |d| {
                            if (comptime from_mod.shouldExportAsConstant(ns, d.name, opts, explicit_names)) {
                                const const_val = @field(ns, d.name);
                                const ConstType = @TypeOf(const_val);
                                const const_name_z = from_mod.comptimeStrZ(d.name);
                                const from_py_value = Conversions.toPy(ConstType, const_val) orelse {
                                    return -1;
                                };

                                if (py.PyModule_AddObject(mod, const_name_z, from_py_value) < 0) {
                                    py.Py_DecRef(from_py_value);
                                    return -1;
                                }
                            }
                        }
                    }
                }
            }

            // === .from: Register submodules ===
            if (has_from) {
                inline for (from_entries) |entry| {
                    if (comptime from_mod.isSub(entry)) {
                        const sub_name = comptime from_mod.getSubName(entry);
                        const sub_ns = from_mod.resolveNamespace(entry);
                        const sub_opts = comptime from_mod.getSourceOptions(entry);

                        // Create the submodule
                        const sub_mod = py.c.PyModule_New(sub_name) orelse {
                            return -1;
                        };

                        // Set submodule docstring from __doc__ if present
                        const sub_doc_str = comptime from_mod.getNamespaceDoc(entry);
                        if (sub_doc_str) |sdoc| {
                            const doc_py = py.c.PyUnicode_FromString(sdoc);
                            if (doc_py) |ds| {
                                _ = py.c.PyObject_SetAttrString(sub_mod, "__doc__", ds);
                                py.Py_DecRef(ds);
                            }
                        }

                        // Register submodule functions directly
                        const sub_decls = @typeInfo(sub_ns).@"struct".decls;
                        inline for (sub_decls) |sd| {
                            if (comptime from_mod.shouldExportAsFunction(sub_ns, sd.name, sub_opts, &.{})) {
                                const sub_func_val = @field(sub_ns, sd.name);
                                const sub_doc = from_mod.getDocstring(entry, sd.name);
                                const SubFnType = @TypeOf(sub_func_val);
                                const sub_func_name = from_mod.comptimeStrZ(sd.name);
                                const sub_is_named = comptime from_mod.isNamedKwargsFunc(SubFnType);
                                const sub_param_names = comptime from_mod.getParamNames(entry, sd.name);
                                const sub_has_optional = comptime !sub_is_named and from_mod.hasOptionalParams(SubFnType);
                                const sub_is_auto_kwargs = sub_has_optional and sub_param_names != null;
                                if (sub_has_optional and sub_param_names == null) {
                                    @compileLog("PyOZ .from: function '" ++ sd.name ++ "' has ?T optional params but no source text for param names — kwargs won't work. Use pyoz.withSource() or add __source__() / " ++ sd.name ++ "__params__ to the namespace.");
                                }
                                const sub_kwargs_mode: stubs_mod.KwargsMode = comptime if (sub_is_named) .args_struct else if (sub_is_auto_kwargs) .auto_kwargs else .positional;
                                const sub_ml_doc = comptime stubs_mod.buildMlDoc(
                                    sd.name,
                                    SubFnType,
                                    .module_func,
                                    sub_kwargs_mode,
                                    sub_doc,
                                    sub_param_names,
                                );

                                // Create a PyCFunction and add via PyModule_AddObject
                                const sub_meth_def = comptime blk_m: {
                                    if (sub_is_named) {
                                        break :blk_m py.c.PyMethodDef{
                                            .ml_name = sub_func_name,
                                            .ml_meth = @ptrCast(wrappers_mod.wrapFunctionWithNamedKeywordsAndErrorMapping(sub_func_val, class_infos, all_error_mappings)),
                                            .ml_flags = py.METH_VARARGS | py.METH_KEYWORDS,
                                            .ml_doc = sub_ml_doc,
                                        };
                                    } else if (sub_is_auto_kwargs) {
                                        break :blk_m py.c.PyMethodDef{
                                            .ml_name = sub_func_name,
                                            .ml_meth = @ptrCast(wrappers_mod.wrapAutoKeywordFunctionWithErrorMapping(sub_func_val, class_infos, sub_param_names.?, all_error_mappings)),
                                            .ml_flags = py.METH_VARARGS | py.METH_KEYWORDS,
                                            .ml_doc = sub_ml_doc,
                                        };
                                    } else {
                                        break :blk_m py.c.PyMethodDef{
                                            .ml_name = sub_func_name,
                                            .ml_meth = if (all_error_mappings.len > 0) wrapFunctionWithErrorMapping(sub_func_val, class_infos, all_error_mappings) else wrapFunctionWithClasses(sub_func_val, class_infos),
                                            .ml_flags = py.METH_VARARGS,
                                            .ml_doc = sub_ml_doc,
                                        };
                                    }
                                };

                                const sub_cfunc = py.c.PyCFunction_NewEx(
                                    @constCast(&sub_meth_def),
                                    null,
                                    null,
                                ) orelse {
                                    py.Py_DecRef(sub_mod);
                                    return -1;
                                };

                                if (py.c.PyModule_AddObject(sub_mod, sub_func_name, sub_cfunc) < 0) {
                                    py.Py_DecRef(sub_cfunc);
                                    py.Py_DecRef(sub_mod);
                                    return -1;
                                }
                            }

                            // Register submodule constants
                            if (comptime from_mod.shouldExportAsConstant(sub_ns, sd.name, sub_opts, &.{})) {
                                const sub_const_val = @field(sub_ns, sd.name);
                                const SubConstType = @TypeOf(sub_const_val);
                                const sub_const_name_z = from_mod.comptimeStrZ(sd.name);
                                const sub_py_value = Conversions.toPy(SubConstType, sub_const_val) orelse {
                                    py.Py_DecRef(sub_mod);
                                    return -1;
                                };

                                if (py.c.PyModule_AddObject(sub_mod, sub_const_name_z, sub_py_value) < 0) {
                                    py.Py_DecRef(sub_py_value);
                                    py.Py_DecRef(sub_mod);
                                    return -1;
                                }
                            }
                        }

                        // Add submodule to parent module
                        if (py.c.PyModule_AddObject(mod, sub_name, sub_mod) < 0) {
                            py.Py_DecRef(sub_mod);
                            return -1;
                        }
                    }
                }
            }

            // Call user-provided post-init callback if present
            if (module_init_fn) |user_init| {
                if (user_init(mod) < 0) return -1;
            }

            return 0;
        }

        // Module slots for multi-phase initialization (PEP 489)
        // `.gil_used = false` declares the module safe to run without the GIL
        // (PEP 703). Without it, importing the module on a free-threaded
        // interpreter silently re-enables the GIL for the whole process.
        const gil_used: bool = if (@hasField(@TypeOf(config), "gil_used")) config.gil_used else true;
        const declare_gil_not_used = !gil_used and @hasDecl(py.c, "Py_mod_gil");
        var module_slots = if (declare_gil_not_used) [_]py.c.PyModuleDef_Slot{
            .{ .slot = py.c.Py_mod_exec, .value = @ptrCast(@constCast(&moduleExec)) },
            .{ .slot = py.c.Py_mod_gil, .value = @ptrFromInt(1) }, // Py_MOD_GIL_NOT_USED
            .{ .slot = 0, .value = null },
        } else [_]py.c.PyModuleDef_Slot{
            .{ .slot = py.c.Py_mod_exec, .value = @ptrCast(@constCast(&moduleExec)) },
            .{ .slot = 0, .value = null },
        };

        // Module docstring: use explicit .doc if set, otherwise try __doc__ from .from namespaces
        const m_doc: ?[*:0]const u8 = if (@hasField(@TypeOf(config), "doc"))
            config.doc
        else if (has_from) blk_doc: {
            for (from_entries) |entry| {
                if (from_mod.isSub(entry)) continue;
                if (from_mod.getNamespaceDoc(entry)) |doc| {
                    break :blk_doc doc;
                }
            }
            break :blk_doc null;
        } else null;

        var module_def: PyModuleDef = .{
            .m_base = py.PyModuleDef_HEAD_INIT,
            .m_name = config.name,
            .m_doc = m_doc,
            .m_size = 0,
            .m_methods = &methods,
            .m_slots = @ptrCast(&module_slots),
            .m_traverse = null,
            .m_clear = null,
            .m_free = null,
        };

        // Generate full exception names at comptime (e.g., "mymodule.MyError")
        // Includes both explicit exceptions and .from exceptions
        const exception_full_names: [num_all_exceptions][256:0]u8 = blk: {
            @setEvalBranchQuota(std.math.maxInt(u32));
            var names: [num_all_exceptions][256:0]u8 = undefined;
            // Get module name length
            var mod_len: usize = 0;
            while (config.name[mod_len] != 0) : (mod_len += 1) {}

            // Explicit exceptions
            for (exceptions, 0..) |exc, i| {
                var buf: [256:0]u8 = [_:0]u8{0} ** 256;
                var exc_len: usize = 0;
                while (exc.name[exc_len] != 0) : (exc_len += 1) {}
                for (0..mod_len) |j| {
                    buf[j] = config.name[j];
                }
                buf[mod_len] = '.';
                for (0..exc_len) |j| {
                    buf[mod_len + 1 + j] = exc.name[j];
                }
                names[i] = buf;
            }

            // .from exceptions
            var from_exc_name_idx: usize = num_exceptions;
            for (from_entries) |entry| {
                if (from_mod.isSub(entry)) continue;
                const ns = from_mod.resolveNamespace(entry);
                const opts = from_mod.getSourceOptions(entry);
                const decls = @typeInfo(ns).@"struct".decls;
                for (decls) |d| {
                    if (from_mod.shouldExportAsException(ns, d.name, opts, explicit_names)) {
                        var buf2: [256:0]u8 = [_:0]u8{0} ** 256;
                        for (0..mod_len) |j| {
                            buf2[j] = config.name[j];
                        }
                        buf2[mod_len] = '.';
                        for (0..d.name.len) |j| {
                            buf2[mod_len + 1 + j] = d.name[j];
                        }
                        names[from_exc_name_idx] = buf2;
                        from_exc_name_idx += 1;
                    }
                }
            }

            break :blk names;
        };

        // Build a comptime list of all exception names (explicit + .from) for lookup
        const all_exception_names: [num_all_exceptions][*:0]const u8 = blk: {
            @setEvalBranchQuota(std.math.maxInt(u32));
            var exc_names: [num_all_exceptions][*:0]const u8 = undefined;
            for (exceptions, 0..) |exc, i| {
                exc_names[i] = exc.name;
            }
            var fe_idx: usize = num_exceptions;
            for (from_entries) |entry| {
                if (from_mod.isSub(entry)) continue;
                const ns = from_mod.resolveNamespace(entry);
                const opts = from_mod.getSourceOptions(entry);
                const decls = @typeInfo(ns).@"struct".decls;
                for (decls) |d| {
                    if (from_mod.shouldExportAsException(ns, d.name, opts, explicit_names)) {
                        exc_names[fe_idx] = from_mod.comptimeStrZ(d.name);
                        fe_idx += 1;
                    }
                }
            }
            break :blk exc_names;
        };

        // Runtime storage for exception types (explicit + .from)
        var exception_types: [num_all_exceptions]?*PyObject = [_]?*PyObject{null} ** num_all_exceptions;

        /// Initialize the module using multi-phase initialization (PEP 489).
        /// Returns a module def object; Python calls moduleExec to populate it.
        pub fn init() callconv(.c) ?*PyObject {
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

        /// Get an exception reference by name (for .from exceptions).
        /// Example: Module.getExceptionByName("MyError").raise("something went wrong");
        pub fn getExceptionByName(comptime name: []const u8) ExceptionRef {
            inline for (0..num_all_exceptions) |i| {
                if (std.mem.eql(u8, std.mem.span(all_exception_names[i]), name))
                    return ExceptionRef{ .idx = i };
            }
            @compileError("Unknown exception: " ++ name);
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
            @setEvalBranchQuota(std.math.maxInt(u32));
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
            @setEvalBranchQuota(std.math.maxInt(u32));
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
            @setEvalBranchQuota(std.math.maxInt(u32));
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

        // Auto-export PyInit_ function so users don't need manual boilerplate.
        // The build system generates a bridge file that forces analysis of this type.
        comptime {
            const mod_name: [*:0]const u8 = config.name;
            @export(&init, .{ .name = "PyInit_" ++ std.mem.span(mod_name) });
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
