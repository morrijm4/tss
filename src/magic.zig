const std = @import("std");

pub const Magic = enum(u32) {
    macho64bit = 0xfeedfacf,
};

pub fn assertMagic(magic: u32) error{InvalidMagic}!void {
    if (std.enums.fromInt(Magic, magic) == null) return error.InvalidMagic;
}
