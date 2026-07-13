const std = @import("std");
const mem = std.mem;
const macho = @import("../macho.zig");

pub const Builder = @This();

magic: ?macho.Magic,
cpu_type: ?macho.CpuType,
cpu_subtype: ?macho.CpuSubType,
file_type: ?macho.FileType,
bit: ?macho.ArchBit,
ptr_size: ?macho.PointerType,
load_commands: std.ArrayList(macho.LoadCommand),

pub const BuilderError = error{ MissingField, InvalidCombination };

pub fn init() Builder {
    return .{
        .magic = null,
        .cpu_type = null,
        .cpu_subtype = null,
        .file_type = null,
        .bit = null,
        .ptr_size = null,
        .load_commands = .empty,
    };
}

pub fn deinit(self: *Builder, allocator: mem.Allocator) void {
    self.load_commands.deinit(allocator);
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

pub fn addLoadCommand(self: *Builder, gpa: mem.Allocator, cmd: macho.LoadCommand) error{OutOfMemory}!void {
    try self.load_commands.append(gpa, cmd);
}

pub fn buildHeader(self: *Builder) BuilderError!macho.MachHeader64 {
    if (self.magic == null or
        self.cpu_type == null or
        self.cpu_subtype == null or
        self.file_type == null or
        self.bit == null or
        self.ptr_size == null)
        return BuilderError.MissingField;

    const cputype = self.cpu_type.?;
    const cpusubtype = self.cpu_subtype.?;

    if (cputype != cpusubtype) return BuilderError.InvalidCombination;

    var hdr: macho.MachHeader64 = .{
        .magic = @intFromEnum(self.magic.?),
        .cputype = @intFromEnum(cputype),
        .filetype = @intFromEnum(self.file_type.?),
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
            .ptr64 => return BuilderError.InvalidCombination,
            .ptr32 => {},
        },
    }

    return hdr;
}

test "it builds ARM" {
    var builder = init();
    const self = builder
        .setMagic(.magic64)
        .setCpuType(.ARM)
        .setPointerType(.ptr64)
        .setCpuSubType(.{ .ARM = .ARM64_ALL })
        .setFileType(.OBJECT);

    const header = try self.buildHeader();

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

    const header = try self.buildHeader();

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

    try std.testing.expectError(BuilderError.InvalidCombination, self.buildHeader());
}

test "it fail if not all fields are present" {
    var builder = init();
    try std.testing.expectError(BuilderError.MissingField, builder.buildHeader());
}

test "it appends a load command" {
    const gpa = std.testing.allocator;

    var builder = init();
    defer builder.deinit(gpa);

    const cmd: macho.UUIDCommand = .{
        .cmd = .UUID,
        .cmdsize = @sizeOf(macho.UUIDCommand),
        .uuid = undefined,
    };

    const data = mem.asBytes(&cmd);
    const lc: macho.LoadCommand = .{
        .hdr = .{ .cmd = cmd.cmd, .cmdsize = cmd.cmdsize },
        .data = data,
    };

    try builder.addLoadCommand(gpa, lc);

    try std.testing.expectEqual(builder.load_commands.items.len, 1);
    try std.testing.expectEqualSlices(u8, builder.load_commands.items[0].data, data);
}
