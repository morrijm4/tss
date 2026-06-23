const std = @import("std");
const Io = std.Io;
const log = std.log.scoped(.main);

const tss = @import("tss");

pub fn main(init: std.process.Init) !void {
    const io = init.io;
    const arena = init.arena.allocator();

    var buf: [1024]u8 = undefined;
    var reader = Io.File.stdin().reader(io, &buf);
    const r = &reader.interface;

    const bin = try tss.macho.init(arena, r, .{});

    var file_writer = Io.File.stdout().writer(io, &buf);
    var w = &file_writer.interface;

    try bin.print(w);
    try w.flush();
}
