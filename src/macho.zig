const std = @import("std");
const Io = std.Io;
const log = std.log.scoped(.macho);

const Magic = @import("./magic.zig").Magic;

pub const MachO = @This();

header: Header,

const Header = packed struct {
    magic: u32,
    cpu_type: u32,
    cpu_subtype: u32,
    file_type: u32,
    num_load_commands: u32,
    load_commands_size: u32,
    flags: u32,
    reserved: u32,
};

pub fn init(reader: *Io.Reader) error{ ReadFailed, EndOfStream }!MachO {
    return .{
        .header = try reader.takeStruct(Header, .native),
    };
}

pub fn print(self: *const MachO, writer: *Io.Writer) error{WriteFailed}!void {
    const h = self.header;
    try writer.print("Magic => 0x{x:0>8}\n", .{h.magic});
    try writer.print("CPU Type => 0x{x:0>8}\n", .{h.cpu_type});
    try writer.print("CPU Subtype => 0x{x:0>8}\n", .{h.cpu_subtype});
    try writer.print("File type => 0x{x:0>8}\n", .{h.file_type});
    try writer.print("Number of load commands => {}\n", .{h.num_load_commands});
    try writer.print("Load commands size => {}\n", .{h.load_commands_size});
    try writer.print("Flags => 0b{b:0>32}\n", .{h.flags});
}
