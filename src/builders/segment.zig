const std = @import("std");
const macho = @import("../macho.zig");
const section = @import("./section.zig");

const Io = std.Io;
const mem = std.mem;

pub const Builder = @This();

header: macho.SegmentCommand64,
sections: std.ArrayList(section.Builder),

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
    for (self.sections.items) |*sect| {
        sect.deinit(allocator);
    }
    self.sections.deinit(allocator);
    self.sections = .empty;
}

pub fn setName(self: *Builder, comptime name: []const u8) *Builder {
    comptime if (name.len > 16) @compileError("Segment name '" ++ name ++ "' exceeds 16 bytes.");
    self.header.segname = @splat(0);
    @memcpy(self.header.segname[0..name.len], name);
    return self;
}

pub fn setVMAddress(self: *Builder, addr: u64) *Builder {
    self.header.vmaddr = addr;
    return self;
}

pub fn setMaxVMProtection(self: *Builder, prot: std.macho.vm_prot_t) *Builder {
    self.header.maxprot = prot;
    return self;
}

pub fn setInitVMProtection(self: *Builder, prot: std.macho.vm_prot_t) *Builder {
    self.header.initprot = prot;
    return self;
}

pub fn setFlags(self: *Builder, flags: u32) *Builder {
    self.header.flags = flags;
    return self;
}

// Section moves to the segment. The passed-in section is reset.
pub fn addSection(self: *Builder, allocator: mem.Allocator, sect: *section.Builder) mem.Allocator.Error!void {
    try self.sections.append(allocator, sect.*);
    self.header.cmdsize += @sizeOf(macho.Section64);
    self.header.vmsize += sect.header.size;
    self.header.filesize += sect.header.size;
    self.header.nsects += 1;
    sect.* = section.init();
}

/// Returns number of bytes to extend the offset
pub fn writeCommand(self: *Builder, w: *Io.Writer, offset: u64) Io.Writer.Error!u64 {
    self.header.fileoff = offset;
    try w.writeAll(mem.asBytes(&self.header));

    var off = offset;
    for (self.sections.items) |*sect| {
        off += try sect.writeHeader(w, off);
    }
    return off;
}

pub fn writeData(self: *const Builder, w: *Io.Writer) Io.Writer.Error!void {
    for (self.sections.items) |sect| {
        try sect.writeData(w);
    }
}

test "it can add a name" {
    var buf: [512]u8 = undefined;
    var writer = Io.Writer.fixed(&buf);
    var reader = Io.Reader.fixed(&buf);

    var builder = init();

    _ = try builder.setName("__TEXT").writeCommand(&writer, 0);

    const seg = try reader.takeStruct(macho.SegmentCommand64, .native);
    try std.testing.expectEqual(.SEGMENT_64, seg.cmd);
    try std.testing.expectEqual(@sizeOf(macho.SegmentCommand64), seg.cmdsize);
    try std.testing.expectEqualSlices(u8, "__TEXT", seg.segName());
}
