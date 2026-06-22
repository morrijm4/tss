const std = @import("std");
const Io = std.Io;
const log = std.log.scoped(.macho);

const Magic = @import("./magic.zig").Magic;

pub const MachO = @This();

header: Header,
loadCommands: []const u8,

const Header = packed struct {
    magic: u32,
    cpuType: u32,
    cpuSubtype: u32,
    fileType: u32,
    numLoadCommands: u32,
    loadCommandsSize: u32,
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

    const loadCommands = try reader.readAlloc(allocator, header.loadCommandsSize);
    errdefer allocator.free(loadCommands);

    const macho: MachO = .{
        .header = header,
        .loadCommands = loadCommands,
    };

    return macho;
}

pub fn print(self: *const MachO, writer: *Io.Writer) error{WriteFailed}!void {
    const h = self.header;
    try writer.print("Magic => 0x{x:0>8}\n", .{h.magic});
    try writer.print("CPU Type => 0x{x:0>8}\n", .{h.cpuType});
    try writer.print("CPU Subtype => 0x{x:0>8}\n", .{h.cpuSubtype});
    try writer.print("File type => 0x{x:0>8}\n", .{h.fileType});
    try writer.print("Number of load commands => {}\n", .{h.numLoadCommands});
    try writer.print("Load commands size => {}\n", .{h.loadCommandsSize});
    try writer.print("Flags => 0b{b:0>32}\n", .{h.flags});
    try writer.print("\n", .{});

    try writer.print("Load Commands:\n", .{});

    var i: u32 = 0;
    var j: u32 = 1;
    while (i < h.loadCommandsSize) : (j += 1) {
        // TODO: handle out of bounds
        const cmdType: u32 = @bitCast(self.loadCommands[i..][0..4].*);
        const cmdSize: u32 = @bitCast(self.loadCommands[i + 4 ..][0..4].*);

        i += cmdSize;

        try writer.print("{}. Command => 0x{x:0>8}, Size => {}\n", .{ j, cmdType, cmdSize });
    }
}
