const std = @import("std");
const Io = std.Io;
const File = Io.File;

pub const Mode = enum {
    out,
    err,
};

pub const Options = struct {
    mode: Mode = .err,
};

pub fn execute(io: Io, opts: Options) Io.Writer.Error!void {
    const file = switch (opts.mode) {
        .out => File.stdout(),
        .err => File.stderr(),
    };

    var buf: [4096]u8 = undefined;
    var writer = file.writer(io, &buf);
    const w = &writer.interface;

    const help_message =
        \\Usage: tss [command] [options]
        \\
        \\Commands:
        \\
        \\  build
        \\  objdump
        \\  help           Print this help message and exit
        \\  version        Print the version number and exit
    ;

    try w.writeAll(help_message);
    try w.writeByte('\n');
    try w.flush();
}
