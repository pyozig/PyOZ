//! PyOZ ABI3 (Stable ABI) Comprehensive Test Suite
//!
//! Tests all ABI3-compatible features of PyOZ using the embedding API.
//! Run with: zig build test_abi3

const std = @import("std");
const pyoz = @import("lib/root.zig");
const py = pyoz.py;

// ============================================================================
// Test Infrastructure
// ============================================================================

var test_python: ?pyoz.Python = null;
var python_version: struct { major: i64, minor: i64 } = .{ .major = 0, .minor = 0 };

fn initTestPython() !*pyoz.Python {
    if (test_python == null) {
        test_python = try pyoz.Python.init();
        // Import the ABI3 example module
        try test_python.?.exec("import sys");
        try test_python.?.exec("sys.path.insert(0, 'zig-out/lib')");
        try test_python.?.exec("import example_abi3");

        // Detect Python version for conditional test skipping
        python_version.major = try test_python.?.eval(i64, "sys.version_info.major");
        python_version.minor = try test_python.?.eval(i64, "sys.version_info.minor");
    }
    return &test_python.?;
}

/// Check if Python version is at least major.minor
fn pythonVersionAtLeast(major: i64, minor: i64) bool {
    if (python_version.major > major) return true;
    if (python_version.major == major and python_version.minor >= minor) return true;
    return false;
}

/// Skip test if Python version is below required
fn requirePythonVersion(major: i64, minor: i64) !void {
    if (!pythonVersionAtLeast(major, minor)) {
        std.debug.print("Skipping: requires Python {}.{}, have {}.{}\n", .{ major, minor, python_version.major, python_version.minor });
        return error.SkipZigTest;
    }
}

/// Skip test if Python version matches exactly (for known broken versions)
fn skipPythonVersion(major: i64, minor: i64) !void {
    if (python_version.major == major and python_version.minor == minor) {
        std.debug.print("Skipping: known issue on Python {}.{}\n", .{ major, minor });
        return error.SkipZigTest;
    }
}

var numpy_available: ?bool = null;

/// Check if numpy is available (cached)
fn hasNumpy(python: *pyoz.Python) bool {
    if (numpy_available) |available| {
        return available;
    }
    python.exec("import numpy as np") catch {
        numpy_available = false;
        return false;
    };
    numpy_available = true;
    return true;
}

/// Skip test if numpy is not installed
fn requireNumpy(python: *pyoz.Python) !void {
    if (!hasNumpy(python)) {
        std.debug.print("Skipping: requires numpy\n", .{});
        return error.SkipZigTest;
    }
}

// ============================================================================
// BASIC ARITHMETIC FUNCTIONS
// ============================================================================

test "abi3 - fn add - basic integer addition" {
    const python = try initTestPython();

    const r1 = try python.eval(i64, "example_abi3.add(2, 3)");
    try std.testing.expectEqual(@as(i64, 5), r1);

    const r2 = try python.eval(i64, "example_abi3.add(-10, 10)");
    try std.testing.expectEqual(@as(i64, 0), r2);

    const r3 = try python.eval(i64, "example_abi3.add(100, 200)");
    try std.testing.expectEqual(@as(i64, 300), r3);
}

test "abi3 - fn multiply - float multiplication" {
    const python = try initTestPython();

    const r1 = try python.eval(f64, "example_abi3.multiply(6.0, 7.0)");
    try std.testing.expectApproxEqAbs(@as(f64, 42.0), r1, 0.0001);

    const r2 = try python.eval(f64, "example_abi3.multiply(2.5, 4.0)");
    try std.testing.expectApproxEqAbs(@as(f64, 10.0), r2, 0.0001);
}

test "abi3 - fn divide - division returning None on zero" {
    const python = try initTestPython();

    const r1 = try python.eval(f64, "example_abi3.divide(10.0, 2.0)");
    try std.testing.expectApproxEqAbs(@as(f64, 5.0), r1, 0.0001);

    // Division by zero returns None
    const is_none = try python.eval(bool, "example_abi3.divide(1.0, 0.0) is None");
    try std.testing.expect(is_none);
}

test "abi3 - fn power - exponentiation" {
    const python = try initTestPython();

    const r1 = try python.eval(f64, "example_abi3.power(2.0, 3)");
    try std.testing.expectApproxEqAbs(@as(f64, 8.0), r1, 0.0001);

    const r2 = try python.eval(f64, "example_abi3.power(3.0, 0)");
    try std.testing.expectApproxEqAbs(@as(f64, 1.0), r2, 0.0001);
}

// ============================================================================
// GIL RELEASE FUNCTIONS
// ============================================================================

test "abi3 - fn compute_sum_no_gil - GIL release" {
    const python = try initTestPython();

    const result = try python.eval(i64, "example_abi3.compute_sum_no_gil(1000)");
    // Just verify it completes and returns a value
    try std.testing.expect(result != 0);
}

test "abi3 - fn compute_sum_with_gil - keeps GIL" {
    const python = try initTestPython();

    const result = try python.eval(i64, "example_abi3.compute_sum_with_gil(1000)");
    // Just verify it completes and returns same value as no_gil version
    const no_gil_result = try python.eval(i64, "example_abi3.compute_sum_no_gil(1000)");
    try std.testing.expectEqual(result, no_gil_result);
}

// ============================================================================
// STRING FUNCTIONS
// ============================================================================

test "abi3 - fn greet - string return" {
    const python = try initTestPython();

    const has_abi3 = try python.eval(bool, "'ABI3' in example_abi3.greet('World')");
    try std.testing.expect(has_abi3);
}

test "abi3 - fn string_length - get string length" {
    const python = try initTestPython();

    try std.testing.expectEqual(@as(i64, 5), try python.eval(i64, "example_abi3.string_length('hello')"));
    try std.testing.expectEqual(@as(i64, 0), try python.eval(i64, "example_abi3.string_length('')"));
}

test "abi3 - fn is_palindrome - check palindrome" {
    const python = try initTestPython();

    try std.testing.expect(try python.eval(bool, "example_abi3.is_palindrome('radar')"));
    try std.testing.expect(try python.eval(bool, "example_abi3.is_palindrome('a')"));
    try std.testing.expect(try python.eval(bool, "example_abi3.is_palindrome('')"));
    try std.testing.expect(!try python.eval(bool, "example_abi3.is_palindrome('hello')"));
}

// ============================================================================
// COMPLEX NUMBER FUNCTIONS
// ============================================================================

test "abi3 - fn complex_add - add complex numbers" {
    const python = try initTestPython();

    try python.exec("c = example_abi3.complex_add(1+2j, 3+4j)");
    try std.testing.expect(try python.eval(bool, "c == (4+6j)"));
}

test "abi3 - fn complex_multiply - multiply complex numbers" {
    const python = try initTestPython();

    try python.exec("c = example_abi3.complex_multiply(1+2j, 3+4j)");
    // (1+2i)(3+4i) = 3 + 4i + 6i + 8i^2 = 3 + 10i - 8 = -5 + 10i
    try std.testing.expect(try python.eval(bool, "c == (-5+10j)"));
}

test "abi3 - fn complex_magnitude - calculate magnitude" {
    const python = try initTestPython();

    const mag = try python.eval(f64, "example_abi3.complex_magnitude(3+4j)");
    try std.testing.expectApproxEqAbs(@as(f64, 5.0), mag, 0.0001);
}

test "abi3 - fn complex_conjugate - get conjugate" {
    const python = try initTestPython();

    try python.exec("c = example_abi3.complex_conjugate(3+4j)");
    try std.testing.expect(try python.eval(bool, "c == (3-4j)"));
}

// ============================================================================
// LIST FUNCTIONS (ListView)
// ============================================================================

test "abi3 - fn sum_list - iterate and sum" {
    const python = try initTestPython();

    const sum1 = try python.eval(i64, "example_abi3.sum_list([1, 2, 3, 4, 5])");
    try std.testing.expectEqual(@as(i64, 15), sum1);

    const sum2 = try python.eval(i64, "example_abi3.sum_list([])");
    try std.testing.expectEqual(@as(i64, 0), sum2);
}

test "abi3 - fn list_length - get length" {
    const python = try initTestPython();

    try std.testing.expectEqual(@as(i64, 5), try python.eval(i64, "example_abi3.list_length([1, 2, 3, 4, 5])"));
    try std.testing.expectEqual(@as(i64, 0), try python.eval(i64, "example_abi3.list_length([])"));
}

// ============================================================================
// DICT FUNCTIONS (DictView)
// ============================================================================

test "abi3 - fn dict_get - get by key" {
    const python = try initTestPython();

    const val = try python.eval(i64, "example_abi3.dict_get({'key': 123}, 'key')");
    try std.testing.expectEqual(@as(i64, 123), val);

    // Missing key returns None
    const missing = try python.eval(bool, "example_abi3.dict_get({'a': 1}, 'b') is None");
    try std.testing.expect(missing);
}

test "abi3 - fn dict_has_key - key lookup" {
    const python = try initTestPython();

    try std.testing.expect(try python.eval(bool, "example_abi3.dict_has_key({'x': 1, 'y': 2}, 'x')"));
    try std.testing.expect(!try python.eval(bool, "example_abi3.dict_has_key({'x': 1}, 'z')"));
}

test "abi3 - fn dict_size - count items" {
    const python = try initTestPython();

    const len1 = try python.eval(i64, "example_abi3.dict_size({'a': 1, 'b': 2, 'c': 3})");
    try std.testing.expectEqual(@as(i64, 3), len1);

    const len2 = try python.eval(i64, "example_abi3.dict_size({})");
    try std.testing.expectEqual(@as(i64, 0), len2);
}

test "abi3 - fn dict_sum_values - iterate and sum" {
    const python = try initTestPython();

    const sum = try python.eval(i64, "example_abi3.dict_sum_values({'a': 10, 'b': 20, 'c': 30})");
    try std.testing.expectEqual(@as(i64, 60), sum);
}

test "abi3 - fn dict_keys_length - count via iteration" {
    const python = try initTestPython();

    const count = try python.eval(i64, "example_abi3.dict_keys_length({'a': 1, 'b': 2, 'c': 3})");
    try std.testing.expectEqual(@as(i64, 3), count);
}

// ============================================================================
// SET FUNCTIONS (SetView)
// ============================================================================

test "abi3 - fn set_contains - membership test" {
    const python = try initTestPython();

    try std.testing.expect(try python.eval(bool, "example_abi3.set_contains({1, 2, 3}, 2)"));
    try std.testing.expect(!try python.eval(bool, "example_abi3.set_contains({1, 2, 3}, 5)"));
}

test "abi3 - fn set_size - count items" {
    const python = try initTestPython();

    try std.testing.expectEqual(@as(i64, 4), try python.eval(i64, "example_abi3.set_size({1, 2, 3, 4})"));
    try std.testing.expectEqual(@as(i64, 0), try python.eval(i64, "example_abi3.set_size(set())"));
}

test "abi3 - fn set_sum - iterate and sum" {
    const python = try initTestPython();

    const sum = try python.eval(i64, "example_abi3.set_sum({1, 2, 3, 4, 5})");
    try std.testing.expectEqual(@as(i64, 15), sum);
}

// ============================================================================
// ITERATOR FUNCTIONS (IteratorView)
// ============================================================================

test "abi3 - fn iter_sum - sum from any iterable" {
    const python = try initTestPython();

    // List
    try std.testing.expectEqual(@as(i64, 15), try python.eval(i64, "example_abi3.iter_sum([1, 2, 3, 4, 5])"));
    // Generator
    try std.testing.expectEqual(@as(i64, 15), try python.eval(i64, "example_abi3.iter_sum(x for x in range(1, 6))"));
    // Set
    try std.testing.expectEqual(@as(i64, 15), try python.eval(i64, "example_abi3.iter_sum({1, 2, 3, 4, 5})"));
}

test "abi3 - fn iter_count - count items" {
    const python = try initTestPython();

    try std.testing.expectEqual(@as(i64, 5), try python.eval(i64, "example_abi3.iter_count([1, 2, 3, 4, 5])"));
    try std.testing.expectEqual(@as(i64, 10), try python.eval(i64, "example_abi3.iter_count(range(10))"));
}

test "abi3 - fn iter_max - find maximum" {
    const python = try initTestPython();

    try std.testing.expectEqual(@as(i64, 9), try python.eval(i64, "example_abi3.iter_max([3, 1, 4, 1, 5, 9, 2, 6])"));

    // Empty iterable returns None
    const empty = try python.eval(bool, "example_abi3.iter_max([]) is None");
    try std.testing.expect(empty);
}

// ============================================================================
// BYTES FUNCTIONS
// ============================================================================

test "abi3 - fn bytes_length - get length" {
    const python = try initTestPython();

    try std.testing.expectEqual(@as(i64, 5), try python.eval(i64, "example_abi3.bytes_length(b'hello')"));
    try std.testing.expectEqual(@as(i64, 0), try python.eval(i64, "example_abi3.bytes_length(b'')"));
}

test "abi3 - fn bytes_sum - sum byte values" {
    const python = try initTestPython();

    const sum = try python.eval(i64, "example_abi3.bytes_sum(b'\\x01\\x02\\x03')");
    try std.testing.expectEqual(@as(i64, 6), sum);
}

test "abi3 - fn make_bytes - create bytes" {
    const python = try initTestPython();

    try python.exec("b = example_abi3.make_bytes()");
    try std.testing.expect(try python.eval(bool, "isinstance(b, bytes)"));
    try std.testing.expect(try python.eval(bool, "b == b'Hello'"));
}

test "abi3 - fn bytes_starts_with - check prefix" {
    const python = try initTestPython();

    try std.testing.expect(try python.eval(bool, "example_abi3.bytes_starts_with(b'hello', 104)")); // 'h' = 104
    try std.testing.expect(!try python.eval(bool, "example_abi3.bytes_starts_with(b'hello', 72)")); // 'H' = 72
}

// ============================================================================
// PATH FUNCTIONS
// ============================================================================

test "abi3 - fn path_str - get path string" {
    try skipPythonVersion(3, 9);
    const python = try initTestPython();

    try python.exec("from pathlib import Path");
    const result = try python.eval(bool, "example_abi3.path_str(Path('/test/path')) == '/test/path'");
    try std.testing.expect(result);
}

test "abi3 - fn path_len - get path length" {
    try skipPythonVersion(3, 9);
    const python = try initTestPython();

    try python.exec("from pathlib import Path");
    const len = try python.eval(i64, "example_abi3.path_len(Path('/home/user'))");
    try std.testing.expectEqual(@as(i64, 10), len);
}

test "abi3 - fn make_path - create path" {
    try skipPythonVersion(3, 9);
    const python = try initTestPython();

    try python.exec("from pathlib import Path");
    try python.exec("p = example_abi3.make_path()");
    try std.testing.expect(try python.eval(bool, "isinstance(p, Path)"));
    try std.testing.expect(try python.eval(bool, "str(p) == '/home/user/documents'"));
}

test "abi3 - fn path_starts_with - check prefix" {
    try skipPythonVersion(3, 9);
    const python = try initTestPython();

    try python.exec("from pathlib import Path");
    try std.testing.expect(try python.eval(bool, "example_abi3.path_starts_with(Path('/home/user'), '/home')"));
    try std.testing.expect(!try python.eval(bool, "example_abi3.path_starts_with(Path('/home/user'), '/etc')"));
}

// ============================================================================
// DECIMAL FUNCTIONS
// ============================================================================

test "abi3 - fn make_decimal - create decimal" {
    const python = try initTestPython();

    try python.exec("from decimal import Decimal");
    try python.exec("d = example_abi3.make_decimal()");
    try std.testing.expect(try python.eval(bool, "isinstance(d, Decimal)"));
    try std.testing.expect(try python.eval(bool, "d == Decimal('123.456789')"));
}

test "abi3 - fn decimal_str - get string representation" {
    const python = try initTestPython();

    try python.exec("from decimal import Decimal");
    const result = try python.eval(bool, "example_abi3.decimal_str(Decimal('999.123')) == '999.123'");
    try std.testing.expect(result);
}

// ============================================================================
// BIGINT (i128/u128) FUNCTIONS
// ============================================================================

test "abi3 - fn bigint_max - i128 max value" {
    const python = try initTestPython();

    const max = try python.eval(i128, "example_abi3.bigint_max()");
    try std.testing.expectEqual(@as(i128, 170141183460469231731687303715884105727), max);
}

test "abi3 - fn bigint_echo - i128 roundtrip" {
    const python = try initTestPython();

    try python.exec("big = 123456789012345678901234567890");
    const result = try python.eval(i128, "example_abi3.bigint_echo(big)");
    try std.testing.expectEqual(@as(i128, 123456789012345678901234567890), result);
}

test "abi3 - fn biguint_echo - u128 roundtrip" {
    const python = try initTestPython();

    try python.exec("big = 999999999999999999999999999999");
    const result = try python.eval(u128, "example_abi3.biguint_echo(big)");
    try std.testing.expectEqual(@as(u128, 999999999999999999999999999999), result);
}

test "abi3 - fn bigint_add - i128 addition" {
    const python = try initTestPython();

    const result = try python.eval(i128, "example_abi3.bigint_add(100000000000000000000, 200000000000000000000)");
    try std.testing.expectEqual(@as(i128, 300000000000000000000), result);
}

// ============================================================================
// OPTIONAL/ERROR HANDLING FUNCTIONS
// ============================================================================

test "abi3 - fn safe_divide - returns None on zero" {
    const python = try initTestPython();

    const result = try python.eval(i64, "example_abi3.safe_divide(10, 2)");
    try std.testing.expectEqual(@as(i64, 5), result);

    const is_none = try python.eval(bool, "example_abi3.safe_divide(10, 0) is None");
    try std.testing.expect(is_none);
}

test "abi3 - fn sqrt_positive - returns None on negative" {
    const python = try initTestPython();

    const result = try python.eval(f64, "example_abi3.sqrt_positive(16.0)");
    try std.testing.expectApproxEqAbs(@as(f64, 4.0), result, 0.0001);

    const is_none = try python.eval(bool, "example_abi3.sqrt_positive(-1.0) is None");
    try std.testing.expect(is_none);
}

// ============================================================================
// TUPLE RETURNS
// ============================================================================

test "abi3 - fn minmax - return tuple" {
    const python = try initTestPython();

    try python.exec("result = example_abi3.minmax(5, 3)");
    try std.testing.expectEqual(@as(i64, 3), try python.eval(i64, "result[0]"));
    try std.testing.expectEqual(@as(i64, 5), try python.eval(i64, "result[1]"));

    try python.exec("result2 = example_abi3.minmax(1, 10)");
    try std.testing.expectEqual(@as(i64, 1), try python.eval(i64, "result2[0]"));
    try std.testing.expectEqual(@as(i64, 10), try python.eval(i64, "result2[1]"));
}

test "abi3 - fn divmod - return tuple or None" {
    const python = try initTestPython();

    try python.exec("result = example_abi3.divmod(17, 5)");
    try std.testing.expectEqual(@as(i64, 3), try python.eval(i64, "result[0]"));
    try std.testing.expectEqual(@as(i64, 2), try python.eval(i64, "result[1]"));

    const is_none = try python.eval(bool, "example_abi3.divmod(10, 0) is None");
    try std.testing.expect(is_none);
}

// ============================================================================
// BOOL FUNCTIONS
// ============================================================================

test "abi3 - fn is_even - check even" {
    const python = try initTestPython();

    try std.testing.expect(try python.eval(bool, "example_abi3.is_even(4)"));
    try std.testing.expect(try python.eval(bool, "example_abi3.is_even(0)"));
    try std.testing.expect(!try python.eval(bool, "example_abi3.is_even(3)"));
}

test "abi3 - fn is_positive - check positive" {
    const python = try initTestPython();

    try std.testing.expect(try python.eval(bool, "example_abi3.is_positive(1.0)"));
    try std.testing.expect(!try python.eval(bool, "example_abi3.is_positive(-1.0)"));
    try std.testing.expect(!try python.eval(bool, "example_abi3.is_positive(0.0)"));
}

test "abi3 - fn all_positive - check all positive" {
    const python = try initTestPython();

    try std.testing.expect(try python.eval(bool, "example_abi3.all_positive([1, 2, 3])"));
    try std.testing.expect(!try python.eval(bool, "example_abi3.all_positive([1, -2, 3])"));
    try std.testing.expect(!try python.eval(bool, "example_abi3.all_positive([0, 1, 2])"));
}

// ============================================================================
// DATETIME FUNCTIONS
// ============================================================================

test "abi3 - fn create_date - create date" {
    const python = try initTestPython();

    try python.exec("from datetime import date");
    try python.exec("d = example_abi3.create_date(2024, 7, 4)");
    try std.testing.expect(try python.eval(bool, "isinstance(d, date)"));
    try std.testing.expectEqual(@as(i64, 2024), try python.eval(i64, "d.year"));
    try std.testing.expectEqual(@as(i64, 7), try python.eval(i64, "d.month"));
    try std.testing.expectEqual(@as(i64, 4), try python.eval(i64, "d.day"));
}

test "abi3 - fn create_datetime - create datetime" {
    const python = try initTestPython();

    try python.exec("from datetime import datetime");
    try python.exec("dt = example_abi3.create_datetime(2024, 12, 25, 10, 30, 45)");
    try std.testing.expect(try python.eval(bool, "isinstance(dt, datetime)"));
    try std.testing.expectEqual(@as(i64, 2024), try python.eval(i64, "dt.year"));
    try std.testing.expectEqual(@as(i64, 10), try python.eval(i64, "dt.hour"));
}

test "abi3 - fn create_time - create time" {
    const python = try initTestPython();

    try python.exec("from datetime import time");
    try python.exec("t = example_abi3.create_time(14, 30, 45)");
    try std.testing.expect(try python.eval(bool, "isinstance(t, time)"));
    try std.testing.expectEqual(@as(i64, 14), try python.eval(i64, "t.hour"));
    try std.testing.expectEqual(@as(i64, 30), try python.eval(i64, "t.minute"));
}

test "abi3 - fn create_timedelta - create timedelta" {
    const python = try initTestPython();

    try python.exec("from datetime import timedelta");
    try python.exec("td = example_abi3.create_timedelta(5, 3600, 0)");
    try std.testing.expect(try python.eval(bool, "isinstance(td, timedelta)"));
    try std.testing.expectEqual(@as(i64, 5), try python.eval(i64, "td.days"));
}

test "abi3 - fn get_date_year/month/day - extract date components" {
    const python = try initTestPython();

    try python.exec("from datetime import date");
    try python.exec("d = date(2023, 12, 25)");
    try std.testing.expectEqual(@as(i64, 2023), try python.eval(i64, "example_abi3.get_date_year(d)"));
    try std.testing.expectEqual(@as(i64, 12), try python.eval(i64, "example_abi3.get_date_month(d)"));
    try std.testing.expectEqual(@as(i64, 25), try python.eval(i64, "example_abi3.get_date_day(d)"));
}

test "abi3 - fn get_datetime_hour - extract datetime hour" {
    const python = try initTestPython();

    try python.exec("from datetime import datetime");
    try python.exec("dt = datetime(2023, 6, 15, 14, 30, 0)");
    try std.testing.expectEqual(@as(i64, 14), try python.eval(i64, "example_abi3.get_datetime_hour(dt)"));
}

test "abi3 - fn get_time_components - extract time components" {
    const python = try initTestPython();

    try python.exec("from datetime import time");
    try python.exec("t = time(10, 20, 30)");
    try python.exec("components = example_abi3.get_time_components(t)");
    try std.testing.expectEqual(@as(i64, 10), try python.eval(i64, "components[0]"));
    try std.testing.expectEqual(@as(i64, 20), try python.eval(i64, "components[1]"));
    try std.testing.expectEqual(@as(i64, 30), try python.eval(i64, "components[2]"));
}

test "abi3 - fn get_timedelta_days - extract timedelta days" {
    const python = try initTestPython();

    try python.exec("from datetime import timedelta");
    try python.exec("td = timedelta(days=7)");
    try std.testing.expectEqual(@as(i64, 7), try python.eval(i64, "example_abi3.get_timedelta_days(td)"));
}

// ============================================================================
// BUFFERVIEW FUNCTIONS (read-only buffer consumer)
// ============================================================================

test "abi3 - fn buffer_sum_f64 - sum f64 buffer" {
    const python = try initTestPython();
    try requireNumpy(python);

    try python.exec("import numpy as np");
    try python.exec("arr = np.array([1.0, 2.0, 3.0, 4.0, 5.0], dtype=np.float64)");
    const sum = try python.eval(f64, "example_abi3.buffer_sum_f64(arr)");
    try std.testing.expectApproxEqAbs(@as(f64, 15.0), sum, 0.0001);
}

test "abi3 - fn buffer_sum_i32 - sum i32 buffer" {
    const python = try initTestPython();
    try requireNumpy(python);

    try python.exec("import numpy as np");
    try python.exec("arr = np.array([1, 2, 3, 4, 5], dtype=np.int32)");
    const sum = try python.eval(i64, "example_abi3.buffer_sum_i32(arr)");
    try std.testing.expectEqual(@as(i64, 15), sum);
}

test "abi3 - fn buffer_len - get buffer length" {
    const python = try initTestPython();
    try requireNumpy(python);

    try python.exec("import numpy as np");
    try python.exec("arr = np.array([1.0, 2.0, 3.0], dtype=np.float64)");
    const len = try python.eval(i64, "example_abi3.buffer_len(arr)");
    try std.testing.expectEqual(@as(i64, 3), len);
}

test "abi3 - fn buffer_ndim - get buffer dimensions" {
    const python = try initTestPython();
    try requireNumpy(python);

    try python.exec("import numpy as np");
    try python.exec("arr = np.array([1.0, 2.0, 3.0], dtype=np.float64)");
    const ndim = try python.eval(i64, "example_abi3.buffer_ndim(arr)");
    try std.testing.expectEqual(@as(i64, 1), ndim);
}

test "abi3 - fn buffer_get - get element at index" {
    const python = try initTestPython();
    try requireNumpy(python);

    try python.exec("import numpy as np");
    try python.exec("arr = np.array([10.0, 20.0, 30.0], dtype=np.float64)");
    try std.testing.expectApproxEqAbs(@as(f64, 20.0), try python.eval(f64, "example_abi3.buffer_get(arr, 1)"), 0.0001);

    // Out of bounds returns None
    const is_none = try python.eval(bool, "example_abi3.buffer_get(arr, 10) is None");
    try std.testing.expect(is_none);
}

// ============================================================================
// ITERATOR PRODUCER FUNCTIONS
// ============================================================================

test "abi3 - fn get_fibonacci - eager iterator" {
    const python = try initTestPython();

    try python.exec("fibs = list(example_abi3.get_fibonacci())");
    try std.testing.expectEqual(@as(i64, 10), try python.eval(i64, "len(fibs)"));
    try std.testing.expectEqual(@as(i64, 1), try python.eval(i64, "fibs[0]"));
    try std.testing.expectEqual(@as(i64, 55), try python.eval(i64, "fibs[9]"));
}

test "abi3 - fn get_squares - eager iterator" {
    const python = try initTestPython();

    try python.exec("squares = list(example_abi3.get_squares())");
    try std.testing.expect(try python.eval(bool, "squares == [1, 4, 9, 16, 25]"));
}

// ============================================================================
// LAZY ITERATOR (generator) FUNCTIONS
// ============================================================================

test "abi3 - fn lazy_range - lazy range iterator" {
    const python = try initTestPython();

    try python.exec("result = list(example_abi3.lazy_range(0, 5, 1))");
    try std.testing.expect(try python.eval(bool, "result == [0, 1, 2, 3, 4]"));

    try python.exec("result2 = list(example_abi3.lazy_range(10, 0, -2))");
    try std.testing.expect(try python.eval(bool, "result2 == [10, 8, 6, 4, 2]"));
}

test "abi3 - fn lazy_fibonacci - lazy fibonacci generator" {
    const python = try initTestPython();

    try python.exec("fibs = list(example_abi3.lazy_fibonacci(8))");
    try std.testing.expect(try python.eval(bool, "fibs == [0, 1, 1, 2, 3, 5, 8, 13]"));
}

// ============================================================================
// KEYWORD ARGUMENT FUNCTIONS
// ============================================================================

test "abi3 - fn greet_person - keyword arguments" {
    const python = try initTestPython();

    try python.exec("result = example_abi3.greet_person('Alice')");
    try std.testing.expect(try python.eval(bool, "result[0] == 'Hello'"));
    try std.testing.expect(try python.eval(bool, "result[1] == 'Alice'"));
    try std.testing.expectEqual(@as(i64, 1), try python.eval(i64, "result[2]"));

    try python.exec("result2 = example_abi3.greet_person('Bob', 'Hi', 3)");
    try std.testing.expect(try python.eval(bool, "result2[0] == 'Hi'"));
    try std.testing.expectEqual(@as(i64, 3), try python.eval(i64, "result2[2]"));
}

test "abi3 - fn power_with_default - keyword with default" {
    const python = try initTestPython();

    // Default exponent is 2
    const r1 = try python.eval(f64, "example_abi3.power_with_default(5.0)");
    try std.testing.expectApproxEqAbs(@as(f64, 25.0), r1, 0.0001);

    // Custom exponent
    const r2 = try python.eval(f64, "example_abi3.power_with_default(2.0, 10.0)");
    try std.testing.expectApproxEqAbs(@as(f64, 1024.0), r2, 0.0001);
}

test "abi3 - fn greet_named - named keyword arguments" {
    const python = try initTestPython();

    try python.exec("result = example_abi3.greet_named(name='Alice')");
    try std.testing.expect(try python.eval(bool, "result[0] == 'Hello'"));
    try std.testing.expect(try python.eval(bool, "result[1] == 'Alice'"));

    try python.exec("result2 = example_abi3.greet_named(name='Bob', greeting='Hi', times=3, excited=True)");
    try std.testing.expect(try python.eval(bool, "result2[0] == 'Hi'"));
    try std.testing.expectEqual(@as(i64, 3), try python.eval(i64, "result2[2]"));
    try std.testing.expect(try python.eval(bool, "result2[3] == True"));
}

test "abi3 - fn calculate_named - named kwargs with operations" {
    const python = try initTestPython();

    const add = try python.eval(f64, "example_abi3.calculate_named(x=10.0, y=5.0)");
    try std.testing.expectApproxEqAbs(@as(f64, 15.0), add, 0.0001);

    const sub = try python.eval(f64, "example_abi3.calculate_named(x=10.0, y=3.0, operation='sub')");
    try std.testing.expectApproxEqAbs(@as(f64, 7.0), sub, 0.0001);

    const mul = try python.eval(f64, "example_abi3.calculate_named(x=6.0, y=7.0, operation='mul')");
    try std.testing.expectApproxEqAbs(@as(f64, 42.0), mul, 0.0001);
}

// ============================================================================
// CLASS: Counter
// ============================================================================

test "abi3 - Counter - creation and basic methods" {
    const python = try initTestPython();

    try python.exec("c = example_abi3.Counter(10)");
    try std.testing.expectEqual(@as(i64, 10), try python.eval(i64, "c.get()"));

    try python.exec("c.increment()");
    try std.testing.expectEqual(@as(i64, 11), try python.eval(i64, "c.get()"));

    try python.exec("c.decrement()");
    try std.testing.expectEqual(@as(i64, 10), try python.eval(i64, "c.get()"));

    try python.exec("c.add(5)");
    try std.testing.expectEqual(@as(i64, 15), try python.eval(i64, "c.get()"));

    try python.exec("c.set(100)");
    try std.testing.expectEqual(@as(i64, 100), try python.eval(i64, "c.get()"));

    try python.exec("c.reset()");
    try std.testing.expectEqual(@as(i64, 0), try python.eval(i64, "c.get()"));
}

// ============================================================================
// CLASS: Point
// ============================================================================

test "abi3 - Point - creation and properties" {
    const python = try initTestPython();

    try python.exec("p = example_abi3.Point(3.0, 4.0)");
    try std.testing.expectApproxEqAbs(@as(f64, 3.0), try python.eval(f64, "p.x"), 0.0001);
    try std.testing.expectApproxEqAbs(@as(f64, 4.0), try python.eval(f64, "p.y"), 0.0001);
}

test "abi3 - Point - magnitude method" {
    const python = try initTestPython();

    try python.exec("p = example_abi3.Point(3.0, 4.0)");
    try std.testing.expectApproxEqAbs(@as(f64, 5.0), try python.eval(f64, "p.magnitude()"), 0.0001);
}

test "abi3 - Point - computed property length" {
    const python = try initTestPython();

    try python.exec("p = example_abi3.Point(3.0, 4.0)");
    try std.testing.expectApproxEqAbs(@as(f64, 5.0), try python.eval(f64, "p.length"), 0.0001);

    try python.exec("p.length = 10.0");
    try std.testing.expectApproxEqAbs(@as(f64, 10.0), try python.eval(f64, "p.length"), 0.0001);
}

test "abi3 - Point - scale and translate" {
    const python = try initTestPython();

    try python.exec("p = example_abi3.Point(2.0, 3.0)");
    try python.exec("p.scale(2.0)");
    try std.testing.expectApproxEqAbs(@as(f64, 4.0), try python.eval(f64, "p.x"), 0.0001);
    try std.testing.expectApproxEqAbs(@as(f64, 6.0), try python.eval(f64, "p.y"), 0.0001);

    try python.exec("p.translate(1.0, 1.0)");
    try std.testing.expectApproxEqAbs(@as(f64, 5.0), try python.eval(f64, "p.x"), 0.0001);
    try std.testing.expectApproxEqAbs(@as(f64, 7.0), try python.eval(f64, "p.y"), 0.0001);
}

test "abi3 - Point - dot product" {
    const python = try initTestPython();

    try python.exec("p = example_abi3.Point(2.0, 3.0)");
    const dot = try python.eval(f64, "p.dot(4.0, 5.0)");
    try std.testing.expectApproxEqAbs(@as(f64, 23.0), dot, 0.0001);
}

test "abi3 - Point - static method origin" {
    const python = try initTestPython();

    try python.exec("p = example_abi3.Point.origin()");
    try std.testing.expectApproxEqAbs(@as(f64, 0.0), try python.eval(f64, "p.x"), 0.0001);
    try std.testing.expectApproxEqAbs(@as(f64, 0.0), try python.eval(f64, "p.y"), 0.0001);
}

test "abi3 - Point - static method from_angle" {
    const python = try initTestPython();

    try python.exec("p = example_abi3.Point.from_angle(0)");
    try std.testing.expectApproxEqAbs(@as(f64, 1.0), try python.eval(f64, "p.x"), 0.0001);
    try std.testing.expectApproxEqAbs(@as(f64, 0.0), try python.eval(f64, "p.y"), 0.0001);
}

test "abi3 - Point - classmethod from_polar" {
    const python = try initTestPython();

    try python.exec("p = example_abi3.Point.from_polar(5.0, 0)");
    try std.testing.expectApproxEqAbs(@as(f64, 5.0), try python.eval(f64, "p.x"), 0.0001);
    try std.testing.expectApproxEqAbs(@as(f64, 0.0), try python.eval(f64, "p.y"), 0.0001);
}

test "abi3 - Point - __eq__" {
    const python = try initTestPython();

    try std.testing.expect(try python.eval(bool, "example_abi3.Point(1, 2) == example_abi3.Point(1, 2)"));
    try std.testing.expect(!try python.eval(bool, "example_abi3.Point(1, 2) == example_abi3.Point(3, 4)"));
}

test "abi3 - Point - __add__" {
    const python = try initTestPython();

    try python.exec("p = example_abi3.Point(1, 2) + example_abi3.Point(3, 4)");
    try std.testing.expectApproxEqAbs(@as(f64, 4.0), try python.eval(f64, "p.x"), 0.0001);
    try std.testing.expectApproxEqAbs(@as(f64, 6.0), try python.eval(f64, "p.y"), 0.0001);
}

test "abi3 - Point - __sub__" {
    const python = try initTestPython();

    try python.exec("p = example_abi3.Point(5, 7) - example_abi3.Point(2, 3)");
    try std.testing.expectApproxEqAbs(@as(f64, 3.0), try python.eval(f64, "p.x"), 0.0001);
    try std.testing.expectApproxEqAbs(@as(f64, 4.0), try python.eval(f64, "p.y"), 0.0001);
}

test "abi3 - Point - __neg__" {
    const python = try initTestPython();

    try python.exec("p = -example_abi3.Point(3, 4)");
    try std.testing.expectApproxEqAbs(@as(f64, -3.0), try python.eval(f64, "p.x"), 0.0001);
    try std.testing.expectApproxEqAbs(@as(f64, -4.0), try python.eval(f64, "p.y"), 0.0001);
}

test "abi3 - Point - docstrings" {
    const python = try initTestPython();

    try std.testing.expect(try python.eval(bool, "example_abi3.Point.__doc__ is not None"));
    try std.testing.expect(try python.eval(bool, "'2D point' in example_abi3.Point.__doc__"));
}

// ============================================================================
// CLASS: Number (arithmetic operations)
// ============================================================================

test "abi3 - Number - creation" {
    const python = try initTestPython();

    try python.exec("n = example_abi3.Number(42.5)");
    try std.testing.expectApproxEqAbs(@as(f64, 42.5), try python.eval(f64, "n.value"), 0.0001);
}

test "abi3 - Number - arithmetic operators" {
    const python = try initTestPython();

    // __add__
    try python.exec("n = example_abi3.Number(10) + example_abi3.Number(5)");
    try std.testing.expectApproxEqAbs(@as(f64, 15.0), try python.eval(f64, "n.value"), 0.0001);

    // __sub__
    try python.exec("n = example_abi3.Number(10) - example_abi3.Number(3)");
    try std.testing.expectApproxEqAbs(@as(f64, 7.0), try python.eval(f64, "n.value"), 0.0001);

    // __mul__
    try python.exec("n = example_abi3.Number(6) * example_abi3.Number(7)");
    try std.testing.expectApproxEqAbs(@as(f64, 42.0), try python.eval(f64, "n.value"), 0.0001);

    // __truediv__
    try python.exec("n = example_abi3.Number(10) / example_abi3.Number(4)");
    try std.testing.expectApproxEqAbs(@as(f64, 2.5), try python.eval(f64, "n.value"), 0.0001);

    // __floordiv__
    try python.exec("n = example_abi3.Number(10) // example_abi3.Number(3)");
    try std.testing.expectApproxEqAbs(@as(f64, 3.0), try python.eval(f64, "n.value"), 0.0001);

    // __mod__
    try python.exec("n = example_abi3.Number(10) % example_abi3.Number(3)");
    try std.testing.expectApproxEqAbs(@as(f64, 1.0), try python.eval(f64, "n.value"), 0.0001);

    // __neg__
    try python.exec("n = -example_abi3.Number(42)");
    try std.testing.expectApproxEqAbs(@as(f64, -42.0), try python.eval(f64, "n.value"), 0.0001);
}

test "abi3 - Number - __divmod__" {
    const python = try initTestPython();

    try python.exec("q, r = divmod(example_abi3.Number(17), example_abi3.Number(5))");
    try std.testing.expectApproxEqAbs(@as(f64, 3.0), try python.eval(f64, "q.value"), 0.0001);
    try std.testing.expectApproxEqAbs(@as(f64, 2.0), try python.eval(f64, "r.value"), 0.0001);
}

test "abi3 - Number - comparison operators" {
    const python = try initTestPython();

    try std.testing.expect(try python.eval(bool, "example_abi3.Number(5) == example_abi3.Number(5)"));
    try std.testing.expect(try python.eval(bool, "example_abi3.Number(3) < example_abi3.Number(5)"));
    try std.testing.expect(try python.eval(bool, "example_abi3.Number(3) <= example_abi3.Number(5)"));
    try std.testing.expect(try python.eval(bool, "example_abi3.Number(3) <= example_abi3.Number(3)"));
}

test "abi3 - Number - division by zero" {
    const python = try initTestPython();

    try python.exec(
        \\try:
        \\    example_abi3.Number(1) / example_abi3.Number(0)
        \\    div_zero = False
        \\except Exception:
        \\    div_zero = True
    );
    try std.testing.expect(try python.eval(bool, "div_zero"));
}

// ============================================================================
// CLASS: Version (comparison operators)
// ============================================================================

test "abi3 - Version - creation" {
    const python = try initTestPython();

    try python.exec("v = example_abi3.Version(1, 2, 3)");
    try std.testing.expectEqual(@as(i64, 1), try python.eval(i64, "v.major"));
    try std.testing.expectEqual(@as(i64, 2), try python.eval(i64, "v.minor"));
    try std.testing.expectEqual(@as(i64, 3), try python.eval(i64, "v.patch"));
}

test "abi3 - Version - comparison operators" {
    const python = try initTestPython();

    try std.testing.expect(try python.eval(bool, "example_abi3.Version(1, 2, 3) == example_abi3.Version(1, 2, 3)"));
    try std.testing.expect(try python.eval(bool, "example_abi3.Version(1, 0, 0) != example_abi3.Version(2, 0, 0)"));
    try std.testing.expect(try python.eval(bool, "example_abi3.Version(1, 0, 0) < example_abi3.Version(2, 0, 0)"));
    try std.testing.expect(try python.eval(bool, "example_abi3.Version(1, 0, 0) <= example_abi3.Version(1, 0, 0)"));
    try std.testing.expect(try python.eval(bool, "example_abi3.Version(2, 0, 0) > example_abi3.Version(1, 0, 0)"));
    try std.testing.expect(try python.eval(bool, "example_abi3.Version(1, 0, 0) >= example_abi3.Version(1, 0, 0)"));
}

test "abi3 - Version - is_major and is_compatible" {
    const python = try initTestPython();

    try std.testing.expect(try python.eval(bool, "example_abi3.Version(1, 0, 0).is_major()"));
    try std.testing.expect(!try python.eval(bool, "example_abi3.Version(1, 1, 0).is_major()"));
    try std.testing.expect(try python.eval(bool, "example_abi3.Version(1, 0, 0).is_compatible(example_abi3.Version(1, 5, 3))"));
    try std.testing.expect(!try python.eval(bool, "example_abi3.Version(1, 0, 0).is_compatible(example_abi3.Version(2, 0, 0))"));
}

// ============================================================================
// CLASS: Adder (callable)
// ============================================================================

test "abi3 - Adder - __call__" {
    const python = try initTestPython();

    try python.exec("adder = example_abi3.Adder(10)");
    try std.testing.expectEqual(@as(i64, 15), try python.eval(i64, "adder(5)"));
    try std.testing.expectEqual(@as(i64, 7), try python.eval(i64, "adder(-3)"));
}

test "abi3 - Adder - base property" {
    const python = try initTestPython();

    try python.exec("adder = example_abi3.Adder(42)");
    try std.testing.expectEqual(@as(i64, 42), try python.eval(i64, "adder.base"));
}

// ============================================================================
// CLASS: IntList (sequence protocol)
// ============================================================================

test "abi3 - IntList - creation and __len__" {
    const python = try initTestPython();

    try python.exec("lst = example_abi3.IntList(10)");
    try std.testing.expectEqual(@as(i64, 1), try python.eval(i64, "len(lst)"));
}

test "abi3 - IntList - __getitem__" {
    const python = try initTestPython();

    try python.exec("lst = example_abi3.IntList(42)");
    try std.testing.expectEqual(@as(i64, 42), try python.eval(i64, "lst[0]"));
    try std.testing.expectEqual(@as(i64, 42), try python.eval(i64, "lst[-1]"));
}

test "abi3 - IntList - append and sum" {
    const python = try initTestPython();

    try python.exec("lst = example_abi3.IntList(1)");
    try python.exec("lst.append(2)");
    try python.exec("lst.append(3)");
    try std.testing.expectEqual(@as(i64, 3), try python.eval(i64, "len(lst)"));
    try std.testing.expectEqual(@as(i64, 6), try python.eval(i64, "lst.sum()"));
}

test "abi3 - IntList - __iter__" {
    const python = try initTestPython();

    try python.exec("lst = example_abi3.IntList(1)");
    try python.exec("lst.append(2)");
    try python.exec("lst.append(3)");
    try python.exec("total = sum(lst)");
    try std.testing.expectEqual(@as(i64, 6), try python.eval(i64, "total"));
}

// ============================================================================
// CLASS: BitSet (bitwise operators)
// ============================================================================

test "abi3 - BitSet - creation" {
    const python = try initTestPython();

    try python.exec("b = example_abi3.BitSet(0b1010)");
    try std.testing.expectEqual(@as(u64, 0b1010), try python.eval(u64, "b.bits"));
}

test "abi3 - BitSet - __bool__" {
    const python = try initTestPython();

    try std.testing.expect(try python.eval(bool, "bool(example_abi3.BitSet(1))"));
    try std.testing.expect(!try python.eval(bool, "bool(example_abi3.BitSet(0))"));
}

test "abi3 - BitSet - bitwise operators" {
    const python = try initTestPython();

    // __and__
    try python.exec("b = example_abi3.BitSet(0b1100) & example_abi3.BitSet(0b1010)");
    try std.testing.expectEqual(@as(u64, 0b1000), try python.eval(u64, "b.bits"));

    // __or__
    try python.exec("b = example_abi3.BitSet(0b1100) | example_abi3.BitSet(0b1010)");
    try std.testing.expectEqual(@as(u64, 0b1110), try python.eval(u64, "b.bits"));

    // __xor__
    try python.exec("b = example_abi3.BitSet(0b1100) ^ example_abi3.BitSet(0b1010)");
    try std.testing.expectEqual(@as(u64, 0b0110), try python.eval(u64, "b.bits"));

    // __invert__
    try python.exec("b = ~example_abi3.BitSet(0)");
    try std.testing.expectEqual(~@as(u64, 0), try python.eval(u64, "b.bits"));

    // __lshift__
    try python.exec("b = example_abi3.BitSet(1) << example_abi3.BitSet(3)");
    try std.testing.expectEqual(@as(u64, 8), try python.eval(u64, "b.bits"));

    // __rshift__
    try python.exec("b = example_abi3.BitSet(8) >> example_abi3.BitSet(2)");
    try std.testing.expectEqual(@as(u64, 2), try python.eval(u64, "b.bits"));
}

test "abi3 - BitSet - count" {
    const python = try initTestPython();

    try std.testing.expectEqual(@as(i64, 4), try python.eval(i64, "example_abi3.BitSet(0b1111).count()"));
    try std.testing.expectEqual(@as(i64, 2), try python.eval(i64, "example_abi3.BitSet(0b1010).count()"));
}

test "abi3 - BitSet - in-place operators" {
    const python = try initTestPython();

    // __iadd__ (in-place OR)
    try python.exec("b = example_abi3.BitSet(0b0011)");
    try python.exec("b += example_abi3.BitSet(0b1100)");
    try std.testing.expectEqual(@as(u64, 0b1111), try python.eval(u64, "b.bits"));

    // __isub__ (in-place AND NOT)
    try python.exec("b2 = example_abi3.BitSet(0b1111)");
    try python.exec("b2 -= example_abi3.BitSet(0b0011)");
    try std.testing.expectEqual(@as(u64, 0b1100), try python.eval(u64, "b2.bits"));

    // __ilshift__
    try python.exec("b3 = example_abi3.BitSet(1)");
    try python.exec("b3 <<= example_abi3.BitSet(4)");
    try std.testing.expectEqual(@as(u64, 16), try python.eval(u64, "b3.bits"));

    // __irshift__
    try python.exec("b4 = example_abi3.BitSet(16)");
    try python.exec("b4 >>= example_abi3.BitSet(2)");
    try std.testing.expectEqual(@as(u64, 4), try python.eval(u64, "b4.bits"));
}

// ============================================================================
// CLASS: PowerNumber (power and coercion operators)
// ============================================================================

test "abi3 - PowerNumber - creation" {
    const python = try initTestPython();

    try python.exec("p = example_abi3.PowerNumber(5.0)");
    try std.testing.expectApproxEqAbs(@as(f64, 5.0), try python.eval(f64, "p.value"), 0.0001);
}

test "abi3 - PowerNumber - __pow__" {
    const python = try initTestPython();

    try python.exec("p = example_abi3.PowerNumber(2) ** example_abi3.PowerNumber(10)");
    try std.testing.expectApproxEqAbs(@as(f64, 1024.0), try python.eval(f64, "p.value"), 0.0001);
}

test "abi3 - PowerNumber - __pos__ and __abs__" {
    const python = try initTestPython();

    try python.exec("p = +example_abi3.PowerNumber(-5)");
    try std.testing.expectApproxEqAbs(@as(f64, -5.0), try python.eval(f64, "p.value"), 0.0001);

    try python.exec("p = abs(example_abi3.PowerNumber(-5))");
    try std.testing.expectApproxEqAbs(@as(f64, 5.0), try python.eval(f64, "p.value"), 0.0001);
}

test "abi3 - PowerNumber - __int__ and __float__" {
    const python = try initTestPython();

    try std.testing.expectEqual(@as(i64, 42), try python.eval(i64, "int(example_abi3.PowerNumber(42.7))"));
    try std.testing.expectApproxEqAbs(@as(f64, 42.5), try python.eval(f64, "float(example_abi3.PowerNumber(42.5))"), 0.0001);
}

test "abi3 - PowerNumber - __bool__" {
    const python = try initTestPython();

    try std.testing.expect(try python.eval(bool, "bool(example_abi3.PowerNumber(1))"));
    try std.testing.expect(!try python.eval(bool, "bool(example_abi3.PowerNumber(0))"));
}

test "abi3 - PowerNumber - __index__" {
    const python = try initTestPython();

    try python.exec("lst = [0, 1, 2, 3, 4, 5]");
    try std.testing.expectEqual(@as(i64, 3), try python.eval(i64, "lst[example_abi3.PowerNumber(3)]"));
}

test "abi3 - PowerNumber - __complex__" {
    const python = try initTestPython();

    try python.exec("c = complex(example_abi3.PowerNumber(5))");
    try std.testing.expect(try python.eval(bool, "c == (5+0j)"));
}

// ============================================================================
// CLASS: Timer (context manager)
// ============================================================================

test "abi3 - Timer - creation" {
    const python = try initTestPython();

    try python.exec("t = example_abi3.Timer('test')");
    try std.testing.expect(try python.eval(bool, "'test' in t.name"));
}

test "abi3 - Timer - context manager protocol" {
    const python = try initTestPython();

    try python.exec(
        \\with example_abi3.Timer("test") as t:
        \\    t.tick()
        \\    t.tick()
        \\    t.tick()
        \\count = t.count
        \\was_active = t.is_active()
    );
    try std.testing.expectEqual(@as(i64, 3), try python.eval(i64, "count"));
    try std.testing.expect(!try python.eval(bool, "was_active"));
}

test "abi3 - Timer - is_active tracking" {
    const python = try initTestPython();

    try python.exec("t = example_abi3.Timer('test')");
    try std.testing.expect(!try python.eval(bool, "t.is_active()"));

    try python.exec("t.__enter__()");
    try std.testing.expect(try python.eval(bool, "t.is_active()"));

    try python.exec("t.__exit__()");
    try std.testing.expect(!try python.eval(bool, "t.is_active()"));
}

// ============================================================================
// CLASS: Multiplier (callable with multiple args)
// ============================================================================

test "abi3 - Multiplier - __call__" {
    const python = try initTestPython();

    try python.exec("mult = example_abi3.Multiplier(2.0)");
    // mult(a, b) = factor * (a + b) = 2 * (3 + 4) = 14
    try std.testing.expectApproxEqAbs(@as(f64, 14.0), try python.eval(f64, "mult(3.0, 4.0)"), 0.0001);
}

// ============================================================================
// CLASS: FrozenPoint (immutable/hashable)
// ============================================================================

test "abi3 - FrozenPoint - creation" {
    const python = try initTestPython();

    try python.exec("fp = example_abi3.FrozenPoint(3.0, 4.0)");
    try std.testing.expectApproxEqAbs(@as(f64, 3.0), try python.eval(f64, "fp.x"), 0.0001);
    try std.testing.expectApproxEqAbs(@as(f64, 4.0), try python.eval(f64, "fp.y"), 0.0001);
}

test "abi3 - FrozenPoint - immutability" {
    const python = try initTestPython();

    try python.exec("fp = example_abi3.FrozenPoint(1.0, 2.0)");
    try python.exec(
        \\try:
        \\    fp.x = 5.0
        \\    immutable = False
        \\except AttributeError:
        \\    immutable = True
    );
    try std.testing.expect(try python.eval(bool, "immutable"));
}

test "abi3 - FrozenPoint - __hash__" {
    const python = try initTestPython();

    try python.exec("fp = example_abi3.FrozenPoint(3.0, 4.0)");
    try python.exec("h = hash(fp)");
    try std.testing.expect(try python.eval(bool, "isinstance(h, int)"));

    // Can be used in sets/dicts
    try python.exec("s = {fp}");
    try std.testing.expectEqual(@as(i64, 1), try python.eval(i64, "len(s)"));
}

test "abi3 - FrozenPoint - __eq__" {
    const python = try initTestPython();

    try std.testing.expect(try python.eval(bool, "example_abi3.FrozenPoint(1, 2) == example_abi3.FrozenPoint(1, 2)"));
    try std.testing.expect(!try python.eval(bool, "example_abi3.FrozenPoint(1, 2) == example_abi3.FrozenPoint(3, 4)"));
}

test "abi3 - FrozenPoint - magnitude and scale" {
    const python = try initTestPython();

    try python.exec("fp = example_abi3.FrozenPoint(3.0, 4.0)");
    try std.testing.expectApproxEqAbs(@as(f64, 5.0), try python.eval(f64, "fp.magnitude()"), 0.0001);

    // scale returns a new FrozenPoint
    try python.exec("fp2 = fp.scale(2.0)");
    try std.testing.expectApproxEqAbs(@as(f64, 6.0), try python.eval(f64, "fp2.x"), 0.0001);
    try std.testing.expectApproxEqAbs(@as(f64, 8.0), try python.eval(f64, "fp2.y"), 0.0001);
}

test "abi3 - FrozenPoint - static origin" {
    const python = try initTestPython();

    try python.exec("fp = example_abi3.FrozenPoint.origin()");
    try std.testing.expectApproxEqAbs(@as(f64, 0.0), try python.eval(f64, "fp.x"), 0.0001);
    try std.testing.expectApproxEqAbs(@as(f64, 0.0), try python.eval(f64, "fp.y"), 0.0001);
}

// ============================================================================
// CLASS: Circle (class attributes)
// ============================================================================

test "abi3 - Circle - class attributes" {
    const python = try initTestPython();

    try std.testing.expect(try python.eval(bool, "example_abi3.Circle.PI > 3.14"));
    try std.testing.expectApproxEqAbs(@as(f64, 1.0), try python.eval(f64, "example_abi3.Circle.UNIT_RADIUS"), 0.0001);
    try std.testing.expect(try python.eval(bool, "example_abi3.Circle.DEFAULT_COLOR == 'red'"));
    try std.testing.expectEqual(@as(i64, 1000), try python.eval(i64, "example_abi3.Circle.MAX_RADIUS"));
}

test "abi3 - Circle - area and circumference" {
    const python = try initTestPython();

    try python.exec("c = example_abi3.Circle(5.0)");
    try std.testing.expect(try python.eval(bool, "c.area() > 78"));
    try std.testing.expect(try python.eval(bool, "c.circumference() > 31"));
}

test "abi3 - Circle - unit static method" {
    const python = try initTestPython();

    try python.exec("c = example_abi3.Circle.unit()");
    try std.testing.expectApproxEqAbs(@as(f64, 1.0), try python.eval(f64, "c.radius"), 0.0001);
}

// ============================================================================
// CLASS: Temperature (pyoz.property() API)
// ============================================================================

test "abi3 - Temperature - celsius property" {
    const python = try initTestPython();

    try python.exec("t = example_abi3.Temperature(25.0)");
    try std.testing.expectApproxEqAbs(@as(f64, 25.0), try python.eval(f64, "t.celsius"), 0.0001);

    try python.exec("t.celsius = 30.0");
    try std.testing.expectApproxEqAbs(@as(f64, 30.0), try python.eval(f64, "t.celsius"), 0.0001);

    // Test clamping to absolute zero
    try python.exec("t.celsius = -300.0");
    try std.testing.expectApproxEqAbs(@as(f64, -273.15), try python.eval(f64, "t.celsius"), 0.0001);
}

test "abi3 - Temperature - fahrenheit property" {
    const python = try initTestPython();

    try python.exec("t = example_abi3.Temperature(0.0)");
    try std.testing.expectApproxEqAbs(@as(f64, 32.0), try python.eval(f64, "t.fahrenheit"), 0.0001);

    try python.exec("t.fahrenheit = 212.0");
    try std.testing.expectApproxEqAbs(@as(f64, 100.0), try python.eval(f64, "t.celsius"), 0.0001);
}

test "abi3 - Temperature - kelvin property (read-only)" {
    const python = try initTestPython();

    try python.exec("t = example_abi3.Temperature(0.0)");
    try std.testing.expectApproxEqAbs(@as(f64, 273.15), try python.eval(f64, "t.kelvin"), 0.0001);
}

test "abi3 - Temperature - is_freezing and is_boiling" {
    const python = try initTestPython();

    try python.exec("t = example_abi3.Temperature(-10.0)");
    try std.testing.expect(try python.eval(bool, "t.is_freezing()"));
    try std.testing.expect(!try python.eval(bool, "t.is_boiling()"));

    try python.exec("t.celsius = 100.0");
    try std.testing.expect(!try python.eval(bool, "t.is_freezing()"));
    try std.testing.expect(try python.eval(bool, "t.is_boiling()"));
}

// ============================================================================
// CLASS: TypedAttribute (descriptor protocol)
// ============================================================================

test "abi3 - TypedAttribute - bounds clamping" {
    const python = try initTestPython();

    try python.exec("attr = example_abi3.TypedAttribute(0.0, 100.0)");

    // Get initial value (should be min) - use a dummy object for the descriptor call
    try python.exec("class Dummy: pass");
    try python.exec("obj = Dummy()");
    try std.testing.expectApproxEqAbs(@as(f64, 0.0), try python.eval(f64, "attr.__get__(obj, type(obj))"), 0.0001);

    // Set within bounds
    try python.exec("attr.__set__(obj, 50.0)");
    try std.testing.expectApproxEqAbs(@as(f64, 50.0), try python.eval(f64, "attr.__get__(obj, type(obj))"), 0.0001);

    // Set above max - should clamp
    try python.exec("attr.__set__(obj, 150.0)");
    try std.testing.expectApproxEqAbs(@as(f64, 100.0), try python.eval(f64, "attr.__get__(obj, type(obj))"), 0.0001);

    // Set below min - should clamp
    try python.exec("attr.__set__(obj, -50.0)");
    try std.testing.expectApproxEqAbs(@as(f64, 0.0), try python.eval(f64, "attr.__get__(obj, type(obj))"), 0.0001);
}

test "abi3 - TypedAttribute - __delete__ resets to min" {
    const python = try initTestPython();

    try python.exec("attr = example_abi3.TypedAttribute(10.0, 100.0)");
    try python.exec("class Dummy: pass");
    try python.exec("obj = Dummy()");
    try python.exec("attr.__set__(obj, 75.0)");
    try std.testing.expectApproxEqAbs(@as(f64, 75.0), try python.eval(f64, "attr.__get__(obj, type(obj))"), 0.0001);

    try python.exec("attr.__delete__(obj)");
    try std.testing.expectApproxEqAbs(@as(f64, 10.0), try python.eval(f64, "attr.__get__(obj, type(obj))"), 0.0001);
}

test "abi3 - TypedAttribute - get_bounds" {
    const python = try initTestPython();

    try python.exec("attr = example_abi3.TypedAttribute(5.0, 95.0)");
    try python.exec("bounds = attr.bounds");
    try std.testing.expectApproxEqAbs(@as(f64, 5.0), try python.eval(f64, "bounds[0]"), 0.0001);
    try std.testing.expectApproxEqAbs(@as(f64, 95.0), try python.eval(f64, "bounds[1]"), 0.0001);
}

// ============================================================================
// CLASS: ReversibleList (__reversed__)
// ============================================================================

test "abi3 - ReversibleList - creation" {
    const python = try initTestPython();

    try python.exec("rl = example_abi3.ReversibleList(1, 2, 3)");
    try std.testing.expectEqual(@as(i64, 3), try python.eval(i64, "len(rl)"));
}

test "abi3 - ReversibleList - forward iteration" {
    const python = try initTestPython();

    try python.exec("rl = example_abi3.ReversibleList(1, 2, 3)");
    try python.exec("fwd = list(rl)");
    try std.testing.expect(try python.eval(bool, "fwd == [1, 2, 3]"));
}

test "abi3 - ReversibleList - __reversed__" {
    const python = try initTestPython();

    try python.exec("rl = example_abi3.ReversibleList(1, 2, 3)");
    try python.exec("rev = list(reversed(rl))");
    try std.testing.expect(try python.eval(bool, "rev == [3, 2, 1]"));
}

test "abi3 - ReversibleList - __getitem__" {
    const python = try initTestPython();

    try python.exec("rl = example_abi3.ReversibleList(10, 20, 30)");
    try std.testing.expectEqual(@as(i64, 10), try python.eval(i64, "rl[0]"));
    try std.testing.expectEqual(@as(i64, 30), try python.eval(i64, "rl[-1]"));
}

// ============================================================================
// CLASS: Vector (reflected operators)
// ============================================================================

test "abi3 - Vector - creation" {
    const python = try initTestPython();

    try python.exec("v = example_abi3.Vector(1.0, 2.0, 3.0)");
    try std.testing.expectApproxEqAbs(@as(f64, 1.0), try python.eval(f64, "v.x"), 0.0001);
    try std.testing.expectApproxEqAbs(@as(f64, 2.0), try python.eval(f64, "v.y"), 0.0001);
    try std.testing.expectApproxEqAbs(@as(f64, 3.0), try python.eval(f64, "v.z"), 0.0001);
}

test "abi3 - Vector - __add__ and __sub__" {
    const python = try initTestPython();

    try python.exec("v = example_abi3.Vector(1, 2, 3) + example_abi3.Vector(4, 5, 6)");
    try std.testing.expectApproxEqAbs(@as(f64, 5.0), try python.eval(f64, "v.x"), 0.0001);
    try std.testing.expectApproxEqAbs(@as(f64, 7.0), try python.eval(f64, "v.y"), 0.0001);
    try std.testing.expectApproxEqAbs(@as(f64, 9.0), try python.eval(f64, "v.z"), 0.0001);

    try python.exec("v2 = example_abi3.Vector(5, 5, 5) - example_abi3.Vector(1, 2, 3)");
    try std.testing.expectApproxEqAbs(@as(f64, 4.0), try python.eval(f64, "v2.x"), 0.0001);
}

test "abi3 - Vector - __mul__ (element-wise)" {
    const python = try initTestPython();

    try python.exec("v = example_abi3.Vector(2, 3, 4) * example_abi3.Vector(1, 2, 3)");
    try std.testing.expectApproxEqAbs(@as(f64, 2.0), try python.eval(f64, "v.x"), 0.0001);
    try std.testing.expectApproxEqAbs(@as(f64, 6.0), try python.eval(f64, "v.y"), 0.0001);
    try std.testing.expectApproxEqAbs(@as(f64, 12.0), try python.eval(f64, "v.z"), 0.0001);
}

test "abi3 - Vector - __rmul__ (scalar * vector)" {
    const python = try initTestPython();

    try python.exec("v = 3.0 * example_abi3.Vector(1, 2, 3)");
    try std.testing.expectApproxEqAbs(@as(f64, 3.0), try python.eval(f64, "v.x"), 0.0001);
    try std.testing.expectApproxEqAbs(@as(f64, 6.0), try python.eval(f64, "v.y"), 0.0001);
    try std.testing.expectApproxEqAbs(@as(f64, 9.0), try python.eval(f64, "v.z"), 0.0001);
}

test "abi3 - Vector - magnitude and dot" {
    const python = try initTestPython();

    try python.exec("v = example_abi3.Vector(1, 2, 2)");
    try std.testing.expectApproxEqAbs(@as(f64, 3.0), try python.eval(f64, "v.magnitude()"), 0.0001);

    try python.exec("v2 = example_abi3.Vector(1, 0, 0)");
    const dot = try python.eval(f64, "v.dot(v2)");
    try std.testing.expectApproxEqAbs(@as(f64, 1.0), dot, 0.0001);
}

test "abi3 - Vector - __matmul__ (cross product)" {
    const python = try initTestPython();

    try python.exec("v = example_abi3.Vector(1, 0, 0) @ example_abi3.Vector(0, 1, 0)");
    try std.testing.expectApproxEqAbs(@as(f64, 0.0), try python.eval(f64, "v.x"), 0.0001);
    try std.testing.expectApproxEqAbs(@as(f64, 0.0), try python.eval(f64, "v.y"), 0.0001);
    try std.testing.expectApproxEqAbs(@as(f64, 1.0), try python.eval(f64, "v.z"), 0.0001);
}

test "abi3 - Vector - __imatmul__ (in-place cross product)" {
    const python = try initTestPython();

    try python.exec("v = example_abi3.Vector(1, 0, 0)");
    try python.exec("v @= example_abi3.Vector(0, 1, 0)");
    try std.testing.expectApproxEqAbs(@as(f64, 0.0), try python.eval(f64, "v.x"), 0.0001);
    try std.testing.expectApproxEqAbs(@as(f64, 0.0), try python.eval(f64, "v.y"), 0.0001);
    try std.testing.expectApproxEqAbs(@as(f64, 1.0), try python.eval(f64, "v.z"), 0.0001);
}

// ============================================================================
// CLASS: DynamicObject (__getattr__/__setattr__/__delattr__)
// ============================================================================

test "abi3 - DynamicObject - dynamic attributes" {
    const python = try initTestPython();

    try python.exec("obj = example_abi3.DynamicObject()");
    try python.exec("obj.foo = 42");
    try std.testing.expectEqual(@as(i64, 42), try python.eval(i64, "obj.foo"));

    try python.exec("obj.bar = 100");
    try std.testing.expectEqual(@as(i64, 100), try python.eval(i64, "obj.bar"));
}

test "abi3 - DynamicObject - __delattr__" {
    const python = try initTestPython();

    try python.exec("obj = example_abi3.DynamicObject()");
    try python.exec("obj.test = 123");
    try std.testing.expectEqual(@as(i64, 1), try python.eval(i64, "obj.count()"));

    try python.exec("del obj.test");
    try std.testing.expectEqual(@as(i64, 0), try python.eval(i64, "obj.count()"));
}

test "abi3 - DynamicObject - keys iterator" {
    const python = try initTestPython();

    try python.exec("obj = example_abi3.DynamicObject()");
    try python.exec("obj.a = 1");
    try python.exec("obj.b = 2");
    try python.exec("keys = list(obj.keys())");
    try std.testing.expectEqual(@as(i64, 2), try python.eval(i64, "len(keys)"));
}

// ============================================================================
// ENUMS
// ============================================================================

test "abi3 - enum Color (IntEnum)" {
    const python = try initTestPython();

    try std.testing.expectEqual(@as(i64, 1), try python.eval(i64, "example_abi3.Color.Red.value"));
    try std.testing.expectEqual(@as(i64, 2), try python.eval(i64, "example_abi3.Color.Green.value"));
    try std.testing.expectEqual(@as(i64, 3), try python.eval(i64, "example_abi3.Color.Blue.value"));
    try std.testing.expectEqual(@as(i64, 4), try python.eval(i64, "example_abi3.Color.Yellow.value"));

    // IntEnum can be used as int
    try std.testing.expect(try python.eval(bool, "example_abi3.Color.Red + example_abi3.Color.Green == 3"));
}

test "abi3 - enum HttpStatus (IntEnum)" {
    const python = try initTestPython();

    try std.testing.expectEqual(@as(i64, 200), try python.eval(i64, "example_abi3.HttpStatus.OK.value"));
    try std.testing.expectEqual(@as(i64, 404), try python.eval(i64, "example_abi3.HttpStatus.NotFound.value"));
    try std.testing.expectEqual(@as(i64, 500), try python.eval(i64, "example_abi3.HttpStatus.InternalServerError.value"));
}

test "abi3 - enum TaskStatus (StrEnum)" {
    const python = try initTestPython();

    try std.testing.expect(try python.eval(bool, "example_abi3.TaskStatus.pending.value == 'pending'"));
    try std.testing.expect(try python.eval(bool, "example_abi3.TaskStatus.in_progress.value == 'in_progress'"));
    try std.testing.expect(try python.eval(bool, "example_abi3.TaskStatus.completed.value == 'completed'"));
}

test "abi3 - enum LogLevel (StrEnum)" {
    const python = try initTestPython();

    try std.testing.expect(try python.eval(bool, "example_abi3.LogLevel.debug.value == 'debug'"));
    try std.testing.expect(try python.eval(bool, "example_abi3.LogLevel.info.value == 'info'"));
    try std.testing.expect(try python.eval(bool, "example_abi3.LogLevel.warning.value == 'warning'"));
    try std.testing.expect(try python.eval(bool, "example_abi3.LogLevel.error.value == 'error'"));
    try std.testing.expect(try python.eval(bool, "example_abi3.LogLevel.critical.value == 'critical'"));
}

// ============================================================================
// CUSTOM EXCEPTIONS
// ============================================================================

test "abi3 - custom exception ValidationError" {
    const python = try initTestPython();

    try std.testing.expect(try python.eval(bool, "issubclass(example_abi3.ValidationError, ValueError)"));
    try std.testing.expect(try python.eval(bool, "'Validation' in example_abi3.ValidationError.__doc__"));
}

test "abi3 - custom exception NotFoundError" {
    const python = try initTestPython();

    try std.testing.expect(try python.eval(bool, "issubclass(example_abi3.NotFoundError, KeyError)"));
}

test "abi3 - custom exception MathError" {
    const python = try initTestPython();

    try std.testing.expect(try python.eval(bool, "issubclass(example_abi3.MathError, RuntimeError)"));
}

// ============================================================================
// MODULE CONSTANTS
// ============================================================================

test "abi3 - module constants" {
    const python = try initTestPython();

    try std.testing.expect(try python.eval(bool, "example_abi3.VERSION == '1.0.0'"));
    try std.testing.expect(try python.eval(bool, "example_abi3.PI > 3.14"));
    try std.testing.expectEqual(@as(i64, 1000000), try python.eval(i64, "example_abi3.MAX_VALUE"));
    try std.testing.expect(!try python.eval(bool, "example_abi3.DEBUG"));
}

// ============================================================================
// MODULE DOCSTRING
// ============================================================================

test "abi3 - module has docstring" {
    const python = try initTestPython();

    try std.testing.expect(try python.eval(bool, "example_abi3.__doc__ is not None"));
    try std.testing.expect(try python.eval(bool, "'ABI3' in example_abi3.__doc__"));
}
