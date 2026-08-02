const std = @import("std");
const Io = std.Io;
const mem = std.mem;

const macho = @import("../macho.zig");

const Builder = @This();

header: macho.SymbolTableCommand,
symbols: std.ArrayList(macho.Symbol64),
strings: std.ArrayList(u8),

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
        .symbols = .empty,
        .strings = .empty,
    };
}

pub fn deinit(self: *Builder, gpa: mem.Allocator) void {
    self.symbols.deinit(gpa);
    self.strings.deinit(gpa);
}

pub fn writeCommand(self: *Builder, w: *Io.Writer, offset: u64) Io.Writer.Error!void {}
pub fn writeData(self: *Builder, w: *Io.Writer) Io.Writer.Error!void {}
