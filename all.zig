const std = @import("std");

const Io = std.Io;
const mem = std.mem;

const m = @import("../macho.zig");

pub const macho = @import("./macho.zig");
pub const segment = @import("./segment.zig");
pub const section = @import("./section.zig");
pub const load_command = @import("./load-command.zig");

test {
    @import("std").testing.refAllDecls(@This());
}

test "adding sections to a segment" {
    const gpa = std.testing.allocator;

    var buf: [512]u8 = @splat(0);
    var writer = Io.Writer.fixed(&buf);
    var reader = Io.Reader.fixed(&buf);

    const segname = "__TEXT";
    var sect = section.Builder.init();
    defer sect.deinit(gpa);
    _ = sect.setSectionName("__text")
        .setSegmentName(segname)
        .setAlignment(2);

    try sect.addInstruction(gpa, 0xd28008a0);
    try sect.addInstruction(gpa, 0xd2800030);
    try sect.addInstruction(gpa, 0xd4001001);

    var seg = segment.Builder.init();
    defer seg.deinit(gpa);
    _ = seg.setName(segname);
    try seg.addSection(gpa, &sect);
    const offset = try seg.writeCommand(&writer, 0);
    try seg.writeData(&writer);

    const segment_header = try reader.takeStruct(m.SegmentCommand64, .native);
    try std.testing.expectEqualStrings(segname, segment_header.segName());
    try std.testing.expectEqual(@sizeOf(m.SegmentCommand64) + @sizeOf(m.Section64), segment_header.cmdsize);
    try std.testing.expectEqual(12, offset);

    const section_header = try reader.takeStruct(m.Section64, .native);
    try std.testing.expectEqualStrings("__text", section_header.sectName());
    try std.testing.expectEqualStrings(segname, section_header.segName());
    try std.testing.expectEqual(12, section_header.size);
    try std.testing.expectEqual(2, section_header.@"align");

    _ = try reader.takeInt(u32, .native);
    _ = try reader.takeInt(u32, .native);
    _ = try reader.takeInt(u32, .native);

    try std.testing.expectEqual(0, reader.takeInt(u32, .native));
}

test "macho builder appends a load command builder" {
    const gpa = std.testing.allocator;

    var sect = section.init();
    defer sect.deinit(gpa);

    const segment_name = "__TEXT";
    _ = sect
        .setSegmentName(segment_name)
        .setSectionName("__text")
        .setAlignment(2);
    try sect.addInstruction(gpa, 0xd28008a0);
    try sect.addInstruction(gpa, 0xd2800030);
    try sect.addInstruction(gpa, 0xd4001001);

    var seg = segment.init();
    defer seg.deinit(gpa);
    _ = seg
        .setName(segment_name)
        .setMaxVMProtection(.{ .READ = true, .EXEC = true })
        .setInitVMProtection(.{ .READ = true, .EXEC = true });
    try seg.addSection(gpa, &sect);

    var builder = macho.init();
    defer builder.deinit(gpa);
    const self = builder
        .setMagic(.magic64)
        .setCpuType(.ARM)
        .setCpuSubType(.{ .ARM = .ARM64_ALL })
        .setPointerType(.ptr64)
        .setFileType(.OBJECT);
    var load_cmd = load_command.from(seg);
    try builder.addLoadCommand(gpa, &load_cmd);

    var buf: [512]u8 = undefined;
    var writer = Io.Writer.fixed(&buf);
    var reader = Io.Reader.fixed(&buf);

    try builder.write(&writer);

    const header = try reader.takeStruct(m.MachHeader64, .native);

    try std.testing.expectEqual(&builder, self);
    try std.testing.expectEqual(std.macho.MH_MAGIC_64, header.magic);
    try std.testing.expectEqual(std.macho.CPU_TYPE_ARM64, header.cputype);
    try std.testing.expectEqual(std.macho.CPU_SUBTYPE_ARM_ALL, header.cpusubtype);
    try std.testing.expectEqual(std.macho.MH_OBJECT, header.filetype);
    try std.testing.expectEqual(1, header.ncmds);
    try std.testing.expectEqual(seg.header.cmdsize, header.sizeofcmds);
    try std.testing.expectEqual(builder.load_commands.items.len, 1);

    const cmds = try reader.take(header.sizeofcmds);
    var it = try std.macho.LoadCommandIterator.init(&header, cmds);

    while (try it.next()) |lc| {
        switch (lc.hdr.cmd) {
            .SEGMENT_64 => {
                const cmd = lc.cast(m.SegmentCommand64).?;
                try std.testing.expectEqualStrings("__TEXT", cmd.segName());
                try std.testing.expectEqual(0, cmd.vmaddr);
                try std.testing.expectEqual(12, cmd.vmsize);
                const off = @sizeOf(m.MachHeader64) + @sizeOf(m.SegmentCommand64) + @sizeOf(m.Section64);
                try std.testing.expectEqual(off, cmd.fileoff);
                try std.testing.expectEqual(12, cmd.filesize);
                const prot: std.macho.vm_prot_t = .{
                    .READ = true,
                    .EXEC = true,
                };
                try std.testing.expectEqualDeep(prot, cmd.maxprot);
                try std.testing.expectEqualDeep(prot, cmd.initprot);
                try std.testing.expectEqual(1, cmd.nsects);
                for (lc.getSections()) |sec| {
                    try std.testing.expectEqualStrings("__text", sec.sectName());
                    try std.testing.expectEqualStrings("__TEXT", sec.segName());
                    try std.testing.expectEqual(0, sec.addr);
                    try std.testing.expectEqual(12, sec.size);
                    try std.testing.expectEqual(off, sec.offset);
                    try std.testing.expectEqual(2, sec.@"align");
                }
            },
            else => unreachable,
        }
    }

    try std.testing.expectEqual(0xd28008a0, try reader.takeInt(u32, .native));
    try std.testing.expectEqual(0xd2800030, try reader.takeInt(u32, .native));
    try std.testing.expectEqual(0xd4001001, try reader.takeInt(u32, .native));
}
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
const std = @import("std");
const segment = @import("./segment.zig");

pub const Builder = union(enum) {
    segment: segment.Builder,

    pub fn deinit(self: *Builder, allocator: std.mem.Allocator) void {
        switch (self.*) {
            .segment => |*cmd| cmd.deinit(allocator),
        }
    }

    /// Returns number of bytes to extend the offset
    pub fn writeCommand(self: *Builder, writer: *std.Io.Writer, offset: u64) std.Io.Writer.Error!u64 {
        switch (self.*) {
            .segment => |*cmd| return try cmd.writeCommand(writer, offset),
        }
    }

    pub fn writeData(self: *const Builder, writer: *std.Io.Writer) std.Io.Writer.Error!void {
        try switch (self.*) {
            .segment => |cmd| cmd.writeData(writer),
        };
    }

    pub fn getSize(self: *const Builder) u32 {
        switch (self.*) {
            .segment => |cmd| return cmd.header.cmdsize,
        }
    }

    pub fn reset(self: *Builder) void {
        switch (self.*) {
            .segment => self.*.segment = segment.init(),
        }
    }
};

pub fn from(builder: anytype) Builder {
    const B = @TypeOf(builder);
    const fields = @typeInfo(Builder).@"union".fields;
    inline for (fields) |field| {
        if (field.type == B) return @unionInit(Builder, field.name, builder);
    }
    @compileError("Builder.from: no variant with type " ++ @typeName(B));
}
