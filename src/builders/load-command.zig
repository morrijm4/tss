const std = @import("std");
const Io = std.Io;

const seg = @import("./segment.zig");
const bv = @import("./build-version.zig");
const sym = @import("./symbol-table.zig");
const dysym = @import("./dynamic-symbol-table.zig");

pub const LoadCommand = enum {
    segment,
    build_version,
    symbol_table,
    dynamic_symbol_table,
};

pub const Builder = union(LoadCommand) {
    segment: seg.Builder,
    build_version: bv.Builder,
    symbol_table: sym.Builder,
    dynamic_symbol_table: dysym.Builder,

    pub fn deinit(self: *Builder, gpa: std.mem.Allocator) void {
        switch (self.*) {
            .segment => |*lc| lc.deinit(gpa),
            .symbol_table => |*lc| lc.deinit(gpa),
            else => {},
        }
    }

    pub fn getSize(self: *const Builder) u32 {
        switch (self.*) {
            .segment => |*lc| return lc.header.cmdsize,
            .build_version => |*lc| return lc.header.cmdsize,
            .symbol_table => |*lc| return lc.header.cmdsize,
            .dynamic_symbol_table => |*lc| return lc.header.cmdsize,
        }
    }

    pub fn writeCommand(self: *Builder, w: *Io.Writer, off: u64) Io.Writer.Error!u64 {
        try switch (self.*) {
            .segment => |*lc| return lc.writeCommand(w, off),
            .build_version => |*lc| lc.writeCommand(w),
            .symbol_table => |*lc| return lc.writeCommand(w, off),
            .dynamic_symbol_table => |*lc| lc.writeCommand(w),
        };

        return 0;
    }

    pub fn writeData(self: *const Builder, writer: *Io.Writer) Io.Writer.Error!void {
        try switch (self.*) {
            .segment => |*lc| lc.writeData(writer),
            .symbol_table => |*lc| lc.writeData(writer),
            else => {},
        };
    }
};

pub fn init(lc: LoadCommand) Builder {
    switch (lc) {
        .segment => return .{ .segment = seg.init() },
        .build_version => return .{ .build_version = bv.init() },
        .symbol_table => return .{ .symbol_table = sym.init() },
        .dynamic_symbol_table => return .{ .dynamic_symbol_table = dysym.init() },
    }
}
