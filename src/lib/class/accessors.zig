//! The `get_X` / `set_X` naming convention for properties.
//!
//! One definition shared by the property table (properties.zig), the method
//! table (methods.zig) and stub generation (stubs.zig), so they always agree
//! on what is a property and what is a method.
//!
//! A getter is `get_X(self)` and a setter is `set_X(self, value)`. Functions
//! with those names but other parameter lists, such as `get_item(self, index)`,
//! are ordinary methods.

const std = @import("std");

fn paramCount(comptime T: type, comptime decl_name: []const u8) ?usize {
    const info = @typeInfo(@TypeOf(@field(T, decl_name)));
    // Not a function: e.g. a `get_error__doc__` docstring constant
    return if (info == .@"fn") info.@"fn".params.len else null;
}

/// `decl_name` is a property getter: `get_X(self)`.
pub fn isGetter(comptime T: type, comptime decl_name: []const u8) bool {
    if (decl_name.len <= 4 or !std.mem.startsWith(u8, decl_name, "get_")) return false;
    return paramCount(T, decl_name) == 1;
}

/// `T` has a getter for property or field `name`.
pub fn hasGetter(comptime T: type, comptime name: []const u8) bool {
    return @hasDecl(T, "get_" ++ name) and isGetter(T, "get_" ++ name);
}

/// `T` has a `set_X(self, value)` function for property or field `name`.
pub fn hasSetter(comptime T: type, comptime name: []const u8) bool {
    return @hasDecl(T, "set_" ++ name) and paramCount(T, "set_" ++ name) == 2;
}

/// `decl_name` is a property setter: `set_X(self, value)` where X has a
/// getter or is a struct field.
pub fn isSetter(comptime T: type, comptime decl_name: []const u8) bool {
    if (decl_name.len <= 4 or !std.mem.startsWith(u8, decl_name, "set_")) return false;
    const name = decl_name[4..];
    if (!hasSetter(T, name)) return false;
    return hasGetter(T, name) or @hasField(T, name);
}

/// `decl_name` is a property getter or setter, not a method.
pub fn isAccessor(comptime T: type, comptime decl_name: []const u8) bool {
    return isGetter(T, decl_name) or isSetter(T, decl_name);
}
