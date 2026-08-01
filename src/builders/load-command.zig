const std = @import("std");
const seg = @import("./segment.zig");
const bv = @import("./build-version.zig");

pub const LoadCommand = enum {
    segment,
    build_version,
};

pub const Builder = union(LoadCommand) {
    segment: seg.Builder,
    build_version: bv.Builder,

    pub fn deinit(self: *Builder, gpa: std.mem.Allocator) void {
        switch (self.*) {
            .segment => |*lc| lc.deinit(gpa),
            else => {},
        }
    }

    pub fn getSize(self: *const Builder) u32 {
        switch (self.*) {
            .segment => |lc| return lc.header.cmdsize,
            .build_version => |lc| return lc.header.cmdsize,
        }
    }

    pub fn writeCommand(self: *Builder, writer: *std.Io.Writer, offset: u64) std.Io.Writer.Error!u64 {
        try switch (self.*) {
            .segment => |*lc| return lc.writeCommand(writer, offset),
            .build_version => |*lc| return lc.writeCommand(writer, offset),
        };
    }

    pub fn writeData(self: *const Builder, writer: *std.Io.Writer) std.Io.Writer.Error!void {
        try switch (self.*) {
            .segment => |lc| lc.writeData(writer),
            else => {},
        };
    }
};

pub fn init(lc: LoadCommand) Builder {
    switch (lc) {
        .segment => return .{ .segment = seg.init() },
        .build_version => return .{ .build_version = bv.init() },
    }
}
