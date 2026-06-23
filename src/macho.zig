const std = @import("std");
const Io = std.Io;
const log = std.log.scoped(.macho);

const MachO = @This();

header: std.macho.mach_header_64,
loadCommands: std.macho.LoadCommandIterator,

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

    const m = try reader.peekInt(u32, .native);
    if (m != std.macho.MH_MAGIC_64) return MachoInitError.InvalidMagic;

    const header = try reader.takeStruct(std.macho.mach_header_64, endian);
    const loadCommandsBuffer = try reader.readAlloc(allocator, header.sizeofcmds);
    errdefer allocator.free(loadCommandsBuffer);

    return .{
        .header = header,
        .loadCommands = try std.macho.LoadCommandIterator.init(&header, loadCommandsBuffer),
    };
}

pub fn print(self: *MachO, writer: *Io.Writer) error{ WriteFailed, InvalidMachO }!void {
    const h = self.header;
    try writer.print("Magic => 0x{x:0>8}\n", .{h.magic});
    try writer.print("CPU Type => 0x{x:0>8}\n", .{@as(u32, @bitCast(h.cputype))});
    try writer.print("CPU Subtype => 0x{x:0>8}\n", .{@as(u32, @bitCast(h.cpusubtype))});
    try writer.print("File type => 0x{x:0>8}\n", .{h.filetype});
    try writer.print("Number of load commands => {}\n", .{h.ncmds});
    try writer.print("Load commands size => {}\n", .{h.sizeofcmds});
    try writer.print("Flags => 0b{b:0>32}\n", .{h.flags});
    try writer.print("\n", .{});

    try writer.print("Load Commands:\n", .{});
    while (try self.loadCommands.next()) |lc| {
        try writer.print("* Command => 0x{x:0>8}, Size => {}\n", .{ lc.hdr.cmd, lc.hdr.cmdsize });
    }
}
