//! Enum Support
//!
//! Provides types for exposing Zig enums as Python IntEnum and StrEnum.
//! Auto-detects whether an enum should be IntEnum or StrEnum based on
//! whether it has an explicit integer tag type.

const std = @import("std");

/// Unified enum definition for the module
/// Auto-detects IntEnum vs StrEnum based on tag type
pub const EnumDef = struct {
    /// Name of the enum in Python (e.g., "Color")
    name: [*:0]const u8,
    /// The Zig enum type
    zig_type: type,
    /// Whether this is a string enum (auto-detected)
    is_str_enum: bool,
};

/// Check if an enum type has an explicit integer tag type
fn isIntEnum(comptime E: type) bool {
    const info = @typeInfo(E);
    if (info != .@"enum") {
        @compileError("Expected enum type");
    }
    // If tag_type is not the default (usize-based), it's an int enum
    // Enums like `enum(i32)` have explicit tag, plain `enum` does not
    const tag_type = info.@"enum".tag_type;
    // Check if it's one of the common explicit int types
    return tag_type == i8 or tag_type == i16 or tag_type == i32 or tag_type == i64 or
        tag_type == u8 or tag_type == u16 or tag_type == u32 or tag_type == u64 or
        tag_type == isize or tag_type == c_int or tag_type == c_long;
}

/// Create an enum definition from a Zig enum type
/// Auto-detects whether it should be IntEnum or StrEnum:
/// - `enum(i32)` -> IntEnum (explicit integer tag)
/// - `enum` -> StrEnum (no explicit tag, field names become values)
pub fn enumDef(comptime name: [*:0]const u8, comptime E: type) EnumDef {
    return .{
        .name = name,
        .zig_type = E,
        .is_str_enum = !isIntEnum(E),
    };
}

// Legacy aliases for backwards compatibility (deprecated)
pub const StrEnumDef = EnumDef;

/// Legacy function - use enumDef instead (deprecated)
pub fn strEnumDef(comptime name: [*:0]const u8, comptime E: type) EnumDef {
    return .{
        .name = name,
        .zig_type = E,
        .is_str_enum = true, // Force string enum for legacy usage
    };
}
