const std = @import("std");
const Io = std.Io;
const log = std.log.scoped(.macho);

const Magic = @import("./magic.zig").Magic;

pub const MachO = @This();

header: Header,
loadCommands: std.ArrayList(LoadCommand),

const Header = packed struct {
    magic: u32,
    cpuType: u32,
    cpuSubtype: u32,
    fileType: u32,
    numLoadCommands: u32,
    loadCommandSize: u32,
    flags: u32,
    reserved: u32,
};

const LoadCommand = packed struct {
    command: u32,
    commandSize: u32,
};

pub const InitOptions = struct {
    endian: std.builtin.Endian = .native,
};

const InitError = error{
    ReadFailed,
    EndOfStream,
    InvalidFormat,
    OutOfMemory,
};

pub fn init(allocator: std.mem.Allocator, reader: *Io.Reader, options: InitOptions) InitError!MachO {
    const endian = options.endian;
    const header = try reader.takeStruct(Header, endian);

    var macho: MachO = .{
        .header = header,
        .loadCommands = .empty,
    };

    var total: u32 = 0;
    for (0..header.numLoadCommands) |i| {
        _ = i;

        const loadCommand = try reader.takeStruct(LoadCommand, endian);
        try reader.discardAll(loadCommand.commandSize - @sizeOf(LoadCommand));

        total += loadCommand.commandSize;
        try macho.loadCommands.append(allocator, loadCommand);
    }

    if (total != header.loadCommandSize) return InitError.InvalidFormat;

    return macho;
}

pub fn print(self: *const MachO, writer: *Io.Writer) error{WriteFailed}!void {
    const h = self.header;
    try writer.print("Magic => 0x{x:0>8}\n", .{h.magic});
    try writer.print("CPU Type => 0x{x:0>8}\n", .{h.cpuType});
    try writer.print("CPU Subtype => 0x{x:0>8}\n", .{h.cpuSubtype});
    try writer.print("File type => 0x{x:0>8}\n", .{h.fileType});
    try writer.print("Number of load commands => {}\n", .{h.numLoadCommands});
    try writer.print("Load commands size => {}\n", .{h.loadCommandSize});
    try writer.print("Flags => 0b{b:0>32}\n", .{h.flags});
    try writer.print("\n", .{});

    try writer.print("Load Commands:\n", .{});
    for (self.loadCommands.items, 1..) |lc, i| {
        try writer.print("{}. Command => 0x{x:0>8}, Size => {}\n", .{ i, lc.command, lc.commandSize });
    }
}
