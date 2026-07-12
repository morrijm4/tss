const std = @import("std");
const mem = std.mem;
const macho = @import("./macho.zig");

pub const MachOBuilder = @This();

magic: ?macho.Magic,
cputype: ?macho.CpuType,
cpusubtype: ?macho.CpuSubType,
filetype: ?macho.FileType,
bit: ?macho.ArchBit,
ptrtype: ?macho.PointerType,
loadCommands: std.ArrayList(macho.LoadCommand),

pub const MachOBuilderError = error{ MissingField, InvalidCombination };

pub fn init() MachOBuilder {
    return .{
        .magic = null,
        .cputype = null,
        .cpusubtype = null,
        .filetype = null,
        .bit = null,
        .ptrtype = null,
        .loadCommands = .empty,
    };
}

pub fn deinit(self: *MachOBuilder, allocator: mem.Allocator) void {
    self.loadCommands.deinit(allocator);
}

pub fn setMagic(self: *MachOBuilder, magic: macho.Magic) *MachOBuilder {
    switch (magic) {
        .magic64, .cigam64 => self.bit = .bit64,
        .magic32, .cigam32 => self.bit = .bit32,
    }

    self.magic = magic;
    return self;
}

pub fn setCpuType(self: *MachOBuilder, cputype: macho.CpuType) *MachOBuilder {
    self.cputype = cputype;
    return self;
}

pub fn setPointerType(self: *MachOBuilder, ptrtype: macho.PointerType) *MachOBuilder {
    self.ptrtype = ptrtype;
    return self;
}

pub fn setCpuSubType(self: *MachOBuilder, cpusubtype: macho.CpuSubType) *MachOBuilder {
    self.cpusubtype = cpusubtype;
    return self;
}

pub fn setFileType(self: *MachOBuilder, filetype: macho.FileType) *MachOBuilder {
    self.filetype = filetype;
    return self;
}

pub fn addLoadCommand(self: *MachOBuilder, gpa: mem.Allocator, cmd: macho.LoadCommand) error{OutOfMemory}!void {
    try self.loadCommands.append(gpa, cmd);
}

pub fn buildHeader(self: *MachOBuilder) MachOBuilderError!macho.MachHeader64 {
    if (self.magic == null or
        self.cputype == null or
        self.cpusubtype == null or
        self.filetype == null or
        self.bit == null or
        self.ptrtype == null)
        return MachOBuilderError.MissingField;

    const cputype = self.cputype.?;
    const cpusubtype = self.cpusubtype.?;

    if (cputype != cpusubtype) return MachOBuilderError.InvalidCombination;

    var hdr: macho.MachHeader64 = .{
        .magic = @intFromEnum(self.magic.?),
        .cputype = @intFromEnum(cputype),
        .filetype = @intFromEnum(self.filetype.?),
    };

    hdr.cpusubtype = switch (cpusubtype) {
        .ARM => |s| @intFromEnum(s),
        .x86 => |s| @intFromEnum(s),
        else => 0,
    };

    const bit = self.bit.?;
    const ptrtype = self.ptrtype.?;

    switch (bit) {
        .bit64 => switch (ptrtype) {
            .ptr64 => hdr.cputype |= macho.CPU_TYPE_64_MASK,
            .ptr32 => hdr.cputype |= macho.CPU_TYPE_64_32_PTRS_MASK,
        },
        .bit32 => switch (ptrtype) {
            .ptr64 => return MachOBuilderError.InvalidCombination,
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

    try std.testing.expectError(MachOBuilderError.InvalidCombination, self.buildHeader());
}

test "it fail if not all fields are present" {
    var builder = init();
    try std.testing.expectError(MachOBuilderError.MissingField, builder.buildHeader());
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

    try std.testing.expectEqual(builder.loadCommands.items.len, 1);
    try std.testing.expectEqualSlices(u8, builder.loadCommands.items[0].data, data);
}
