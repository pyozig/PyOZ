// PyOZ Version - Single source of truth for both library and CLI
// This file is automatically parsed by build.zig for embed and metadata

pub const major: u8 = 0;
pub const minor: u8 = 5;
pub const patch: u8 = 0;

/// Pre-release identifier (e.g., "alpha", "beta", "rc1", or null for release)
pub const pre_release: ?[]const u8 = null;

/// Build metadata (e.g., git commit hash, set at build time)
pub const build_metadata: ?[]const u8 = null;

/// Full semantic version string
pub const string: []const u8 = blk: {
    var buf: []const u8 = std.fmt.comptimePrint("{d}.{d}.{d}", .{ major, minor, patch });
    if (pre_release) |pre| {
        buf = buf ++ "-" ++ pre;
    }
    if (build_metadata) |meta| {
        buf = buf ++ "+" ++ meta;
    }
    break :blk buf;
};

/// Version as a single integer for easy comparison: major * 10000 + minor * 100 + patch
pub const code: u32 = @as(u32, major) * 10000 + @as(u32, minor) * 100 + @as(u32, patch);

const std = @import("std");

/// Compare this version against another
pub const Ordering = enum { less, equal, greater };

pub fn compare(other_major: u8, other_minor: u8, other_patch: u8) Ordering {
    const other_code: u32 = @as(u32, other_major) * 10000 + @as(u32, other_minor) * 100 + @as(u32, other_patch);
    if (code < other_code) return .less;
    if (code > other_code) return .greater;
    return .equal;
}

/// Check if this version is at least the given version
pub fn isAtLeast(min_major: u8, min_minor: u8, min_patch: u8) bool {
    return compare(min_major, min_minor, min_patch) != .less;
}

test "version string format" {
    const testing = std.testing;
    // Basic format check
    try testing.expect(string.len > 0);
    try testing.expect(std.mem.indexOf(u8, string, ".") != null);
}

test "version comparison" {
    const testing = std.testing;
    try testing.expect(compare(0, 5, 0) == .equal);
    try testing.expect(compare(0, 4, 0) == .greater);
    try testing.expect(compare(1, 0, 0) == .less);
    try testing.expect(isAtLeast(0, 5, 0));
    try testing.expect(isAtLeast(0, 4, 0));
    try testing.expect(!isAtLeast(1, 0, 0));
}
