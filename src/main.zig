const std = @import("std");
const Io = std.Io;
const log = std.log.scoped(.main);

const tss = @import("tss");

pub fn main(init: std.process.Init) !void {
    const io = init.io;
    const file = try std.Io.Dir.cwd().openFile(io, "./test/simple", .{});
    defer file.close(io);

    var buf: [1024]u8 = undefined;
    var reader = file.reader(io, &buf);
    const r = &reader.interface;

    const magic = try r.peekInt(u32, .native);
    try tss.magic.assertMagic(magic);
    const bin = try tss.macho.init(r);

    var file_writer = Io.File.stdin().writer(io, &buf);
    var w = &file_writer.interface;

    try bin.print(w);
    try w.flush();
}
