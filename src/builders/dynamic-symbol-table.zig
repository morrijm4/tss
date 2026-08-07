const std = @import("std");
const Io = std.Io;

const macho = @import("../macho.zig");

pub const Builder = @This();

header: macho.DynamicSymbolTableCommand,

pub fn init() Builder {
    return .{ .header = .{} };
}

pub fn setLocalIndex(self: *Builder, index: u32) void {
    self.header.ilocalsym = index;
}

pub fn setLocalCount(self: *Builder, count: u32) void {
    self.header.nlocalsym = count;
}

pub fn setExternalIndex(self: *Builder, index: u32) void {
    self.header.iextdefsym = index;
}

pub fn setExternalCount(self: *Builder, count: u32) void {
    self.header.nextdefsym = count;
}

pub fn setUndefinedIndex(self: *Builder, index: u32) void {
    self.header.iundefsym = index;
}

pub fn setUndefinedCount(self: *Builder, count: u32) void {
    self.header.nundefsym = count;
}

pub fn writeCommand(self: *const Builder, w: *Io.Writer) Io.Writer.Error!void {
    try w.writeStruct(self.header, .native);
}
