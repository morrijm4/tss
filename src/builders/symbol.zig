const std = @import("std");
const Io = std.Io;
const macho = @import("../macho.zig");

pub const Builder = @This();

symbol: []const u8,
header: macho.Symbol64,

const SymbolType = @FieldType(std.macho.nlist_64, "n_type");
const SymbolDescription = @FieldType(std.macho.nlist_64, "n_desc");
const SymbolBits = @FieldType(SymbolType, "bits");
const SymbolDebugKind = @FieldType(SymbolType, "stab");
const SymbolKind = @FieldType(SymbolBits, "type");

pub fn init() Builder {
    return .{
        .symbol = &.{},
        .header = .{
            .n_strx = 0,
            .n_type = .{
                .bits = .{
                    .ext = false,
                    .type = .undf,
                    .pext = false,
                    .is_stab = 0,
                },
            },
            .n_sect = 0,
            .n_desc = .{
                .arm_thumb_def = false,
                .referenced_dynamically = false,
                .discarded_or_no_dead_strip = false,
                .weak_ref = false,
                .weak_def_or_ref_to_weak = false,
                .symbol_resolver = false,
                .alt_entry = false,
            },
            .n_value = 0,
        },
    };
}

pub fn setSymbol(self: *Builder, symbol: []const u8) void {
    self.symbol = symbol;
}

pub fn setOffset(self: *Builder, offset: u32) void {
    self.header.n_strx = offset;
}

pub fn setType(self: *Builder, symbol_type: SymbolType) void {
    self.header.n_type = symbol_type;
}

pub fn setSection(self: *Builder, idx: u8) void {
    self.header.n_sect = idx;
}

pub fn setDescription(self: *Builder, desc: SymbolDescription) void {
    self.header.n_desc = desc;
}

pub fn setValue(self: *Builder, value: u64) void {
    self.header.n_value = value;
}

pub fn write(self: *Builder, w: *Io.Writer) Io.Writer.Error!void {
    try w.writeStruct(self.header, .native);
}
