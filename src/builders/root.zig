const std = @import("std");

const Io = std.Io;
const mem = std.mem;

const m = @import("../macho.zig");

pub const macho = @import("./macho.zig");
pub const segment = @import("./segment.zig");
pub const section = @import("./section.zig");
pub const load_command = @import("./load-command.zig");

test {
    @import("std").testing.refAllDecls(@This());
}

test "adding sections to a segment" {
    const gpa = std.testing.allocator;

    var buf: [512]u8 = @splat(0);
    var writer = Io.Writer.fixed(&buf);
    var reader = Io.Reader.fixed(&buf);

    const segname = "__TEXT";
    var sect = section.Builder.init();
    defer sect.deinit(gpa);
    _ = sect.setSectionName("__text")
        .setSegmentName(segname)
        .setAlignment(2);

    try sect.addInstruction(gpa, 0xd28008a0);
    try sect.addInstruction(gpa, 0xd2800030);
    try sect.addInstruction(gpa, 0xd4001001);

    var seg = segment.Builder.init();
    defer seg.deinit(gpa);
    _ = seg.setName(segname);
    try seg.addSection(gpa, &sect);
    const offset = try seg.writeCommand(&writer, 0);
    try seg.writeData(&writer);

    const segment_header = try reader.takeStruct(m.SegmentCommand64, .native);
    try std.testing.expectEqualStrings(segname, segment_header.segName());
    try std.testing.expectEqual(@sizeOf(m.SegmentCommand64) + @sizeOf(m.Section64), segment_header.cmdsize);
    try std.testing.expectEqual(12, offset);

    const section_header = try reader.takeStruct(m.Section64, .native);
    try std.testing.expectEqualStrings("__text", section_header.sectName());
    try std.testing.expectEqualStrings(segname, section_header.segName());
    try std.testing.expectEqual(12, section_header.size);
    try std.testing.expectEqual(2, section_header.@"align");

    _ = try reader.takeInt(u32, .native);
    _ = try reader.takeInt(u32, .native);
    _ = try reader.takeInt(u32, .native);

    try std.testing.expectEqual(0, reader.takeInt(u32, .native));
}

test "macho builder appends a load command builder" {
    const gpa = std.testing.allocator;

    var sect = section.init();
    defer sect.deinit(gpa);

    const segment_name = "__TEXT";
    _ = sect
        .setSegmentName(segment_name)
        .setSectionName("__text")
        .setAlignment(2);
    try sect.addInstruction(gpa, 0xd28008a0);
    try sect.addInstruction(gpa, 0xd2800030);
    try sect.addInstruction(gpa, 0xd4001001);

    var seg = segment.init();
    defer seg.deinit(gpa);
    _ = seg
        .setName(segment_name)
        .setMaxVMProtection(.{ .READ = true, .EXEC = true })
        .setInitVMProtection(.{ .READ = true, .EXEC = true });
    try seg.addSection(gpa, &sect);

    var builder = macho.init();
    defer builder.deinit(gpa);
    const self = builder
        .setMagic(.magic64)
        .setCpuType(.ARM)
        .setCpuSubType(.{ .ARM = .ARM64_ALL })
        .setPointerType(.ptr64)
        .setFileType(.OBJECT);
    var load_cmd = load_command.from(&seg);
    try builder.addLoadCommand(gpa, &load_cmd);

    var buf: [512]u8 = undefined;
    var writer = Io.Writer.fixed(&buf);
    var reader = Io.Reader.fixed(&buf);

    try builder.write(&writer);

    const header = try reader.takeStruct(m.MachHeader64, .native);

    try std.testing.expectEqual(&builder, self);
    try std.testing.expectEqual(std.macho.MH_MAGIC_64, header.magic);
    try std.testing.expectEqual(std.macho.CPU_TYPE_ARM64, header.cputype);
    try std.testing.expectEqual(std.macho.CPU_SUBTYPE_ARM_ALL, header.cpusubtype);
    try std.testing.expectEqual(std.macho.MH_OBJECT, header.filetype);
    try std.testing.expectEqual(1, header.ncmds);
    try std.testing.expectEqual(152, header.sizeofcmds);
    try std.testing.expectEqual(builder.load_commands.items.len, 1);

    const cmds = try reader.take(header.sizeofcmds);
    var it = try std.macho.LoadCommandIterator.init(&header, cmds);

    while (try it.next()) |lc| {
        switch (lc.hdr.cmd) {
            .SEGMENT_64 => {
                const cmd = lc.cast(m.SegmentCommand64).?;
                try std.testing.expectEqualStrings("__TEXT", cmd.segName());
                try std.testing.expectEqual(0, cmd.vmaddr);
                try std.testing.expectEqual(12, cmd.vmsize);
                const off = @sizeOf(m.MachHeader64) + @sizeOf(m.SegmentCommand64) + @sizeOf(m.Section64);
                try std.testing.expectEqual(off, cmd.fileoff);
                try std.testing.expectEqual(12, cmd.filesize);
                const prot: std.macho.vm_prot_t = .{
                    .READ = true,
                    .EXEC = true,
                };
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
            else => unreachable,
        }
    }

    try std.testing.expectEqual(0xd28008a0, try reader.takeInt(u32, .native));
    try std.testing.expectEqual(0xd2800030, try reader.takeInt(u32, .native));
    try std.testing.expectEqual(0xd4001001, try reader.takeInt(u32, .native));
}
