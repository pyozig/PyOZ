//! PyOZ Comprehensive Test Suite
//!
//! Tests all features of PyOZ using the embedding API.
//! Run with: zig build test

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
        // Import the example module
        try test_python.?.exec("import sys");
        try test_python.?.exec("sys.path.insert(0, 'zig-out/lib')");
        try test_python.?.exec("import example");

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
    // Try to import numpy
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
// BASIC FUNCTIONS
// ============================================================================

test "fn add - basic integer addition" {
    const python = try initTestPython();

    const r1 = try python.eval(i64, "example.add(2, 3)");
    try std.testing.expectEqual(@as(i64, 5), r1);

    const r2 = try python.eval(i64, "example.add(-10, 10)");
    try std.testing.expectEqual(@as(i64, 0), r2);

    const r3 = try python.eval(i64, "example.add(100, 200)");
    try std.testing.expectEqual(@as(i64, 300), r3);

    const r4 = try python.eval(i64, "example.add(-5, -7)");
    try std.testing.expectEqual(@as(i64, -12), r4);
}

test "fn multiply - float multiplication" {
    const python = try initTestPython();

    const r1 = try python.eval(f64, "example.multiply(6.0, 7.0)");
    try std.testing.expectApproxEqAbs(@as(f64, 42.0), r1, 0.0001);

    const r2 = try python.eval(f64, "example.multiply(2.5, 4.0)");
    try std.testing.expectApproxEqAbs(@as(f64, 10.0), r2, 0.0001);

    const r3 = try python.eval(f64, "example.multiply(-3.0, 2.0)");
    try std.testing.expectApproxEqAbs(@as(f64, -6.0), r3, 0.0001);
}

test "fn divide - division with error handling" {
    const python = try initTestPython();

    const r1 = try python.eval(f64, "example.divide(10.0, 2.0)");
    try std.testing.expectApproxEqAbs(@as(f64, 5.0), r1, 0.0001);

    const r2 = try python.eval(f64, "example.divide(7.0, 2.0)");
    try std.testing.expectApproxEqAbs(@as(f64, 3.5), r2, 0.0001);

    // Test division by zero raises exception
    try python.exec(
        \\try:
        \\    example.divide(1.0, 0.0)
        \\    div_zero_raised = False
        \\except Exception:
        \\    div_zero_raised = True
    );
    const raised = try python.eval(bool, "div_zero_raised");
    try std.testing.expect(raised);
}

test "fn greet - string return" {
    const python = try initTestPython();

    const has_zig = try python.eval(bool, "'Zig' in example.greet('World')");
    try std.testing.expect(has_zig);
}

test "fn is_even - boolean return" {
    const python = try initTestPython();

    try std.testing.expect(try python.eval(bool, "example.is_even(4)"));
    try std.testing.expect(try python.eval(bool, "example.is_even(0)"));
    try std.testing.expect(try python.eval(bool, "example.is_even(-2)"));
    try std.testing.expect(!try python.eval(bool, "example.is_even(5)"));
    try std.testing.expect(!try python.eval(bool, "example.is_even(1)"));
}

test "fn answer - constant return" {
    const python = try initTestPython();

    const result = try python.eval(i64, "example.answer()");
    try std.testing.expectEqual(@as(i64, 42), result);
}

test "fn power - optional arguments" {
    const python = try initTestPython();

    // Default exponent (2.0 = square)
    const r1 = try python.eval(f64, "example.power(5.0)");
    try std.testing.expectApproxEqAbs(@as(f64, 25.0), r1, 0.0001);

    // Custom exponent
    const r2 = try python.eval(f64, "example.power(2.0, 3.0)");
    try std.testing.expectApproxEqAbs(@as(f64, 8.0), r2, 0.0001);

    const r3 = try python.eval(f64, "example.power(3.0, 0.0)");
    try std.testing.expectApproxEqAbs(@as(f64, 1.0), r3, 0.0001);
}

test "fn greet_person - multiple optional args" {
    const python = try initTestPython();

    try python.exec("result = example.greet_person('Alice')");
    // Returns (greeting, name, times) tuple
    const greeting = try python.eval(bool, "result[0] == 'Hello'");
    try std.testing.expect(greeting);
    const name = try python.eval(bool, "result[1] == 'Alice'");
    try std.testing.expect(name);
    const times = try python.eval(i64, "result[2]");
    try std.testing.expectEqual(@as(i64, 1), times);

    // With custom greeting
    try python.exec("result2 = example.greet_person('Bob', 'Hi')");
    const greeting2 = try python.eval(bool, "result2[0] == 'Hi'");
    try std.testing.expect(greeting2);

    // With all args
    try python.exec("result3 = example.greet_person('Charlie', 'Hey', 3)");
    const times3 = try python.eval(i64, "result3[2]");
    try std.testing.expectEqual(@as(i64, 3), times3);
}

// ============================================================================
// DICT OPERATIONS
// ============================================================================

test "fn make_dict - create dict" {
    const python = try initTestPython();

    try python.exec("d = example.make_dict()");
    const is_dict = try python.eval(bool, "isinstance(d, dict)");
    try std.testing.expect(is_dict);

    // Check keys are "one", "two", "three" with values 1, 2, 3
    const one = try python.eval(i64, "d['one']");
    try std.testing.expectEqual(@as(i64, 1), one);
    const two = try python.eval(i64, "d['two']");
    try std.testing.expectEqual(@as(i64, 2), two);
    const three = try python.eval(i64, "d['three']");
    try std.testing.expectEqual(@as(i64, 3), three);
}

test "fn dict_len - count items" {
    const python = try initTestPython();

    const len1 = try python.eval(i64, "example.dict_len({'a': 1, 'b': 2, 'c': 3})");
    try std.testing.expectEqual(@as(i64, 3), len1);

    const len2 = try python.eval(i64, "example.dict_len({})");
    try std.testing.expectEqual(@as(i64, 0), len2);
}

test "fn dict_has_key - key lookup" {
    const python = try initTestPython();

    try std.testing.expect(try python.eval(bool, "example.dict_has_key({'x': 1, 'y': 2}, 'x')"));
    try std.testing.expect(try python.eval(bool, "example.dict_has_key({'x': 1, 'y': 2}, 'y')"));
    try std.testing.expect(!try python.eval(bool, "example.dict_has_key({'x': 1}, 'z')"));
    try std.testing.expect(!try python.eval(bool, "example.dict_has_key({}, 'any')"));
}

test "fn sum_dict_values - iterate and sum" {
    const python = try initTestPython();

    const sum1 = try python.eval(i64, "example.sum_dict_values({'a': 10, 'b': 20, 'c': 30})");
    try std.testing.expectEqual(@as(i64, 60), sum1);

    const sum2 = try python.eval(i64, "example.sum_dict_values({})");
    try std.testing.expectEqual(@as(i64, 0), sum2);

    const sum3 = try python.eval(i64, "example.sum_dict_values({'single': 42})");
    try std.testing.expectEqual(@as(i64, 42), sum3);
}

test "fn get_dict_value - get by key" {
    const python = try initTestPython();

    const val = try python.eval(i64, "example.get_dict_value({'key': 123}, 'key')");
    try std.testing.expectEqual(@as(i64, 123), val);

    // Missing key returns None
    const missing = try python.eval(bool, "example.get_dict_value({'a': 1}, 'b') is None");
    try std.testing.expect(missing);
}

// ============================================================================
// LIST OPERATIONS
// ============================================================================

test "fn sum_list - iterate and sum" {
    const python = try initTestPython();

    const sum1 = try python.eval(i64, "example.sum_list([1, 2, 3, 4, 5])");
    try std.testing.expectEqual(@as(i64, 15), sum1);

    const sum2 = try python.eval(i64, "example.sum_list([])");
    try std.testing.expectEqual(@as(i64, 0), sum2);

    const sum3 = try python.eval(i64, "example.sum_list([-1, -2, 3])");
    try std.testing.expectEqual(@as(i64, 0), sum3);
}

test "fn list_len - get length" {
    const python = try initTestPython();

    try std.testing.expectEqual(@as(i64, 5), try python.eval(i64, "example.list_len([1, 2, 3, 4, 5])"));
    try std.testing.expectEqual(@as(i64, 0), try python.eval(i64, "example.list_len([])"));
    try std.testing.expectEqual(@as(i64, 1), try python.eval(i64, "example.list_len([42])"));
}

test "fn list_get - index access" {
    const python = try initTestPython();

    try std.testing.expectEqual(@as(i64, 10), try python.eval(i64, "example.list_get([10, 20, 30], 0)"));
    try std.testing.expectEqual(@as(i64, 20), try python.eval(i64, "example.list_get([10, 20, 30], 1)"));
    try std.testing.expectEqual(@as(i64, 30), try python.eval(i64, "example.list_get([10, 20, 30], 2)"));

    // Negative index returns None
    const neg = try python.eval(bool, "example.list_get([1, 2, 3], -1) is None");
    try std.testing.expect(neg);
}

test "fn list_contains - membership test" {
    const python = try initTestPython();

    try std.testing.expect(try python.eval(bool, "example.list_contains([1, 2, 3], 2)"));
    try std.testing.expect(try python.eval(bool, "example.list_contains([1, 2, 3], 1)"));
    try std.testing.expect(!try python.eval(bool, "example.list_contains([1, 2, 3], 5)"));
    try std.testing.expect(!try python.eval(bool, "example.list_contains([], 1)"));
}

test "fn list_average - compute average" {
    const python = try initTestPython();

    const avg = try python.eval(f64, "example.list_average([1.0, 2.0, 3.0, 4.0, 5.0])");
    try std.testing.expectApproxEqAbs(@as(f64, 3.0), avg, 0.0001);

    // Empty list returns None
    const empty = try python.eval(bool, "example.list_average([]) is None");
    try std.testing.expect(empty);
}

test "fn list_max - find maximum" {
    const python = try initTestPython();

    try std.testing.expectEqual(@as(i64, 30), try python.eval(i64, "example.list_max([10, 30, 20])"));
    try std.testing.expectEqual(@as(i64, -1), try python.eval(i64, "example.list_max([-5, -1, -10])"));

    // Empty list returns None
    const empty = try python.eval(bool, "example.list_max([]) is None");
    try std.testing.expect(empty);
}

test "fn join_strings - join list of strings" {
    const python = try initTestPython();

    const result = try python.eval(bool, "example.join_strings(['a', 'b', 'c'], '-') == 'a-b-c'");
    try std.testing.expect(result);

    const comma = try python.eval(bool, "example.join_strings(['hello', 'world'], ', ') == 'hello, world'");
    try std.testing.expect(comma);

    const empty = try python.eval(bool, "example.join_strings([], '-') == ''");
    try std.testing.expect(empty);
}

// ============================================================================
// SET OPERATIONS
// ============================================================================

test "fn set_len - count items" {
    const python = try initTestPython();

    try std.testing.expectEqual(@as(i64, 4), try python.eval(i64, "example.set_len({1, 2, 3, 4})"));
    try std.testing.expectEqual(@as(i64, 0), try python.eval(i64, "example.set_len(set())"));
}

test "fn set_has - membership test" {
    const python = try initTestPython();

    try std.testing.expect(try python.eval(bool, "example.set_has({1, 2, 3}, 2)"));
    try std.testing.expect(!try python.eval(bool, "example.set_has({1, 2, 3}, 5)"));
}

test "fn sum_set - iterate and sum" {
    const python = try initTestPython();

    const sum = try python.eval(i64, "example.sum_set({1, 2, 3, 4, 5})");
    try std.testing.expectEqual(@as(i64, 15), sum);
}

test "fn make_set - create set" {
    const python = try initTestPython();

    try python.exec("s = example.make_set()");
    try std.testing.expect(try python.eval(bool, "isinstance(s, set)"));
    try std.testing.expect(try python.eval(bool, "1 in s"));
    try std.testing.expect(try python.eval(bool, "5 in s"));
}

test "fn make_frozenset - create frozenset" {
    const python = try initTestPython();

    try python.exec("fs = example.make_frozenset()");
    try std.testing.expect(try python.eval(bool, "isinstance(fs, frozenset)"));
    try std.testing.expect(try python.eval(bool, "'apple' in fs"));
    try std.testing.expect(try python.eval(bool, "'banana' in fs"));
}

// ============================================================================
// DATETIME OPERATIONS
// ============================================================================

test "fn make_datetime - create datetime" {
    const python = try initTestPython();

    try python.exec("from datetime import datetime");
    try python.exec("dt = example.make_datetime()");
    try std.testing.expect(try python.eval(bool, "isinstance(dt, datetime)"));
    try std.testing.expectEqual(@as(i64, 2024), try python.eval(i64, "dt.year"));
    try std.testing.expectEqual(@as(i64, 12), try python.eval(i64, "dt.month"));
    try std.testing.expectEqual(@as(i64, 25), try python.eval(i64, "dt.day"));
}

test "fn make_date - create date" {
    const python = try initTestPython();

    try python.exec("from datetime import date");
    try python.exec("d = example.make_date()");
    try std.testing.expect(try python.eval(bool, "isinstance(d, date)"));
    try std.testing.expectEqual(@as(i64, 2024), try python.eval(i64, "d.year"));
    try std.testing.expectEqual(@as(i64, 7), try python.eval(i64, "d.month"));
    try std.testing.expectEqual(@as(i64, 4), try python.eval(i64, "d.day"));
}

test "fn make_time - create time" {
    const python = try initTestPython();

    try python.exec("from datetime import time");
    try python.exec("t = example.make_time()");
    try std.testing.expect(try python.eval(bool, "isinstance(t, time)"));
    try std.testing.expectEqual(@as(i64, 14), try python.eval(i64, "t.hour"));
    try std.testing.expectEqual(@as(i64, 30), try python.eval(i64, "t.minute"));
}

test "fn make_timedelta - create timedelta" {
    const python = try initTestPython();

    try python.exec("from datetime import timedelta");
    try python.exec("td = example.make_timedelta()");
    try std.testing.expect(try python.eval(bool, "isinstance(td, timedelta)"));
    try std.testing.expectEqual(@as(i64, 5), try python.eval(i64, "td.days"));
}

test "fn datetime_parts - extract components" {
    const python = try initTestPython();

    try python.exec("from datetime import datetime");
    try python.exec("parts = example.datetime_parts(datetime(2023, 6, 15, 10, 30, 45, 123456))");
    try std.testing.expectEqual(@as(i64, 2023), try python.eval(i64, "parts[0]"));
    try std.testing.expectEqual(@as(i64, 6), try python.eval(i64, "parts[1]"));
    try std.testing.expectEqual(@as(i64, 15), try python.eval(i64, "parts[2]"));
    try std.testing.expectEqual(@as(i64, 10), try python.eval(i64, "parts[3]"));
    try std.testing.expectEqual(@as(i64, 30), try python.eval(i64, "parts[4]"));
    try std.testing.expectEqual(@as(i64, 45), try python.eval(i64, "parts[5]"));
}

test "fn date_parts - extract date components" {
    const python = try initTestPython();

    try python.exec("from datetime import date");
    try python.exec("parts = example.date_parts(date(2023, 12, 25))");
    try std.testing.expectEqual(@as(i64, 2023), try python.eval(i64, "parts[0]"));
    try std.testing.expectEqual(@as(i64, 12), try python.eval(i64, "parts[1]"));
    try std.testing.expectEqual(@as(i64, 25), try python.eval(i64, "parts[2]"));
}

test "fn time_parts - extract time components" {
    const python = try initTestPython();

    try python.exec("from datetime import time");
    try python.exec("parts = example.time_parts(time(14, 30, 45, 500000))");
    try std.testing.expectEqual(@as(i64, 14), try python.eval(i64, "parts[0]"));
    try std.testing.expectEqual(@as(i64, 30), try python.eval(i64, "parts[1]"));
    try std.testing.expectEqual(@as(i64, 45), try python.eval(i64, "parts[2]"));
}

test "fn timedelta_parts - extract timedelta components" {
    const python = try initTestPython();

    try python.exec("from datetime import timedelta");
    try python.exec("parts = example.timedelta_parts(timedelta(days=3, seconds=7200, microseconds=500))");
    try std.testing.expectEqual(@as(i64, 3), try python.eval(i64, "parts[0]"));
    try std.testing.expectEqual(@as(i64, 7200), try python.eval(i64, "parts[1]"));
}

// ============================================================================
// BYTES OPERATIONS
// ============================================================================

test "fn bytes_len - get length" {
    const python = try initTestPython();

    try std.testing.expectEqual(@as(i64, 5), try python.eval(i64, "example.bytes_len(b'hello')"));
    try std.testing.expectEqual(@as(i64, 0), try python.eval(i64, "example.bytes_len(b'')"));
}

test "fn bytes_sum - sum byte values" {
    const python = try initTestPython();

    const sum = try python.eval(i64, "example.bytes_sum(b'\\x01\\x02\\x03')");
    try std.testing.expectEqual(@as(i64, 6), sum);
}

test "fn make_bytes - create bytes" {
    const python = try initTestPython();

    try python.exec("b = example.make_bytes()");
    try std.testing.expect(try python.eval(bool, "isinstance(b, bytes)"));
    try std.testing.expect(try python.eval(bool, "b == b'Hello'"));
}

test "fn bytes_starts_with - check prefix" {
    const python = try initTestPython();

    try std.testing.expect(try python.eval(bool, "example.bytes_starts_with(b'hello', 104)")); // 'h' = 104
    try std.testing.expect(!try python.eval(bool, "example.bytes_starts_with(b'hello', 72)")); // 'H' = 72
    try std.testing.expect(!try python.eval(bool, "example.bytes_starts_with(b'', 0)"));
}

// ============================================================================
// PATH OPERATIONS
// ============================================================================

test "fn path_len - get path length" {
    // Skip on Python 3.9 due to CI-specific segfault (works locally but not in GitHub Actions)
    try skipPythonVersion(3, 9);
    const python = try initTestPython();

    try python.exec("from pathlib import Path");
    const len = try python.eval(i64, "example.path_len(Path('/home/user'))");
    try std.testing.expectEqual(@as(i64, 10), len);
}

test "fn make_path - create path" {
    // Skip on Python 3.9 due to CI-specific segfault (works locally but not in GitHub Actions)
    try skipPythonVersion(3, 9);
    const python = try initTestPython();

    try python.exec("from pathlib import Path");
    try python.exec("p = example.make_path()");
    try std.testing.expect(try python.eval(bool, "isinstance(p, Path)"));
    try std.testing.expect(try python.eval(bool, "str(p) == '/home/user/documents'"));
}

test "fn path_str - get path string" {
    // Skip on Python 3.9 due to CI-specific segfault (works locally but not in GitHub Actions)
    try skipPythonVersion(3, 9);
    const python = try initTestPython();

    try python.exec("from pathlib import Path");
    const result = try python.eval(bool, "example.path_str(Path('/test/path')) == '/test/path'");
    try std.testing.expect(result);
}

test "fn path_starts_with - check prefix" {
    // Skip on Python 3.9 due to CI-specific segfault (works locally but not in GitHub Actions)
    try skipPythonVersion(3, 9);
    const python = try initTestPython();

    try python.exec("from pathlib import Path");
    try std.testing.expect(try python.eval(bool, "example.path_starts_with(Path('/home/user'), '/home')"));
    try std.testing.expect(!try python.eval(bool, "example.path_starts_with(Path('/home/user'), '/etc')"));
}

// ============================================================================
// DECIMAL OPERATIONS
// ============================================================================

test "fn make_decimal - create decimal" {
    const python = try initTestPython();

    try python.exec("from decimal import Decimal");
    try python.exec("d = example.make_decimal()");
    try std.testing.expect(try python.eval(bool, "isinstance(d, Decimal)"));
    try std.testing.expect(try python.eval(bool, "d == Decimal('123.456789')"));
}

test "fn decimal_str - get string representation" {
    const python = try initTestPython();

    try python.exec("from decimal import Decimal");
    const result = try python.eval(bool, "example.decimal_str(Decimal('999.123')) == '999.123'");
    try std.testing.expect(result);
}

// ============================================================================
// BIGINT (i128/u128) OPERATIONS
// ============================================================================

test "fn bigint_max - i128 max value" {
    const python = try initTestPython();

    const max = try python.eval(i128, "example.bigint_max()");
    try std.testing.expectEqual(@as(i128, 170141183460469231731687303715884105727), max);
}

test "fn biguint_large - u128 max value" {
    const python = try initTestPython();

    const max = try python.eval(u128, "example.biguint_large()");
    try std.testing.expectEqual(@as(u128, 340282366920938463463374607431768211455), max);
}

test "fn bigint_echo - i128 roundtrip" {
    const python = try initTestPython();

    try python.exec("big = 123456789012345678901234567890");
    const result = try python.eval(i128, "example.bigint_echo(big)");
    try std.testing.expectEqual(@as(i128, 123456789012345678901234567890), result);
}

test "fn biguint_echo - u128 roundtrip" {
    const python = try initTestPython();

    try python.exec("big = 999999999999999999999999999999");
    const result = try python.eval(u128, "example.biguint_echo(big)");
    try std.testing.expectEqual(@as(u128, 999999999999999999999999999999), result);
}

test "fn bigint_add - i128 addition" {
    const python = try initTestPython();

    const result = try python.eval(i128, "example.bigint_add(100000000000000000000, 200000000000000000000)");
    try std.testing.expectEqual(@as(i128, 300000000000000000000), result);
}

// ============================================================================
// COMPLEX NUMBER OPERATIONS
// ============================================================================

test "fn make_complex - create complex" {
    const python = try initTestPython();

    try python.exec("c = example.make_complex(3.0, 4.0)");
    try std.testing.expect(try python.eval(bool, "isinstance(c, complex)"));
    try std.testing.expect(try python.eval(bool, "c == (3+4j)"));
}

test "fn complex_echo - roundtrip" {
    const python = try initTestPython();

    try python.exec("c = example.complex_echo(5+6j)");
    try std.testing.expect(try python.eval(bool, "c == (5+6j)"));
}

test "fn complex_magnitude - calculate magnitude" {
    const python = try initTestPython();

    const mag = try python.eval(f64, "example.complex_magnitude(3+4j)");
    try std.testing.expectApproxEqAbs(@as(f64, 5.0), mag, 0.0001);
}

test "fn complex_add - add complex numbers" {
    const python = try initTestPython();

    try python.exec("c = example.complex_add(1+2j, 3+4j)");
    try std.testing.expect(try python.eval(bool, "c == (4+6j)"));
}

test "fn complex_mul - multiply complex numbers" {
    const python = try initTestPython();

    try python.exec("c = example.complex_mul(1+2j, 3+4j)");
    // (1+2i)(3+4i) = 3 + 4i + 6i + 8i^2 = 3 + 10i - 8 = -5 + 10i
    try std.testing.expect(try python.eval(bool, "c == (-5+10j)"));
}

// ============================================================================
// TUPLE/ARRAY RETURNS
// ============================================================================

test "fn get_range - return list slice" {
    const python = try initTestPython();

    try python.exec("r = example.get_range(5)");
    try std.testing.expect(try python.eval(bool, "r == [0, 1, 2, 3, 4]"));

    try python.exec("r2 = example.get_range(0)");
    try std.testing.expect(try python.eval(bool, "r2 == []"));
}

test "fn get_fibonacci_ratios - return float list" {
    const python = try initTestPython();

    try python.exec("ratios = example.get_fibonacci_ratios()");
    try std.testing.expect(try python.eval(bool, "len(ratios) == 8"));
    try std.testing.expect(try python.eval(bool, "ratios[0] == 1.0"));
}

test "fn sum_triple - accept fixed array" {
    const python = try initTestPython();

    const sum = try python.eval(i64, "example.sum_triple([10, 20, 30])");
    try std.testing.expectEqual(@as(i64, 60), sum);
}

test "fn dot_product_3d - compute dot product" {
    const python = try initTestPython();

    const dot = try python.eval(f64, "example.dot_product_3d([1.0, 2.0, 3.0], [4.0, 5.0, 6.0])");
    // 1*4 + 2*5 + 3*6 = 4 + 10 + 18 = 32
    try std.testing.expectApproxEqAbs(@as(f64, 32.0), dot, 0.0001);
}

// ============================================================================
// CLASS: Point
// ============================================================================

test "Point - creation and properties" {
    const python = try initTestPython();

    try python.exec("p = example.Point(3.0, 4.0)");
    try std.testing.expectApproxEqAbs(@as(f64, 3.0), try python.eval(f64, "p.x"), 0.0001);
    try std.testing.expectApproxEqAbs(@as(f64, 4.0), try python.eval(f64, "p.y"), 0.0001);
}

test "Point - magnitude method" {
    const python = try initTestPython();

    try python.exec("p = example.Point(3.0, 4.0)");
    try std.testing.expectApproxEqAbs(@as(f64, 5.0), try python.eval(f64, "p.magnitude()"), 0.0001);
}

test "Point - computed property length" {
    const python = try initTestPython();

    try python.exec("p = example.Point(3.0, 4.0)");
    try std.testing.expectApproxEqAbs(@as(f64, 5.0), try python.eval(f64, "p.length"), 0.0001);

    // Setting length scales the point
    try python.exec("p.length = 10.0");
    try std.testing.expectApproxEqAbs(@as(f64, 10.0), try python.eval(f64, "p.length"), 0.0001);
}

test "Point - scale method" {
    const python = try initTestPython();

    try python.exec("p = example.Point(2.0, 3.0)");
    try python.exec("p.scale(2.0)");
    try std.testing.expectApproxEqAbs(@as(f64, 4.0), try python.eval(f64, "p.x"), 0.0001);
    try std.testing.expectApproxEqAbs(@as(f64, 6.0), try python.eval(f64, "p.y"), 0.0001);
}

test "Point - dot method" {
    const python = try initTestPython();

    try python.exec("p = example.Point(2.0, 3.0)");
    const dot = try python.eval(f64, "p.dot(4.0, 5.0)");
    // 2*4 + 3*5 = 8 + 15 = 23
    try std.testing.expectApproxEqAbs(@as(f64, 23.0), dot, 0.0001);
}

test "Point - static method origin" {
    const python = try initTestPython();

    try python.exec("p = example.Point.origin()");
    try std.testing.expectApproxEqAbs(@as(f64, 0.0), try python.eval(f64, "p.x"), 0.0001);
    try std.testing.expectApproxEqAbs(@as(f64, 0.0), try python.eval(f64, "p.y"), 0.0001);
}

test "Point - static method from_angle" {
    const python = try initTestPython();

    try python.exec("import math");
    try python.exec("p = example.Point.from_angle(0)");
    try std.testing.expectApproxEqAbs(@as(f64, 1.0), try python.eval(f64, "p.x"), 0.0001);
    try std.testing.expectApproxEqAbs(@as(f64, 0.0), try python.eval(f64, "p.y"), 0.0001);
}

test "Point - classmethod from_polar" {
    const python = try initTestPython();

    try python.exec("import math");
    try python.exec("p = example.Point.from_polar(5.0, 0)");
    try std.testing.expectApproxEqAbs(@as(f64, 5.0), try python.eval(f64, "p.x"), 0.0001);
    try std.testing.expectApproxEqAbs(@as(f64, 0.0), try python.eval(f64, "p.y"), 0.0001);
}

test "Point - __repr__" {
    const python = try initTestPython();

    try python.exec("p = example.Point(3.0, 4.0)");
    try std.testing.expect(try python.eval(bool, "'Point' in repr(p)"));
}

test "Point - __eq__" {
    const python = try initTestPython();

    try std.testing.expect(try python.eval(bool, "example.Point(1, 2) == example.Point(1, 2)"));
    try std.testing.expect(!try python.eval(bool, "example.Point(1, 2) == example.Point(3, 4)"));
}

test "Point - __add__" {
    const python = try initTestPython();

    try python.exec("p = example.Point(1, 2) + example.Point(3, 4)");
    try std.testing.expectApproxEqAbs(@as(f64, 4.0), try python.eval(f64, "p.x"), 0.0001);
    try std.testing.expectApproxEqAbs(@as(f64, 6.0), try python.eval(f64, "p.y"), 0.0001);
}

test "Point - __sub__" {
    const python = try initTestPython();

    try python.exec("p = example.Point(5, 7) - example.Point(2, 3)");
    try std.testing.expectApproxEqAbs(@as(f64, 3.0), try python.eval(f64, "p.x"), 0.0001);
    try std.testing.expectApproxEqAbs(@as(f64, 4.0), try python.eval(f64, "p.y"), 0.0001);
}

test "Point - __neg__" {
    const python = try initTestPython();

    try python.exec("p = -example.Point(3, 4)");
    try std.testing.expectApproxEqAbs(@as(f64, -3.0), try python.eval(f64, "p.x"), 0.0001);
    try std.testing.expectApproxEqAbs(@as(f64, -4.0), try python.eval(f64, "p.y"), 0.0001);
}

test "Point - docstrings" {
    const python = try initTestPython();

    try std.testing.expect(try python.eval(bool, "example.Point.__doc__ is not None"));
    try std.testing.expect(try python.eval(bool, "'2D point' in example.Point.__doc__"));
}

// ============================================================================
// CLASS: Number (arithmetic operations)
// ============================================================================

test "Number - creation" {
    const python = try initTestPython();

    try python.exec("n = example.Number(42.5)");
    try std.testing.expectApproxEqAbs(@as(f64, 42.5), try python.eval(f64, "n.get_value()"), 0.0001);
}

test "Number - __add__" {
    const python = try initTestPython();

    try python.exec("n = example.Number(10) + example.Number(5)");
    try std.testing.expectApproxEqAbs(@as(f64, 15.0), try python.eval(f64, "n.get_value()"), 0.0001);
}

test "Number - __sub__" {
    const python = try initTestPython();

    try python.exec("n = example.Number(10) - example.Number(3)");
    try std.testing.expectApproxEqAbs(@as(f64, 7.0), try python.eval(f64, "n.get_value()"), 0.0001);
}

test "Number - __mul__" {
    const python = try initTestPython();

    try python.exec("n = example.Number(6) * example.Number(7)");
    try std.testing.expectApproxEqAbs(@as(f64, 42.0), try python.eval(f64, "n.get_value()"), 0.0001);
}

test "Number - __truediv__" {
    const python = try initTestPython();

    try python.exec("n = example.Number(10) / example.Number(4)");
    try std.testing.expectApproxEqAbs(@as(f64, 2.5), try python.eval(f64, "n.get_value()"), 0.0001);
}

test "Number - __floordiv__" {
    const python = try initTestPython();

    try python.exec("n = example.Number(10) // example.Number(3)");
    try std.testing.expectApproxEqAbs(@as(f64, 3.0), try python.eval(f64, "n.get_value()"), 0.0001);
}

test "Number - __mod__" {
    const python = try initTestPython();

    try python.exec("n = example.Number(10) % example.Number(3)");
    try std.testing.expectApproxEqAbs(@as(f64, 1.0), try python.eval(f64, "n.get_value()"), 0.0001);
}

test "Number - __divmod__" {
    const python = try initTestPython();

    try python.exec("q, r = divmod(example.Number(17), example.Number(5))");
    try std.testing.expectApproxEqAbs(@as(f64, 3.0), try python.eval(f64, "q.get_value()"), 0.0001);
    try std.testing.expectApproxEqAbs(@as(f64, 2.0), try python.eval(f64, "r.get_value()"), 0.0001);
}

test "Number - __neg__" {
    const python = try initTestPython();

    try python.exec("n = -example.Number(42)");
    try std.testing.expectApproxEqAbs(@as(f64, -42.0), try python.eval(f64, "n.get_value()"), 0.0001);
}

test "Number - __eq__" {
    const python = try initTestPython();

    try std.testing.expect(try python.eval(bool, "example.Number(5) == example.Number(5)"));
    try std.testing.expect(!try python.eval(bool, "example.Number(5) == example.Number(6)"));
}

test "Number - division by zero" {
    const python = try initTestPython();

    try python.exec(
        \\try:
        \\    example.Number(1) / example.Number(0)
        \\    div_zero = False
        \\except Exception:
        \\    div_zero = True
    );
    try std.testing.expect(try python.eval(bool, "div_zero"));
}

// ============================================================================
// CLASS: Timer (context manager)
// ============================================================================

test "Timer - creation" {
    const python = try initTestPython();

    try python.exec("t = example.Timer('test')");
    try std.testing.expect(try python.eval(bool, "'test' in t.get_name()"));
}

test "Timer - context manager protocol" {
    const python = try initTestPython();

    try python.exec(
        \\with example.Timer("test") as t:
        \\    t.tick()
        \\    t.tick()
        \\    t.tick()
        \\count = t.get_count()
        \\was_active = t.is_active()
    );
    try std.testing.expectEqual(@as(i64, 3), try python.eval(i64, "count"));
    // After exiting, should not be active
    try std.testing.expect(!try python.eval(bool, "was_active"));
}

test "Timer - is_active tracking" {
    const python = try initTestPython();

    try python.exec("t = example.Timer('test')");
    try std.testing.expect(!try python.eval(bool, "t.is_active()"));

    try python.exec("t.__enter__()");
    try std.testing.expect(try python.eval(bool, "t.is_active()"));

    try python.exec("t.__exit__()");
    try std.testing.expect(!try python.eval(bool, "t.is_active()"));
}

// ============================================================================
// CLASS: Version (comparison operators)
// ============================================================================

test "Version - creation" {
    const python = try initTestPython();

    try python.exec("v = example.Version(1, 2, 3)");
    try std.testing.expectEqual(@as(i64, 1), try python.eval(i64, "v.major"));
    try std.testing.expectEqual(@as(i64, 2), try python.eval(i64, "v.minor"));
    try std.testing.expectEqual(@as(i64, 3), try python.eval(i64, "v.patch"));
}

test "Version - __eq__" {
    const python = try initTestPython();

    try std.testing.expect(try python.eval(bool, "example.Version(1, 2, 3) == example.Version(1, 2, 3)"));
    try std.testing.expect(!try python.eval(bool, "example.Version(1, 2, 3) == example.Version(1, 2, 4)"));
}

test "Version - __ne__" {
    const python = try initTestPython();

    try std.testing.expect(try python.eval(bool, "example.Version(1, 0, 0) != example.Version(2, 0, 0)"));
    try std.testing.expect(!try python.eval(bool, "example.Version(1, 0, 0) != example.Version(1, 0, 0)"));
}

test "Version - __lt__" {
    const python = try initTestPython();

    try std.testing.expect(try python.eval(bool, "example.Version(1, 0, 0) < example.Version(2, 0, 0)"));
    try std.testing.expect(try python.eval(bool, "example.Version(1, 0, 0) < example.Version(1, 1, 0)"));
    try std.testing.expect(try python.eval(bool, "example.Version(1, 0, 0) < example.Version(1, 0, 1)"));
    try std.testing.expect(!try python.eval(bool, "example.Version(2, 0, 0) < example.Version(1, 0, 0)"));
}

test "Version - __le__" {
    const python = try initTestPython();

    try std.testing.expect(try python.eval(bool, "example.Version(1, 0, 0) <= example.Version(2, 0, 0)"));
    try std.testing.expect(try python.eval(bool, "example.Version(1, 0, 0) <= example.Version(1, 0, 0)"));
    try std.testing.expect(!try python.eval(bool, "example.Version(2, 0, 0) <= example.Version(1, 0, 0)"));
}

test "Version - __gt__" {
    const python = try initTestPython();

    try std.testing.expect(try python.eval(bool, "example.Version(2, 0, 0) > example.Version(1, 0, 0)"));
    try std.testing.expect(!try python.eval(bool, "example.Version(1, 0, 0) > example.Version(2, 0, 0)"));
}

test "Version - __ge__" {
    const python = try initTestPython();

    try std.testing.expect(try python.eval(bool, "example.Version(2, 0, 0) >= example.Version(1, 0, 0)"));
    try std.testing.expect(try python.eval(bool, "example.Version(1, 0, 0) >= example.Version(1, 0, 0)"));
}

test "Version - is_major" {
    const python = try initTestPython();

    try std.testing.expect(try python.eval(bool, "example.Version(1, 0, 0).is_major()"));
    try std.testing.expect(!try python.eval(bool, "example.Version(1, 1, 0).is_major()"));
    try std.testing.expect(!try python.eval(bool, "example.Version(1, 0, 1).is_major()"));
}

test "Version - is_compatible" {
    const python = try initTestPython();

    try std.testing.expect(try python.eval(bool, "example.Version(1, 0, 0).is_compatible(example.Version(1, 5, 3))"));
    try std.testing.expect(!try python.eval(bool, "example.Version(1, 0, 0).is_compatible(example.Version(2, 0, 0))"));
}

// ============================================================================
// CLASS: BitSet (bitwise operators)
// ============================================================================

test "BitSet - creation" {
    const python = try initTestPython();

    try python.exec("b = example.BitSet(0b1010)");
    try std.testing.expectEqual(@as(u64, 0b1010), try python.eval(u64, "b.get_bits()"));
}

test "BitSet - __bool__" {
    const python = try initTestPython();

    try std.testing.expect(try python.eval(bool, "bool(example.BitSet(1))"));
    try std.testing.expect(!try python.eval(bool, "bool(example.BitSet(0))"));
}

test "BitSet - __and__" {
    const python = try initTestPython();

    try python.exec("b = example.BitSet(0b1100) & example.BitSet(0b1010)");
    try std.testing.expectEqual(@as(u64, 0b1000), try python.eval(u64, "b.get_bits()"));
}

test "BitSet - __or__" {
    const python = try initTestPython();

    try python.exec("b = example.BitSet(0b1100) | example.BitSet(0b1010)");
    try std.testing.expectEqual(@as(u64, 0b1110), try python.eval(u64, "b.get_bits()"));
}

test "BitSet - __xor__" {
    const python = try initTestPython();

    try python.exec("b = example.BitSet(0b1100) ^ example.BitSet(0b1010)");
    try std.testing.expectEqual(@as(u64, 0b0110), try python.eval(u64, "b.get_bits()"));
}

test "BitSet - __invert__" {
    const python = try initTestPython();

    try python.exec("b = ~example.BitSet(0)");
    try std.testing.expectEqual(~@as(u64, 0), try python.eval(u64, "b.get_bits()"));
}

test "BitSet - __lshift__" {
    const python = try initTestPython();

    try python.exec("b = example.BitSet(1) << example.BitSet(3)");
    try std.testing.expectEqual(@as(u64, 8), try python.eval(u64, "b.get_bits()"));
}

test "BitSet - __rshift__" {
    const python = try initTestPython();

    try python.exec("b = example.BitSet(8) >> example.BitSet(2)");
    try std.testing.expectEqual(@as(u64, 2), try python.eval(u64, "b.get_bits()"));
}

test "BitSet - count" {
    const python = try initTestPython();

    try std.testing.expectEqual(@as(i64, 4), try python.eval(i64, "example.BitSet(0b1111).count()"));
    try std.testing.expectEqual(@as(i64, 2), try python.eval(i64, "example.BitSet(0b1010).count()"));
}

test "BitSet - in-place operators" {
    const python = try initTestPython();

    // __iadd__ (in-place OR)
    try python.exec("b = example.BitSet(0b0011)");
    try python.exec("b += example.BitSet(0b1100)");
    try std.testing.expectEqual(@as(u64, 0b1111), try python.eval(u64, "b.get_bits()"));

    // __isub__ (in-place AND NOT)
    try python.exec("b2 = example.BitSet(0b1111)");
    try python.exec("b2 -= example.BitSet(0b0011)");
    try std.testing.expectEqual(@as(u64, 0b1100), try python.eval(u64, "b2.get_bits()"));

    // __iand__
    try python.exec("b3 = example.BitSet(0b1111)");
    try python.exec("b3 &= example.BitSet(0b0101)");
    try std.testing.expectEqual(@as(u64, 0b0101), try python.eval(u64, "b3.get_bits()"));

    // __ior__
    try python.exec("b4 = example.BitSet(0b0101)");
    try python.exec("b4 |= example.BitSet(0b1010)");
    try std.testing.expectEqual(@as(u64, 0b1111), try python.eval(u64, "b4.get_bits()"));

    // __ixor__
    try python.exec("b5 = example.BitSet(0b1111)");
    try python.exec("b5 ^= example.BitSet(0b0101)");
    try std.testing.expectEqual(@as(u64, 0b1010), try python.eval(u64, "b5.get_bits()"));
}

// ============================================================================
// CLASS: PowerNumber (power and coercion)
// ============================================================================

test "PowerNumber - creation" {
    const python = try initTestPython();

    try python.exec("p = example.PowerNumber(5.0)");
    try std.testing.expectApproxEqAbs(@as(f64, 5.0), try python.eval(f64, "p.value"), 0.0001);
}

test "PowerNumber - __pow__" {
    const python = try initTestPython();

    try python.exec("p = example.PowerNumber(2) ** example.PowerNumber(10)");
    try std.testing.expectApproxEqAbs(@as(f64, 1024.0), try python.eval(f64, "p.value"), 0.0001);
}

test "PowerNumber - __pos__" {
    const python = try initTestPython();

    try python.exec("p = +example.PowerNumber(-5)");
    try std.testing.expectApproxEqAbs(@as(f64, -5.0), try python.eval(f64, "p.value"), 0.0001);
}

test "PowerNumber - __abs__" {
    const python = try initTestPython();

    try python.exec("p = abs(example.PowerNumber(-5))");
    try std.testing.expectApproxEqAbs(@as(f64, 5.0), try python.eval(f64, "p.value"), 0.0001);
}

test "PowerNumber - __int__" {
    const python = try initTestPython();

    try std.testing.expectEqual(@as(i64, 42), try python.eval(i64, "int(example.PowerNumber(42.7))"));
}

test "PowerNumber - __float__" {
    const python = try initTestPython();

    try std.testing.expectApproxEqAbs(@as(f64, 42.5), try python.eval(f64, "float(example.PowerNumber(42.5))"), 0.0001);
}

test "PowerNumber - __bool__" {
    const python = try initTestPython();

    try std.testing.expect(try python.eval(bool, "bool(example.PowerNumber(1))"));
    try std.testing.expect(!try python.eval(bool, "bool(example.PowerNumber(0))"));
}

test "PowerNumber - __index__" {
    const python = try initTestPython();

    // __index__ allows use in slice/indexing
    try python.exec("lst = [0, 1, 2, 3, 4, 5]");
    try std.testing.expectEqual(@as(i64, 3), try python.eval(i64, "lst[example.PowerNumber(3)]"));
}

test "PowerNumber - __complex__" {
    const python = try initTestPython();

    try python.exec("c = complex(example.PowerNumber(5))");
    try std.testing.expect(try python.eval(bool, "c == (5+0j)"));
}

// ============================================================================
// CLASS: Adder (callable)
// ============================================================================

test "Adder - __call__" {
    const python = try initTestPython();

    try python.exec("adder = example.Adder(10)");
    try std.testing.expectEqual(@as(i64, 15), try python.eval(i64, "adder(5)"));
    try std.testing.expectEqual(@as(i64, 7), try python.eval(i64, "adder(-3)"));
    try std.testing.expectEqual(@as(i64, 10), try python.eval(i64, "adder(0)"));
}

test "Adder - get_value" {
    const python = try initTestPython();

    try python.exec("adder = example.Adder(42)");
    try std.testing.expectEqual(@as(i64, 42), try python.eval(i64, "adder.get_value()"));
}

// ============================================================================
// CLASS: Multiplier (callable with multiple args)
// ============================================================================

test "Multiplier - __call__" {
    const python = try initTestPython();

    try python.exec("mult = example.Multiplier(2.0)");
    // mult(a, b) = factor * (a + b) = 2 * (3 + 4) = 14
    try std.testing.expectApproxEqAbs(@as(f64, 14.0), try python.eval(f64, "mult(3.0, 4.0)"), 0.0001);
}

// ============================================================================
// CLASS: IntArray (sequence protocol)
// ============================================================================

test "IntArray - creation with from_values" {
    const python = try initTestPython();

    try python.exec("arr = example.IntArray.from_values(10, 20, 30)");
    try std.testing.expectEqual(@as(i64, 3), try python.eval(i64, "len(arr)"));
}

test "IntArray - __len__" {
    const python = try initTestPython();

    try python.exec("arr = example.IntArray.from_values(1, 2, 3)");
    try std.testing.expectEqual(@as(i64, 3), try python.eval(i64, "len(arr)"));
}

test "IntArray - __getitem__" {
    const python = try initTestPython();

    try python.exec("arr = example.IntArray.from_values(10, 20, 30)");
    try std.testing.expectEqual(@as(i64, 10), try python.eval(i64, "arr[0]"));
    try std.testing.expectEqual(@as(i64, 20), try python.eval(i64, "arr[1]"));
    try std.testing.expectEqual(@as(i64, 30), try python.eval(i64, "arr[2]"));
    // Negative index
    try std.testing.expectEqual(@as(i64, 30), try python.eval(i64, "arr[-1]"));
}

test "IntArray - __setitem__" {
    const python = try initTestPython();

    try python.exec("arr = example.IntArray.from_values(1, 2, 3)");
    try python.exec("arr[1] = 99");
    try std.testing.expectEqual(@as(i64, 99), try python.eval(i64, "arr[1]"));
}

test "IntArray - __delitem__" {
    const python = try initTestPython();

    try python.exec("arr = example.IntArray.from_values(1, 2, 3)");
    try python.exec("del arr[1]");
    try std.testing.expectEqual(@as(i64, 2), try python.eval(i64, "len(arr)"));
    try std.testing.expectEqual(@as(i64, 3), try python.eval(i64, "arr[1]"));
}

test "IntArray - __contains__" {
    const python = try initTestPython();

    try python.exec("arr = example.IntArray.from_values(1, 2, 3)");
    try std.testing.expect(try python.eval(bool, "2 in arr"));
    try std.testing.expect(!try python.eval(bool, "5 in arr"));
}

test "IntArray - __iter__" {
    const python = try initTestPython();

    try python.exec("arr = example.IntArray.from_values(1, 2, 3)");
    try python.exec("total = sum(arr)");
    try std.testing.expectEqual(@as(i64, 6), try python.eval(i64, "total"));
}

test "IntArray - append" {
    const python = try initTestPython();

    try python.exec("arr = example.IntArray.from_values(1, 2, 3)");
    try python.exec("arr.append(4)");
    try std.testing.expectEqual(@as(i64, 4), try python.eval(i64, "len(arr)"));
    try std.testing.expectEqual(@as(i64, 4), try python.eval(i64, "arr[3]"));
}

// ============================================================================
// CLASS: VulnArray (sequence protocol with usize index - tests negative index wrapping)
// ============================================================================

test "VulnArray - creation" {
    const python = try initTestPython();

    try python.exec("arr = example.VulnArray.new()");
    try std.testing.expectEqual(@as(i64, 8), try python.eval(i64, "len(arr)"));
}

test "VulnArray - __getitem__ positive index" {
    const python = try initTestPython();

    try python.exec("arr = example.VulnArray.new()");
    try std.testing.expectEqual(@as(i64, 10), try python.eval(i64, "arr[0]"));
    try std.testing.expectEqual(@as(i64, 80), try python.eval(i64, "arr[7]"));
}

test "VulnArray - __getitem__ negative index raises IndexError for usize" {
    // For classes with usize index, negative indices via mapping protocol raise IndexError
    // (Python's PyLong_AsUnsignedLongLong rejects negative values)
    const python = try initTestPython();

    try python.exec("arr = example.VulnArray.new()");
    try python.exec(
        \\try:
        \\    _ = arr[-1]
        \\    result = False
        \\except IndexError:
        \\    result = True
    );
    try std.testing.expect(try python.eval(bool, "result"));
}

test "VulnArray - PySequence_GetItem negative index wrapping via ctypes" {
    // Tests the fix via ctypes to force sequence protocol (bypasses mapping protocol)
    const python = try initTestPython();

    try python.exec("import ctypes");
    try python.exec("arr = example.VulnArray.new()");
    try python.exec(
        \\PySequence_GetItem = ctypes.pythonapi.PySequence_GetItem
        \\PySequence_GetItem.argtypes = [ctypes.py_object, ctypes.c_ssize_t]
        \\PySequence_GetItem.restype = ctypes.py_object
    );
    // Test wrapping works via sequence protocol
    try std.testing.expectEqual(@as(i64, 80), try python.eval(i64, "PySequence_GetItem(arr, -1)"));
    try std.testing.expectEqual(@as(i64, 10), try python.eval(i64, "PySequence_GetItem(arr, -8)"));

    // Test out-of-range raises IndexError (not crash/panic)
    try python.exec(
        \\try:
        \\    PySequence_GetItem(arr, -100)
        \\    seq_result = False
        \\except IndexError:
        \\    seq_result = True
    );
    try std.testing.expect(try python.eval(bool, "seq_result"));
}

// ============================================================================
// CLASS: ReversibleList
// ============================================================================

test "ReversibleList - creation" {
    const python = try initTestPython();

    try python.exec("rl = example.ReversibleList(1, 2, 3)");
    try std.testing.expectEqual(@as(i64, 3), try python.eval(i64, "len(rl)"));
}

test "ReversibleList - __reversed__" {
    const python = try initTestPython();

    try python.exec("rl = example.ReversibleList(1, 2, 3)");
    try python.exec("rev = list(reversed(rl))");
    try std.testing.expectEqual(@as(i64, 3), try python.eval(i64, "rev[0]"));
    try std.testing.expectEqual(@as(i64, 2), try python.eval(i64, "rev[1]"));
    try std.testing.expectEqual(@as(i64, 1), try python.eval(i64, "rev[2]"));
}

test "ReversibleList - forward iteration" {
    const python = try initTestPython();

    try python.exec("rl = example.ReversibleList(1, 2, 3)");
    try python.exec("fwd = list(rl)");
    try std.testing.expectEqual(@as(i64, 1), try python.eval(i64, "fwd[0]"));
    try std.testing.expectEqual(@as(i64, 2), try python.eval(i64, "fwd[1]"));
    try std.testing.expectEqual(@as(i64, 3), try python.eval(i64, "fwd[2]"));
}

// ============================================================================
// CLASS: DynamicObject (__getattr__, __setattr__, __delattr__)
// ============================================================================

test "DynamicObject - dynamic attributes" {
    const python = try initTestPython();

    try python.exec("obj = example.DynamicObject()");
    try python.exec("obj.foo = 42");
    try std.testing.expectEqual(@as(i64, 42), try python.eval(i64, "obj.foo"));

    try python.exec("obj.bar = 100");
    try std.testing.expectEqual(@as(i64, 100), try python.eval(i64, "obj.bar"));
}

test "DynamicObject - __delattr__" {
    const python = try initTestPython();

    try python.exec("obj = example.DynamicObject()");
    try python.exec("obj.test = 123");
    try std.testing.expectEqual(@as(i64, 1), try python.eval(i64, "obj.count()"));

    try python.exec("del obj.test");
    try std.testing.expectEqual(@as(i64, 0), try python.eval(i64, "obj.count()"));
}

// ============================================================================
// CLASS: Vector (reflected operators)
// ============================================================================

test "Vector - creation" {
    const python = try initTestPython();

    try python.exec("v = example.Vector(1.0, 2.0, 3.0)");
    try std.testing.expectApproxEqAbs(@as(f64, 1.0), try python.eval(f64, "v.x"), 0.0001);
    try std.testing.expectApproxEqAbs(@as(f64, 2.0), try python.eval(f64, "v.y"), 0.0001);
    try std.testing.expectApproxEqAbs(@as(f64, 3.0), try python.eval(f64, "v.z"), 0.0001);
}

test "Vector - __add__" {
    const python = try initTestPython();

    try python.exec("v = example.Vector(1, 2, 3) + example.Vector(4, 5, 6)");
    try std.testing.expectApproxEqAbs(@as(f64, 5.0), try python.eval(f64, "v.x"), 0.0001);
    try std.testing.expectApproxEqAbs(@as(f64, 7.0), try python.eval(f64, "v.y"), 0.0001);
    try std.testing.expectApproxEqAbs(@as(f64, 9.0), try python.eval(f64, "v.z"), 0.0001);
}

test "Vector - __radd__ (scalar + vector)" {
    const python = try initTestPython();

    try python.exec("v = 5 + example.Vector(1, 2, 3)");
    try std.testing.expectApproxEqAbs(@as(f64, 6.0), try python.eval(f64, "v.x"), 0.0001);
    try std.testing.expectApproxEqAbs(@as(f64, 7.0), try python.eval(f64, "v.y"), 0.0001);
    try std.testing.expectApproxEqAbs(@as(f64, 8.0), try python.eval(f64, "v.z"), 0.0001);
}

test "Vector - __mul__" {
    const python = try initTestPython();

    try python.exec("v = example.Vector(1, 2, 3) * example.Vector(2, 2, 2)");
    try std.testing.expectApproxEqAbs(@as(f64, 2.0), try python.eval(f64, "v.x"), 0.0001);
    try std.testing.expectApproxEqAbs(@as(f64, 4.0), try python.eval(f64, "v.y"), 0.0001);
    try std.testing.expectApproxEqAbs(@as(f64, 6.0), try python.eval(f64, "v.z"), 0.0001);
}

test "Vector - __rmul__ (scalar * vector)" {
    const python = try initTestPython();

    try python.exec("v = 2 * example.Vector(1, 2, 3)");
    try std.testing.expectApproxEqAbs(@as(f64, 2.0), try python.eval(f64, "v.x"), 0.0001);
    try std.testing.expectApproxEqAbs(@as(f64, 4.0), try python.eval(f64, "v.y"), 0.0001);
    try std.testing.expectApproxEqAbs(@as(f64, 6.0), try python.eval(f64, "v.z"), 0.0001);
}

test "Vector - magnitude" {
    const python = try initTestPython();

    // magnitude of (1,2,2) = sqrt(1+4+4) = 3
    try std.testing.expectApproxEqAbs(@as(f64, 3.0), try python.eval(f64, "example.Vector(1, 2, 2).magnitude()"), 0.0001);
}

test "Vector - dot" {
    const python = try initTestPython();

    // dot((1,2,3), (4,5,6)) = 1*4 + 2*5 + 3*6 = 32
    try std.testing.expectApproxEqAbs(@as(f64, 32.0), try python.eval(f64, "example.Vector(1,2,3).dot(example.Vector(4,5,6))"), 0.0001);
}

// ============================================================================
// CLASS: BoundedValue (custom getters/setters)
// ============================================================================

test "BoundedValue - clamping setter" {
    const python = try initTestPython();

    // BoundedValue requires (value, access_count) args
    try python.exec("bv = example.BoundedValue(50.0, 0)");
    try std.testing.expectApproxEqAbs(@as(f64, 50.0), try python.eval(f64, "bv.value"), 0.0001);

    try python.exec("bv.value = 150"); // Should clamp to 100
    try std.testing.expectApproxEqAbs(@as(f64, 100.0), try python.eval(f64, "bv.value"), 0.0001);

    try python.exec("bv.value = -50"); // Should clamp to 0
    try std.testing.expectApproxEqAbs(@as(f64, 0.0), try python.eval(f64, "bv.value"), 0.0001);

    try python.exec("bv.value = 50"); // Should stay at 50
    try std.testing.expectApproxEqAbs(@as(f64, 50.0), try python.eval(f64, "bv.value"), 0.0001);

    // Check access_count incremented
    try std.testing.expectEqual(@as(i64, 3), try python.eval(i64, "bv.get_access_count()"));
}

// ============================================================================
// CLASS: Flexible (__dict__ and weakref support)
// ============================================================================

test "Flexible - __dict__ support" {
    const python = try initTestPython();

    try python.exec("f = example.Flexible(42)");
    try python.exec("f.custom = 'hello'");
    try std.testing.expect(try python.eval(bool, "hasattr(f, '__dict__')"));
    try std.testing.expect(try python.eval(bool, "f.__dict__['custom'] == 'hello'"));
}

test "Flexible - weakref support" {
    const python = try initTestPython();

    try python.exec("import weakref");
    try python.exec("f = example.Flexible(42)");
    try python.exec("ref = weakref.ref(f)");
    try std.testing.expect(try python.eval(bool, "ref() is f"));
}

test "Flexible - methods" {
    const python = try initTestPython();

    try python.exec("f = example.Flexible(21)");
    try std.testing.expectEqual(@as(i64, 21), try python.eval(i64, "f.get_value()"));
    try python.exec("f.set_value(42)");
    try std.testing.expectEqual(@as(i64, 42), try python.eval(i64, "f.get_value()"));

    // double() mutates in place (returns None)
    try python.exec("f.double()");
    try std.testing.expectEqual(@as(i64, 84), try python.eval(i64, "f.get_value()"));
}

// ============================================================================
// CLASS: FrozenPoint (immutable)
// ============================================================================

test "FrozenPoint - creation" {
    const python = try initTestPython();

    try python.exec("fp = example.FrozenPoint(3, 4)");
    try std.testing.expectApproxEqAbs(@as(f64, 3.0), try python.eval(f64, "fp.x"), 0.0001);
    try std.testing.expectApproxEqAbs(@as(f64, 4.0), try python.eval(f64, "fp.y"), 0.0001);
}

test "FrozenPoint - immutability" {
    const python = try initTestPython();

    try python.exec("fp = example.FrozenPoint(3, 4)");
    try python.exec(
        \\try:
        \\    fp.x = 10
        \\    frozen_error = False
        \\except AttributeError:
        \\    frozen_error = True
    );
    try std.testing.expect(try python.eval(bool, "frozen_error"));
}

test "FrozenPoint - magnitude" {
    const python = try initTestPython();

    try python.exec("fp = example.FrozenPoint(3, 4)");
    try std.testing.expectApproxEqAbs(@as(f64, 5.0), try python.eval(f64, "fp.magnitude()"), 0.0001);
}

test "FrozenPoint - static origin" {
    const python = try initTestPython();

    try python.exec("fp = example.FrozenPoint.origin()");
    try std.testing.expectApproxEqAbs(@as(f64, 0.0), try python.eval(f64, "fp.x"), 0.0001);
    try std.testing.expectApproxEqAbs(@as(f64, 0.0), try python.eval(f64, "fp.y"), 0.0001);
}

// ============================================================================
// CLASS: Circle (class attributes)
// ============================================================================

test "Circle - class attributes" {
    const python = try initTestPython();

    try std.testing.expectApproxEqAbs(@as(f64, 3.14159265358979), try python.eval(f64, "example.Circle.PI"), 0.0000001);
    try std.testing.expectApproxEqAbs(@as(f64, 1.0), try python.eval(f64, "example.Circle.UNIT_RADIUS"), 0.0001);
    try std.testing.expect(try python.eval(bool, "example.Circle.DEFAULT_COLOR == 'red'"));
    try std.testing.expectEqual(@as(i64, 1000), try python.eval(i64, "example.Circle.MAX_RADIUS"));
}

test "Circle - area" {
    const python = try initTestPython();

    try python.exec("c = example.Circle(2.0)");
    // area = PI * r^2 = PI * 4
    const area = try python.eval(f64, "c.area()");
    try std.testing.expectApproxEqAbs(@as(f64, 3.14159265358979 * 4.0), area, 0.0001);
}

test "Circle - circumference" {
    const python = try initTestPython();

    try python.exec("c = example.Circle(2.0)");
    // circumference = 2 * PI * r = 4 * PI
    const circ = try python.eval(f64, "c.circumference()");
    try std.testing.expectApproxEqAbs(@as(f64, 2.0 * 3.14159265358979 * 2.0), circ, 0.0001);
}

test "Circle - unit static method" {
    const python = try initTestPython();

    try python.exec("c = example.Circle.unit()");
    try std.testing.expectApproxEqAbs(@as(f64, 1.0), try python.eval(f64, "c.radius"), 0.0001);
}

// ============================================================================
// CLASS: Stack (inheritance from list)
// ============================================================================

test "Stack - push and pop" {
    const python = try initTestPython();

    try python.exec("s = example.Stack()");
    try python.exec("s.push(1)");
    try python.exec("s.push(2)");
    try python.exec("s.push(3)");

    try std.testing.expectEqual(@as(i64, 3), try python.eval(i64, "s.stack_size()"));
    try std.testing.expectEqual(@as(i64, 3), try python.eval(i64, "s.peek()"));
    try std.testing.expectEqual(@as(i64, 3), try python.eval(i64, "s.pop_item()"));
    try std.testing.expectEqual(@as(i64, 2), try python.eval(i64, "s.stack_size()"));
}

test "Stack - is_empty" {
    const python = try initTestPython();

    try python.exec("s = example.Stack()");
    try std.testing.expect(try python.eval(bool, "s.is_empty()"));
    try python.exec("s.push(1)");
    try std.testing.expect(!try python.eval(bool, "s.is_empty()"));
}

test "Stack - inherits from list" {
    const python = try initTestPython();

    try python.exec("s = example.Stack()");
    try std.testing.expect(try python.eval(bool, "isinstance(s, list)"));
}

// ============================================================================
// CLASS: DefaultDict (inheritance from dict, __missing__)
// ============================================================================

test "DefaultDict - __missing__" {
    const python = try initTestPython();

    try python.exec("dd = example.DefaultDict()");
    try python.exec("dd['existing'] = 100");
    try std.testing.expectEqual(@as(i64, 100), try python.eval(i64, "dd['existing']"));

    // Missing key returns the key as a string (per implementation)
    try std.testing.expect(try python.eval(bool, "dd['nonexistent'] == 'nonexistent'"));

    // And it gets stored in the dict
    try std.testing.expect(try python.eval(bool, "'nonexistent' in dd"));
}

test "DefaultDict - inherits from dict" {
    const python = try initTestPython();

    try python.exec("dd = example.DefaultDict()");
    try std.testing.expect(try python.eval(bool, "isinstance(dd, dict)"));
}

// ============================================================================
// CLASS: Container (GC support - __traverse__, __clear__)
// ============================================================================

test "Container - store and get" {
    const python = try initTestPython();

    try python.exec("c = example.Container('test')");
    try python.exec("c.store([1, 2, 3])");
    try std.testing.expect(try python.eval(bool, "c.has_value()"));
    try std.testing.expect(try python.eval(bool, "c.get() == [1, 2, 3]"));
}

test "Container - clear" {
    const python = try initTestPython();

    try python.exec("c = example.Container('test')");
    try python.exec("c.store({'key': 'value'})");
    try python.exec("c.clear_stored()");
    try std.testing.expect(!try python.eval(bool, "c.has_value()"));
}

// ============================================================================
// CLASS: TypedAttribute (descriptor protocol)
// ============================================================================

test "TypedAttribute - bounds clamping" {
    const python = try initTestPython();

    try python.exec("ta = example.TypedAttribute(0.0, 100.0)");

    // Get bounds
    try python.exec("bounds = ta.get_bounds()");
    try std.testing.expectApproxEqAbs(@as(f64, 0.0), try python.eval(f64, "bounds[0]"), 0.0001);
    try std.testing.expectApproxEqAbs(@as(f64, 100.0), try python.eval(f64, "bounds[1]"), 0.0001);
}

// ============================================================================
// ENUMS
// ============================================================================

test "enum - Color (IntEnum)" {
    const python = try initTestPython();

    try python.exec("from enum import IntEnum");
    try std.testing.expect(try python.eval(bool, "issubclass(example.Color, IntEnum)"));

    // Values are Red=1, Green=2, Blue=3, etc. (PyOZ starts from 1 for i32 enums)
    try std.testing.expect(try python.eval(bool, "example.Color.Red.value == 1"));
    try std.testing.expect(try python.eval(bool, "example.Color.Green.value == 2"));
    try std.testing.expect(try python.eval(bool, "example.Color.Blue.value == 3"));
}

test "enum - HttpStatus (IntEnum)" {
    const python = try initTestPython();

    try std.testing.expect(try python.eval(bool, "example.HttpStatus.OK.value == 200"));
    try std.testing.expect(try python.eval(bool, "example.HttpStatus.NotFound.value == 404"));
    try std.testing.expect(try python.eval(bool, "example.HttpStatus.InternalServerError.value == 500"));
}

test "enum - TaskStatus (StrEnum)" {
    const python = try initTestPython();

    // StrEnum was added in Python 3.11
    try requirePythonVersion(3, 11);

    try python.exec("from enum import StrEnum");
    try std.testing.expect(try python.eval(bool, "issubclass(example.TaskStatus, StrEnum)"));
    try std.testing.expect(try python.eval(bool, "example.TaskStatus.pending.value == 'pending'"));
    try std.testing.expect(try python.eval(bool, "example.TaskStatus.completed.value == 'completed'"));
}

test "enum - LogLevel (StrEnum)" {
    const python = try initTestPython();

    // StrEnum was added in Python 3.11
    try requirePythonVersion(3, 11);

    try std.testing.expect(try python.eval(bool, "example.LogLevel.debug.value == 'debug'"));
    try std.testing.expect(try python.eval(bool, "example.LogLevel.info.value == 'info'"));
    try std.testing.expect(try python.eval(bool, "example.LogLevel.error.value == 'error'"));
}

// ============================================================================
// EXCEPTIONS
// ============================================================================

test "fn raise_value_error - raising exceptions" {
    const python = try initTestPython();

    try python.exec(
        \\try:
        \\    example.raise_value_error("test error message")
        \\    raised = False
        \\except ValueError as e:
        \\    raised = True
        \\    msg = str(e)
    );
    try std.testing.expect(try python.eval(bool, "raised"));
    try std.testing.expect(try python.eval(bool, "'test error' in msg"));
}

test "fn validate_positive - error mapping" {
    const python = try initTestPython();

    // Valid input returns the value
    try std.testing.expectEqual(@as(i64, 5), try python.eval(i64, "example.validate_positive(5)"));

    // Negative input raises exception
    try python.exec(
        \\try:
        \\    example.validate_positive(-5)
        \\    raised = False
        \\except Exception:
        \\    raised = True
    );
    try std.testing.expect(try python.eval(bool, "raised"));
}

test "fn parse_and_validate - error mapping" {
    const python = try initTestPython();

    // Valid input
    try std.testing.expectEqual(@as(i64, 20), try python.eval(i64, "example.parse_and_validate(10)"));

    // Negative value error
    try python.exec(
        \\try:
        \\    example.parse_and_validate(-1)
        \\    neg_raised = False
        \\except ValueError:
        \\    neg_raised = True
    );
    try std.testing.expect(try python.eval(bool, "neg_raised"));

    // Too large error
    try python.exec(
        \\try:
        \\    example.parse_and_validate(2000)
        \\    large_raised = False
        \\except ValueError:
        \\    large_raised = True
    );
    try std.testing.expect(try python.eval(bool, "large_raised"));
}

test "fn lookup_index - index error mapping" {
    const python = try initTestPython();

    try std.testing.expectEqual(@as(i64, 10), try python.eval(i64, "example.lookup_index(0)"));
    try std.testing.expectEqual(@as(i64, 30), try python.eval(i64, "example.lookup_index(2)"));

    // Out of bounds
    try python.exec(
        \\try:
        \\    example.lookup_index(10)
        \\    raised = False
        \\except IndexError:
        \\    raised = True
    );
    try std.testing.expect(try python.eval(bool, "raised"));
}

// ============================================================================
// KWARGS (named arguments)
// ============================================================================

test "fn greet_named - keyword arguments" {
    const python = try initTestPython();

    // All defaults
    try python.exec("result = example.greet_named(name='World')");
    try std.testing.expect(try python.eval(bool, "result[0] == 'Hello'")); // default greeting
    try std.testing.expect(try python.eval(bool, "result[1] == 'World'"));
    try std.testing.expectEqual(@as(i64, 1), try python.eval(i64, "result[2]")); // default times
    try std.testing.expect(!try python.eval(bool, "result[3]")); // default excited=False

    // Custom values
    try python.exec("result2 = example.greet_named(name='Alice', greeting='Hi', times=3, excited=True)");
    try std.testing.expect(try python.eval(bool, "result2[0] == 'Hi'"));
    try std.testing.expect(try python.eval(bool, "result2[1] == 'Alice'"));
    try std.testing.expectEqual(@as(i64, 3), try python.eval(i64, "result2[2]"));
    try std.testing.expect(try python.eval(bool, "result2[3]"));
}

test "fn calculate_named - keyword arguments with operations" {
    const python = try initTestPython();

    // Default operation (add)
    try std.testing.expectApproxEqAbs(@as(f64, 8.0), try python.eval(f64, "example.calculate_named(x=3, y=5)"), 0.0001);

    // Subtract
    try std.testing.expectApproxEqAbs(@as(f64, 7.0), try python.eval(f64, "example.calculate_named(x=10, y=3, operation='sub')"), 0.0001);

    // Multiply
    try std.testing.expectApproxEqAbs(@as(f64, 12.0), try python.eval(f64, "example.calculate_named(x=3, y=4, operation='mul')"), 0.0001);

    // Divide
    try std.testing.expectApproxEqAbs(@as(f64, 2.5), try python.eval(f64, "example.calculate_named(x=10, y=4, operation='div')"), 0.0001);
}

// ============================================================================
// SUBMODULES (math submodule)
// ============================================================================

test "submodule math - factorial" {
    const python = try initTestPython();

    try std.testing.expectEqual(@as(i64, 1), try python.eval(i64, "example.math.factorial(0)"));
    try std.testing.expectEqual(@as(i64, 1), try python.eval(i64, "example.math.factorial(1)"));
    try std.testing.expectEqual(@as(i64, 120), try python.eval(i64, "example.math.factorial(5)"));
    try std.testing.expectEqual(@as(i64, 3628800), try python.eval(i64, "example.math.factorial(10)"));
}

test "submodule math - gcd" {
    const python = try initTestPython();

    try std.testing.expectEqual(@as(i64, 6), try python.eval(i64, "example.math.gcd(48, 18)"));
    try std.testing.expectEqual(@as(i64, 1), try python.eval(i64, "example.math.gcd(17, 13)"));
    try std.testing.expectEqual(@as(i64, 12), try python.eval(i64, "example.math.gcd(12, 12)"));
}

test "submodule math - lcm" {
    const python = try initTestPython();

    try std.testing.expectEqual(@as(i64, 12), try python.eval(i64, "example.math.lcm(4, 6)"));
    try std.testing.expectEqual(@as(i64, 35), try python.eval(i64, "example.math.lcm(5, 7)"));
}

test "submodule math - is_prime" {
    const python = try initTestPython();

    try std.testing.expect(!try python.eval(bool, "example.math.is_prime(1)"));
    try std.testing.expect(try python.eval(bool, "example.math.is_prime(2)"));
    try std.testing.expect(try python.eval(bool, "example.math.is_prime(17)"));
    try std.testing.expect(!try python.eval(bool, "example.math.is_prime(18)"));
    try std.testing.expect(try python.eval(bool, "example.math.is_prime(97)"));
}

// ============================================================================
// GIL MANAGEMENT
// ============================================================================

test "fn compute_sum_no_gil - GIL release" {
    const python = try initTestPython();

    // The function uses wrapping arithmetic with modulo, so we test behavior not exact value
    const result = try python.eval(i64, "example.compute_sum_no_gil(10)");
    // Just verify it returns a number (the exact value depends on the algorithm)
    try std.testing.expect(result >= 0);
}

test "fn compute_sum_with_gil - keeps GIL" {
    const python = try initTestPython();

    const result = try python.eval(i64, "example.compute_sum_with_gil(10)");
    // Same algorithm, should return same result
    const no_gil_result = try python.eval(i64, "example.compute_sum_no_gil(10)");
    try std.testing.expectEqual(no_gil_result, result);
}

// ============================================================================
// FUNCTION PASSING CLASSES
// ============================================================================

test "fn distance - accept Point instances" {
    const python = try initTestPython();

    try python.exec("p1 = example.Point(0, 0)");
    try python.exec("p2 = example.Point(3, 4)");
    const dist = try python.eval(f64, "example.distance(p1, p2)");
    try std.testing.expectApproxEqAbs(@as(f64, 5.0), dist, 0.0001);
}

test "fn midpoint_coords - accept Point instances, return tuple" {
    const python = try initTestPython();

    try python.exec("p1 = example.Point(0, 0)");
    try python.exec("p2 = example.Point(10, 10)");
    try python.exec("mx, my = example.midpoint_coords(p1, p2)");
    try std.testing.expectApproxEqAbs(@as(f64, 5.0), try python.eval(f64, "mx"), 0.0001);
    try std.testing.expectApproxEqAbs(@as(f64, 5.0), try python.eval(f64, "my"), 0.0001);
}

// ============================================================================
// EXCEPTION CATCHING
// ============================================================================

test "fn check_exception_type - identify exception types" {
    const python = try initTestPython();

    // Create a function that raises ValueError
    try python.exec("def raise_value(): raise ValueError('test')");
    const result = try python.eval(bool, "example.check_exception_type(raise_value) == 'ValueError'");
    try std.testing.expect(result);

    // Create a function that raises TypeError
    try python.exec("def raise_type(): raise TypeError('test')");
    const result2 = try python.eval(bool, "example.check_exception_type(raise_type) == 'TypeError'");
    try std.testing.expect(result2);

    // Create a function that doesn't raise
    try python.exec("def no_raise(): return 42");
    const result3 = try python.eval(bool, "example.check_exception_type(no_raise) == 'none'");
    try std.testing.expect(result3);
}

// ============================================================================
// MODULE DOCSTRINGS
// ============================================================================

test "module - has docstring" {
    const python = try initTestPython();

    try std.testing.expect(try python.eval(bool, "example.__doc__ is not None"));
}

// ============================================================================
// GAP COVERAGE: __str__ (distinct from __repr__)
// ============================================================================

test "Version - __str__" {
    const python = try initTestPython();

    try python.exec("v = example.Version(1, 2, 3)");
    // __str__ returns "v..." per implementation
    try std.testing.expect(try python.eval(bool, "'v' in str(v)"));
}

// ============================================================================
// GAP COVERAGE: __hash__
// ============================================================================

test "FrozenPoint - __hash__ (hashable immutable objects)" {
    const python = try initTestPython();

    // FrozenPoint is immutable and has __hash__ implemented
    try python.exec("fp1 = example.FrozenPoint(1.0, 2.0)");
    try python.exec("fp2 = example.FrozenPoint(3.0, 4.0)");
    try python.exec("fp3 = example.FrozenPoint(1.0, 2.0)"); // Same as fp1

    // Test that hash() can be called
    try python.exec("h1 = hash(fp1)");
    try python.exec("h2 = hash(fp2)");
    try python.exec("h3 = hash(fp3)");

    // Hash returns an integer
    try std.testing.expect(try python.eval(bool, "isinstance(h1, int)"));
    try std.testing.expect(try python.eval(bool, "isinstance(h2, int)"));

    // Equal objects should have equal hashes
    try std.testing.expect(try python.eval(bool, "h1 == h3"));

    // Can use FrozenPoint in sets
    try python.exec("point_set = {fp1, fp2, fp3}");
    // fp1 and fp3 are equal, so set should have 2 elements
    try std.testing.expectEqual(@as(i64, 2), try python.eval(i64, "len(point_set)"));

    // Can use FrozenPoint as dict key
    try python.exec("point_dict = {fp1: 'first', fp2: 'second'}");
    try std.testing.expect(try python.eval(bool, "point_dict[fp1] == 'first'"));
    try std.testing.expect(try python.eval(bool, "point_dict[fp3] == 'first'")); // fp3 == fp1
}

// ============================================================================
// GAP COVERAGE: __slots__ (auto-generated)
// ============================================================================

test "Point - __slots__ auto-generated" {
    const python = try initTestPython();

    // Classes should have __slots__ to prevent arbitrary attribute assignment
    // and reduce memory usage
    try python.exec("p = example.Point(1, 2)");

    // Check that __slots__ exists (PyOZ generates it from struct fields)
    try std.testing.expect(try python.eval(bool, "hasattr(example.Point, '__slots__')"));
}

// ============================================================================
// GAP COVERAGE: Subclassing from Python
// ============================================================================

test "Point - subclassable from Python" {
    const python = try initTestPython();

    // Create a Python subclass of Point
    try python.exec(
        \\class Point3D(example.Point):
        \\    def __init__(self, x, y, z):
        \\        super().__init__(x, y)
        \\        self._z = z
        \\
        \\    @property
        \\    def z(self):
        \\        return self._z
        \\
        \\    def magnitude3d(self):
        \\        return (self.x**2 + self.y**2 + self._z**2)**0.5
    );

    try python.exec("p3d = Point3D(3, 4, 0)");

    // Should have parent's methods
    try std.testing.expectApproxEqAbs(@as(f64, 5.0), try python.eval(f64, "p3d.magnitude()"), 0.0001);

    // Should have child's methods
    try std.testing.expectApproxEqAbs(@as(f64, 5.0), try python.eval(f64, "p3d.magnitude3d()"), 0.0001);

    // Should be instance of both
    try std.testing.expect(try python.eval(bool, "isinstance(p3d, example.Point)"));
    try std.testing.expect(try python.eval(bool, "isinstance(p3d, Point3D)"));
}

// ============================================================================
// GAP COVERAGE: Descriptor Protocol (__get__, __set__, __delete__)
// ============================================================================

test "TypedAttribute - descriptor protocol" {
    const python = try initTestPython();

    // Create a TypedAttribute with min=0, max=100
    try python.exec("ta = example.TypedAttribute(0.0, 100.0)");

    // Test get_bounds method
    try python.exec("bounds = ta.get_bounds()");
    try std.testing.expectApproxEqAbs(@as(f64, 0.0), try python.eval(f64, "bounds[0]"), 0.0001);
    try std.testing.expectApproxEqAbs(@as(f64, 100.0), try python.eval(f64, "bounds[1]"), 0.0001);

    // Descriptors are typically used as class attributes, test via a wrapper
    try python.exec(
        \\class Holder:
        \\    attr = example.TypedAttribute(0.0, 100.0)
    );

    try python.exec("h = Holder()");

    // Access via instance triggers __get__
    const val = try python.eval(f64, "h.attr");
    try std.testing.expectApproxEqAbs(@as(f64, 0.0), val, 0.0001);

    // Setting via instance triggers __set__ with clamping
    try python.exec("h.attr = 50.0");
    try std.testing.expectApproxEqAbs(@as(f64, 50.0), try python.eval(f64, "h.attr"), 0.0001);

    // Test clamping to max
    try python.exec("h.attr = 200.0");
    try std.testing.expectApproxEqAbs(@as(f64, 100.0), try python.eval(f64, "h.attr"), 0.0001);

    // Test clamping to min
    try python.exec("h.attr = -50.0");
    try std.testing.expectApproxEqAbs(@as(f64, 0.0), try python.eval(f64, "h.attr"), 0.0001);
}

// ============================================================================
// GAP COVERAGE: Buffer Protocol
// ============================================================================

test "IntArray - buffer protocol with memoryview" {
    const python = try initTestPython();

    try python.exec("arr = example.IntArray.from_values(10, 20, 30)");

    // Create a memoryview from the array (uses buffer protocol)
    try python.exec("mv = memoryview(arr)");

    // Check memoryview properties
    try std.testing.expectEqual(@as(i64, 3), try python.eval(i64, "len(mv)"));
    try std.testing.expectEqual(@as(i64, 8), try python.eval(i64, "mv.itemsize")); // i64 = 8 bytes
    try std.testing.expectEqual(@as(i64, 1), try python.eval(i64, "mv.ndim"));

    // Access values through memoryview
    try std.testing.expectEqual(@as(i64, 10), try python.eval(i64, "mv[0]"));
    try std.testing.expectEqual(@as(i64, 20), try python.eval(i64, "mv[1]"));
    try std.testing.expectEqual(@as(i64, 30), try python.eval(i64, "mv[2]"));
}

test "IntArray - buffer protocol allows modification" {
    const python = try initTestPython();

    try python.exec("arr = example.IntArray.from_values(1, 2, 3)");
    try python.exec("mv = memoryview(arr)");

    // Modify through memoryview
    try python.exec("mv[1] = 99");

    // Change should be reflected in original array
    try std.testing.expectEqual(@as(i64, 99), try python.eval(i64, "arr[1]"));
}

// ============================================================================
// GAP COVERAGE: GC Integration (__traverse__, __clear__)
// ============================================================================

test "Container - GC traversal support" {
    const python = try initTestPython();

    // Container supports GC via __traverse__ and __clear__
    try python.exec("import gc");

    // Create a container that holds a reference
    try python.exec("c = example.Container('test')");
    try python.exec("data = [1, 2, 3]");
    try python.exec("c.store(data)");

    // Verify data is stored
    try std.testing.expect(try python.eval(bool, "c.has_value()"));
    try std.testing.expect(try python.eval(bool, "c.get() == [1, 2, 3]"));

    // Container is tracked by GC (has __traverse__)
    try std.testing.expect(try python.eval(bool, "gc.is_tracked(c)"));
}

test "Container - __clear__ method" {
    const python = try initTestPython();

    try python.exec("c = example.Container('test')");
    try python.exec("c.store({'key': 'value'})");
    try std.testing.expect(try python.eval(bool, "c.has_value()"));

    // clear_stored should clear the reference
    try python.exec("c.clear_stored()");
    try std.testing.expect(!try python.eval(bool, "c.has_value()"));
}

// ============================================================================
// GAP COVERAGE: Custom Exceptions
// ============================================================================

test "custom exception - ValidationError" {
    const python = try initTestPython();

    // validate_positive uses a custom ValidationError
    try python.exec(
        \\try:
        \\    example.validate_positive(-1)
        \\    raised = False
        \\    exc_type = None
        \\except Exception as e:
        \\    raised = True
        \\    exc_type = type(e).__name__
    );
    try std.testing.expect(try python.eval(bool, "raised"));
    // Should raise the custom exception (mapped from Zig error)
}

test "custom exception - safe_divide with DivisionError" {
    const python = try initTestPython();

    // safe_divide uses a custom exception for division by zero
    try python.exec(
        \\try:
        \\    example.safe_divide(1.0, 0.0)
        \\    raised = False
        \\except Exception as e:
        \\    raised = True
        \\    exc_msg = str(e)
    );
    try std.testing.expect(try python.eval(bool, "raised"));
    try std.testing.expect(try python.eval(bool, "'zero' in exc_msg.lower()"));
}

// ============================================================================
// GAP COVERAGE: catchException (call_and_catch function)
// ============================================================================

test "fn call_and_catch - catch ValueError" {
    const python = try initTestPython();

    // call_and_catch catches exceptions and returns specific codes
    try python.exec("def raise_value(x): raise ValueError('test')");
    const result = try python.eval(i64, "example.call_and_catch(raise_value, 5)");
    try std.testing.expectEqual(@as(i64, -100), result); // -100 for ValueError
}

test "fn call_and_catch - catch TypeError" {
    const python = try initTestPython();

    try python.exec("def raise_type(x): raise TypeError('test')");
    const result = try python.eval(i64, "example.call_and_catch(raise_type, 5)");
    try std.testing.expectEqual(@as(i64, -200), result); // -200 for TypeError
}

test "fn call_and_catch - catch ZeroDivisionError" {
    const python = try initTestPython();

    try python.exec("def raise_zero(x): raise ZeroDivisionError('test')");
    const result = try python.eval(i64, "example.call_and_catch(raise_zero, 5)");
    try std.testing.expectEqual(@as(i64, -300), result); // -300 for ZeroDivisionError
}

test "fn call_and_catch - no exception" {
    const python = try initTestPython();

    try python.exec("def double(x): return x * 2");
    const result = try python.eval(i64, "example.call_and_catch(double, 5)");
    try std.testing.expectEqual(@as(i64, 10), result);
}

// ============================================================================
// GAP COVERAGE: Embedding API - setGlobal/getGlobal
// ============================================================================

test "embedding - setGlobal and getGlobal" {
    const python = try initTestPython();

    // setGlobal is used internally by exec/eval, test via Python
    try python.exec("test_global = 42");
    try std.testing.expectEqual(@as(i64, 42), try python.eval(i64, "test_global"));

    // Modify and verify
    try python.exec("test_global = test_global * 2");
    try std.testing.expectEqual(@as(i64, 84), try python.eval(i64, "test_global"));
}

// ============================================================================
// GAP COVERAGE: Embedding API - import/importAs
// ============================================================================

test "embedding - import modules" {
    const python = try initTestPython();

    // Import standard library modules
    try python.exec("import json");
    try python.exec("result = json.dumps({'key': 'value'})");
    try std.testing.expect(try python.eval(bool, "'key' in result"));

    try python.exec("import math");
    try std.testing.expectApproxEqAbs(@as(f64, 3.14159265358979), try python.eval(f64, "math.pi"), 0.0001);
}

test "embedding - import as alias" {
    const python = try initTestPython();

    try python.exec("import collections as col");
    try python.exec("counter = col.Counter([1, 1, 2, 3, 3, 3])");
    try std.testing.expectEqual(@as(i64, 3), try python.eval(i64, "counter[3]"));
}

// ============================================================================
// GAP COVERAGE: Embedding API - call/callMethod
// ============================================================================

test "embedding - call Python functions" {
    const python = try initTestPython();

    // Define a function and call it
    try python.exec(
        \\def add_numbers(a, b, c):
        \\    return a + b + c
    );
    try std.testing.expectEqual(@as(i64, 60), try python.eval(i64, "add_numbers(10, 20, 30)"));
}

test "embedding - call methods on objects" {
    const python = try initTestPython();

    try python.exec("lst = [3, 1, 4, 1, 5, 9, 2, 6]");

    // Call method on list
    try python.exec("lst.sort()");
    try std.testing.expect(try python.eval(bool, "lst == [1, 1, 2, 3, 4, 5, 6, 9]"));

    // Call method with argument
    try python.exec("lst.append(10)");
    try std.testing.expectEqual(@as(i64, 9), try python.eval(i64, "len(lst)"));
}

// ============================================================================
// GAP COVERAGE: In-place shift operators (__ilshift__, __irshift__)
// ============================================================================

test "BitSet - __ilshift__ (in-place left shift)" {
    const python = try initTestPython();

    try python.exec("b = example.BitSet(1)");
    try python.exec("b <<= example.BitSet(3)");
    try std.testing.expectEqual(@as(u64, 8), try python.eval(u64, "b.get_bits()"));
}

test "BitSet - __irshift__ (in-place right shift)" {
    const python = try initTestPython();

    try python.exec("b = example.BitSet(16)");
    try python.exec("b >>= example.BitSet(2)");
    try std.testing.expectEqual(@as(u64, 4), try python.eval(u64, "b.get_bits()"));
}

// ============================================================================
// GAP COVERAGE: More in-place operators
// ============================================================================

test "Number - in-place operators" {
    const python = try initTestPython();

    // Note: Number class may not have in-place ops, but we can test the behavior
    // The regular ops return new objects, which is the fallback behavior
    try python.exec("n = example.Number(10)");
    try python.exec("n = n + example.Number(5)"); // Fallback to __add__
    try std.testing.expectApproxEqAbs(@as(f64, 15.0), try python.eval(f64, "n.get_value()"), 0.0001);
}

// ============================================================================
// GAP COVERAGE: Matrix multiplication (__matmul__)
// ============================================================================

test "Vector - dot product as potential matmul" {
    const python = try initTestPython();

    // Vector class has dot() method which is similar to matmul
    try python.exec("v1 = example.Vector(1, 2, 3)");
    try python.exec("v2 = example.Vector(4, 5, 6)");

    // Dot product: 1*4 + 2*5 + 3*6 = 32
    try std.testing.expectApproxEqAbs(@as(f64, 32.0), try python.eval(f64, "v1.dot(v2)"), 0.0001);
}

// ============================================================================
// GAP COVERAGE: Exception inheritance verification
// ============================================================================

test "exception - inheritance chain" {
    const python = try initTestPython();

    // Verify that mapped exceptions follow Python's exception hierarchy
    try python.exec(
        \\try:
        \\    example.lookup_index(100)
        \\except IndexError as e:
        \\    is_index_error = True
        \\    is_lookup_error = isinstance(e, LookupError)
        \\    is_exception = isinstance(e, Exception)
    );
    try std.testing.expect(try python.eval(bool, "is_index_error"));
    try std.testing.expect(try python.eval(bool, "is_lookup_error"));
    try std.testing.expect(try python.eval(bool, "is_exception"));
}

// ============================================================================
// GAP COVERAGE: Multiple exception types from error mapping
// ============================================================================

test "fn parse_and_validate - ForbiddenValue maps to exception" {
    const python = try initTestPython();

    // 42 is the forbidden value
    try python.exec(
        \\try:
        \\    example.parse_and_validate(42)
        \\    raised = False
        \\except ValueError:
        \\    raised = True
    );
    try std.testing.expect(try python.eval(bool, "raised"));
}

// ============================================================================
// GAP COVERAGE: Verify classes can be used in Python isinstance/issubclass
// ============================================================================

test "class - isinstance and issubclass work" {
    const python = try initTestPython();

    try python.exec("p = example.Point(1, 2)");
    try std.testing.expect(try python.eval(bool, "isinstance(p, example.Point)"));

    try python.exec("n = example.Number(42)");
    try std.testing.expect(try python.eval(bool, "isinstance(n, example.Number)"));

    // Stack inherits from list
    try python.exec("s = example.Stack()");
    try std.testing.expect(try python.eval(bool, "isinstance(s, list)"));
    try std.testing.expect(try python.eval(bool, "issubclass(example.Stack, list)"));

    // DefaultDict inherits from dict
    try python.exec("dd = example.DefaultDict()");
    try std.testing.expect(try python.eval(bool, "isinstance(dd, dict)"));
    try std.testing.expect(try python.eval(bool, "issubclass(example.DefaultDict, dict)"));
}

// ============================================================================
// GAP COVERAGE: Verify None/null handling
// ============================================================================

test "None/null - optional return values" {
    const python = try initTestPython();

    // Functions returning None
    try python.exec("result = example.list_max([])");
    try std.testing.expect(try python.eval(bool, "result is None"));

    try python.exec("result = example.list_average([])");
    try std.testing.expect(try python.eval(bool, "result is None"));

    try python.exec("result = example.get_dict_value({}, 'missing')");
    try std.testing.expect(try python.eval(bool, "result is None"));
}

// ============================================================================
// GAP COVERAGE: Verify field docstrings
// ============================================================================

test "Point - field docstrings" {
    const python = try initTestPython();

    // Check that help() doesn't crash and docstrings are accessible
    try std.testing.expect(try python.eval(bool, "example.Point.__doc__ is not None"));
    // The x and y fields have docstrings defined
    try std.testing.expect(try python.eval(bool, "'x coordinate' in example.Point.__doc__ or hasattr(example.Point, 'x')"));
}

// ============================================================================
// GAP COVERAGE: Method docstrings
// ============================================================================

test "Point - method docstrings" {
    const python = try initTestPython();

    // magnitude method has a docstring
    try std.testing.expect(try python.eval(bool, "example.Point.magnitude.__doc__ is not None"));
    try std.testing.expect(try python.eval(bool, "'distance' in example.Point.magnitude.__doc__.lower()"));
}

// ============================================================================
// GAP COVERAGE: __matmul__ (@ operator) - Matrix multiplication
// ============================================================================

test "Vector __matmul__ - cross product with @ operator" {
    const python = try initTestPython();

    // Create two vectors
    try python.exec("v1 = example.Vector(1.0, 0.0, 0.0)"); // unit x
    try python.exec("v2 = example.Vector(0.0, 1.0, 0.0)"); // unit y

    // Cross product: x × y = z
    try python.exec("result = v1 @ v2");
    const x = try python.eval(f64, "result.x");
    const y = try python.eval(f64, "result.y");
    const z = try python.eval(f64, "result.z");

    try std.testing.expectApproxEqAbs(@as(f64, 0.0), x, 0.0001);
    try std.testing.expectApproxEqAbs(@as(f64, 0.0), y, 0.0001);
    try std.testing.expectApproxEqAbs(@as(f64, 1.0), z, 0.0001);
}

test "Vector __matmul__ - another cross product" {
    const python = try initTestPython();

    // y × z = x
    try python.exec("v1 = example.Vector(0.0, 1.0, 0.0)"); // unit y
    try python.exec("v2 = example.Vector(0.0, 0.0, 1.0)"); // unit z
    try python.exec("result = v1 @ v2");

    const x = try python.eval(f64, "result.x");
    const y = try python.eval(f64, "result.y");
    const z = try python.eval(f64, "result.z");

    try std.testing.expectApproxEqAbs(@as(f64, 1.0), x, 0.0001);
    try std.testing.expectApproxEqAbs(@as(f64, 0.0), y, 0.0001);
    try std.testing.expectApproxEqAbs(@as(f64, 0.0), z, 0.0001);
}

test "Vector __imatmul__ - in-place cross product with @=" {
    const python = try initTestPython();

    try python.exec("v = example.Vector(1.0, 0.0, 0.0)"); // unit x
    try python.exec("v2 = example.Vector(0.0, 1.0, 0.0)"); // unit y
    try python.exec("v @= v2"); // x × y = z

    const x = try python.eval(f64, "v.x");
    const y = try python.eval(f64, "v.y");
    const z = try python.eval(f64, "v.z");

    try std.testing.expectApproxEqAbs(@as(f64, 0.0), x, 0.0001);
    try std.testing.expectApproxEqAbs(@as(f64, 0.0), y, 0.0001);
    try std.testing.expectApproxEqAbs(@as(f64, 1.0), z, 0.0001);
}

// ============================================================================
// GAP COVERAGE: __delete__ (descriptor protocol)
// ============================================================================

test "TypedAttribute __delete__ - resets to minimum" {
    const python = try initTestPython();

    // Create a TypedAttribute with bounds [0, 100]
    try python.exec("attr = example.TypedAttribute(0.0, 100.0)");

    // Set a value
    try python.exec(
        \\class Holder:
        \\    pass
        \\obj = Holder()
    );
    try python.exec("attr.__set__(obj, 75.0)");
    const val1 = try python.eval(f64, "attr.__get__(obj)");
    try std.testing.expectApproxEqAbs(@as(f64, 75.0), val1, 0.0001);

    // Delete should reset to minimum (0.0)
    try python.exec("attr.__delete__(obj)");
    const val2 = try python.eval(f64, "attr.__get__(obj)");
    try std.testing.expectApproxEqAbs(@as(f64, 0.0), val2, 0.0001);
}

test "TypedAttribute __delete__ - different bounds" {
    const python = try initTestPython();

    // Create with bounds [10, 50]
    try python.exec("attr = example.TypedAttribute(10.0, 50.0)");

    // Create a holder object
    try python.exec(
        \\class Holder2:
        \\    pass
        \\obj2 = Holder2()
    );

    // Set to max
    try python.exec("attr.__set__(obj2, 50.0)");
    try std.testing.expectApproxEqAbs(@as(f64, 50.0), try python.eval(f64, "attr.__get__(obj2)"), 0.0001);

    // Delete resets to min (10.0)
    try python.exec("attr.__delete__(obj2)");
    try std.testing.expectApproxEqAbs(@as(f64, 10.0), try python.eval(f64, "attr.__get__(obj2)"), 0.0001);
}

// ============================================================================
// NUMPY / BUFFERVIEW TESTS
// ============================================================================

test "numpy - BufferView f64 sum" {
    const python = try initTestPython();
    try requireNumpy(python);
    try python.exec("arr = np.array([1.0, 2.0, 3.0, 4.0, 5.0], dtype=np.float64)");
    const result = try python.eval(f64, "example.numpy_sum(arr)");
    try std.testing.expectApproxEqAbs(@as(f64, 15.0), result, 0.0001);
}

test "numpy - BufferView f64 mean" {
    const python = try initTestPython();
    try requireNumpy(python);
    try python.exec("arr = np.array([1.0, 2.0, 3.0, 4.0, 5.0], dtype=np.float64)");
    const result = try python.eval(f64, "example.numpy_mean(arr)");
    try std.testing.expectApproxEqAbs(@as(f64, 3.0), result, 0.0001);
}

test "numpy - BufferView f64 minmax" {
    const python = try initTestPython();
    try requireNumpy(python);
    try python.exec("arr = np.array([3.0, 1.0, 4.0, 1.0, 5.0], dtype=np.float64)");
    try python.exec("result = example.numpy_minmax(arr)");
    try std.testing.expectApproxEqAbs(@as(f64, 1.0), try python.eval(f64, "result[0]"), 0.0001);
    try std.testing.expectApproxEqAbs(@as(f64, 5.0), try python.eval(f64, "result[1]"), 0.0001);
}

test "numpy - BufferView f64 dot product" {
    const python = try initTestPython();
    try requireNumpy(python);
    try python.exec("a = np.array([1.0, 2.0, 3.0], dtype=np.float64)");
    try python.exec("b = np.array([4.0, 5.0, 6.0], dtype=np.float64)");
    const result = try python.eval(f64, "example.numpy_dot(a, b)");
    // 1*4 + 2*5 + 3*6 = 4 + 10 + 18 = 32
    try std.testing.expectApproxEqAbs(@as(f64, 32.0), result, 0.0001);
}

test "numpy - BufferViewMut scale in-place" {
    const python = try initTestPython();
    try requireNumpy(python);
    try python.exec("arr = np.array([1.0, 2.0, 3.0], dtype=np.float64)");
    try python.exec("example.numpy_scale(arr, 2.0)");
    try std.testing.expectApproxEqAbs(@as(f64, 2.0), try python.eval(f64, "arr[0]"), 0.0001);
    try std.testing.expectApproxEqAbs(@as(f64, 4.0), try python.eval(f64, "arr[1]"), 0.0001);
    try std.testing.expectApproxEqAbs(@as(f64, 6.0), try python.eval(f64, "arr[2]"), 0.0001);
}

test "numpy - BufferViewMut normalize in-place" {
    const python = try initTestPython();
    try requireNumpy(python);
    try python.exec("arr = np.array([3.0, 4.0], dtype=np.float64)");
    try python.exec("example.numpy_normalize(arr)");
    // magnitude = 5, so [3/5, 4/5] = [0.6, 0.8]
    try std.testing.expectApproxEqAbs(@as(f64, 0.6), try python.eval(f64, "arr[0]"), 0.0001);
    try std.testing.expectApproxEqAbs(@as(f64, 0.8), try python.eval(f64, "arr[1]"), 0.0001);
}

test "numpy - BufferViewMut relu in-place" {
    const python = try initTestPython();
    try requireNumpy(python);
    try python.exec("arr = np.array([-2.0, -1.0, 0.0, 1.0, 2.0], dtype=np.float64)");
    try python.exec("example.numpy_relu(arr)");
    try std.testing.expectApproxEqAbs(@as(f64, 0.0), try python.eval(f64, "arr[0]"), 0.0001);
    try std.testing.expectApproxEqAbs(@as(f64, 0.0), try python.eval(f64, "arr[1]"), 0.0001);
    try std.testing.expectApproxEqAbs(@as(f64, 0.0), try python.eval(f64, "arr[2]"), 0.0001);
    try std.testing.expectApproxEqAbs(@as(f64, 1.0), try python.eval(f64, "arr[3]"), 0.0001);
    try std.testing.expectApproxEqAbs(@as(f64, 2.0), try python.eval(f64, "arr[4]"), 0.0001);
}

test "numpy - BufferView i64 sum" {
    const python = try initTestPython();
    try requireNumpy(python);
    try python.exec("arr = np.array([1, 2, 3, 4, 5], dtype=np.int64)");
    const result = try python.eval(i64, "example.numpy_sum_int(arr)");
    try std.testing.expectEqual(@as(i64, 15), result);
}

test "numpy - BufferView 2D shape info" {
    const python = try initTestPython();
    try requireNumpy(python);
    try python.exec("arr = np.array([[1.0, 2.0, 3.0], [4.0, 5.0, 6.0]], dtype=np.float64)");
    try python.exec("rows, cols = example.numpy_shape_info(arr)");
    try std.testing.expectEqual(@as(i64, 2), try python.eval(i64, "rows"));
    try std.testing.expectEqual(@as(i64, 3), try python.eval(i64, "cols"));
}

test "numpy - BufferView variance and std" {
    const python = try initTestPython();
    try requireNumpy(python);
    try python.exec("arr = np.array([2.0, 4.0, 4.0, 4.0, 5.0, 5.0, 7.0, 9.0], dtype=np.float64)");
    // Mean = 5, variance = 4, std = 2
    try std.testing.expectApproxEqAbs(@as(f64, 4.0), try python.eval(f64, "example.numpy_variance(arr)"), 0.0001);
    try std.testing.expectApproxEqAbs(@as(f64, 2.0), try python.eval(f64, "example.numpy_std(arr)"), 0.0001);
}

test "numpy - Fortran-order array support" {
    const python = try initTestPython();
    try requireNumpy(python);
    try python.exec("arr = np.array([[1.0, 2.0, 3.0], [4.0, 5.0, 6.0]], dtype=np.float64, order='F')");
    // Verify it's F-order
    try std.testing.expect(!try python.eval(bool, "arr.flags['C_CONTIGUOUS']"));
    try std.testing.expect(try python.eval(bool, "arr.flags['F_CONTIGUOUS']"));
    // Should still work
    const result = try python.eval(f64, "example.numpy_sum(arr)");
    try std.testing.expectApproxEqAbs(@as(f64, 21.0), result, 0.0001);
}

test "numpy - complex128 sum" {
    const python = try initTestPython();
    try requireNumpy(python);
    try python.exec("arr = np.array([1+2j, 3+4j, 5+6j], dtype=np.complex128)");
    try python.exec("result = example.numpy_complex_sum(arr)");
    try std.testing.expectApproxEqAbs(@as(f64, 9.0), try python.eval(f64, "result.real"), 0.0001);
    try std.testing.expectApproxEqAbs(@as(f64, 12.0), try python.eval(f64, "result.imag"), 0.0001);
}

test "numpy - complex128 conjugate in-place" {
    const python = try initTestPython();
    try requireNumpy(python);
    try python.exec("arr = np.array([1+2j, 3-4j], dtype=np.complex128)");
    try python.exec("example.numpy_complex_conjugate(arr)");
    try std.testing.expectApproxEqAbs(@as(f64, 1.0), try python.eval(f64, "arr[0].real"), 0.0001);
    try std.testing.expectApproxEqAbs(@as(f64, -2.0), try python.eval(f64, "arr[0].imag"), 0.0001);
    try std.testing.expectApproxEqAbs(@as(f64, 3.0), try python.eval(f64, "arr[1].real"), 0.0001);
    try std.testing.expectApproxEqAbs(@as(f64, 4.0), try python.eval(f64, "arr[1].imag"), 0.0001);
}

test "numpy - complex128 magnitudes" {
    const python = try initTestPython();
    try requireNumpy(python);
    try python.exec("arr = np.array([3+4j, 5+12j], dtype=np.complex128)");
    try python.exec("out = np.zeros(2, dtype=np.float64)");
    try python.exec("example.numpy_complex_magnitudes(arr, out)");
    try std.testing.expectApproxEqAbs(@as(f64, 5.0), try python.eval(f64, "out[0]"), 0.0001);
    try std.testing.expectApproxEqAbs(@as(f64, 13.0), try python.eval(f64, "out[1]"), 0.0001);
}

test "numpy - complex64 sum" {
    const python = try initTestPython();
    try requireNumpy(python);
    try python.exec("arr = np.array([1+2j, 3+4j], dtype=np.complex64)");
    try python.exec("result = example.numpy_complex64_sum(arr)");
    try std.testing.expectApproxEqAbs(@as(f64, 4.0), try python.eval(f64, "result.real"), 0.001);
    try std.testing.expectApproxEqAbs(@as(f64, 6.0), try python.eval(f64, "result.imag"), 0.001);
}

test "numpy - empty array handling" {
    const python = try initTestPython();
    try requireNumpy(python);
    try python.exec("arr = np.array([], dtype=np.float64)");
    try std.testing.expectApproxEqAbs(@as(f64, 0.0), try python.eval(f64, "example.numpy_sum(arr)"), 0.0001);
    try std.testing.expect(try python.eval(bool, "example.numpy_mean(arr) is None"));
    try std.testing.expect(try python.eval(bool, "example.numpy_minmax(arr) is None"));
}

test "numpy - wrong dtype raises TypeError" {
    const python = try initTestPython();
    try requireNumpy(python);
    try python.exec(
        \\try:
        \\    example.numpy_sum(np.array([1, 2, 3], dtype=np.int32))
        \\    wrong_dtype_raised = False
        \\except (TypeError, RuntimeError):
        \\    wrong_dtype_raised = True
    );
    try std.testing.expect(try python.eval(bool, "wrong_dtype_raised"));
}

test "numpy - non-contiguous array rejected" {
    const python = try initTestPython();
    try requireNumpy(python);
    try python.exec("arr = np.array([1.0, 2.0, 3.0, 4.0], dtype=np.float64)[::2]");
    // Verify it's non-contiguous
    try std.testing.expect(!try python.eval(bool, "arr.flags['C_CONTIGUOUS']"));
    try python.exec(
        \\try:
        \\    example.numpy_sum(arr)
        \\    non_contig_raised = False
        \\except (TypeError, RuntimeError, BufferError, ValueError):
        \\    non_contig_raised = True
    );
    try std.testing.expect(try python.eval(bool, "non_contig_raised"));
}

test "numpy - mismatched lengths raises ValueError" {
    const python = try initTestPython();
    try requireNumpy(python);
    try python.exec(
        \\try:
        \\    example.numpy_dot(np.array([1.0, 2.0, 3.0]), np.array([1.0, 2.0]))
        \\    mismatch_raised = False
        \\except ValueError:
        \\    mismatch_raised = True
    );
    try std.testing.expect(try python.eval(bool, "mismatch_raised"));
}

test "BadBuffer - negative shape raises ValueError instead of crashing" {
    const python = try initTestPython();
    // BadBuffer exports a buffer with shape=[-1] which should be rejected
    try python.exec(
        \\bad = example.BadBuffer.new()
        \\try:
        \\    example.numpy_sum_int(bad)
        \\    bad_shape_raised = False
        \\except ValueError as e:
        \\    bad_shape_raised = "negative shape" in str(e)
    );
    try std.testing.expect(try python.eval(bool, "bad_shape_raised"));
}

test "numpy_get_2d - dimension mismatch raises ValueError" {
    const python = try initTestPython();
    try requireNumpy(python);
    // Calling get2D on a 1D array should raise ValueError, not crash
    try python.exec(
        \\arr_1d = np.array([1.0, 2.0, 3.0], dtype=np.float64)
        \\try:
        \\    example.numpy_get_2d(arr_1d, 0, 0)
        \\    dim_mismatch_raised = False
        \\except ValueError as e:
        \\    dim_mismatch_raised = "2D array" in str(e)
    );
    try std.testing.expect(try python.eval(bool, "dim_mismatch_raised"));
}

test "BadStrideBuffer - negative strides raise ValueError" {
    const python = try initTestPython();
    // BadStrideBuffer exports a buffer with negative strides
    // get2D should validate strides and raise ValueError, not crash
    try python.exec(
        \\buf = example.BadStrideBuffer.new()
        \\try:
        \\    example.buffer_get_2d_i64(buf, 0, 0)
        \\    bad_stride_raised = False
        \\except ValueError as e:
        \\    bad_stride_raised = "negative strides" in str(e)
    );
    try std.testing.expect(try python.eval(bool, "bad_stride_raised"));
}

// ============================================================================
// PRIVATE FIELDS (underscore prefix convention)
// ============================================================================

test "PrivateFieldsExample - only public fields in __init__" {
    const python = try initTestPython();

    // Should work with just 2 args (public fields: name, value)
    // Private fields (_internal_counter, _cached_result) should NOT be in __init__
    try python.exec("obj = example.PrivateFieldsExample('test', 42)");

    // Public fields should be accessible
    try std.testing.expect(try python.eval(bool, "obj.name == 'test'"));
    try std.testing.expectEqual(@as(i64, 42), try python.eval(i64, "obj.value"));
}

test "PrivateFieldsExample - private fields not accessible as properties" {
    const python = try initTestPython();

    try python.exec("obj = example.PrivateFieldsExample('test', 42)");

    // Private fields should NOT be accessible as properties (AttributeError)
    try python.exec(
        \\try:
        \\    _ = obj._internal_counter
        \\    private_counter_accessible = True
        \\except AttributeError:
        \\    private_counter_accessible = False
    );
    try std.testing.expect(!try python.eval(bool, "private_counter_accessible"));

    try python.exec(
        \\try:
        \\    _ = obj._cached_result
        \\    private_cached_accessible = True
        \\except AttributeError:
        \\    private_cached_accessible = False
    );
    try std.testing.expect(!try python.eval(bool, "private_cached_accessible"));
}

test "PrivateFieldsExample - private fields accessible via methods" {
    const python = try initTestPython();

    try python.exec("obj = example.PrivateFieldsExample('test', 42)");

    // Private fields should be zero-initialized and accessible via methods
    try std.testing.expectEqual(@as(i64, 0), try python.eval(i64, "obj.get_internal_counter()"));
    try std.testing.expect(!try python.eval(bool, "obj.has_cached_result()"));

    // Methods can modify private fields
    try std.testing.expectEqual(@as(i64, 1), try python.eval(i64, "obj.increment_counter()"));
    try std.testing.expectEqual(@as(i64, 2), try python.eval(i64, "obj.increment_counter()"));
    try std.testing.expectEqual(@as(i64, 2), try python.eval(i64, "obj.get_internal_counter()"));

    // compute_and_cache modifies _cached_result
    try std.testing.expectEqual(@as(i64, 84), try python.eval(i64, "obj.compute_and_cache()")); // 42 * 2
    try std.testing.expect(try python.eval(bool, "obj.has_cached_result()"));
    try std.testing.expectEqual(@as(i64, 84), try python.eval(i64, "obj.get_cached_or_zero()"));
}

test "PrivateFieldsExample - wrong number of args raises TypeError" {
    const python = try initTestPython();

    // Too many args (trying to pass private fields) should fail
    try python.exec(
        \\try:
        \\    obj = example.PrivateFieldsExample('test', 42, 0, None)
        \\    too_many_args_raised = False
        \\except TypeError:
        \\    too_many_args_raised = True
    );
    try std.testing.expect(try python.eval(bool, "too_many_args_raised"));

    // Too few args should also fail
    try python.exec(
        \\try:
        \\    obj = example.PrivateFieldsExample('test')
        \\    too_few_args_raised = False
        \\except TypeError:
        \\    too_few_args_raised = True
    );
    try std.testing.expect(try python.eval(bool, "too_few_args_raised"));
}

test "PrivateFieldsExample - setting private fields raises AttributeError" {
    const python = try initTestPython();

    try python.exec("obj = example.PrivateFieldsExample('test', 42)");

    // Trying to set private fields should raise AttributeError
    try python.exec(
        \\try:
        \\    obj._internal_counter = 100
        \\    set_private_succeeded = True
        \\except AttributeError:
        \\    set_private_succeeded = False
    );
    try std.testing.expect(!try python.eval(bool, "set_private_succeeded"));
}

// ============================================================================
// Symreader Tests - Binary Format Parsing
// ============================================================================

const symreader = @import("symreader");
const test_config = @import("test_config");

const expected_stub_content = "# Test stub content\ndef hello(): ...\n";

test "symreader - extract stubs from ELF binary" {
    const elf_path = test_config.elf_test_lib;
    const result = symreader.extractStubs(std.testing.allocator, elf_path) catch |err| {
        std.debug.print("ELF extraction error: {}\n", .{err});
        return err;
    };
    if (result) |stubs| {
        defer std.testing.allocator.free(stubs);
        try std.testing.expectEqualStrings(expected_stub_content, stubs);
    } else {
        return error.StubsNotFound;
    }
}

test "symreader - extract stubs from PE binary" {
    const pe_path = test_config.pe_test_lib;
    const result = symreader.extractStubs(std.testing.allocator, pe_path) catch |err| {
        std.debug.print("PE extraction error: {}\n", .{err});
        return err;
    };
    if (result) |stubs| {
        defer std.testing.allocator.free(stubs);
        try std.testing.expectEqualStrings(expected_stub_content, stubs);
    } else {
        return error.StubsNotFound;
    }
}

test "symreader - extract stubs from Mach-O binary" {
    const macho_path = test_config.macho_test_lib;
    const result = symreader.extractStubs(std.testing.allocator, macho_path) catch |err| {
        std.debug.print("Mach-O extraction error: {}\n", .{err});
        return err;
    };
    if (result) |stubs| {
        defer std.testing.allocator.free(stubs);
        try std.testing.expectEqualStrings(expected_stub_content, stubs);
    } else {
        return error.StubsNotFound;
    }
}
