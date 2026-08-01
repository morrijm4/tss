const std = @import("std");
const opts = @import("build-options");
const macho = @import("../macho.zig");

pub const Builder = @This();

header: macho.BuildVersionCommand,
tool: macho.BuildToolVersion,

pub fn init() Builder {
    const tss_version: macho.Version = .{
        .major = opts.semver.major,
        .minor = opts.semver.minor,
        .patch = opts.semver.patch,
    };

    return .{
        .header = .{
            .cmd = .BUILD_VERSION,
            .cmdsize = @sizeOf(macho.BuildVersionCommand),
            .platform = .UNKNOWN,
            .minos = 0,
            .sdk = 0,
            .ntools = 0,
        },
        .tool = .{
            .tool = .TSS,
            .version = @bitCast(tss_version),
        },
    };
}

test "uses default version" {
    const bv = init();
    const actual: macho.Version = @bitCast(bv.tool.version);
    const expected: macho.Version = .{ .major = 0, .minor = 0, .patch = 1 };
    try std.testing.expectEqual(expected, actual);
}
