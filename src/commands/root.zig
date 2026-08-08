pub const help = @import("./help.zig");
pub const version = @import("./version.zig");

pub const Command = enum {
    build,
    objdump,
    help,
    halp,
    version,
};

test {
    @import("std").testing.refAllDecls(@This());
}
