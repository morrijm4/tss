const std = @import("std");
pub const macho = @import("./macho.zig");
pub const opts = @import("./opts.zig");
pub const builder = @import("./macho-builder.zig");

test {
    @import("std").testing.refAllDecls(@This());
}

test "it can build a header, parse, and print" {
    const gpa = std.testing.allocator;

    var build: builder.MachOBuilder = .init();
    const header = try build
        .setMagic(.magic64)
        .setCpuType(.x86)
        .setPointerType(.ptr64)
        .setCpuSubType(.{ .x86 = .x86_ALL })
        .setFileType(.OBJECT)
        .buildHeader();

    const bytes = std.mem.asBytes(&header);
    var reader = std.Io.Reader.fixed(bytes);

    var m = try macho.init(gpa, &reader);
    defer m.deinit(gpa);

    var buf: [1024]u8 = undefined;
    var discard = std.Io.Writer.Discarding.init(&buf);

    try m.print(&discard.writer);
    try discard.writer.flush();
}
