//! ABI3-compatible example module
//!
//! This example demonstrates features that work in ABI3 (Stable ABI) mode.
//! Build with: zig build example_abi3 -Dabi3=true
//!
//! Features available in ABI3 mode:
//! - Module-level functions with basic types (int, float, str, bool)
//! - Complex numbers
//! - Lists, dicts, sets (consumer and producer)
//! - Bytes and ByteArray
//! - Optional types
//! - Tuples
//! - Custom exceptions
//! - Enums (IntEnum and StrEnum)
//! - DateTime types (emulated via Python object calls)
//! - BufferView (read-only, copy-based in ABI3)
//! - Custom classes via PyType_FromSpec:
//!   - Basic classes with methods and properties
//!   - Number protocol (__add__, __sub__, __mul__, etc.)
//!   - Comparison protocol (__eq__, __lt__, __gt__, etc.)
//!   - Iterator protocol (__iter__, __next__)
//!   - Callable protocol (__call__)
//!   - Context manager (__enter__, __exit__)
//!   - LazyIterator for generators
//!
//! Features NOT available in ABI3 mode:
//! - BufferViewMut (mutable buffer access)
//! - Buffer producer (__buffer__ protocol)
//! - Python embedding (exec/eval)
//! - __dict__ and __weakref__ support on classes
//! - GC protocol (__traverse__, __clear__)

const std = @import("std");
const pyoz = @import("PyOZ");

// ============================================================================
// Basic arithmetic functions
// ============================================================================

fn add(a: i64, b: i64) i64 {
    return a + b;
}

fn multiply(a: f64, b: f64) f64 {
    return a * b;
}

fn divide(a: f64, b: f64) ?f64 {
    if (b == 0) return null;
    return a / b;
}

fn power(base: f64, exp: i32) f64 {
    return std.math.pow(f64, base, @floatFromInt(exp));
}

// ============================================================================
// GIL release functions - demonstrate thread-safe computation
// ============================================================================

/// CPU-intensive computation that releases the GIL
/// This allows other Python threads to run while computing
fn compute_sum_no_gil(n: i64) i64 {
    // Release the GIL - other Python threads can now run!
    const gil = pyoz.releaseGIL();
    defer gil.acquire();

    // Do expensive computation without the GIL
    // Use wrapping arithmetic to avoid overflow in debug builds
    var sum: i64 = 0;
    var i: i64 = 0;
    while (i < n) : (i += 1) {
        // Simulate some work with wrapping to avoid overflow
        sum +%= @mod(i *% i, 1000000007);
    }
    return sum;
}

/// Same computation but keeps the GIL (for comparison)
fn compute_sum_with_gil(n: i64) i64 {
    var sum: i64 = 0;
    var i: i64 = 0;
    while (i < n) : (i += 1) {
        sum +%= @mod(i *% i, 1000000007);
    }
    return sum;
}

// ============================================================================
// String functions
// ============================================================================

fn greet(name: []const u8) []const u8 {
    // Note: In a real app, you'd want to allocate and format
    // For simplicity, we just return a static greeting
    _ = name;
    return "Hello from ABI3!";
}

fn string_length(s: []const u8) usize {
    return s.len;
}

fn is_palindrome(s: []const u8) bool {
    if (s.len == 0) return true;
    var left: usize = 0;
    var right: usize = s.len - 1;
    while (left < right) {
        if (s[left] != s[right]) return false;
        left += 1;
        right -= 1;
    }
    return true;
}

// ============================================================================
// Complex number functions
// ============================================================================

fn complex_add(a: pyoz.Complex, b: pyoz.Complex) pyoz.Complex {
    return .{
        .real = a.real + b.real,
        .imag = a.imag + b.imag,
    };
}

fn complex_multiply(a: pyoz.Complex, b: pyoz.Complex) pyoz.Complex {
    return .{
        .real = a.real * b.real - a.imag * b.imag,
        .imag = a.real * b.imag + a.imag * b.real,
    };
}

fn complex_magnitude(c: pyoz.Complex) f64 {
    return @sqrt(c.real * c.real + c.imag * c.imag);
}

fn complex_conjugate(c: pyoz.Complex) pyoz.Complex {
    return .{ .real = c.real, .imag = -c.imag };
}

// ============================================================================
// List functions
// ============================================================================

fn sum_list(items: pyoz.ListView(i64)) i64 {
    var total: i64 = 0;
    var iter = items.iterator();
    while (iter.next()) |value| {
        total += value;
    }
    return total;
}

fn list_length(items: pyoz.ListView(i64)) usize {
    return items.len();
}

fn double_list(items: pyoz.ListView(i64)) pyoz.Iterator(i64) {
    // We can't easily create a new list in Zig without allocation
    // So we return the original values doubled via Iterator
    _ = items;
    const doubled = [_]i64{ 2, 4, 6 }; // Placeholder
    return .{ .items = &doubled };
}

// ============================================================================
// Dict functions
// ============================================================================

fn dict_get(d: pyoz.DictView([]const u8, i64), key: []const u8) ?i64 {
    return d.get(key);
}

fn dict_has_key(d: pyoz.DictView([]const u8, i64), key: []const u8) bool {
    return d.contains(key);
}

fn dict_size(d: pyoz.DictView([]const u8, i64)) usize {
    return d.len();
}

// ============================================================================
// Set functions
// ============================================================================

fn set_contains(s: pyoz.SetView(i64), value: i64) bool {
    return s.contains(value);
}

fn set_size(s: pyoz.SetView(i64)) usize {
    return s.len();
}

// ============================================================================
// Bytes functions
// ============================================================================

fn bytes_length(b: pyoz.Bytes) usize {
    return b.data.len;
}

fn bytes_sum(b: pyoz.Bytes) u64 {
    var total: u64 = 0;
    for (b.data) |byte| {
        total += byte;
    }
    return total;
}

// ============================================================================
// Optional/Error handling
// ============================================================================

fn safe_divide(a: i64, b: i64) ?i64 {
    if (b == 0) return null;
    return @divTrunc(a, b);
}

fn sqrt_positive(x: f64) ?f64 {
    if (x < 0) return null;
    return @sqrt(x);
}

// ============================================================================
// Tuple returns
// ============================================================================

fn minmax(a: i64, b: i64) struct { i64, i64 } {
    return if (a < b) .{ a, b } else .{ b, a };
}

fn divmod(a: i64, b: i64) ?struct { i64, i64 } {
    if (b == 0) return null;
    return .{ @divTrunc(a, b), @mod(a, b) };
}

// ============================================================================
// Bool functions
// ============================================================================

fn is_even(n: i64) bool {
    return @mod(n, 2) == 0;
}

fn is_positive(n: f64) bool {
    return n > 0;
}

fn all_positive(items: pyoz.ListView(i64)) bool {
    var iter = items.iterator();
    while (iter.next()) |value| {
        if (value <= 0) return false;
    }
    return true;
}

// ============================================================================
// DateTime functions (works in ABI3 via emulation)
// ============================================================================

fn create_date(year: i32, month: i32, day: i32) pyoz.Date {
    return .{ .year = year, .month = @intCast(month), .day = @intCast(day) };
}

fn create_datetime(year: i32, month: i32, day: i32, hour: i32, minute: i32, second: i32) pyoz.DateTime {
    return .{
        .year = year,
        .month = @intCast(month),
        .day = @intCast(day),
        .hour = @intCast(hour),
        .minute = @intCast(minute),
        .second = @intCast(second),
        .microsecond = 0,
    };
}

fn create_time(hour: i32, minute: i32, second: i32) pyoz.Time {
    return .{ .hour = @intCast(hour), .minute = @intCast(minute), .second = @intCast(second), .microsecond = 0 };
}

fn create_timedelta(days: i32, seconds: i32, microseconds: i32) pyoz.TimeDelta {
    return .{ .days = days, .seconds = seconds, .microseconds = microseconds };
}

fn get_date_year(date: pyoz.Date) i32 {
    return date.year;
}

fn get_date_month(date: pyoz.Date) u8 {
    return date.month;
}

fn get_date_day(date: pyoz.Date) u8 {
    return date.day;
}

fn get_datetime_hour(dt: pyoz.DateTime) u8 {
    return dt.hour;
}

fn get_time_components(time: pyoz.Time) struct { u8, u8, u8 } {
    return .{ time.hour, time.minute, time.second };
}

fn get_timedelta_days(td: pyoz.TimeDelta) i32 {
    return td.days;
}

// ============================================================================
// BufferView functions (read-only buffer consumer, works in ABI3 via copy)
// ============================================================================

fn buffer_sum_f64(arr: pyoz.BufferView(f64)) f64 {
    var total: f64 = 0;
    for (arr.data) |v| {
        total += v;
    }
    return total;
}

fn buffer_sum_i32(arr: pyoz.BufferView(i32)) i64 {
    var total: i64 = 0;
    for (arr.data) |v| {
        total += v;
    }
    return total;
}

fn buffer_len(arr: pyoz.BufferView(f64)) usize {
    return arr.len();
}

fn buffer_ndim(arr: pyoz.BufferView(f64)) usize {
    return arr.ndim;
}

fn buffer_get(arr: pyoz.BufferView(f64), index: usize) ?f64 {
    if (index >= arr.len()) return null;
    return arr.get(index);
}

// ============================================================================
// Classes (works in ABI3 via PyType_FromSpec)
// ============================================================================

/// A simple counter class to test ABI3 class support
const Counter = struct {
    value: i64,

    pub fn get(self: *const Counter) i64 {
        return self.value;
    }

    pub fn set(self: *Counter, value: i64) void {
        self.value = value;
    }

    pub fn increment(self: *Counter) void {
        self.value += 1;
    }

    pub fn decrement(self: *Counter) void {
        self.value -= 1;
    }

    pub fn add(self: *Counter, amount: i64) void {
        self.value += amount;
    }

    pub fn reset(self: *Counter) void {
        self.value = 0;
    }

    pub fn __repr__(self: *const Counter) []const u8 {
        _ = self;
        return "Counter(...)";
    }
};

/// A simple Point class with arithmetic operators
const Point = struct {
    // Class docstring
    pub const __doc__: [*:0]const u8 = "A 2D point with x and y coordinates.\n\nSupports vector arithmetic (+, -, negation) and geometric operations.";

    // Field docstrings
    pub const x__doc__: [*:0]const u8 = "The x coordinate of the point";
    pub const y__doc__: [*:0]const u8 = "The y coordinate of the point";

    x: f64,
    y: f64,

    // Method docstrings
    pub const magnitude__doc__: [*:0]const u8 = "Calculate the distance from this point to the origin.\n\nReturns:\n    float: The Euclidean distance sqrt(x^2 + y^2)";

    /// Calculate distance from origin (same as distance_from_origin, but matches non-ABI3)
    pub fn magnitude(self: *const Point) f64 {
        return @sqrt(self.x * self.x + self.y * self.y);
    }

    /// Alias for magnitude
    pub fn distance_from_origin(self: *const Point) f64 {
        return self.magnitude();
    }

    // Computed property docstring
    pub const length__doc__: [*:0]const u8 = "The length (magnitude) of the point vector.\n\nThis is a read/write property - setting it scales the point.";

    /// Computed property: length (same as magnitude, demonstrates get_X pattern)
    pub fn get_length(self: *const Point) f64 {
        return @sqrt(self.x * self.x + self.y * self.y);
    }

    /// Computed property setter: length (scales point to have given length)
    pub fn set_length(self: *Point, new_length: f64) void {
        const current = @sqrt(self.x * self.x + self.y * self.y);
        if (current > 0.0) {
            const factor = new_length / current;
            self.x *= factor;
            self.y *= factor;
        }
    }

    /// Scale the point by a factor
    pub fn scale(self: *Point, factor: f64) void {
        self.x *= factor;
        self.y *= factor;
    }

    pub fn translate(self: *Point, dx: f64, dy: f64) void {
        self.x += dx;
        self.y += dy;
    }

    /// Dot product with another point's coordinates
    pub fn dot(self: *const Point, other_x: f64, other_y: f64) f64 {
        return self.x * other_x + self.y * other_y;
    }

    /// Static method: create origin point (no self!)
    pub fn origin() Point {
        return .{ .x = 0.0, .y = 0.0 };
    }

    /// Static method: create unit point from angle
    pub fn from_angle(radians: f64) Point {
        return .{ .x = @cos(radians), .y = @sin(radians) };
    }

    /// Class method: create point from polar coordinates
    pub fn from_polar(comptime cls: type, r: f64, theta: f64) Point {
        _ = cls;
        return .{ .x = r * @cos(theta), .y = r * @sin(theta) };
    }

    pub fn __repr__(self: *const Point) []const u8 {
        _ = self;
        return "Point(...)";
    }

    /// __eq__ - compare points for equality
    pub fn __eq__(self: *const Point, other: *const Point) bool {
        return self.x == other.x and self.y == other.y;
    }

    /// __add__ - add two points
    pub fn __add__(self: *const Point, other: *const Point) Point {
        return .{ .x = self.x + other.x, .y = self.y + other.y };
    }

    /// __sub__ - subtract points
    pub fn __sub__(self: *const Point, other: *const Point) Point {
        return .{ .x = self.x - other.x, .y = self.y - other.y };
    }

    /// __neg__ - negate a point
    pub fn __neg__(self: *const Point) Point {
        return .{ .x = -self.x, .y = -self.y };
    }
};

/// Number class with full arithmetic protocol
const Number = struct {
    value: f64,

    pub fn __new__(value: f64) Number {
        return .{ .value = value };
    }

    pub fn __repr__(self: *const Number) []const u8 {
        _ = self;
        return "Number(...)";
    }

    pub fn get_value(self: *const Number) f64 {
        return self.value;
    }

    pub fn __add__(self: *const Number, other: *const Number) Number {
        return .{ .value = self.value + other.value };
    }

    pub fn __sub__(self: *const Number, other: *const Number) Number {
        return .{ .value = self.value - other.value };
    }

    pub fn __mul__(self: *const Number, other: *const Number) Number {
        return .{ .value = self.value * other.value };
    }

    pub fn __truediv__(self: *const Number, other: *const Number) !Number {
        if (other.value == 0.0) return error.DivisionByZero;
        return .{ .value = self.value / other.value };
    }

    /// __floordiv__ - floor division
    pub fn __floordiv__(self: *const Number, other: *const Number) !Number {
        if (other.value == 0.0) return error.DivisionByZero;
        return .{ .value = @floor(self.value / other.value) };
    }

    /// __mod__ - modulo
    pub fn __mod__(self: *const Number, other: *const Number) !Number {
        if (other.value == 0.0) return error.DivisionByZero;
        return .{ .value = @mod(self.value, other.value) };
    }

    /// __divmod__ - returns (quotient, remainder) tuple
    pub fn __divmod__(self: *const Number, other: *const Number) !struct { Number, Number } {
        if (other.value == 0.0) return error.DivisionByZero;
        return .{
            .{ .value = @floor(self.value / other.value) },
            .{ .value = @mod(self.value, other.value) },
        };
    }

    pub fn __neg__(self: *const Number) Number {
        return .{ .value = -self.value };
    }

    pub fn __eq__(self: *const Number, other: *const Number) bool {
        return self.value == other.value;
    }

    pub fn __lt__(self: *const Number, other: *const Number) bool {
        return self.value < other.value;
    }

    pub fn __le__(self: *const Number, other: *const Number) bool {
        return self.value <= other.value;
    }
};

/// Version class with comparison operators
const Version = struct {
    major: i32,
    minor: i32,
    patch: i32,

    pub fn __new__(major: i32, minor: i32, patch: i32) Version {
        return .{ .major = major, .minor = minor, .patch = patch };
    }

    pub fn __repr__(self: *const Version) []const u8 {
        _ = self;
        return "Version(...)";
    }

    pub fn __str__(self: *const Version) []const u8 {
        _ = self;
        return "v...";
    }

    /// __eq__ - versions are equal if all components match
    pub fn __eq__(self: *const Version, other: *const Version) bool {
        return self.major == other.major and self.minor == other.minor and self.patch == other.patch;
    }

    /// __ne__ - explicit not-equal
    pub fn __ne__(self: *const Version, other: *const Version) bool {
        return self.major != other.major or self.minor != other.minor or self.patch != other.patch;
    }

    pub fn __lt__(self: *const Version, other: *const Version) bool {
        if (self.major != other.major) return self.major < other.major;
        if (self.minor != other.minor) return self.minor < other.minor;
        return self.patch < other.patch;
    }

    pub fn __le__(self: *const Version, other: *const Version) bool {
        return self.__lt__(other) or self.__eq__(other);
    }

    pub fn __gt__(self: *const Version, other: *const Version) bool {
        if (self.major != other.major) return self.major > other.major;
        if (self.minor != other.minor) return self.minor > other.minor;
        return self.patch > other.patch;
    }

    pub fn __ge__(self: *const Version, other: *const Version) bool {
        return self.__gt__(other) or self.__eq__(other);
    }

    /// Check if this is a major version (minor and patch are 0)
    pub fn is_major(self: *const Version) bool {
        return self.minor == 0 and self.patch == 0;
    }

    /// Check if compatible with another version (same major)
    pub fn is_compatible(self: *const Version, other: *const Version) bool {
        return self.major == other.major;
    }
};

/// Callable class (__call__ protocol)
const Adder = struct {
    base: i64,

    pub fn __new__(base: i64) Adder {
        return .{ .base = base };
    }

    pub fn __repr__(self: *const Adder) []const u8 {
        _ = self;
        return "Adder(...)";
    }

    /// __call__ - make instances callable
    pub fn __call__(self: *const Adder, value: i64) i64 {
        return self.base + value;
    }

    pub fn get_base(self: *const Adder) i64 {
        return self.base;
    }
};

/// Simple sequence class with __len__, __getitem__, __iter__, __next__
const IntList = struct {
    data: [16]i64,
    len: usize,
    iter_index: usize,

    pub fn __new__(initial: i64) IntList {
        var list = IntList{
            .data = undefined,
            .len = 1,
            .iter_index = 0,
        };
        list.data[0] = initial;
        return list;
    }

    pub fn __repr__(self: *const IntList) []const u8 {
        _ = self;
        return "IntList(...)";
    }

    pub fn __len__(self: *const IntList) usize {
        return self.len;
    }

    pub fn __getitem__(self: *const IntList, index: i64) !i64 {
        const idx: usize = if (index < 0)
            @intCast(@as(i64, @intCast(self.len)) + index)
        else
            @intCast(index);
        if (idx >= self.len) return error.IndexError;
        return self.data[idx];
    }

    pub fn __iter__(self: *IntList) *IntList {
        self.iter_index = 0;
        return self;
    }

    pub fn __next__(self: *IntList) ?i64 {
        if (self.iter_index >= self.len) return null;
        const value = self.data[self.iter_index];
        self.iter_index += 1;
        return value;
    }

    pub fn append(self: *IntList, value: i64) !void {
        if (self.len >= 16) return error.ListFull;
        self.data[self.len] = value;
        self.len += 1;
    }

    pub fn sum(self: *const IntList) i64 {
        var total: i64 = 0;
        for (self.data[0..self.len]) |v| {
            total += v;
        }
        return total;
    }
};

// ============================================================================
// FailingResource - tests that __del__ is NOT called when __new__ fails
// ============================================================================

const FailingResource = struct {
    handle: i64,
    _freed: bool,

    pub fn __new__(handle: i64) ?FailingResource {
        if (handle < 0) {
            return pyoz.raiseValueError("handle must be non-negative");
        }
        return .{ .handle = handle, ._freed = false };
    }

    pub fn __del__(self: *FailingResource) void {
        self._freed = true;
        self.handle = -1;
    }

    pub fn is_valid(self: *const FailingResource) bool {
        return self.handle >= 0 and !self._freed;
    }
};

// ============================================================================
// DelCounter - __del__ must run for instances a Zig function returns by value
// (not only for instances created by calling the class)
// Atomic: __del__ can run on any thread in a free-threaded build
var del_counter_deleted = std.atomic.Value(i64).init(0);

const DelCounter = struct {
    value: i64,

    pub fn __del__(self: *DelCounter) void {
        _ = self;
        _ = del_counter_deleted.fetchAdd(1, .monotonic);
    }
};

fn make_del_counter(value: i64) DelCounter {
    return .{ .value = value };
}

fn del_counter_deleted_count() i64 {
    return del_counter_deleted.load(.monotonic);
}

// ============================================================================
// LazyIterator example (generator-like)
// ============================================================================

const RangeState = struct {
    current: i64,
    end: i64,
    step: i64,

    pub fn next(self: *RangeState) ?i64 {
        if ((self.step > 0 and self.current >= self.end) or
            (self.step < 0 and self.current <= self.end))
        {
            return null;
        }
        const val = self.current;
        self.current += self.step;
        return val;
    }
};

fn lazy_range(start: i64, end: i64, step: i64) pyoz.LazyIterator(i64, RangeState) {
    return .{ .state = .{ .current = start, .end = end, .step = step } };
}

const FibState = struct {
    a: i64,
    b: i64,
    remaining: i64,

    pub fn next(self: *FibState) ?i64 {
        if (self.remaining <= 0) return null;
        const val = self.a;
        const new_b = self.a + self.b;
        self.a = self.b;
        self.b = new_b;
        self.remaining -= 1;
        return val;
    }
};

fn lazy_fibonacci(count: i64) pyoz.LazyIterator(i64, FibState) {
    return .{ .state = .{ .a = 0, .b = 1, .remaining = count } };
}

// ============================================================================
// Enums
// ============================================================================

/// Color enum (becomes IntEnum in Python)
const Color = enum(i32) {
    Red = 1,
    Green = 2,
    Blue = 3,
    Yellow = 4,
};

/// HTTP status codes
const HttpStatus = enum(i32) {
    OK = 200,
    Created = 201,
    BadRequest = 400,
    NotFound = 404,
    InternalServerError = 500,
};

/// Task status (becomes StrEnum in Python)
const TaskStatus = enum {
    pending,
    in_progress,
    completed,
    cancelled,
};

// ============================================================================
// DictView with iteration
// ============================================================================

fn dict_sum_values(d: pyoz.DictView([]const u8, i64)) i64 {
    var total: i64 = 0;
    var iter = d.iterator();
    while (iter.next()) |entry| {
        total += entry.value;
    }
    return total;
}

fn dict_keys_length(d: pyoz.DictView([]const u8, i64)) usize {
    var count: usize = 0;
    var iter = d.iterator();
    while (iter.next()) |_| {
        count += 1;
    }
    return count;
}

// ============================================================================
// SetView iteration
// ============================================================================

fn set_sum(s: pyoz.SetView(i64)) i64 {
    var total: i64 = 0;
    var iter = s.iterator();
    defer iter.deinit();
    while (iter.next()) |value| {
        total += value;
    }
    return total;
}

// ============================================================================
// IteratorView - works with any Python iterable
// ============================================================================

fn iter_sum(items: pyoz.IteratorView(i64)) i64 {
    var iter = items;
    var total: i64 = 0;
    while (iter.next()) |value| {
        total += value;
    }
    return total;
}

fn iter_count(items: pyoz.IteratorView(i64)) usize {
    var iter = items;
    return iter.count();
}

fn iter_max(items: pyoz.IteratorView(i64)) ?i64 {
    var iter = items;
    var max_val: ?i64 = null;
    while (iter.next()) |value| {
        if (max_val == null or value > max_val.?) {
            max_val = value;
        }
    }
    return max_val;
}

// ============================================================================
// Keyword arguments (kwfunc) — uses pyoz.Args(T) for named kwargs
// ============================================================================

fn greet_person(args: pyoz.Args(struct { name: []const u8, greeting: []const u8 = "Hello", times: i64 = 1 })) struct { []const u8, []const u8, i64 } {
    return .{ args.value.greeting, args.value.name, args.value.times };
}

fn power_with_default(args: pyoz.Args(struct { base: f64, exponent: f64 = 2.0 })) f64 {
    return std.math.pow(f64, args.value.base, args.value.exponent);
}

// Named keyword arguments
const GreetNamedArgs = struct {
    name: []const u8,
    greeting: []const u8 = "Hello",
    times: i64 = 1,
    excited: bool = false,
};

fn greet_named(args: pyoz.Args(GreetNamedArgs)) struct { []const u8, []const u8, i64, bool } {
    const a = args.value;
    return .{ a.greeting, a.name, a.times, a.excited };
}

const CalcArgs = struct {
    x: f64,
    y: f64,
    operation: []const u8 = "add",
};

fn calculate_named(args: pyoz.Args(CalcArgs)) f64 {
    const a = args.value;
    if (std.mem.eql(u8, a.operation, "add")) return a.x + a.y;
    if (std.mem.eql(u8, a.operation, "sub")) return a.x - a.y;
    if (std.mem.eql(u8, a.operation, "mul")) return a.x * a.y;
    if (std.mem.eql(u8, a.operation, "div")) return a.x / a.y;
    return 0.0;
}

// ============================================================================
// Iterator producer (eager)
// ============================================================================

fn get_fibonacci() pyoz.Iterator(i64) {
    const fibs = [_]i64{ 1, 1, 2, 3, 5, 8, 13, 21, 34, 55 };
    return .{ .items = &fibs };
}

fn get_squares() pyoz.Iterator(i64) {
    const squares = [_]i64{ 1, 4, 9, 16, 25 };
    return .{ .items = &squares };
}

// ============================================================================
// Bytes output
// ============================================================================

fn make_bytes() pyoz.Bytes {
    const data = &[_]u8{ 0x48, 0x65, 0x6c, 0x6c, 0x6f }; // "Hello"
    return .{ .data = data };
}

fn bytes_starts_with(b: pyoz.Bytes, value: u8) bool {
    if (b.data.len == 0) return false;
    return b.data[0] == value;
}

// ============================================================================
// Path input/output
// ============================================================================

fn path_str(p: pyoz.Path) []const u8 {
    return p.path;
}

fn path_len(p: pyoz.Path) usize {
    return p.path.len;
}

fn make_path() pyoz.Path {
    return pyoz.Path.init("/home/user/documents");
}

fn path_starts_with(p: pyoz.Path, prefix: []const u8) bool {
    if (p.path.len < prefix.len) return false;
    return std.mem.eql(u8, p.path[0..prefix.len], prefix);
}

// ============================================================================
// Decimal input/output
// ============================================================================

fn decimal_str(d: pyoz.Decimal) []const u8 {
    return d.value;
}

fn make_decimal() pyoz.Decimal {
    return pyoz.Decimal.init("123.456789");
}

fn decimal_double(d: pyoz.Decimal) !pyoz.Owned(pyoz.Decimal) {
    // Heap-allocate the digits: a Decimal over a local buffer would dangle,
    // because PyOZ converts the return value after this function returns.
    const alloc = std.heap.smp_allocator;
    const f = d.toFloat() orelse return error.InvalidDecimal;
    return pyoz.owned(alloc, pyoz.Decimal.init(try std.fmt.allocPrint(alloc, "{d}", .{f * 2.0})));
}

// ============================================================================
// BigInt (i128/u128)
// ============================================================================

fn bigint_echo(n: i128) i128 {
    return n;
}

fn biguint_echo(n: u128) u128 {
    return n;
}

fn bigint_add(a: i128, b: i128) i128 {
    return a + b;
}

fn bigint_max() i128 {
    return 170141183460469231731687303715884105727;
}

// ============================================================================
// BitSet class - demonstrates bitwise operators
// ============================================================================

const BitSet = struct {
    bits: u64,

    pub fn __new__(bits: u64) BitSet {
        return .{ .bits = bits };
    }

    pub fn __repr__(self: *const BitSet) []const u8 {
        _ = self;
        return "BitSet(...)";
    }

    /// __bool__ - returns true if any bit is set
    pub fn __bool__(self: *const BitSet) bool {
        return self.bits != 0;
    }

    /// __and__ - bitwise AND
    pub fn __and__(self: *const BitSet, other: *const BitSet) BitSet {
        return .{ .bits = self.bits & other.bits };
    }

    /// __or__ - bitwise OR
    pub fn __or__(self: *const BitSet, other: *const BitSet) BitSet {
        return .{ .bits = self.bits | other.bits };
    }

    /// __xor__ - bitwise XOR
    pub fn __xor__(self: *const BitSet, other: *const BitSet) BitSet {
        return .{ .bits = self.bits ^ other.bits };
    }

    /// __invert__ - bitwise NOT
    pub fn __invert__(self: *const BitSet) BitSet {
        return .{ .bits = ~self.bits };
    }

    /// __lshift__ - left shift
    pub fn __lshift__(self: *const BitSet, other: *const BitSet) BitSet {
        const shift: u6 = @intCast(@min(other.bits, 63));
        return .{ .bits = self.bits << shift };
    }

    /// __rshift__ - right shift
    pub fn __rshift__(self: *const BitSet, other: *const BitSet) BitSet {
        const shift: u6 = @intCast(@min(other.bits, 63));
        return .{ .bits = self.bits >> shift };
    }

    pub fn get_bits(self: *const BitSet) u64 {
        return self.bits;
    }

    pub fn count(self: *const BitSet) i64 {
        return @intCast(@popCount(self.bits));
    }

    // In-place operators

    /// __iadd__ - in-place OR (add bits)
    pub fn __iadd__(self: *BitSet, other: *const BitSet) void {
        self.bits |= other.bits;
    }

    /// __isub__ - in-place AND NOT (remove bits)
    pub fn __isub__(self: *BitSet, other: *const BitSet) void {
        self.bits &= ~other.bits;
    }

    /// __iand__ - in-place AND
    pub fn __iand__(self: *BitSet, other: *const BitSet) void {
        self.bits &= other.bits;
    }

    /// __ior__ - in-place OR
    pub fn __ior__(self: *BitSet, other: *const BitSet) void {
        self.bits |= other.bits;
    }

    /// __ixor__ - in-place XOR
    pub fn __ixor__(self: *BitSet, other: *const BitSet) void {
        self.bits ^= other.bits;
    }

    /// __ilshift__ - in-place left shift
    pub fn __ilshift__(self: *BitSet, other: *const BitSet) void {
        const shift: u6 = @intCast(@min(other.bits, 63));
        self.bits <<= shift;
    }

    /// __irshift__ - in-place right shift
    pub fn __irshift__(self: *BitSet, other: *const BitSet) void {
        const shift: u6 = @intCast(@min(other.bits, 63));
        self.bits >>= shift;
    }
};

// ============================================================================
// PowerNumber class - demonstrates __pow__, __abs__, __int__, __float__, __index__
// ============================================================================

const PowerNumber = struct {
    value: f64,

    pub fn __new__(value: f64) PowerNumber {
        return .{ .value = value };
    }

    pub fn __repr__(self: *const PowerNumber) []const u8 {
        _ = self;
        return "PowerNumber(...)";
    }

    /// __pow__ - power operator
    pub fn __pow__(self: *const PowerNumber, other: *const PowerNumber) PowerNumber {
        return .{ .value = std.math.pow(f64, self.value, other.value) };
    }

    /// __pos__ - unary positive
    pub fn __pos__(self: *const PowerNumber) PowerNumber {
        return .{ .value = self.value };
    }

    /// __abs__ - absolute value
    pub fn __abs__(self: *const PowerNumber) PowerNumber {
        return .{ .value = @abs(self.value) };
    }

    /// __int__ - convert to int
    pub fn __int__(self: *const PowerNumber) i64 {
        return @intFromFloat(self.value);
    }

    /// __float__ - convert to float
    pub fn __float__(self: *const PowerNumber) f64 {
        return self.value;
    }

    /// __index__ - convert to index
    pub fn __index__(self: *const PowerNumber) i64 {
        return @intFromFloat(self.value);
    }

    /// __bool__ - true if non-zero
    pub fn __bool__(self: *const PowerNumber) bool {
        return self.value != 0.0;
    }

    /// __complex__ - convert to complex number
    pub fn __complex__(self: *const PowerNumber) pyoz.Complex {
        return pyoz.Complex.init(self.value, 0.0);
    }
};

// ============================================================================
// Exceptions
// ============================================================================

// ============================================================================
// Timer class - context manager with __enter__/__exit__
// ============================================================================

const Timer = struct {
    name: [32]u8,
    name_len: usize,
    started: bool,
    counter: i64,

    pub fn __new__(name: []const u8) Timer {
        var self = Timer{
            .name = undefined,
            .name_len = @min(name.len, 32),
            .started = false,
            .counter = 0,
        };
        @memcpy(self.name[0..self.name_len], name[0..self.name_len]);
        return self;
    }

    pub fn __repr__(self: *const Timer) []const u8 {
        _ = self;
        return "Timer(...)";
    }

    /// __enter__ - called when entering 'with' block
    pub fn __enter__(self: *Timer) *Timer {
        self.started = true;
        self.counter = 0;
        return self;
    }

    /// __exit__ - called when exiting 'with' block
    /// Returns True to suppress exceptions, False to propagate
    pub fn __exit__(self: *Timer) bool {
        self.started = false;
        return false; // Don't suppress exceptions
    }

    pub fn get_name(self: *const Timer) []const u8 {
        return self.name[0..self.name_len];
    }

    pub fn is_active(self: *const Timer) bool {
        return self.started;
    }

    pub fn tick(self: *Timer) void {
        if (self.started) {
            self.counter += 1;
        }
    }

    pub fn get_count(self: *const Timer) i64 {
        return self.counter;
    }
};

// ============================================================================
// Multiplier class - callable with multiple arguments
// ============================================================================

const Multiplier = struct {
    factor: f64,

    pub fn __new__(factor: f64) Multiplier {
        return .{ .factor = factor };
    }

    pub fn __repr__(self: *const Multiplier) []const u8 {
        _ = self;
        return "Multiplier(...)";
    }

    /// __call__ with two arguments
    /// Usage: mult = Multiplier(2.0); mult(3.0, 4.0) -> 14.0 (2*(3+4))
    pub fn __call__(self: *const Multiplier, a: f64, b: f64) f64 {
        return self.factor * (a + b);
    }
};

// ============================================================================
// FrozenPoint - immutable/hashable class
// ============================================================================

const FrozenPoint = struct {
    pub const __frozen__ = true;

    x: f64,
    y: f64,

    pub fn __repr__(self: *const FrozenPoint) []const u8 {
        _ = self;
        return "FrozenPoint(...)";
    }

    /// __hash__ - make frozen objects hashable
    pub fn __hash__(self: *const FrozenPoint) i64 {
        // Simple hash combining x and y
        const x_bits: u64 = @bitCast(self.x);
        const y_bits: u64 = @bitCast(self.y);
        const combined = x_bits ^ (y_bits *% 31);
        return @bitCast(combined);
    }

    pub fn __eq__(self: *const FrozenPoint, other: *const FrozenPoint) bool {
        return self.x == other.x and self.y == other.y;
    }

    pub fn magnitude(self: *const FrozenPoint) f64 {
        return @sqrt(self.x * self.x + self.y * self.y);
    }

    pub fn scale(self: *const FrozenPoint, factor: f64) FrozenPoint {
        return .{ .x = self.x * factor, .y = self.y * factor };
    }

    pub fn origin() FrozenPoint {
        return .{ .x = 0.0, .y = 0.0 };
    }
};

// ============================================================================
// Circle - class with class attributes
// ============================================================================

const Circle = struct {
    radius: f64,

    // Class attributes (constants accessible on the class)
    pub const classattr_PI: f64 = 3.14159265358979;
    pub const classattr_UNIT_RADIUS: f64 = 1.0;
    pub const classattr_DEFAULT_COLOR: []const u8 = "red";
    pub const classattr_MAX_RADIUS: i64 = 1000;

    pub fn __repr__(self: *const Circle) []const u8 {
        _ = self;
        return "Circle(...)";
    }

    pub fn area(self: *const Circle) f64 {
        return classattr_PI * self.radius * self.radius;
    }

    pub fn circumference(self: *const Circle) f64 {
        return 2.0 * classattr_PI * self.radius;
    }

    pub fn unit() Circle {
        return .{ .radius = classattr_UNIT_RADIUS };
    }
};

// ============================================================================
// Temperature - demonstrates pyoz.property() API
// ============================================================================

const Temperature = struct {
    _celsius: f64,

    const Self = @This();

    pub fn __new__(initial_celsius: f64) Temperature {
        return .{ ._celsius = initial_celsius };
    }

    pub fn __repr__(self: *const Temperature) []const u8 {
        _ = self;
        return "Temperature(...)";
    }

    /// Property using pyoz.property() - celsius with validation
    pub const celsius = pyoz.property(.{
        .get = struct {
            fn get(self: *const Self) f64 {
                return self._celsius;
            }
        }.get,
        .set = struct {
            fn set(self: *Self, value: f64) void {
                // Clamp to absolute zero minimum
                self._celsius = if (value < -273.15) -273.15 else value;
            }
        }.set,
        .doc = "Temperature in Celsius (clamped to >= -273.15)",
    });

    /// Property using pyoz.property() - fahrenheit (computed, read-write)
    pub const fahrenheit = pyoz.property(.{
        .get = struct {
            fn get(self: *const Self) f64 {
                return self._celsius * 9.0 / 5.0 + 32.0;
            }
        }.get,
        .set = struct {
            fn set(self: *Self, value: f64) void {
                self._celsius = (value - 32.0) * 5.0 / 9.0;
            }
        }.set,
        .doc = "Temperature in Fahrenheit",
    });

    /// Property using pyoz.property() - kelvin (read-only, no setter)
    pub const kelvin = pyoz.property(.{
        .get = struct {
            fn get(self: *const Self) f64 {
                return self._celsius + 273.15;
            }
        }.get,
        .doc = "Temperature in Kelvin (read-only)",
    });

    /// Check if temperature is below freezing
    pub fn is_freezing(self: *const Self) bool {
        return self._celsius < 0.0;
    }

    /// Check if temperature is boiling (at sea level)
    pub fn is_boiling(self: *const Self) bool {
        return self._celsius >= 100.0;
    }
};

// ============================================================================
// TypedAttribute - A descriptor that enforces type and range constraints
// ============================================================================

/// A descriptor that stores a value with min/max bounds
/// Usage: Create as class attribute, then access on instances
const TypedAttribute = struct {
    value: f64,
    min_val: f64,
    max_val: f64,
    name: [32]u8,
    name_len: usize,

    pub fn __new__(min_val: f64, max_val: f64) TypedAttribute {
        return .{
            .value = min_val, // Default to minimum
            .min_val = min_val,
            .max_val = max_val,
            .name = undefined,
            .name_len = 0,
        };
    }

    pub fn __repr__(self: *const TypedAttribute) []const u8 {
        _ = self;
        return "TypedAttribute(...)";
    }

    /// __get__ - called when attribute is accessed
    /// Returns the stored value (or self if accessed on class)
    pub fn __get__(self: *const TypedAttribute, obj: ?*pyoz.PyObject) f64 {
        _ = obj; // Could use to return self when obj is null (class access)
        return self.value;
    }

    /// __set__ - called when attribute is assigned
    /// Clamps value to [min_val, max_val]
    pub fn __set__(self: *TypedAttribute, obj: ?*pyoz.PyObject, value: f64) void {
        _ = obj;
        self.value = @max(self.min_val, @min(self.max_val, value));
    }

    /// __delete__ - called when attribute is deleted
    /// Resets value to the minimum (default)
    pub fn __delete__(self: *TypedAttribute, obj: ?*pyoz.PyObject) void {
        _ = obj;
        self.value = self.min_val;
    }

    /// Get the current bounds
    pub fn get_bounds(self: *const TypedAttribute) struct { f64, f64 } {
        return .{ self.min_val, self.max_val };
    }
};

// ============================================================================
// ReversibleList - sequence with __reversed__
// ============================================================================

/// A simple list that supports reversed iteration
/// Uses a single type with a reverse_mode flag to work around converter limitations
const ReversibleList = struct {
    data: [8]i64,
    len: usize,
    iter_index: usize,
    reverse_mode: bool,

    pub fn __new__(a: i64, b: i64, c: i64) ReversibleList {
        var list = ReversibleList{
            .data = [_]i64{0} ** 8,
            .len = 3,
            .iter_index = 0,
            .reverse_mode = false,
        };
        list.data[0] = a;
        list.data[1] = b;
        list.data[2] = c;
        return list;
    }

    pub fn __repr__(self: *const ReversibleList) []const u8 {
        _ = self;
        return "ReversibleList(...)";
    }

    pub fn __len__(self: *const ReversibleList) usize {
        return self.len;
    }

    pub fn __getitem__(self: *const ReversibleList, index: i64) !i64 {
        const idx: usize = if (index < 0)
            @intCast(@as(i64, @intCast(self.len)) + index)
        else
            @intCast(index);

        if (idx >= self.len) {
            return error.IndexOutOfBounds;
        }
        return self.data[idx];
    }

    /// __iter__ - return self, preserving reverse_mode
    pub fn __iter__(self: *ReversibleList) *ReversibleList {
        self.iter_index = 0;
        // Don't reset reverse_mode - let __reversed__ control it
        return self;
    }

    /// __next__ - get next item based on reverse_mode
    pub fn __next__(self: *ReversibleList) ?i64 {
        if (self.iter_index >= self.len) {
            // Reset reverse_mode after iteration completes
            self.reverse_mode = false;
            return null;
        }
        const idx = if (self.reverse_mode)
            self.len - 1 - self.iter_index
        else
            self.iter_index;
        self.iter_index += 1;
        return self.data[idx];
    }

    /// __reversed__ - return self configured for reverse iteration
    /// This sets reverse_mode=true before __iter__ is called
    pub fn __reversed__(self: *ReversibleList) *ReversibleList {
        self.reverse_mode = true;
        self.iter_index = 0;
        return self;
    }

    /// Append a value
    pub fn append(self: *ReversibleList, value: i64) !void {
        if (self.len >= 8) {
            return error.ListFull;
        }
        self.data[self.len] = value;
        self.len += 1;
    }
};

// ============================================================================
// Vector - class with reflected operators
// Reflected operators receive a raw PyObject for the "other" operand
// ============================================================================

const Vector = struct {
    x: f64,
    y: f64,
    z: f64,

    pub fn __new__(x: f64, y: f64, z: f64) Vector {
        return .{ .x = x, .y = y, .z = z };
    }

    pub fn __repr__(self: *const Vector) []const u8 {
        _ = self;
        return "Vector(...)";
    }

    pub fn __add__(self: *const Vector, other: *const Vector) Vector {
        return .{ .x = self.x + other.x, .y = self.y + other.y, .z = self.z + other.z };
    }

    /// __radd__ - reflected addition (scalar + vector)
    /// Called when: 5 + vector (left operand doesn't support the operation)
    pub fn __radd__(self: *const Vector, other: *pyoz.PyObject) Vector {
        // Try to convert the other object to a float
        const scalar = pyoz.Conversions.fromPy(f64, other) catch return self.*;
        return .{ .x = self.x + scalar, .y = self.y + scalar, .z = self.z + scalar };
    }

    /// __mul__ - vector * vector (element-wise)
    pub fn __mul__(self: *const Vector, other: *const Vector) Vector {
        return .{ .x = self.x * other.x, .y = self.y * other.y, .z = self.z * other.z };
    }

    /// __rmul__ - reflected multiplication (scalar * vector)
    /// Called when: 3.0 * vector
    pub fn __rmul__(self: *const Vector, other: *pyoz.PyObject) Vector {
        const scalar = pyoz.Conversions.fromPy(f64, other) catch return self.*;
        return .{ .x = self.x * scalar, .y = self.y * scalar, .z = self.z * scalar };
    }

    pub fn __sub__(self: *const Vector, other: *const Vector) Vector {
        return .{ .x = self.x - other.x, .y = self.y - other.y, .z = self.z - other.z };
    }

    /// __rsub__ - reflected subtraction (scalar - vector)
    /// Called when: 10 - vector
    pub fn __rsub__(self: *const Vector, other: *pyoz.PyObject) Vector {
        const scalar = pyoz.Conversions.fromPy(f64, other) catch return self.*;
        return .{ .x = scalar - self.x, .y = scalar - self.y, .z = scalar - self.z };
    }

    pub fn magnitude(self: *const Vector) f64 {
        return @sqrt(self.x * self.x + self.y * self.y + self.z * self.z);
    }

    pub fn dot(self: *const Vector, other: *const Vector) f64 {
        return self.x * other.x + self.y * other.y + self.z * other.z;
    }

    /// __matmul__ - matrix multiplication operator (@)
    /// For vectors, this computes the cross product
    pub fn __matmul__(self: *const Vector, other: *const Vector) Vector {
        // Cross product: a × b = (a.y*b.z - a.z*b.y, a.z*b.x - a.x*b.z, a.x*b.y - a.y*b.x)
        return .{
            .x = self.y * other.z - self.z * other.y,
            .y = self.z * other.x - self.x * other.z,
            .z = self.x * other.y - self.y * other.x,
        };
    }

    /// __rmatmul__ - reflected matrix multiplication operator
    /// Called when: other @ vector (and other doesn't support @)
    pub fn __rmatmul__(self: *const Vector, other: *pyoz.PyObject) Vector {
        // Try to interpret other as a scalar for scalar @ vector (unusual but demonstrable)
        const scalar = pyoz.Conversions.fromPy(f64, other) catch return self.*;
        return .{ .x = self.x * scalar, .y = self.y * scalar, .z = self.z * scalar };
    }

    /// __imatmul__ - in-place matrix multiplication operator (@=)
    /// For demonstration, we'll make this compute cross product with another vector
    pub fn __imatmul__(self: *Vector, other: *const Vector) void {
        const new_x = self.y * other.z - self.z * other.y;
        const new_y = self.z * other.x - self.x * other.z;
        const new_z = self.x * other.y - self.y * other.x;
        self.x = new_x;
        self.y = new_y;
        self.z = new_z;
    }
};

// ============================================================================
// DynamicObject - __getattr__/__setattr__/__delattr__
// ============================================================================

const DynamicObject = struct {
    // Simple key-value storage
    attr_names: [8][32]u8,
    attr_name_lens: [8]usize,
    attr_values: [8]i64,
    attr_count: usize,

    pub fn __new__() DynamicObject {
        return .{
            .attr_names = undefined,
            .attr_name_lens = undefined,
            .attr_values = undefined,
            .attr_count = 0,
        };
    }

    pub fn __repr__(self: *const DynamicObject) []const u8 {
        _ = self;
        return "DynamicObject(...)";
    }

    /// __getattr__ - called when attribute not found normally
    pub fn __getattr__(self: *const DynamicObject, name: []const u8) !i64 {
        for (0..self.attr_count) |i| {
            const stored_len = self.attr_name_lens[i];
            if (stored_len == name.len and std.mem.eql(u8, self.attr_names[i][0..stored_len], name)) {
                return self.attr_values[i];
            }
        }
        return error.AttributeError;
    }

    /// __setattr__ - called when setting any attribute
    pub fn __setattr__(self: *DynamicObject, name: []const u8, value: i64) !void {
        const name_len = @min(name.len, 32);

        // Check if attribute exists
        for (0..self.attr_count) |i| {
            const stored_len = self.attr_name_lens[i];
            if (stored_len == name_len and std.mem.eql(u8, self.attr_names[i][0..stored_len], name[0..name_len])) {
                self.attr_values[i] = value;
                return;
            }
        }

        // Add new attribute
        if (self.attr_count >= 8) return error.ValueError;
        @memcpy(self.attr_names[self.attr_count][0..name_len], name[0..name_len]);
        self.attr_name_lens[self.attr_count] = name_len;
        self.attr_values[self.attr_count] = value;
        self.attr_count += 1;
    }

    /// __delattr__ - called when deleting an attribute
    pub fn __delattr__(self: *DynamicObject, name: []const u8) !void {
        const name_len = @min(name.len, 32);
        for (0..self.attr_count) |i| {
            const stored_len = self.attr_name_lens[i];
            if (stored_len == name_len and std.mem.eql(u8, self.attr_names[i][0..stored_len], name[0..name_len])) {
                // Shift remaining attributes down
                var j = i;
                while (j < self.attr_count - 1) : (j += 1) {
                    self.attr_names[j] = self.attr_names[j + 1];
                    self.attr_name_lens[j] = self.attr_name_lens[j + 1];
                    self.attr_values[j] = self.attr_values[j + 1];
                }
                self.attr_count -= 1;
                return;
            }
        }
        return error.AttributeError;
    }

    pub fn count(self: *const DynamicObject) usize {
        return self.attr_count;
    }

    /// Get all attribute names as an iterator
    pub fn keys(self: *const DynamicObject) pyoz.LazyIterator([]const u8, KeysIterState) {
        return .{ .state = .{
            .names = &self.attr_names,
            .name_lens = &self.attr_name_lens,
            .total = self.attr_count,
            .index = 0,
        } };
    }
};

/// State for DynamicObject.keys() iterator
const KeysIterState = struct {
    names: *const [8][32]u8,
    name_lens: *const [8]usize,
    total: usize,
    index: usize,

    pub fn next(self: *KeysIterState) ?[]const u8 {
        if (self.index >= self.total) return null;
        const len = self.name_lens[self.index];
        const name = self.names[self.index][0..len];
        self.index += 1;
        return name;
    }
};

// ============================================================================
// LogLevel enum
// ============================================================================

const LogLevel = enum {
    debug,
    info,
    warning,
    @"error",
    critical,
};

// ============================================================================
// Exceptions
// ============================================================================

const ValidationError = pyoz.exception("ValidationError", .{ .base = .ValueError, .doc = "Validation failed" });
const NotFoundError = pyoz.exception("NotFoundError", .{ .base = .KeyError, .doc = "Item not found" });
const MathError = pyoz.exception("MathError", .{ .base = .RuntimeError, .doc = "Math error" });

// ============================================================================
// Module definition
// ============================================================================

/// Async on the Limited API: sleep on the Io runtime, then add.
fn async_add(io: std.Io, a: i64, b: i64) !i64 {
    try io.sleep(.fromMilliseconds(1), .awake);
    return a + b;
}

/// Completion step (pyoz.asyncThen): runs on the event loop thread with Python
/// attached, and passes the sum to a Python callable.
fn async_add_then(sum: i64, callback: *pyoz.PyObject, extra: ?*pyoz.PyObject) ?*pyoz.PyObject {
    const arg = pyoz.py.PyLong_FromLongLong(sum) orelse return null;
    defer pyoz.py.Py_DecRef(arg);
    return pyoz.py.c.PyObject_CallFunctionObjArgs(callback, arg, extra, @as(?*pyoz.PyObject, null));
}

/// Async protocols on the Limited API (tp_as_async via PyType_FromSpec slots).
/// `async for` yields n-1 .. 0; each item comes from a std.Io task, and the
/// task returning null ends the iteration.
fn nextTick(io: std.Io, n: i64) !?i64 {
    try io.sleep(.fromMilliseconds(1), .awake);
    return if (n > 0) n - 1 else null;
}
const next_tick = pyoz.asyncFn(nextTick);

const AsyncTicker = struct {
    n: i64,

    pub fn __aiter__(self: *AsyncTicker) *AsyncTicker {
        return self;
    }

    pub fn __anext__(self: *AsyncTicker) !pyoz.Future(nextTick) {
        const current = self.n;
        if (self.n > 0) self.n -= 1;
        return next_tick(current);
    }

    /// `await AsyncTicker(n)` completes immediately with n.
    pub fn __await__(self: *const AsyncTicker) i64 {
        return self.n;
    }

    pub fn __aenter__(self: *AsyncTicker) *AsyncTicker {
        return self;
    }

    pub fn __aexit__(self: *AsyncTicker, exc_type: ?*pyoz.PyObject, exc: ?*pyoz.PyObject, tb: ?*pyoz.PyObject) void {
        _ = exc_type;
        _ = exc;
        _ = tb;
        self.n = -1;
    }
};

pub const Abi3Example = pyoz.module(.{
    .name = "example_abi3",
    .doc = "ABI3-compatible example module demonstrating Stable ABI features",
    .funcs = &.{
        pyoz.func("make_del_counter", make_del_counter, "Return a DelCounter by value"),
        pyoz.func("del_counter_deleted_count", del_counter_deleted_count, "How many DelCounter instances were deleted"),
        // Basic arithmetic
        pyoz.func("async_add", pyoz.asyncFn(async_add), "await: a+b (ABI3)"),
        pyoz.func("async_add_apply", pyoz.asyncThen(async_add, async_add_then), "await: callback(a+b[, extra])").withParams("a, b, callback, extra"),
        pyoz.func("add", add, "Add two integers"),
        pyoz.func("multiply", multiply, "Multiply two floats"),
        pyoz.func("divide", divide, "Divide two floats (returns None if divisor is 0)"),
        pyoz.func("power", power, "Raise base to integer power"),

        // GIL release
        pyoz.func("compute_sum_no_gil", compute_sum_no_gil, "Sum of squares (releases GIL)"),
        pyoz.func("compute_sum_with_gil", compute_sum_with_gil, "Sum of squares (keeps GIL)"),

        // Strings
        pyoz.func("greet", greet, "Return a greeting"),
        pyoz.func("string_length", string_length, "Get string length"),
        pyoz.func("is_palindrome", is_palindrome, "Check if string is a palindrome"),

        // Complex numbers
        pyoz.func("complex_add", complex_add, "Add two complex numbers"),
        pyoz.func("complex_multiply", complex_multiply, "Multiply two complex numbers"),
        pyoz.func("complex_magnitude", complex_magnitude, "Get magnitude of complex number"),
        pyoz.func("complex_conjugate", complex_conjugate, "Get complex conjugate"),

        // ListView
        pyoz.func("sum_list", sum_list, "Sum all integers in a list"),
        pyoz.func("list_length", list_length, "Get list length"),

        // DictView with iteration
        pyoz.func("dict_get", dict_get, "Get value from dict by key"),
        pyoz.func("dict_has_key", dict_has_key, "Check if dict has key"),
        pyoz.func("dict_size", dict_size, "Get dict size"),
        pyoz.func("dict_sum_values", dict_sum_values, "Sum all values in dict (iteration)"),
        pyoz.func("dict_keys_length", dict_keys_length, "Count keys via iteration"),

        // SetView with iteration
        pyoz.func("set_contains", set_contains, "Check if set contains value"),
        pyoz.func("set_size", set_size, "Get set size"),
        pyoz.func("set_sum", set_sum, "Sum all values in set (iteration)"),

        // IteratorView - works with any iterable
        pyoz.func("iter_sum", iter_sum, "Sum integers from any iterable"),
        pyoz.func("iter_count", iter_count, "Count items in any iterable"),
        pyoz.func("iter_max", iter_max, "Find max in any iterable"),

        // Bytes input/output
        pyoz.func("bytes_length", bytes_length, "Get bytes length"),
        pyoz.func("bytes_sum", bytes_sum, "Sum all byte values"),
        pyoz.func("make_bytes", make_bytes, "Create bytes object"),
        pyoz.func("bytes_starts_with", bytes_starts_with, "Check if bytes starts with value"),

        // Path input/output
        pyoz.func("path_str", path_str, "Get path as string"),
        pyoz.func("path_len", path_len, "Get path length"),
        pyoz.func("make_path", make_path, "Create a path object"),
        pyoz.func("path_starts_with", path_starts_with, "Check if path starts with prefix"),

        // Decimal input/output
        pyoz.func("decimal_str", decimal_str, "Get decimal as string"),
        pyoz.func("make_decimal", make_decimal, "Create a decimal"),
        pyoz.func("decimal_double", decimal_double, "Double a decimal value"),

        // BigInt (i128/u128)
        pyoz.func("bigint_echo", bigint_echo, "Echo an i128"),
        pyoz.func("biguint_echo", biguint_echo, "Echo a u128"),
        pyoz.func("bigint_add", bigint_add, "Add two i128 values"),
        pyoz.func("bigint_max", bigint_max, "Return i128 max value"),

        // Optional/Error handling
        pyoz.func("safe_divide", safe_divide, "Divide with None on zero"),
        pyoz.func("sqrt_positive", sqrt_positive, "Square root (None if negative)"),

        // Tuples
        pyoz.func("minmax", minmax, "Return (min, max) of two values"),
        pyoz.func("divmod", divmod, "Return (quotient, remainder)"),

        // Bools
        pyoz.func("is_even", is_even, "Check if number is even"),
        pyoz.func("is_positive", is_positive, "Check if number is positive"),
        pyoz.func("all_positive", all_positive, "Check if all list items are positive"),

        // DateTime
        pyoz.func("create_date", create_date, "Create a date object"),
        pyoz.func("create_datetime", create_datetime, "Create a datetime object"),
        pyoz.func("create_time", create_time, "Create a time object"),
        pyoz.func("create_timedelta", create_timedelta, "Create a timedelta object"),
        pyoz.func("get_date_year", get_date_year, "Get year from date"),
        pyoz.func("get_date_month", get_date_month, "Get month from date"),
        pyoz.func("get_date_day", get_date_day, "Get day from date"),
        pyoz.func("get_datetime_hour", get_datetime_hour, "Get hour from datetime"),
        pyoz.func("get_time_components", get_time_components, "Get (hour, minute, second) from time"),
        pyoz.func("get_timedelta_days", get_timedelta_days, "Get days from timedelta"),

        // BufferView (read-only buffer consumer)
        pyoz.func("buffer_sum_f64", buffer_sum_f64, "Sum all f64 elements in buffer"),
        pyoz.func("buffer_sum_i32", buffer_sum_i32, "Sum all i32 elements in buffer"),
        pyoz.func("buffer_len", buffer_len, "Get buffer length"),
        pyoz.func("buffer_ndim", buffer_ndim, "Get buffer dimensions"),
        pyoz.func("buffer_get", buffer_get, "Get element at index"),

        // Iterator producer (eager)
        pyoz.func("get_fibonacci", get_fibonacci, "Get first 10 fibonacci numbers"),
        pyoz.func("get_squares", get_squares, "Get squares of 1-5"),

        // LazyIterator (generators)
        pyoz.func("lazy_range", lazy_range, "Create a lazy range iterator"),
        pyoz.func("lazy_fibonacci", lazy_fibonacci, "Create a lazy Fibonacci iterator"),

        // Keyword arguments
        pyoz.kwfunc("greet_person", greet_person, "Greet with keyword arguments"),
        pyoz.kwfunc("power_with_default", power_with_default, "Power with default exponent=2"),
        pyoz.kwfunc("greet_named", greet_named, "Greet with named kwargs"),
        pyoz.kwfunc("calculate_named", calculate_named, "Calculate with named kwargs"),
    },
    .classes = &.{
        pyoz.class("Counter", Counter),
        pyoz.class("AsyncTicker", AsyncTicker),
        pyoz.class("Point", Point),
        pyoz.class("Number", Number),
        pyoz.class("Version", Version),
        pyoz.class("Adder", Adder),
        pyoz.class("IntList", IntList),
        pyoz.class("FailingResource", FailingResource),
        pyoz.class("DelCounter", DelCounter),
        pyoz.class("BitSet", BitSet),
        pyoz.class("PowerNumber", PowerNumber),
        // New classes for ABI3 testing
        pyoz.class("Timer", Timer),
        pyoz.class("Multiplier", Multiplier),
        pyoz.class("FrozenPoint", FrozenPoint),
        pyoz.class("Circle", Circle),
        pyoz.class("Temperature", Temperature),
        pyoz.class("TypedAttribute", TypedAttribute),
        pyoz.class("ReversibleList", ReversibleList),
        pyoz.class("Vector", Vector),
        pyoz.class("DynamicObject", DynamicObject),
    },
    .enums = &.{
        pyoz.enumDef("Color", Color),
        pyoz.enumDef("HttpStatus", HttpStatus),
        pyoz.enumDef("TaskStatus", TaskStatus),
        pyoz.enumDef("LogLevel", LogLevel),
    },
    .exceptions = &.{
        ValidationError,
        NotFoundError,
        MathError,
    },
    .consts = &.{
        pyoz.constant("VERSION", "1.0.0"),
        pyoz.constant("PI", 3.14159265358979),
        pyoz.constant("MAX_VALUE", @as(i64, 1000000)),
        pyoz.constant("DEBUG", false),
    },
    .error_mappings = &.{
        pyoz.mapError("IndexError", .IndexError),
        pyoz.mapError("ListFull", .ValueError),
        pyoz.mapErrorMsg("DivisionByZero", .RuntimeError, "Cannot divide by zero"),
    },
    // .from: auto-scan a Zig namespace — functions, constants, and docstrings
    // are discovered automatically from pub declarations.
    .from = &.{
        @import("from_extras.zig"),
    },
});

// Required: forces analysis of all pub decls so PyInit_ is exported.
comptime {
    for (@typeInfo(@This()).@"struct".decls) |decl| {
        _ = @field(@This(), decl.name);
    }
}
