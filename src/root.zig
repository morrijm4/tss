const std = @import("std");

const Io = std.Io;

pub const macho = @import("./macho.zig");
pub const opts = @import("./opts.zig");
pub const builders = @import("./builders/root.zig");
pub const commands = @import("./commands/root.zig");

test {
    @import("std").testing.refAllDecls(@This());
}

test "it can build a header, parse, and print" {
    const gpa = std.testing.allocator;

    var header_buf: [512]u8 = undefined;
    var writer = Io.Writer.fixed(&header_buf);
    var reader = Io.Reader.fixed(&header_buf);

    var build: builders.macho.Builder = .init();
    build.setMagic(.magic64);
    build.setPointerType(.ptr64);
    build.setCpuType(.x86);
    build.setCpuSubType(.{ .x86 = .x86_ALL });
    build.setFileType(.OBJECT);
    try build.write(&writer);

    var m = try macho.init(gpa, &reader);
    defer m.deinit(gpa);

    var discard_buf: [1024]u8 = undefined;
    var discard = Io.Writer.Discarding.init(&discard_buf);

    try m.print(&discard.writer);
    try discard.writer.flush();
}
