//! Regression example: a class with many documented methods.

/// PyOZ builds the signature and docstring text of every method at compile
/// time, in one evaluation for the whole class, so the cost adds up. A class
/// like this one used to exceed Zig's comptime branch quota, which the user
/// could not raise from their own code.
pub const WideClass = struct {
    v: i64,

    pub const read_0__doc__: [*:0]const u8 = "Return (v + offset + 0) * scale; scale defaults to 1 and data is unused. " ++
        "The text is long on purpose: its cost counts against the class's compile-time budget.";
    pub fn read_0(self: *const WideClass, data: []const u8, offset: i64, scale: ?i64) i64 {
        _ = data;
        return (self.v + offset + 0) * (scale orelse 1);
    }

    pub const read_1__doc__: [*:0]const u8 = "Return (v + offset + 1) * scale; scale defaults to 1 and data is unused. " ++
        "The text is long on purpose: its cost counts against the class's compile-time budget.";
    pub fn read_1(self: *const WideClass, data: []const u8, offset: i64, scale: ?i64) i64 {
        _ = data;
        return (self.v + offset + 1) * (scale orelse 1);
    }

    pub const read_2__doc__: [*:0]const u8 = "Return (v + offset + 2) * scale; scale defaults to 1 and data is unused. " ++
        "The text is long on purpose: its cost counts against the class's compile-time budget.";
    pub fn read_2(self: *const WideClass, data: []const u8, offset: i64, scale: ?i64) i64 {
        _ = data;
        return (self.v + offset + 2) * (scale orelse 1);
    }

    pub const read_3__doc__: [*:0]const u8 = "Return (v + offset + 3) * scale; scale defaults to 1 and data is unused. " ++
        "The text is long on purpose: its cost counts against the class's compile-time budget.";
    pub fn read_3(self: *const WideClass, data: []const u8, offset: i64, scale: ?i64) i64 {
        _ = data;
        return (self.v + offset + 3) * (scale orelse 1);
    }

    pub const read_4__doc__: [*:0]const u8 = "Return (v + offset + 4) * scale; scale defaults to 1 and data is unused. " ++
        "The text is long on purpose: its cost counts against the class's compile-time budget.";
    pub fn read_4(self: *const WideClass, data: []const u8, offset: i64, scale: ?i64) i64 {
        _ = data;
        return (self.v + offset + 4) * (scale orelse 1);
    }

    pub const read_5__doc__: [*:0]const u8 = "Return (v + offset + 5) * scale; scale defaults to 1 and data is unused. " ++
        "The text is long on purpose: its cost counts against the class's compile-time budget.";
    pub fn read_5(self: *const WideClass, data: []const u8, offset: i64, scale: ?i64) i64 {
        _ = data;
        return (self.v + offset + 5) * (scale orelse 1);
    }

    pub const read_6__doc__: [*:0]const u8 = "Return (v + offset + 6) * scale; scale defaults to 1 and data is unused. " ++
        "The text is long on purpose: its cost counts against the class's compile-time budget.";
    pub fn read_6(self: *const WideClass, data: []const u8, offset: i64, scale: ?i64) i64 {
        _ = data;
        return (self.v + offset + 6) * (scale orelse 1);
    }

    pub const read_7__doc__: [*:0]const u8 = "Return (v + offset + 7) * scale; scale defaults to 1 and data is unused. " ++
        "The text is long on purpose: its cost counts against the class's compile-time budget.";
    pub fn read_7(self: *const WideClass, data: []const u8, offset: i64, scale: ?i64) i64 {
        _ = data;
        return (self.v + offset + 7) * (scale orelse 1);
    }

    pub const read_8__doc__: [*:0]const u8 = "Return (v + offset + 8) * scale; scale defaults to 1 and data is unused. " ++
        "The text is long on purpose: its cost counts against the class's compile-time budget.";
    pub fn read_8(self: *const WideClass, data: []const u8, offset: i64, scale: ?i64) i64 {
        _ = data;
        return (self.v + offset + 8) * (scale orelse 1);
    }

    pub const read_9__doc__: [*:0]const u8 = "Return (v + offset + 9) * scale; scale defaults to 1 and data is unused. " ++
        "The text is long on purpose: its cost counts against the class's compile-time budget.";
    pub fn read_9(self: *const WideClass, data: []const u8, offset: i64, scale: ?i64) i64 {
        _ = data;
        return (self.v + offset + 9) * (scale orelse 1);
    }

    pub const read_10__doc__: [*:0]const u8 = "Return (v + offset + 10) * scale; scale defaults to 1 and data is unused. " ++
        "The text is long on purpose: its cost counts against the class's compile-time budget.";
    pub fn read_10(self: *const WideClass, data: []const u8, offset: i64, scale: ?i64) i64 {
        _ = data;
        return (self.v + offset + 10) * (scale orelse 1);
    }

    pub const read_11__doc__: [*:0]const u8 = "Return (v + offset + 11) * scale; scale defaults to 1 and data is unused. " ++
        "The text is long on purpose: its cost counts against the class's compile-time budget.";
    pub fn read_11(self: *const WideClass, data: []const u8, offset: i64, scale: ?i64) i64 {
        _ = data;
        return (self.v + offset + 11) * (scale orelse 1);
    }

    pub const read_12__doc__: [*:0]const u8 = "Return (v + offset + 12) * scale; scale defaults to 1 and data is unused. " ++
        "The text is long on purpose: its cost counts against the class's compile-time budget.";
    pub fn read_12(self: *const WideClass, data: []const u8, offset: i64, scale: ?i64) i64 {
        _ = data;
        return (self.v + offset + 12) * (scale orelse 1);
    }

    pub const read_13__doc__: [*:0]const u8 = "Return (v + offset + 13) * scale; scale defaults to 1 and data is unused. " ++
        "The text is long on purpose: its cost counts against the class's compile-time budget.";
    pub fn read_13(self: *const WideClass, data: []const u8, offset: i64, scale: ?i64) i64 {
        _ = data;
        return (self.v + offset + 13) * (scale orelse 1);
    }

    pub const read_14__doc__: [*:0]const u8 = "Return (v + offset + 14) * scale; scale defaults to 1 and data is unused. " ++
        "The text is long on purpose: its cost counts against the class's compile-time budget.";
    pub fn read_14(self: *const WideClass, data: []const u8, offset: i64, scale: ?i64) i64 {
        _ = data;
        return (self.v + offset + 14) * (scale orelse 1);
    }

    pub const read_15__doc__: [*:0]const u8 = "Return (v + offset + 15) * scale; scale defaults to 1 and data is unused. " ++
        "The text is long on purpose: its cost counts against the class's compile-time budget.";
    pub fn read_15(self: *const WideClass, data: []const u8, offset: i64, scale: ?i64) i64 {
        _ = data;
        return (self.v + offset + 15) * (scale orelse 1);
    }

    pub const read_16__doc__: [*:0]const u8 = "Return (v + offset + 16) * scale; scale defaults to 1 and data is unused. " ++
        "The text is long on purpose: its cost counts against the class's compile-time budget.";
    pub fn read_16(self: *const WideClass, data: []const u8, offset: i64, scale: ?i64) i64 {
        _ = data;
        return (self.v + offset + 16) * (scale orelse 1);
    }

    pub const read_17__doc__: [*:0]const u8 = "Return (v + offset + 17) * scale; scale defaults to 1 and data is unused. " ++
        "The text is long on purpose: its cost counts against the class's compile-time budget.";
    pub fn read_17(self: *const WideClass, data: []const u8, offset: i64, scale: ?i64) i64 {
        _ = data;
        return (self.v + offset + 17) * (scale orelse 1);
    }

    pub const read_18__doc__: [*:0]const u8 = "Return (v + offset + 18) * scale; scale defaults to 1 and data is unused. " ++
        "The text is long on purpose: its cost counts against the class's compile-time budget.";
    pub fn read_18(self: *const WideClass, data: []const u8, offset: i64, scale: ?i64) i64 {
        _ = data;
        return (self.v + offset + 18) * (scale orelse 1);
    }

    pub const read_19__doc__: [*:0]const u8 = "Return (v + offset + 19) * scale; scale defaults to 1 and data is unused. " ++
        "The text is long on purpose: its cost counts against the class's compile-time budget.";
    pub fn read_19(self: *const WideClass, data: []const u8, offset: i64, scale: ?i64) i64 {
        _ = data;
        return (self.v + offset + 19) * (scale orelse 1);
    }

    pub const read_20__doc__: [*:0]const u8 = "Return (v + offset + 20) * scale; scale defaults to 1 and data is unused. " ++
        "The text is long on purpose: its cost counts against the class's compile-time budget.";
    pub fn read_20(self: *const WideClass, data: []const u8, offset: i64, scale: ?i64) i64 {
        _ = data;
        return (self.v + offset + 20) * (scale orelse 1);
    }

    pub const read_21__doc__: [*:0]const u8 = "Return (v + offset + 21) * scale; scale defaults to 1 and data is unused. " ++
        "The text is long on purpose: its cost counts against the class's compile-time budget.";
    pub fn read_21(self: *const WideClass, data: []const u8, offset: i64, scale: ?i64) i64 {
        _ = data;
        return (self.v + offset + 21) * (scale orelse 1);
    }

    pub const read_22__doc__: [*:0]const u8 = "Return (v + offset + 22) * scale; scale defaults to 1 and data is unused. " ++
        "The text is long on purpose: its cost counts against the class's compile-time budget.";
    pub fn read_22(self: *const WideClass, data: []const u8, offset: i64, scale: ?i64) i64 {
        _ = data;
        return (self.v + offset + 22) * (scale orelse 1);
    }

    pub const read_23__doc__: [*:0]const u8 = "Return (v + offset + 23) * scale; scale defaults to 1 and data is unused. " ++
        "The text is long on purpose: its cost counts against the class's compile-time budget.";
    pub fn read_23(self: *const WideClass, data: []const u8, offset: i64, scale: ?i64) i64 {
        _ = data;
        return (self.v + offset + 23) * (scale orelse 1);
    }

    pub const read_24__doc__: [*:0]const u8 = "Return (v + offset + 24) * scale; scale defaults to 1 and data is unused. " ++
        "The text is long on purpose: its cost counts against the class's compile-time budget.";
    pub fn read_24(self: *const WideClass, data: []const u8, offset: i64, scale: ?i64) i64 {
        _ = data;
        return (self.v + offset + 24) * (scale orelse 1);
    }

    pub const read_25__doc__: [*:0]const u8 = "Return (v + offset + 25) * scale; scale defaults to 1 and data is unused. " ++
        "The text is long on purpose: its cost counts against the class's compile-time budget.";
    pub fn read_25(self: *const WideClass, data: []const u8, offset: i64, scale: ?i64) i64 {
        _ = data;
        return (self.v + offset + 25) * (scale orelse 1);
    }

    pub const read_26__doc__: [*:0]const u8 = "Return (v + offset + 26) * scale; scale defaults to 1 and data is unused. " ++
        "The text is long on purpose: its cost counts against the class's compile-time budget.";
    pub fn read_26(self: *const WideClass, data: []const u8, offset: i64, scale: ?i64) i64 {
        _ = data;
        return (self.v + offset + 26) * (scale orelse 1);
    }

    pub const read_27__doc__: [*:0]const u8 = "Return (v + offset + 27) * scale; scale defaults to 1 and data is unused. " ++
        "The text is long on purpose: its cost counts against the class's compile-time budget.";
    pub fn read_27(self: *const WideClass, data: []const u8, offset: i64, scale: ?i64) i64 {
        _ = data;
        return (self.v + offset + 27) * (scale orelse 1);
    }

    pub const read_28__doc__: [*:0]const u8 = "Return (v + offset + 28) * scale; scale defaults to 1 and data is unused. " ++
        "The text is long on purpose: its cost counts against the class's compile-time budget.";
    pub fn read_28(self: *const WideClass, data: []const u8, offset: i64, scale: ?i64) i64 {
        _ = data;
        return (self.v + offset + 28) * (scale orelse 1);
    }

    pub const read_29__doc__: [*:0]const u8 = "Return (v + offset + 29) * scale; scale defaults to 1 and data is unused. " ++
        "The text is long on purpose: its cost counts against the class's compile-time budget.";
    pub fn read_29(self: *const WideClass, data: []const u8, offset: i64, scale: ?i64) i64 {
        _ = data;
        return (self.v + offset + 29) * (scale orelse 1);
    }

    pub const read_30__doc__: [*:0]const u8 = "Return (v + offset + 30) * scale; scale defaults to 1 and data is unused. " ++
        "The text is long on purpose: its cost counts against the class's compile-time budget.";
    pub fn read_30(self: *const WideClass, data: []const u8, offset: i64, scale: ?i64) i64 {
        _ = data;
        return (self.v + offset + 30) * (scale orelse 1);
    }

    pub const read_31__doc__: [*:0]const u8 = "Return (v + offset + 31) * scale; scale defaults to 1 and data is unused. " ++
        "The text is long on purpose: its cost counts against the class's compile-time budget.";
    pub fn read_31(self: *const WideClass, data: []const u8, offset: i64, scale: ?i64) i64 {
        _ = data;
        return (self.v + offset + 31) * (scale orelse 1);
    }

    pub const read_32__doc__: [*:0]const u8 = "Return (v + offset + 32) * scale; scale defaults to 1 and data is unused. " ++
        "The text is long on purpose: its cost counts against the class's compile-time budget.";
    pub fn read_32(self: *const WideClass, data: []const u8, offset: i64, scale: ?i64) i64 {
        _ = data;
        return (self.v + offset + 32) * (scale orelse 1);
    }

    pub const read_33__doc__: [*:0]const u8 = "Return (v + offset + 33) * scale; scale defaults to 1 and data is unused. " ++
        "The text is long on purpose: its cost counts against the class's compile-time budget.";
    pub fn read_33(self: *const WideClass, data: []const u8, offset: i64, scale: ?i64) i64 {
        _ = data;
        return (self.v + offset + 33) * (scale orelse 1);
    }

    pub const read_34__doc__: [*:0]const u8 = "Return (v + offset + 34) * scale; scale defaults to 1 and data is unused. " ++
        "The text is long on purpose: its cost counts against the class's compile-time budget.";
    pub fn read_34(self: *const WideClass, data: []const u8, offset: i64, scale: ?i64) i64 {
        _ = data;
        return (self.v + offset + 34) * (scale orelse 1);
    }

    pub const read_35__doc__: [*:0]const u8 = "Return (v + offset + 35) * scale; scale defaults to 1 and data is unused. " ++
        "The text is long on purpose: its cost counts against the class's compile-time budget.";
    pub fn read_35(self: *const WideClass, data: []const u8, offset: i64, scale: ?i64) i64 {
        _ = data;
        return (self.v + offset + 35) * (scale orelse 1);
    }

    pub const read_36__doc__: [*:0]const u8 = "Return (v + offset + 36) * scale; scale defaults to 1 and data is unused. " ++
        "The text is long on purpose: its cost counts against the class's compile-time budget.";
    pub fn read_36(self: *const WideClass, data: []const u8, offset: i64, scale: ?i64) i64 {
        _ = data;
        return (self.v + offset + 36) * (scale orelse 1);
    }

    pub const read_37__doc__: [*:0]const u8 = "Return (v + offset + 37) * scale; scale defaults to 1 and data is unused. " ++
        "The text is long on purpose: its cost counts against the class's compile-time budget.";
    pub fn read_37(self: *const WideClass, data: []const u8, offset: i64, scale: ?i64) i64 {
        _ = data;
        return (self.v + offset + 37) * (scale orelse 1);
    }

    pub const read_38__doc__: [*:0]const u8 = "Return (v + offset + 38) * scale; scale defaults to 1 and data is unused. " ++
        "The text is long on purpose: its cost counts against the class's compile-time budget.";
    pub fn read_38(self: *const WideClass, data: []const u8, offset: i64, scale: ?i64) i64 {
        _ = data;
        return (self.v + offset + 38) * (scale orelse 1);
    }

    pub const read_39__doc__: [*:0]const u8 = "Return (v + offset + 39) * scale; scale defaults to 1 and data is unused. " ++
        "The text is long on purpose: its cost counts against the class's compile-time budget.";
    pub fn read_39(self: *const WideClass, data: []const u8, offset: i64, scale: ?i64) i64 {
        _ = data;
        return (self.v + offset + 39) * (scale orelse 1);
    }
};
