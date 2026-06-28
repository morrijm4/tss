const std = @import("std");
const Io = std.Io;
const log = std.log.scoped(.macho);

const MachO = @This();

header: MachHeader64,
loadCommands: LoadCommandIterator,

const MachHeader64 = std.macho.mach_header_64;
const LoadCommandIterator = std.macho.LoadCommandIterator;
const LoadCommand = std.macho.LoadCommandIterator.LoadCommand;
const SegmentCommand64 = std.macho.segment_command_64;
const BuildVersionCommand = std.macho.build_version_command;

pub const CPU_TYPE_64_MASK = 0x01000000;
pub const CPU_TYPE_64_32_PTRS_MASK = 0x02000000;

pub const CpuType = enum(std.macho.cpu_type_t) {
    NONE = 0x0,
    x86 = 0x7,
    ARM = 0xc,
};

pub const Version = packed struct {
    patch: u8,
    minor: u8,
    major: u16,
};

pub const InitOptions = struct {
    endian: std.builtin.Endian = .native,
};

const MachoInitError = Io.Reader.Error || error{
    OutOfMemory,
    InvalidMachO,
    InvalidMagic,
};

pub fn init(allocator: std.mem.Allocator, reader: *Io.Reader, options: InitOptions) MachoInitError!MachO {
    const endian = options.endian;

    const m = try reader.peekInt(u32, endian);
    if (m != std.macho.MH_MAGIC_64) return MachoInitError.InvalidMagic;

    const header = try reader.takeStruct(MachHeader64, endian);
    const loadCommandsBuffer = try reader.readAlloc(allocator, header.sizeofcmds);
    errdefer allocator.free(loadCommandsBuffer);

    return .{
        .header = header,
        .loadCommands = try LoadCommandIterator.init(&header, loadCommandsBuffer),
    };
}

pub fn deinit(self: *MachO, allocator: std.mem.Allocator) void {
    allocator.free(self.loadCommands.r.buffer);
}

pub fn getCpuType(header: MachHeader64) ?CpuType {
    const bitVersionMask = 0xF0FFFFFF;
    return std.enums.fromInt(CpuType, bitVersionMask & @as(u32, @bitCast(header.cputype)));
}

pub fn print(self: *MachO, writer: *Io.Writer) error{ WriteFailed, InvalidMachO }!void {
    try printMachHeader64(self.header, writer);

    try writer.print("Load Commands:\n", .{});
    while (try self.loadCommands.next()) |lc| {
        try writer.print("* Command => {} (1x{x:0>8}), Header Size => {}, Size => {}\n", .{ lc.hdr.cmd, lc.hdr.cmd, @sizeOf(SegmentCommand64), lc.hdr.cmdsize });
        switch (lc.hdr.cmd) {
            .SEGMENT_64 => try printSegmentCommand64(lc, writer),
            .BUILD_VERSION => try printBuildVersionCommand(lc, writer),
            else => {},
        }
    }
}

pub fn printMachHeader64(header: MachHeader64, writer: *Io.Writer) Io.Writer.Error!void {
    try writer.print("Magic => 0x{x:0>8}\n", .{header.magic});
    try writer.print("CPU Type => {?} (0x{x:0>8})\n", .{ getCpuType(header), @as(u32, @bitCast(header.cputype)) });
    try writer.print("CPU Subtype => 0x{x:0>8}\n", .{@as(u32, @bitCast(header.cpusubtype))});
    try writer.print("File type => 0x{x:0>8}\n", .{header.filetype});
    try writer.print("Number of load commands => {}\n", .{header.ncmds});
    try writer.print("Load commands size => {}\n", .{header.sizeofcmds});
    try writer.print("Flags => 0b{b:0>32}\n", .{header.flags});
    try writer.print("\n", .{});
}

pub fn printSegmentCommand64(lc: LoadCommand, writer: *Io.Writer) Io.Writer.Error!void {
    const cmd = lc.cast(SegmentCommand64).?;
    try writer.print("\t- Name => {s}\n", .{cmd.segName()});
    try writer.print("\t- VM Address => 0x{x:0>16}\n", .{cmd.vmaddr});
    try writer.print("\t- VM Size => {d}\n", .{cmd.vmsize});
    try writer.print("\t- File Offset => {d}\n", .{cmd.fileoff});
    try writer.print("\t- File Size => {d}\n", .{cmd.filesize});
    try writer.print("\t- Max VM Protection => {}\n", .{cmd.maxprot});
    try writer.print("\t- Initial VM Protection => {}\n", .{cmd.initprot});
    try writer.print("\t- Number of Sections => {d}\n", .{cmd.nsects});
    try writer.print("\t- Flags => 0b{b:0>32}\n", .{cmd.flags});
    try writer.print("\t- Sections:\n", .{});

    const sections = lc.getSections();
    for (sections) |section| {
        try writer.print("\t\t> Section Name => {s}\n", .{section.sectName()});
        try writer.print("\t\t> Segment Name => {s}\n", .{section.segName()});
        try writer.print("\t\t> Section Address => 0x{x:0>16}\n", .{section.addr});
        try writer.print("\t\t> Section File Offset => {d}\n", .{section.offset});
        try writer.print("\t\t> Alignment => {d}\n", .{section.@"align"});
        try writer.print("\t\t> Relocations File Offset => {d}\n", .{section.reloff});
        try writer.print("\t\t> Number of Relocations => {d}\n", .{section.nreloc});
        try writer.print("\t\t> Flags/Type => 0b{b:0>32}\n", .{section.flags});
        try writer.print("\t\t> Reserved1 => {d}\n", .{section.reserved1});
        try writer.print("\t\t> Reserved2 => {d}\n", .{section.reserved2});
        try writer.print("\t\t> Reserved3 => {d}\n", .{section.reserved3});
        try writer.print("\n", .{});
    }
}

pub fn printBuildVersionCommand(lc: LoadCommand, writer: *Io.Writer) Io.Writer.Error!void {
    const cmd = lc.cast(BuildVersionCommand).?;
    const minos: Version = @bitCast(cmd.minos);
    const sdk: Version = @bitCast(cmd.sdk);

    try writer.print("\t- Platform Type => {} (0x{x:0>8})\n", .{ cmd.platform, cmd.platform });
    try writer.print("\t- Minimum OS Version => v{}.{}.{}\n", .{ minos.major, minos.minor, minos.patch });
    try writer.print("\t- SDK Version => v{}.{}.{}\n", .{ sdk.major, sdk.minor, sdk.patch });
    try writer.print("\t- Number of Tools => {}\n", .{cmd.ntools});
    try writer.print("\t- Tools:\n", .{});

    const tools = lc.getBuildVersionTools();
    for (tools) |t| {
        const v: Version = @bitCast(t.version);
        try writer.print("\t\t> Tool => {} (v{}.{}.{})\n", .{ t.tool, v.major, v.minor, v.patch });
    }
}

test "Validate macho 64 magic value" {
    const gpa = std.testing.allocator;
    const buf: [4]u8 = @bitCast(@as(u32, std.macho.MH_MAGIC_64));
    var reader = std.Io.Reader.fixed(&buf);
    try std.testing.expectError(MachoInitError.EndOfStream, init(gpa, &reader, .{}));
}

test "Validate invalid macho 64 magic value" {
    const gpa = std.testing.allocator;
    const buf: [4]u8 = @bitCast(@as(u32, 0xBAD));
    var reader = std.Io.Reader.fixed(&buf);
    try std.testing.expectError(MachoInitError.InvalidMagic, init(gpa, &reader, .{}));
}
