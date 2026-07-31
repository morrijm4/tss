const std = @import("std");
const seg = @import("./segment.zig");

pub const LoadCommand = enum {
    segment,
};

pub const Builder = union(LoadCommand) {
    segment: seg.Builder,

    pub fn deinit(self: *Builder, gpa: std.mem.Allocator) void {
        switch (self.*) {
            .segment => |*lc| lc.deinit(gpa),
        }
    }

    pub fn getSize(self: *const Builder) u32 {
        switch (self.*) {
            .segment => |lc| return lc.header.cmdsize,
        }
    }

    pub fn writeCommand(self: *Builder, writer: *std.Io.Writer, offset: u64) std.Io.Writer.Error!u64 {
        try switch (self.*) {
            .segment => |*lc| return lc.writeCommand(writer, offset),
        };
    }

    pub fn writeData(self: *const Builder, writer: *std.Io.Writer) std.Io.Writer.Error!void {
        try switch (self.*) {
            .segment => |lc| lc.writeData(writer),
        };
    }
};

pub fn init(lc: LoadCommand) Builder {
    switch (lc) {
        .segment => return .{ .segment = seg.init() },
    }
}
