const std = @import("std");
const Io = std.Io;
const log = std.log.scoped(.main);

const tss = @import("tss");

pub fn main(init: std.process.Init) !void {
    const io = init.io;
    const arena = init.arena.allocator();
    const args = try tss.args.init(arena, io, init.minimal.args);

    var buf: [1024]u8 = undefined;
    var reader = args.file.reader(io, &buf);
    const r = &reader.interface;

    var macho = try tss.macho.init(arena, r, .{});

    var stdoutWriter = Io.File.stdout().writer(io, &buf);
    var w = &stdoutWriter.interface;

    try macho.print(w);
    try w.flush();
}
