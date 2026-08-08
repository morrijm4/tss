const std = @import("std");
const bo = @import("build-options");
const Io = std.Io;

pub fn execute(io: Io) Io.Writer.Error!void {
    const file = Io.File.stdout();
    var buf: [64]u8 = undefined;
    var writer = file.writer(io, &buf);
    const w = &writer.interface;
    try w.writeAll(bo.version);
    try w.writeByte('\n');
    try w.flush();
}
