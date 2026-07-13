const std = @import("std");
const Io = std.Io;
const log = std.log.scoped(.main);

const tss = @import("tss");

const BUFFER_SIZE = 4096;

pub fn main(init: std.process.Init) !void {
    const io = init.io;
    const arena = init.arena.allocator();

    const args = try init.minimal.args.toSlice(arena);
    const opts = try tss.opts.init(io, args);
    defer opts.deinit(io);

    var buf: [BUFFER_SIZE]u8 = undefined;
    var reader = opts.bin.reader(io, &buf);
    const r = &reader.interface;

    var macho = try tss.macho.init(arena, r);
    defer macho.deinit(arena);

    const stdout = Io.File.stdout();
    defer stdout.close(io);

    var stdout_writer = stdout.writer(io, &buf);
    const w = &stdout_writer.interface;

    try macho.print(w);
    try w.flush();
}
