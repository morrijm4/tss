const std = @import("std");

const Io = std.Io;
const mem = std.mem;

const macho = @import("../macho.zig");
const lc = @import("./load-command.zig");

pub const Builder = @This();

header: macho.MachHeader64,
ptr_size: macho.PointerType,
cpusubtype: macho.CpuSubType,
load_commands: std.ArrayList(lc.Builder),

pub const Error = error{ MissingField, InvalidField } || Io.Writer.Error;

pub fn init() Builder {
    return .{
        .header = mem.zeroInit(macho.MachHeader64, .{}),
        .ptr_size = .ptr64,
        .cpusubtype = .NONE,
        .load_commands = .empty,
    };
}

pub fn deinit(self: *Builder, allocator: mem.Allocator) void {
    for (self.load_commands.items) |*cmd| {
        cmd.deinit(allocator);
    }
    self.load_commands.deinit(allocator);
    self.load_commands = .empty;
}

pub fn setMagic(self: *Builder, magic: macho.Magic) void {
    self.header.magic = @intFromEnum(magic);
}

pub fn setCpuType(self: *Builder, cputype: macho.CpuType) void {
    self.header.cputype = @intFromEnum(cputype);
}

pub fn setPointerType(self: *Builder, ptrtype: macho.PointerType) void {
    self.ptr_size = ptrtype;
}

pub fn setCpuSubType(self: *Builder, cpusubtype: macho.CpuSubType) void {
    self.cpusubtype = cpusubtype;
    switch (cpusubtype) {
        .x86 => |t| self.header.cpusubtype = @intFromEnum(t),
        .ARM => |t| self.header.cpusubtype = @intFromEnum(t),
        else => {},
    }
}

pub fn setFileType(self: *Builder, filetype: macho.FileType) void {
    self.header.filetype = @intFromEnum(filetype);
}

// Returns handle to load command
pub fn addLoadCommand(self: *Builder, gpa: mem.Allocator, cmd: lc.LoadCommand) std.mem.Allocator.Error!usize {
    try self.load_commands.append(gpa, lc.init(cmd));
    return self.load_commands.items.len - 1;
}

pub fn getLoadCommand(self: *Builder, idx: usize) *lc.Builder {
    return &self.load_commands.items[idx];
}

pub fn write(self: *Builder, writer: *Io.Writer) Error!void {
    const magic = std.enums.fromInt(macho.Magic, self.header.magic);

    if (magic == null)
        return Error.InvalidField;

    if (self.header.cputype == 0 or self.header.filetype == 0)
        return Error.MissingField;

    if (self.header.cputype != @intFromEnum(self.cpusubtype))
        return Error.InvalidField;

    switch (magic.?) {
        .magic64, .cigam64 => switch (self.ptr_size) {
            .ptr64 => self.header.cputype |= macho.CPU_TYPE_64_MASK,
            .ptr32 => self.header.cputype |= macho.CPU_TYPE_64_32_PTRS_MASK,
        },
        .magic32, .cigam32 => switch (self.ptr_size) {
            .ptr64 => return Error.InvalidField,
            .ptr32 => {},
        },
    }

    var sizeofcmds: u32 = 0;
    for (self.load_commands.items) |*cmd| {
        sizeofcmds += cmd.getSize();
    }
    self.header.sizeofcmds = sizeofcmds;
    self.header.ncmds = @intCast(self.load_commands.items.len);

    try writer.writeStruct(self.header, .native);

    var offset: u64 = @sizeOf(macho.MachHeader64) + self.header.sizeofcmds;
    for (self.load_commands.items) |*cmd| {
        offset += try cmd.writeCommand(writer, offset);
    }
    for (self.load_commands.items) |cmd| {
        try cmd.writeData(writer);
    }
}

test "it builds ARM" {
    var builder = init();
    builder.setMagic(.magic64);
    builder.setCpuType(.ARM);
    builder.setPointerType(.ptr64);
    builder.setCpuSubType(.{ .ARM = .ARM64_ALL });
    builder.setFileType(.OBJECT);

    var buf: [64]u8 = undefined;
    var writer = Io.Writer.fixed(&buf);
    var reader = Io.Reader.fixed(&buf);

    try builder.write(&writer);
    const header = try reader.takeStruct(macho.MachHeader64, .native);

    try std.testing.expectEqual(std.macho.MH_MAGIC_64, header.magic);
    try std.testing.expectEqual(std.macho.CPU_TYPE_ARM64, header.cputype);
    try std.testing.expectEqual(std.macho.CPU_SUBTYPE_ARM_ALL, header.cpusubtype);
    try std.testing.expectEqual(std.macho.MH_OBJECT, header.filetype);
}

test "it builds x86" {
    var builder = init();
    builder.setMagic(.magic64);
    builder.setCpuType(.x86);
    builder.setPointerType(.ptr64);
    builder.setCpuSubType(.{ .x86 = .x86_ALL });
    builder.setFileType(.OBJECT);

    var buf: [64]u8 = undefined;
    var writer = Io.Writer.fixed(&buf);
    var reader = Io.Reader.fixed(&buf);

    try builder.write(&writer);
    const header = try reader.takeStruct(macho.MachHeader64, .native);

    try std.testing.expectEqual(std.macho.MH_MAGIC_64, header.magic);
    try std.testing.expectEqual(std.macho.CPU_TYPE_X86_64, header.cputype);
    try std.testing.expectEqual(std.macho.CPU_SUBTYPE_X86_64_ALL, header.cpusubtype);
    try std.testing.expectEqual(std.macho.MH_OBJECT, header.filetype);
}

test "it fails if cputype and cpusubtype don't match" {
    var builder = init();
    builder.setMagic(.magic64);
    builder.setCpuType(.x86);
    builder.setPointerType(.ptr64);
    builder.setCpuSubType(.{ .ARM = .ARM64_ALL });
    builder.setFileType(.OBJECT);

    var buf: [64]u8 = undefined;
    var writer = Io.Writer.fixed(&buf);

    try std.testing.expectError(Error.InvalidField, builder.write(&writer));
}

test "it fail if not all fields are present" {
    var builder = init();
    var buf: [64]u8 = undefined;
    var writer = Io.Writer.fixed(&buf);
    try std.testing.expectError(Error.MissingField, builder.write(&writer));
}

test "it can create a segment" {
    const gpa = std.testing.allocator;

    var builder = init();
    defer builder.deinit(gpa);

    const idx = try builder.addLoadCommand(gpa, .segment);
    var cmd = builder.getLoadCommand(idx);
    cmd.segment.setName("__TEXT");
    cmd.segment.setMaxVMProtection(.{ .READ = true, .EXEC = true });
    cmd.segment.setInitVMProtection(.{ .READ = true, .EXEC = true });

    try std.testing.expectEqualStrings("__TEXT", cmd.segment.header.segName());
}
