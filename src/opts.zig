const std = @import("std");
const process = std.process;
const mem = std.mem;

const Io = std.Io;
const File = Io.File;
const Reader = Io.File.Reader;

pub const Options = @This();

bin: File,
endian: std.builtin.Endian = .native,

pub const OptionsInitError = process.Args.ToSliceError || File.OpenError;

pub fn init(arena: mem.Allocator, io: std.Io, args: process.Args) OptionsInitError!Options {
    const argv = try args.toSlice(arena);

    var a: Options = .{
        .bin = undefined,
        .endian = .native,
    };

    if (argv.len > 1) {
        const path = argv[1];
        a.bin = try Io.Dir.cwd().openFile(io, path, .{});
    } else {
        a.bin = File.stdin();
    }

    return a;
}

pub fn deinit(self: *const Options, io: std.Io) void {
    self.bin.close(io);
}
