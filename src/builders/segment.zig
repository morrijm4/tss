const std = @import("std");
const macho = @import("../macho.zig");
const sect = @import("./section.zig");

const Io = std.Io;
const mem = std.mem;

pub const Builder = @This();

pub const Error = mem.Allocator.Error || sect.Error;

header: macho.SegmentCommand64,
sections: std.ArrayList(sect.Builder),

pub fn init() Builder {
    return .{
        .header = mem.zeroInit(macho.SegmentCommand64, .{
            .cmd = .SEGMENT_64,
            .cmdsize = @sizeOf(macho.SegmentCommand64),
        }),
        .sections = .empty,
    };
}

pub fn deinit(self: *Builder, allocator: mem.Allocator) void {
    for (self.sections.items) |*s| {
        s.deinit(allocator);
    }
    self.sections.deinit(allocator);
    self.sections = .empty;
}

pub fn setName(self: *Builder, comptime name: []const u8) void {
    comptime if (name.len > 16) @compileError("Segment name '" ++ name ++ "' exceeds 16 bytes.");
    self.header.segname = @splat(0);
    @memcpy(self.header.segname[0..name.len], name);
}

pub fn setVMAddress(self: *Builder, addr: u64) void {
    self.header.vmaddr = addr;
}

pub fn setMaxVMProtection(self: *Builder, prot: std.macho.vm_prot_t) void {
    self.header.maxprot = prot;
}

pub fn setInitVMProtection(self: *Builder, prot: std.macho.vm_prot_t) void {
    self.header.initprot = prot;
}

pub fn setFlags(self: *Builder, flags: u32) void {
    self.header.flags = flags;
}

// Returns handle to section
pub fn createSection(self: *Builder, allocator: mem.Allocator) Error!usize {
    var section = sect.init();
    try section.setSegmentName(self.header.segName());
    try self.sections.append(allocator, section);
    self.header.cmdsize += @sizeOf(macho.Section64);
    return self.sections.items.len - 1;
}

pub fn getSectionRef(self: *Builder, idx: usize) *sect.Builder {
    return &self.sections.items[idx];
}

/// Returns number of bytes to extend the offset
pub fn writeCommand(self: *Builder, w: *Io.Writer, offset: u64) Io.Writer.Error!u64 {
    var size: u64 = 0;
    for (self.sections.items) |*section| {
        size += section.header.size;
    }

    self.header.vmsize = size;
    self.header.filesize = size;
    self.header.fileoff = offset;
    self.header.nsects = @intCast(self.sections.items.len);

    try w.writeAll(mem.asBytes(&self.header));

    var off = offset;
    for (self.sections.items) |*s| {
        off += try s.writeHeader(w, off);
    }
    return size + self.getPadSize();
}

pub fn writeData(self: *const Builder, w: *Io.Writer) Io.Writer.Error!void {
    for (self.sections.items) |s| {
        try s.writeData(w);
    }
    try w.splatByteAll(0, self.getPadSize());
}

fn getPadSize(self: *const Builder) u32 {
    const alignment = 8;
    const size: u32 = @intCast(self.header.filesize);
    return alignment - (size % alignment);
}

test "it can add a name" {
    var buf: [512]u8 = undefined;
    var writer = Io.Writer.fixed(&buf);
    var reader = Io.Reader.fixed(&buf);

    var builder = init();
    builder.setName("__TEXT");
    _ = try builder.writeCommand(&writer, 0);

    const seg = try reader.takeStruct(macho.SegmentCommand64, .native);
    try std.testing.expectEqual(.SEGMENT_64, seg.cmd);
    try std.testing.expectEqual(@sizeOf(macho.SegmentCommand64), seg.cmdsize);
    try std.testing.expectEqualSlices(u8, "__TEXT", seg.segName());
}

test "it can add a section" {
    const gpa = std.testing.allocator;
    var segment = init();
    defer segment.deinit(gpa);
    segment.setName("__TEXT");

    const idx = try segment.createSection(gpa);
    var section = segment.getSectionRef(idx);
    try section.setSectionName("__text");
    section.setAlignment(2);

    try std.testing.expectEqualStrings(segment.header.segName(), section.header.segName());
    try std.testing.expectEqualStrings("__text", section.header.sectName());
    try std.testing.expectEqual(2, section.header.@"align");
}
