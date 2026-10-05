//! ABI3 (Stable ABI / Limited API) Support Module
//!
//! This module provides compile-time detection and guards for Python's Stable ABI.
//! When ABI3 mode is enabled, PyOZ builds extension modules that work across
//! multiple Python versions without recompilation.
//!
//! ## Usage
//!
//! ABI3 mode is controlled via build options:
//! ```
//! zig build example -Dabi3=true
//! ```
//!
//! Or in pyproject.toml:
//! ```toml
//! [tool.pyoz]
//! abi3 = true
//! (the minimum is fixed at Python 3.10; see python/types.zig)
//! ```

const std = @import("std");
const build_options = @import("build_options");

// =============================================================================
// Core ABI3 Configuration
// =============================================================================

/// Whether ABI3 (Limited API) mode is enabled.
/// When true, only Stable ABI functions are available.
pub const enabled: bool = build_options.abi3;

/// Alias for backwards compatibility
pub const abi3_enabled = enabled;

/// The minimum Python version for ABI3 compatibility.
/// Format: 0x03XXYYZZ where XX=major, YY=minor, ZZ=micro
/// Python 3.10. Derived from python/types.zig so the Py_LIMITED_API define and
/// these version checks can never disagree. (Previously read from a build
/// option that no build script defined.)
pub const min_version: u32 = @import("python/types.zig").abi3_version_hex;

/// Python version components extracted from min_version
pub const version = struct {
    pub const major: u8 = @intCast((min_version >> 24) & 0xFF);
    pub const minor: u8 = @intCast((min_version >> 16) & 0xFF);
    pub const micro: u8 = @intCast((min_version >> 8) & 0xFF);

    /// Format version as string (comptime)
    pub fn string() []const u8 {
        return std.fmt.comptimePrint("{d}.{d}", .{ major, minor });
    }

    /// Get the hex version string for Py_LIMITED_API
    pub fn hexString() []const u8 {
        return std.fmt.comptimePrint("0x{X:0>8}", .{min_version});
    }
};

// =============================================================================
// Compile-Time Guards
// =============================================================================

/// Emit a compile error if a feature is used in ABI3 mode.
/// Use this to guard features that have no ABI3-compatible alternative.
///
/// Example:
/// ```zig
/// pub fn PyDateTime_GET_YEAR(obj: *PyObject) c_int {
///     comptime abi.requireFullApi("DateTime C API");
///     // ... implementation
/// }
/// ```
pub fn requireFullApi(comptime feature: []const u8) void {
    if (enabled) {
        @compileError("Feature '" ++ feature ++ "' is not available in ABI3 mode. " ++
            "This feature requires direct access to Python internals which are not " ++
            "part of the Stable ABI. Set abi3 = false to use this feature.");
    }
}

/// Emit a compile error if a feature is used in ABI3 mode, with a custom message.
pub fn requireFullApiMsg(comptime feature: []const u8, comptime msg: []const u8) void {
    if (enabled) {
        @compileError("Feature '" ++ feature ++ "' is not available in ABI3 mode. " ++ msg);
    }
}

/// Emit a compile error if the ABI3 version is below a required minimum.
/// Use for features that were added to the Limited API in later Python versions.
///
/// Example:
/// ```zig
/// // PyModule_AddType was added in Python 3.9
/// pub fn addType(module: *PyObject, type_obj: *PyTypeObject) c_int {
///     comptime abi.requireMinVersion(3, 9, "PyModule_AddType");
///     return c.PyModule_AddType(module, type_obj);
/// }
/// ```
pub fn requireMinVersion(comptime major: u8, comptime minor: u8, comptime feature: []const u8) void {
    if (enabled) {
        const required = (@as(u32, major) << 24) | (@as(u32, minor) << 16);
        if (min_version < required) {
            @compileError(std.fmt.comptimePrint(
                "Feature '{s}' requires Python {d}.{d}+, but ABI3 min version is {d}.{d}. " ++
                    "Increase abi3-min-version or set abi3 = false.",
                .{ feature, major, minor, version.major, version.minor },
            ));
        }
    }
}

/// Check at comptime if a feature requiring a specific Python version is available.
/// Returns true if either ABI3 is disabled OR the version requirement is met.
pub fn isVersionAvailable(comptime major: u8, comptime minor: u8) bool {
    if (!enabled) return true;
    const required = (@as(u32, major) << 24) | (@as(u32, minor) << 16);
    return min_version >= required;
}

// =============================================================================
// Feature Availability Flags
// =============================================================================

/// Compile-time feature flags based on ABI3 mode and version
pub const features = struct {
    // --- Always available in ABI3 mode ---

    /// Basic type operations (int, float, str, bool, bytes, etc.)
    pub const basic_types = true;

    /// List, dict, set, tuple operations
    pub const collections = true;

    /// Buffer consumer (reading from buffers) - PyObject_GetBuffer is in Limited API
    pub const buffer_consumer = true;

    /// Complex number operations
    pub const complex_numbers = true;

    /// Module-level functions
    pub const module_functions = true;

    /// Custom exceptions (PyErr_NewException is in Limited API)
    pub const exceptions = true;

    /// Classes via PyType_FromSpec (Python 3.2+)
    pub const classes_via_spec = true;

    /// Iterator consumer (PyObject_GetIter, PyIter_Next)
    pub const iterator_consumer = true;

    /// GC protocol (__traverse__/__clear__): PyType_FromSpec accepts
    /// Py_TPFLAGS_HAVE_GC with Py_tp_traverse/Py_tp_clear, and PyObject_GC_*
    /// and PyType_GetSlot are in the Limited API
    pub const gc_protocol = true;

    // --- Version-dependent features ---

    /// PyModule_AddType (Python 3.9+)
    pub const module_add_type = isVersionAvailable(3, 9);

    /// Py_NewRef, Py_XNewRef (Python 3.10+)
    pub const new_ref_functions = isVersionAvailable(3, 10);

    // --- Features NOT available in ABI3 ---

    /// DateTime C API (direct struct field access)
    pub const datetime_capi = !enabled;

    /// Buffer producer (__buffer__ protocol via PyBufferProcs)
    pub const buffer_producer = !enabled;

    /// Embedding APIs (PyRun_String, PyRun_SimpleString, etc.)
    pub const embedding = !enabled;

    /// structmember.h (T_OBJECT_EX, READONLY for __dict__/__weakref__)
    pub const structmember = !enabled;

    /// Direct tp_dict access for class attributes
    pub const tp_dict_access = !enabled;

    /// Static PyTypeObject definition (use PyType_FromSpec instead in ABI3)
    pub const static_type_object = !enabled;

    /// PySequenceMethods, PyMappingMethods, PyNumberMethods structs
    /// (use Py_sq_*, Py_mp_*, Py_nb_* slots instead in ABI3)
    pub const protocol_structs = !enabled;
};

// =============================================================================
// Detailed Error Messages
// =============================================================================

/// Standard error messages for various ABI3-incompatible features
pub const errors = struct {
    pub const datetime =
        \\DateTime/Date/Time/TimeDelta types require the datetime C API which uses
        \\direct struct field access (PyDateTime_GET_YEAR, etc.). This is not part
        \\of the Stable ABI.
        \\
        \\Workaround: Import the datetime module via PyImport_ImportModule() and
        \\work with PyObject directly, or set abi3 = false.
    ;

    pub const buffer_producer =
        \\The buffer producer protocol (__buffer__/PyBufferProcs) is not part of
        \\the Stable ABI. You can still READ buffers using BufferView(T), but cannot
        \\implement __buffer__ to make your types buffer-compatible.
        \\
        \\Workaround: Return bytes or a list instead of implementing __buffer__,
        \\or set abi3 = false.
    ;

    pub const embedding =
        \\Python embedding APIs (PyRun_SimpleString, PyRun_String, etc.) are not
        \\part of the Stable ABI.
        \\
        \\Workaround: Use PyObject_Call() with imported modules and functions,
        \\or set abi3 = false.
    ;

    pub const dict_weakref =
        \\The __dict__ and __weakref__ support requires structmember.h types
        \\(T_OBJECT_EX, READONLY) which are not part of the Stable ABI.
        \\
        \\Workaround: Custom classes in ABI3 mode cannot have __dict__ or __weakref__.
        \\If you need these features, set abi3 = false.
    ;

    pub const class_attributes =
        \\Adding class attributes via tp_dict access is not available in ABI3 mode.
        \\The tp_dict field of PyTypeObject is not part of the Stable ABI.
        \\
        \\Workaround: Use module-level constants instead of class attributes,
        \\or set abi3 = false.
    ;

    pub const static_type_object =
        \\Static PyTypeObject initialization is not available in ABI3 mode because
        \\the struct layout may change between Python versions.
        \\
        \\Note: PyOZ automatically uses PyType_FromSpec() in ABI3 mode, so this
        \\error indicates an internal issue.
    ;
};

// =============================================================================
// Conditional Type Helper
// =============================================================================

/// Returns T in non-ABI3 mode, void in ABI3 mode.
/// Useful for conditionally including struct fields or function parameters.
pub fn Optional(comptime T: type) type {
    return if (enabled) void else T;
}

/// Returns the value in non-ABI3 mode, null in ABI3 mode.
pub fn optional(comptime T: type, value: T) ?T {
    return if (enabled) null else value;
}

// =============================================================================
// Mode Selection Helper
// =============================================================================

/// Select between two values based on ABI3 mode.
/// Useful for choosing different implementations at comptime.
///
/// Example:
/// ```zig
/// const type_flags = abi.select(
///     py.Py_TPFLAGS_DEFAULT,  // ABI3 mode: no GC
///     py.Py_TPFLAGS_DEFAULT | py.Py_TPFLAGS_HAVE_GC,  // Full mode: with GC
/// );
/// ```
pub fn select(comptime abi3_value: anytype, comptime full_value: anytype) @TypeOf(abi3_value) {
    return if (enabled) abi3_value else full_value;
}

/// Select a type based on ABI3 mode.
pub fn SelectType(comptime Abi3Type: type, comptime FullType: type) type {
    return if (enabled) Abi3Type else FullType;
}

// =============================================================================
// Tests
// =============================================================================

test "version parsing" {
    // Minimum is 3.10.0
    try std.testing.expectEqual(@as(u8, 3), version.major);
    try std.testing.expectEqual(@as(u8, 10), version.minor);
    try std.testing.expectEqual(@as(u8, 0), version.micro);
}

test "feature flags consistency" {
    // Basic features should always be available
    try std.testing.expect(features.basic_types);
    try std.testing.expect(features.collections);
    try std.testing.expect(features.buffer_consumer);

    // In non-ABI3 mode (default), all features should be available
    if (!enabled) {
        try std.testing.expect(features.datetime_capi);
        try std.testing.expect(features.buffer_producer);
        try std.testing.expect(features.embedding);
    }
    try std.testing.expect(features.gc_protocol);

    // Inverse relationship
    try std.testing.expectEqual(!enabled, features.datetime_capi);
    try std.testing.expectEqual(!enabled, features.static_type_object);
}

test "version availability" {
    // 3.10 is the minimum, so it is always available
    try std.testing.expect(isVersionAvailable(3, 10));

    // If not in ABI3 mode, any version is "available"
    if (!enabled) {
        try std.testing.expect(isVersionAvailable(3, 20));
    }
}

test "select helper" {
    const val = select(@as(i32, 10), @as(i32, 20));
    if (enabled) {
        try std.testing.expectEqual(@as(i32, 10), val);
    } else {
        try std.testing.expectEqual(@as(i32, 20), val);
    }
}
