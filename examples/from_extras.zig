//! Extra utilities auto-discovered via .from
//!
//! This file demonstrates ALL .from auto-scan features:
//!   - pub fn           → auto-registered as Python function
//!   - /// doc comments → auto-extracted as docstrings (via withSource)
//!   - pub const scalar → Python module constant
//!   - pub const string → Python module constant
//!   - pyoz.Args(T)     → auto-detected as named keyword arguments
//!   - struct w/ fields  → auto-registered as Python class
//!   - enum(i32)        → auto-registered as IntEnum
//!   - enum (plain)     → auto-registered as StrEnum
//!   - pyoz.Exception   → auto-registered as custom exception
//!   - pyoz.ErrorMap    → auto-merged error mappings
//!   - __tests__        → auto-merged inline tests
//!   - __benchmarks__   → auto-merged inline benchmarks
//!   - _prefixed names  → auto-skipped (private convention)

const std = @import("std");
const pyoz = @import("PyOZ");

// ============================================================================
// String utilities (pub fn → function)
// ============================================================================

/// Count the number of words in a string (split by whitespace).
pub fn count_words(s: []const u8) i64 {
    if (s.len == 0) return 0;
    var count: i64 = 0;
    var in_word = false;
    for (s) |c| {
        if (c == ' ' or c == '\t' or c == '\n' or c == '\r') {
            in_word = false;
        } else if (!in_word) {
            in_word = true;
            count += 1;
        }
    }
    return count;
}

/// Check if a string is a pangram (contains every letter a-z).
pub fn is_pangram(s: []const u8) bool {
    var seen: u26 = 0;
    for (s) |c| {
        if (c >= 'a' and c <= 'z') {
            seen |= @as(u26, 1) << @intCast(c - 'a');
        } else if (c >= 'A' and c <= 'Z') {
            seen |= @as(u26, 1) << @intCast(c - 'A');
        }
    }
    return seen == (1 << 26) - 1;
}

/// Get the length of a string in bytes.
pub fn string_len(s: []const u8) i64 {
    return @intCast(s.len);
}

// ============================================================================
// Number utilities (pub fn → function)
// ============================================================================

/// Calculate the Fibonacci number at position n.
pub fn fibonacci(n: i64) i64 {
    if (n <= 0) return 0;
    if (n == 1) return 1;
    var a: i64 = 0;
    var b: i64 = 1;
    var i: i64 = 2;
    while (i <= n) : (i += 1) {
        const temp = a +% b;
        a = b;
        b = temp;
    }
    return b;
}

/// Check if a number is a perfect square.
pub fn is_perfect_square(n: i64) bool {
    if (n < 0) return false;
    if (n == 0) return true;
    const root = @sqrt(@as(f64, @floatFromInt(n)));
    const int_root: i64 = @intFromFloat(root);
    return int_root * int_root == n;
}

/// Clamp a value between min and max bounds.
pub fn clamp_value(value: f64, min_val: f64, max_val: f64) f64 {
    return @max(min_val, @min(max_val, value));
}

/// Compute the greatest common divisor of two integers.
pub fn from_gcd(a: i64, b: i64) i64 {
    var x = if (a < 0) -a else a;
    var y = if (b < 0) -b else b;
    while (y != 0) {
        const temp = y;
        y = @mod(x, y);
        x = temp;
    }
    return x;
}

/// Compute the least common multiple of two integers.
pub fn from_lcm(a: i64, b: i64) i64 {
    if (a == 0 or b == 0) return 0;
    const g = from_gcd(a, b);
    return @divExact(if (a < 0) -a else a, g) * (if (b < 0) -b else b);
}

// ============================================================================
// Keyword argument function (auto-detected: pyoz.Args(T) → kwfunc)
// ============================================================================

/// Square root with optional default for negative values.
/// Python signature: safe_sqrt(value, default=None)
pub fn safe_sqrt(args: pyoz.Args(struct { value: f64, default: ?f64 = null })) f64 {
    if (args.value.value < 0) return args.value.default orelse 0.0;
    return @sqrt(args.value.value);
}

// ============================================================================
// Struct → Class (auto-detected: struct with fields/methods/__doc__)
// ============================================================================

/// A 2D vector with x and y components.
pub const Vec2 = struct {
    x: f64,
    y: f64,

    pub fn magnitude(self: *const Vec2) f64 {
        return @sqrt(self.x * self.x + self.y * self.y);
    }
    pub const magnitude__doc__: [*:0]const u8 = "Compute the magnitude (length) of the vector";

    pub fn dot(self: *const Vec2, other: *const Vec2) f64 {
        return self.x * other.x + self.y * other.y;
    }
    pub const dot__doc__: [*:0]const u8 = "Compute the dot product with another Vec2";

    pub fn scale(self: *const Vec2, factor: f64) Vec2 {
        return .{ .x = self.x * factor, .y = self.y * factor };
    }
    pub const scale__doc__: [*:0]const u8 = "Return a new Vec2 scaled by the given factor";

    pub fn __repr__(self: *const Vec2) pyoz.Formatted("Vec2({d:.2}, {d:.2})", struct { f64, f64 }) {
        return .{ .args = .{ self.x, self.y } };
    }

    pub fn __add__(self: *const Vec2, other: *const Vec2) Vec2 {
        return .{ .x = self.x + other.x, .y = self.y + other.y };
    }

    pub fn __eq__(self: *const Vec2, other: *const Vec2) bool {
        return self.x == other.x and self.y == other.y;
    }
};

// ============================================================================
// Enum → IntEnum / StrEnum (auto-detected)
// ============================================================================

/// IntEnum — has explicit integer tags
pub const Priority = enum(i32) {
    Low = 1,
    Medium = 2,
    High = 3,
    Critical = 4,
};

/// IntEnum with unsigned tag (u8) — sequential values starting from 0
pub const OpCode = enum(u8) {
    OP_NOP,
    OP_READ,
    OP_WRITE,
    OP_SYNC,
    OP_CLOSE,
};

/// StrEnum — plain enum without integer tags
pub const Weekday = enum {
    monday,
    tuesday,
    wednesday,
    thursday,
    friday,
    saturday,
    sunday,
};

// ============================================================================
// Exception markers (auto-detected: pyoz.Exception → custom exception)
// ============================================================================

pub const RangeError = pyoz.Exception(.ValueError, "Value is out of the allowed range");
pub const ComputeError = pyoz.Exception(.RuntimeError, "A computation failed unexpectedly");

// ============================================================================
// Error mapping marker (auto-detected: pyoz.ErrorMap → merged error mappings)
// ============================================================================

/// A class with a custom constructor. With pyoz.withSource the parameter names
/// of __new__ come from this source, so Interval(start=2, length=3) works.
pub const Interval = struct {
    lo: i64,
    hi: i64,

    pub fn __new__(start: i64, length: ?i64) Interval {
        return .{ .lo = start, .hi = start + (length orelse 1) };
    }
};

/// A constructor taking pyoz.Args: the names and defaults come from the struct,
/// so Notice(2, line=7) works with or without withSource.
pub const Notice = struct {
    level: i64,
    line: i64,
    column: i64,

    pub fn __new__(args: pyoz.Args(struct { level: i64, line: i64 = 0, column: ?i64 = null })) Notice {
        const a = args.value;
        return .{ .level = a.level, .line = a.line, .column = a.column orelse -1 };
    }
};

/// Field defaults apply to the default constructor: Options(3) or
/// Options(3, verbose=True).
pub const Options = struct {
    width: i64,
    height: i64 = 10,
    verbose: bool = false,
};

/// A required field after one with a default can only be passed by keyword
/// when the earlier one is omitted: Margins(right=3).
pub const Margins = struct {
    left: i64 = 0,
    right: i64,
};

/// Keyword function (pyoz.Args) whose error uses the module's error mappings.
pub fn checked_sqrt(args: pyoz.Args(struct { value: f64 })) !f64 {
    if (args.value.value < 0) return error.OutOfRange;
    return @sqrt(args.value.value);
}

/// Optional parameter (keyword-capable) whose error uses the error mappings.
/// The names are declared because example_abi3 loads this namespace without
/// withSource, which is where they would otherwise come from.
pub const checked_div__params__ = "a, b";
pub fn checked_div(a: i64, b: ?i64) !i64 {
    const d = b orelse 1;
    if (d == 0) return error.OutOfRange;
    return @divTrunc(a, d);
}

pub const __errors__ = pyoz.ErrorMap(.{
    .{ "OutOfRange", .ValueError, "Value is out of range" },
    .{ "ComputeFailed", .RuntimeError },
});

// ============================================================================
// Constants (auto-detected: scalar/string pub const → module constant)
// ============================================================================

pub const GOLDEN_RATIO: f64 = 1.6180339887498948;
pub const MAX_FIB_INDEX: i64 = 92;
pub const LIB_NAME: []const u8 = "from_extras";
pub const ENABLE_FAST_PATH: bool = true;

// ============================================================================
// Private helper — auto-skipped due to _ prefix
// ============================================================================

fn _internal_helper() void {}
pub const _PRIVATE_CONST: i64 = 42;

// ============================================================================
// Incompatible function — auto-skipped (comptime/generic params)
// ============================================================================

pub fn _comptime_only(comptime T: type) T {
    return undefined;
}

// ============================================================================
// Inline tests (auto-detected: __tests__ → merged with .tests)
// ============================================================================

pub const __tests__ = &[_]pyoz.TestDef{
    // Function tests
    pyoz.@"test"("from: count_words",
        \\assert example.count_words("hello world foo") == 3
        \\assert example.count_words("") == 0
        \\assert example.count_words("single") == 1
    ),
    pyoz.@"test"("from: fibonacci",
        \\assert example.fibonacci(0) == 0
        \\assert example.fibonacci(1) == 1
        \\assert example.fibonacci(10) == 55
    ),
    pyoz.@"test"("from: is_pangram",
        \\assert example.is_pangram("The quick brown fox jumps over the lazy dog")
        \\assert not example.is_pangram("Hello world")
    ),
    pyoz.@"test"("from: safe_sqrt kwargs",
        \\assert example.safe_sqrt(value=4.0) == 2.0
        \\assert example.safe_sqrt(value=-1.0) == 0.0
        \\assert example.safe_sqrt(value=-1.0, default=-1.0) == -1.0
    ),
    pyoz.@"test"("from: clamp_value",
        \\assert example.clamp_value(15.0, 0.0, 10.0) == 10.0
        \\assert example.clamp_value(-5.0, 0.0, 10.0) == 0.0
        \\assert example.clamp_value(5.0, 0.0, 10.0) == 5.0
    ),
    pyoz.@"test"("from: gcd and lcm",
        \\assert example.from_gcd(12, 8) == 4
        \\assert example.from_lcm(4, 6) == 12
    ),
    // Class tests
    pyoz.@"test"("from: Vec2 construction",
        \\v = example.Vec2(3.0, 4.0)
        \\assert v.x == 3.0
        \\assert v.y == 4.0
    ),
    pyoz.@"test"("from: Vec2 magnitude",
        \\v = example.Vec2(3.0, 4.0)
        \\assert abs(v.magnitude() - 5.0) < 1e-10
    ),
    pyoz.@"test"("from: Vec2 dot product",
        \\v1 = example.Vec2(1.0, 2.0)
        \\v2 = example.Vec2(3.0, 4.0)
        \\assert v1.dot(v2) == 11.0
    ),
    pyoz.@"test"("from: Vec2 scale",
        \\v = example.Vec2(1.0, 2.0)
        \\v2 = v.scale(3.0)
        \\assert v2.x == 3.0
        \\assert v2.y == 6.0
    ),
    pyoz.@"test"("from: Vec2 __add__",
        \\v1 = example.Vec2(1.0, 2.0)
        \\v2 = example.Vec2(3.0, 4.0)
        \\v3 = v1 + v2
        \\assert v3.x == 4.0
        \\assert v3.y == 6.0
    ),
    pyoz.@"test"("from: Vec2 __eq__",
        \\v1 = example.Vec2(1.0, 2.0)
        \\v2 = example.Vec2(1.0, 2.0)
        \\assert v1 == v2
    ),
    pyoz.@"test"("from: Vec2 __repr__",
        \\v = example.Vec2(1.5, 2.5)
        \\assert "Vec2" in repr(v)
    ),
    // Enum tests
    pyoz.@"test"("from: Priority IntEnum",
        \\assert example.Priority.Low == 1
        \\assert example.Priority.Critical == 4
        \\assert example.Priority(2) == example.Priority.Medium
    ),
    pyoz.@"test"("from: Weekday StrEnum",
        \\assert example.Weekday.monday == "monday"
        \\assert example.Weekday.friday == "friday"
    ),
    // Constant tests
    pyoz.@"test"("from: constants",
        \\assert abs(example.GOLDEN_RATIO - 1.618033988749895) < 1e-10
        \\assert example.MAX_FIB_INDEX == 92
        \\assert example.LIB_NAME == "from_extras"
        \\assert example.ENABLE_FAST_PATH == True
    ),
    // Exception tests
    pyoz.@"test"("from: RangeError is importable",
        \\err = example.RangeError
        \\assert issubclass(err, ValueError)
    ),
    pyoz.@"test"("from: ComputeError is importable",
        \\err = example.ComputeError
        \\assert issubclass(err, RuntimeError)
    ),
    pyoz.testRaises("from: RangeError can be raised", "example.RangeError",
        \\raise example.RangeError("test")
    ),
};

// ============================================================================
// Inline benchmarks (auto-detected: __benchmarks__ → merged with .benchmarks)
// ============================================================================

pub const __benchmarks__ = &[_]pyoz.BenchDef{
    pyoz.bench("from: fibonacci(20)",
        \\example.fibonacci(20)
    ),
    pyoz.bench("from: count_words",
        \\example.count_words("the quick brown fox jumps over the lazy dog")
    ),
    pyoz.bench("from: Vec2 creation",
        \\example.Vec2(3.0, 4.0)
    ),
    pyoz.bench("from: Vec2.magnitude",
        \\example.Vec2(3.0, 4.0).magnitude()
    ),
};
