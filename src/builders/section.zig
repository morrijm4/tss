const std = @import("std");
const macho = @import("../macho.zig");

pub const Builder = @This();

header: macho.Section64,
section: std.ArrayList(u32),

pub fn init() Builder {
    return .{
        .header = std.mem.zeroes(macho.Section64),
        .section = .empty,
    };
}

pub fn deinit(self: *Builder, allocator: std.mem.Allocator) void {
    self.section.deinit(allocator);
    self.section = .empty;
}

pub fn setSectionName(self: *Builder, comptime name: []const u8) *Builder {
    comptime if (name.len > 16) @compileError("Segment name '" ++ name ++ "' exceeds 16 bytes.");
    self.header.sectname = @splat(0);
    @memcpy(self.header.sectname[0..name.len], name);
    return self;
}

pub fn setSegmentName(self: *Builder, comptime name: []const u8) *Builder {
    comptime if (name.len > 16) @compileError("Segment name '" ++ name ++ "' exceeds 16 bytes.");
    self.header.segname = @splat(0);
    @memcpy(self.header.segname[0..name.len], name);
    return self;
}

pub fn setAddress(self: *Builder, addr: u64) *Builder {
    self.header.addr = addr;
    return self;
}

pub fn setAlignment(self: *Builder, alignment: u32) *Builder {
    self.header.@"align" = alignment;
    return self;
}

pub fn setFlags(self: *Builder, flags: u32) *Builder {
    self.header.flags = flags;
    return self;
}

pub fn addInstruction(self: *Builder, allocator: std.mem.Allocator, inst: u32) std.mem.Allocator.Error!void {
    try self.section.append(allocator, inst);
    self.header.size += @sizeOf(u32);
}

/// Returns number of bytes to extend the offset
pub fn writeHeader(self: *Builder, w: *std.Io.Writer, offset: u64) std.Io.Writer.Error!u64 {
    self.header.offset = @intCast(offset); // TODO: why do I have to cast this?
    try w.writeAll(std.mem.asBytes(&self.header));
    return offset + self.header.size;
}

pub fn writeData(self: *const Builder, w: *std.Io.Writer) std.Io.Writer.Error!void {
    try w.writeAll(std.mem.sliceAsBytes(self.section.items));
}

test "can create a section" {
    var buf: [512]u8 = undefined;
    var writer = std.Io.Writer.fixed(&buf);
    var reader = std.Io.Reader.fixed(&buf);

    const gpa = std.testing.allocator;
    var section = init();
    defer section.deinit(gpa);

    _ = try section
        .setSectionName("__text")
        .setSegmentName("__TEXT")
        .setAlignment(2)
        .setAddress(0)
        .writeHeader(&writer, 0);
    try section.addInstruction(gpa, 0xd28008a0);
    try section.addInstruction(gpa, 0xd2800030);
    try section.addInstruction(gpa, 0xd4001001);

    const sect = try reader.takeStruct(macho.Section64, .native);
    try std.testing.expectEqualStrings("__text", sect.sectName());
    try std.testing.expectEqualStrings("__TEXT", sect.segName());
    try std.testing.expectEqual(section.section.items.len, 3);
    try std.testing.expectEqual(section.header.size, 12);
}
