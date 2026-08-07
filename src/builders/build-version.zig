const std = @import("std");
const opts = @import("build-options");
const macho = @import("../macho.zig");

const Io = std.Io;

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
            .cmdsize = @sizeOf(macho.BuildVersionCommand) + @sizeOf(macho.BuildToolVersion),
            .platform = .UNKNOWN,
            .minos = 0,
            .sdk = 0,
            .ntools = 1,
        },
        .tool = .{
            .tool = .TSS,
            .version = @bitCast(tss_version),
        },
    };
}

pub fn setPlatform(self: *Builder, platform: std.macho.PLATFORM) void {
    self.header.platform = platform;
}

pub fn setMinOS(self: *Builder, minos: macho.Version) void {
    self.header.minos = @bitCast(minos);
}

pub fn setSDKVersion(self: *Builder, sdk: macho.Version) void {
    self.header.sdk = @bitCast(sdk);
}

pub fn writeCommand(self: *Builder, w: *Io.Writer) Io.Writer.Error!void {
    try w.writeStruct(self.header, .native);
    try w.writeStruct(self.tool, .native);
}

test "uses default version" {
    const bv = init();
    const actual: macho.Version = @bitCast(bv.tool.version);
    const expected: macho.Version = .{ .major = 0, .minor = 0, .patch = 1 };
    try std.testing.expectEqual(expected, actual);
}
