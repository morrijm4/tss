const std = @import("std");

const Io = std.Io;
const mem = std.mem;

const m = @import("../macho.zig");

pub const macho = @import("./macho.zig");
pub const segment = @import("./segment.zig");
pub const section = @import("./section.zig");
pub const build_version = @import("./build-version.zig");
pub const load_command = @import("./load-command.zig");

test {
    @import("std").testing.refAllDecls(@This());
}

test "adding sections to a segment" {
    const gpa = std.testing.allocator;

    var buf: [512]u8 = @splat(0);
    var writer = Io.Writer.fixed(&buf);
    var reader = Io.Reader.fixed(&buf);

    var seg = segment.Builder.init();
    defer seg.deinit(gpa);
    seg.setName("__TEXT");

    const section_idx = try seg.createSection(gpa);
    var sect = seg.getSectionRef(section_idx);
    try sect.setSectionName("__text");
    sect.setAlignment(2);
    try sect.addInstruction(gpa, 0xd28008a0);
    try sect.addInstruction(gpa, 0xd2800030);
    try sect.addInstruction(gpa, 0xd4001001);

    const offset = try seg.writeCommand(&writer, 0);
    try seg.writeData(&writer);

    const segment_header = try reader.takeStruct(m.SegmentCommand64, .native);
    try std.testing.expectEqualStrings("__TEXT", segment_header.segName());
    try std.testing.expectEqual(@sizeOf(m.SegmentCommand64) + @sizeOf(m.Section64), segment_header.cmdsize);
    try std.testing.expectEqual(16, offset);

    const section_header = try reader.takeStruct(m.Section64, .native);
    try std.testing.expectEqualStrings("__text", section_header.sectName());
    try std.testing.expectEqualStrings("__TEXT", section_header.segName());
    try std.testing.expectEqual(12, section_header.size);
    try std.testing.expectEqual(2, section_header.@"align");

    _ = try reader.takeInt(u32, .native);
    _ = try reader.takeInt(u32, .native);
    _ = try reader.takeInt(u32, .native);

    try std.testing.expectEqual(0, reader.takeInt(u32, .native));
}

test "macho builder appends a load command builder" {
    const gpa = std.testing.allocator;

    var builder = macho.init();
    defer builder.deinit(gpa);
    builder.setMagic(.magic64);
    builder.setCpuType(.ARM);
    builder.setCpuSubType(.{ .ARM = .ARM64_ALL });
    builder.setPointerType(.ptr64);
    builder.setFileType(.OBJECT);

    const segment_idx = try builder.createLoadCommand(gpa, .segment);
    const segment_cmd = builder.getLoadCommandRef(segment_idx);
    segment_cmd.segment.setName("__TEXT");
    segment_cmd.segment.setMaxVMProtection(.{ .READ = true, .EXEC = true });
    segment_cmd.segment.setInitVMProtection(.{ .READ = true, .EXEC = true });

    const section_idx = try segment_cmd.segment.createSection(gpa);
    const sect = segment_cmd.segment.getSectionRef(section_idx);
    try sect.setSectionName("__text");
    sect.setAlignment(2);
    sect.setFlags(0b10000000000000000000010000000000);
    try sect.addInstruction(gpa, 0xd28008a0);
    try sect.addInstruction(gpa, 0xd2800030);
    try sect.addInstruction(gpa, 0xd4001001);

    const build_version_idx = try builder.createLoadCommand(gpa, .build_version);
    const build_version_cmd = builder.getLoadCommandRef(build_version_idx);
    build_version_cmd.build_version.setPlatform(.MACOS);
    build_version_cmd.build_version.setMinOS(.{ .major = 26, .minor = 0, .patch = 0 });
    build_version_cmd.build_version.setSDKVersion(.{ .major = 0, .minor = 0, .patch = 0 });

    const symbol_table_idx = try builder.createLoadCommand(gpa, .symbol_table);
    const symbol_table_cmd = builder.getLoadCommandRef(symbol_table_idx);

    const _main_idx = try symbol_table_cmd.symbol_table.createExternalSymbol(gpa, "_main");
    const _main = symbol_table_cmd.symbol_table.getExternalSymbolRef(_main_idx);
    _main.setSection(1);

    const ltmp0_idx = try symbol_table_cmd.symbol_table.createLocalSymbol(gpa, "ltmp0");
    const ltmp0 = symbol_table_cmd.symbol_table.getLocalSymbolRef(ltmp0_idx);
    ltmp0.setSection(1);

    const dysymtab_idx = try builder.createLoadCommand(gpa, .dynamic_symbol_table);
    var dysymtab_cmd = builder.getLoadCommandRef(dysymtab_idx);

    var idx: u32 = 0;

    const nlocal: u32 = @intCast(symbol_table_cmd.symbol_table.local.items.len);
    dysymtab_cmd.dynamic_symbol_table.setLocalIndex(idx);
    dysymtab_cmd.dynamic_symbol_table.setLocalCount(nlocal);
    idx += nlocal;

    const nexternal: u32 = @intCast(symbol_table_cmd.symbol_table.external.items.len);
    dysymtab_cmd.dynamic_symbol_table.setExternalIndex(idx);
    dysymtab_cmd.dynamic_symbol_table.setExternalCount(nexternal);
    idx += nexternal;

    const nundefined: u32 = @intCast(symbol_table_cmd.symbol_table.undefined.items.len);
    dysymtab_cmd.dynamic_symbol_table.setUndefinedIndex(idx);
    dysymtab_cmd.dynamic_symbol_table.setUndefinedCount(nundefined);
    idx += nundefined;

    var buf: [512]u8 = undefined;
    var writer = Io.Writer.fixed(&buf);
    var reader = Io.Reader.fixed(&buf);

    try builder.write(&writer);

    const header = try reader.takeStruct(m.MachHeader64, .native);

    try std.testing.expectEqual(std.macho.MH_MAGIC_64, header.magic);
    try std.testing.expectEqual(std.macho.CPU_TYPE_ARM64, header.cputype);
    try std.testing.expectEqual(std.macho.CPU_SUBTYPE_ARM_ALL, header.cpusubtype);
    try std.testing.expectEqual(std.macho.MH_OBJECT, header.filetype);
    try std.testing.expectEqual(0, header.flags);
    try std.testing.expectEqual(4, header.ncmds);
    try std.testing.expectEqual(288, header.sizeofcmds);

    const cmds = try reader.take(header.sizeofcmds);
    var it = try std.macho.LoadCommandIterator.init(&header, cmds);

    while (try it.next()) |lc| {
        switch (lc.hdr.cmd) {
            .SEGMENT_64 => {
                const off =
                    @sizeOf(m.MachHeader64) +
                    @sizeOf(m.SegmentCommand64) +
                    @sizeOf(m.Section64) +
                    @sizeOf(m.BuildVersionCommand) +
                    @sizeOf(m.BuildToolVersion) +
                    @sizeOf(m.SymbolTableCommand) +
                    @sizeOf(m.DynamicSymbolTableCommand);

                const cmd = lc.cast(m.SegmentCommand64).?;
                try std.testing.expectEqualStrings("__TEXT", cmd.segName());
                try std.testing.expectEqual(0, cmd.vmaddr);
                try std.testing.expectEqual(12, cmd.vmsize);
                try std.testing.expectEqual(off, cmd.fileoff);
                try std.testing.expectEqual(12, cmd.filesize);
                const prot: std.macho.vm_prot_t = .{ .READ = true, .EXEC = true };
                try std.testing.expectEqualDeep(prot, cmd.maxprot);
                try std.testing.expectEqualDeep(prot, cmd.initprot);
                try std.testing.expectEqual(1, cmd.nsects);

                for (lc.getSections()) |sec| {
                    try std.testing.expectEqualStrings("__text", sec.sectName());
                    try std.testing.expectEqualStrings("__TEXT", sec.segName());
                    try std.testing.expectEqual(0, sec.addr);
                    try std.testing.expectEqual(12, sec.size);
                    try std.testing.expectEqual(off, sec.offset);
                    try std.testing.expectEqual(2, sec.@"align");
                }
            },
            .BUILD_VERSION => {
                const cmd = lc.cast(m.BuildVersionCommand).?;
                try std.testing.expectEqual(32, cmd.cmdsize);
                try std.testing.expectEqual(.MACOS, cmd.platform);
                const minos: u32 = @bitCast(m.Version{ .major = 26, .minor = 0, .patch = 0 });
                try std.testing.expectEqual(minos, cmd.minos);
                const sdk: u32 = @bitCast(m.Version{ .major = 0, .minor = 0, .patch = 0 });
                try std.testing.expectEqual(sdk, cmd.sdk);
                try std.testing.expectEqual(1, cmd.ntools);
            },
            .SYMTAB => {
                const cmd = lc.cast(m.SymbolTableCommand).?;
                try std.testing.expectEqual(24, cmd.cmdsize);
                try std.testing.expectEqual(336, cmd.symoff);
                try std.testing.expectEqual(2, cmd.nsyms);
                try std.testing.expectEqual(368, cmd.stroff);
                try std.testing.expectEqual(16, cmd.strsize);
            },
            .DYSYMTAB => {
                const cmd = lc.cast(m.DynamicSymbolTableCommand).?;
                try std.testing.expectEqual(0, cmd.ilocalsym);
                try std.testing.expectEqual(1, cmd.nlocalsym);
                try std.testing.expectEqual(1, cmd.iextdefsym);
                try std.testing.expectEqual(1, cmd.nextdefsym);
                try std.testing.expectEqual(2, cmd.iundefsym);
                try std.testing.expectEqual(0, cmd.nundefsym);
            },
            else => unreachable,
        }
    }

    try std.testing.expectEqual(0xd28008a0, try reader.takeInt(u32, .native));
    try std.testing.expectEqual(0xd2800030, try reader.takeInt(u32, .native));
    try std.testing.expectEqual(0xd4001001, try reader.takeInt(u32, .native));
}
