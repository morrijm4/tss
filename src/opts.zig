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

pub fn init(io: std.Io, args: []const [:0]const u8) OptionsInitError!Options {
    var a: Options = .{
        .bin = undefined,
        .endian = .native,
    };

    if (args.len > 1) {
        const path = args[1];
        a.bin = try Io.Dir.cwd().openFile(io, path, .{});
    } else {
        a.bin = File.stdin();
    }

    return a;
}

pub fn deinit(self: *const Options, io: std.Io) void {
    self.bin.close(io);
}

test "can open and close files" {
    const io = std.testing.io;
    const args = [_][:0]const u8{ "./tss", "./test/simple" };
    const opts = try init(io, &args);
    defer opts.deinit(io);
}
