const std = @import("std");
const process = std.process;
const mem = std.mem;

const File = std.Io.File;

const Args = @This();

file: File,

const FILE_BUFFER_SIZE = 4096;

pub const ArgsInitError = process.Args.ToSliceError || File.OpenError;

pub fn init(arena: mem.Allocator, io: std.Io, args: process.Args) ArgsInitError!Args {
    const argv = try args.toSlice(arena);

    var a: Args = .{
        .file = undefined,
    };

    if (argv.len > 1) {
        const path = argv[1];
        a.file = try std.Io.Dir.cwd().openFile(io, path, .{});
    } else {
        a.file = File.stdin();
    }

    return a;
}
