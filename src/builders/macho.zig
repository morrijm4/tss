const std = @import("std");

const Io = std.Io;
const mem = std.mem;

const macho = @import("../macho.zig");
const load_command = @import("./load-command.zig");

pub const Builder = @This();

magic: ?macho.Magic,
cpu_type: ?macho.CpuType,
cpu_subtype: ?macho.CpuSubType,
file_type: ?macho.FileType,
bit: ?macho.ArchBit,
ptr_size: ?macho.PointerType,
load_commands: std.ArrayList(load_command.Builder),
load_command_size: u32,

pub const Error = error{ MissingField, InvalidCombination } || Io.Writer.Error;

pub fn init() Builder {
    return .{
        .magic = null,
        .cpu_type = null,
        .cpu_subtype = null,
        .file_type = null,
        .bit = null,
        .ptr_size = null,
        .load_commands = .empty,
        .load_command_size = 0,
    };
}

pub fn deinit(self: *Builder, allocator: mem.Allocator) void {
    for (self.load_commands.items) |*lc| {
        lc.deinit(allocator);
    }
    self.load_commands.deinit(allocator);
    self.load_commands = .empty;
}

pub fn setMagic(self: *Builder, magic: macho.Magic) *Builder {
    switch (magic) {
        .magic64, .cigam64 => self.bit = .bit64,
        .magic32, .cigam32 => self.bit = .bit32,
    }

    self.magic = magic;
    return self;
}

pub fn setCpuType(self: *Builder, cputype: macho.CpuType) *Builder {
    self.cpu_type = cputype;
    return self;
}

pub fn setPointerType(self: *Builder, ptrtype: macho.PointerType) *Builder {
    self.ptr_size = ptrtype;
    return self;
}

pub fn setCpuSubType(self: *Builder, cpusubtype: macho.CpuSubType) *Builder {
    self.cpu_subtype = cpusubtype;
    return self;
}

pub fn setFileType(self: *Builder, filetype: macho.FileType) *Builder {
    self.file_type = filetype;
    return self;
}

/// Load command moves to the builder and is reset.
pub fn addLoadCommand(self: *Builder, gpa: mem.Allocator, lc: *load_command.Builder) std.mem.Allocator.Error!void {
    self.load_command_size += lc.getSize();
    try self.load_commands.append(gpa, lc.*);
    lc.reset();
}

pub fn writeHeader(self: *Builder, writer: *Io.Writer) Error!void {
    if (self.magic == null or
        self.cpu_type == null or
        self.cpu_subtype == null or
        self.file_type == null or
        self.bit == null or
        self.ptr_size == null)
        return Error.MissingField;

    const cputype = self.cpu_type.?;
    const cpusubtype = self.cpu_subtype.?;

    if (cputype != cpusubtype) return Error.InvalidCombination;

    var hdr: macho.MachHeader64 = .{
        .magic = @intFromEnum(self.magic.?),
        .cputype = @intFromEnum(cputype),
        .filetype = @intFromEnum(self.file_type.?),
        .ncmds = @intCast(self.load_commands.items.len),
        .sizeofcmds = self.load_command_size,
    };

    hdr.cpusubtype = switch (cpusubtype) {
        .ARM => |s| @intFromEnum(s),
        .x86 => |s| @intFromEnum(s),
        else => 0,
    };

    const bit = self.bit.?;
    const ptrtype = self.ptr_size.?;

    switch (bit) {
        .bit64 => switch (ptrtype) {
            .ptr64 => hdr.cputype |= macho.CPU_TYPE_64_MASK,
            .ptr32 => hdr.cputype |= macho.CPU_TYPE_64_32_PTRS_MASK,
        },
        .bit32 => switch (ptrtype) {
            .ptr64 => return Error.InvalidCombination,
            .ptr32 => {},
        },
    }

    try writer.writeStruct(hdr, .native);
}

pub fn write(self: *Builder, writer: *Io.Writer) Error!void {
    try self.writeHeader(writer);

    var offset: u64 = @sizeOf(macho.MachHeader64) + self.load_command_size;
    for (self.load_commands.items) |*lc| {
        offset += try lc.writeCommand(writer, offset);
    }
    for (self.load_commands.items) |lc| {
        try lc.writeData(writer);
    }
}

test "it builds ARM" {
    var builder = init();
    const self = builder
        .setMagic(.magic64)
        .setCpuType(.ARM)
        .setPointerType(.ptr64)
        .setCpuSubType(.{ .ARM = .ARM64_ALL })
        .setFileType(.OBJECT);

    var buf: [64]u8 = undefined;
    var writer = Io.Writer.fixed(&buf);
    var reader = Io.Reader.fixed(&buf);

    try self.writeHeader(&writer);
    const header = try reader.takeStruct(macho.MachHeader64, .native);

    try std.testing.expectEqual(&builder, self);
    try std.testing.expectEqual(std.macho.MH_MAGIC_64, header.magic);
    try std.testing.expectEqual(std.macho.CPU_TYPE_ARM64, header.cputype);
    try std.testing.expectEqual(std.macho.CPU_SUBTYPE_ARM_ALL, header.cpusubtype);
    try std.testing.expectEqual(std.macho.MH_OBJECT, header.filetype);
}

test "it builds x86" {
    var builder = init();
    const self = builder
        .setMagic(.magic64)
        .setCpuType(.x86)
        .setPointerType(.ptr64)
        .setCpuSubType(.{ .x86 = .x86_ALL })
        .setFileType(.OBJECT);

    var buf: [64]u8 = undefined;
    var writer = Io.Writer.fixed(&buf);
    var reader = Io.Reader.fixed(&buf);

    try self.writeHeader(&writer);
    const header = try reader.takeStruct(macho.MachHeader64, .native);

    try std.testing.expectEqual(&builder, self);
    try std.testing.expectEqual(std.macho.MH_MAGIC_64, header.magic);
    try std.testing.expectEqual(std.macho.CPU_TYPE_X86_64, header.cputype);
    try std.testing.expectEqual(std.macho.CPU_SUBTYPE_X86_64_ALL, header.cpusubtype);
    try std.testing.expectEqual(std.macho.MH_OBJECT, header.filetype);
}

test "it fails if cputype and cpusubtype don't match" {
    var builder = init();
    const self = builder
        .setMagic(.magic64)
        .setCpuType(.x86)
        .setPointerType(.ptr64)
        .setCpuSubType(.{ .ARM = .ARM64_ALL })
        .setFileType(.OBJECT);

    var buf: [64]u8 = undefined;
    var writer = Io.Writer.fixed(&buf);

    try std.testing.expectError(Error.InvalidCombination, self.writeHeader(&writer));
}

test "it fail if not all fields are present" {
    var builder = init();
    var buf: [64]u8 = undefined;
    var writer = Io.Writer.fixed(&buf);
    try std.testing.expectError(Error.MissingField, builder.writeHeader(&writer));
}
