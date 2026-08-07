const std = @import("std");
const Io = std.Io;
const mem = std.mem;

const macho = @import("../macho.zig");
const sym = @import("./symbol.zig");

pub const Builder = @This();

header: macho.SymbolTableCommand,
local: std.ArrayList(sym.Builder),
external: std.ArrayList(sym.Builder),
undefined: std.ArrayList(sym.Builder),
lsize: u32,
esize: u32,
usize: u32,

pub fn init() Builder {
    return .{
        .header = .{
            .cmd = .SYMTAB,
            .cmdsize = @sizeOf(macho.SymbolTableCommand),
            .symoff = 0,
            .nsyms = 0,
            .stroff = 0,
            .strsize = 0,
        },
        .local = .empty,
        .external = .empty,
        .undefined = .empty,
        .lsize = 0,
        .esize = 0,
        .usize = 0,
    };
}

pub fn deinit(self: *Builder, gpa: mem.Allocator) void {
    self.local.deinit(gpa);
    self.external.deinit(gpa);
    self.undefined.deinit(gpa);
}

pub fn createLocalSymbol(self: *Builder, gpa: mem.Allocator, str: []const u8) mem.Allocator.Error!usize {
    var symbol = sym.init();
    symbol.setSymbol(str);
    symbol.setType(.{
        .bits = .{
            .type = .sect,
            .ext = false,
            .pext = false,
            .is_stab = 0,
        },
    });

    try self.local.append(gpa, symbol);

    self.header.nsyms += 1;
    self.lsize += @intCast(str.len + 1);
    return self.local.items.len - 1;
}

pub fn getLocalSymbolRef(self: *Builder, idx: usize) *sym.Builder {
    return &self.local.items[idx];
}

pub fn createExternalSymbol(self: *Builder, gpa: mem.Allocator, str: []const u8) mem.Allocator.Error!usize {
    var symbol = sym.init();
    symbol.setSymbol(str);
    symbol.setType(.{
        .bits = .{
            .type = .sect,
            .ext = true,
            .pext = false,
            .is_stab = 0,
        },
    });

    try self.external.append(gpa, symbol);

    self.header.nsyms += 1;
    self.esize += @intCast(str.len + 1);
    return self.external.items.len - 1;
}

pub fn getExternalSymbolRef(self: *Builder, idx: usize) *sym.Builder {
    return &self.external.items[idx];
}

pub fn createUndefinedSymbol(self: *Builder, gpa: mem.Allocator, str: []const u8) mem.Allocator.Error!usize {
    var symbol = sym.init();
    symbol.setSymbol(str);
    symbol.setType(.{
        .bits = .{
            .type = .undf,
            .ext = true,
            .pext = false,
            .is_stab = 0,
        },
    });

    try self.undefined.append(gpa, symbol);

    self.header.nsyms += 1;
    self.usize += @intCast(str.len + 1);
    return self.undefined.items.len - 1;
}

pub fn getUndefinedSymbolRef(self: *Builder, idx: usize) *sym.Builder {
    return &self.undefined.items[idx];
}

fn getStringsSize(self: *const Builder) u32 {
    return self.lsize + self.esize + self.usize + 1;
}

fn getStringPad(self: *const Builder) u32 {
    const alignment = 8;
    return alignment - (self.getStringsSize() % alignment);
}

pub fn writeCommand(self: *Builder, w: *Io.Writer, offset: u64) Io.Writer.Error!u64 {
    self.header.symoff = @intCast(offset);
    const symsize = self.header.nsyms * @sizeOf(macho.Symbol64);
    self.header.stroff = self.header.symoff + symsize;
    self.header.strsize = self.getStringsSize() + self.getStringPad();
    try w.writeStruct(self.header, .native);
    return symsize + self.header.strsize;
}

pub fn writeData(self: *const Builder, w: *Io.Writer) Io.Writer.Error!void {
    var offset: u32 = 1;

    for (self.local.items) |*item| {
        item.setOffset(offset);
        try item.write(w);
        offset += @intCast(item.symbol.len + 1);
    }
    for (self.external.items) |*item| {
        item.setOffset(offset);
        try item.write(w);
        offset += @intCast(item.symbol.len + 1);
    }
    for (self.undefined.items) |*item| {
        item.setOffset(offset);
        try item.write(w);
        offset += @intCast(item.symbol.len + 1);
    }

    try w.writeByte(0);
    for (self.local.items) |*item| {
        try w.writeAll(item.symbol);
        try w.writeByte(0);
    }
    for (self.external.items) |*item| {
        try w.writeAll(item.symbol);
        try w.writeByte(0);
    }
    for (self.undefined.items) |*item| {
        try w.writeAll(item.symbol);
        try w.writeByte(0);
    }

    try w.splatByteAll(0, self.getStringPad());
}
