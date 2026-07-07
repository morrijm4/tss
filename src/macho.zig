const std = @import("std");
const Options = @import("./opts.zig").Options;

const Io = std.Io;
const log = std.log.scoped(.macho);

const MachO = @This();

contents: []const u8,

const MachHeader64 = std.macho.mach_header_64;
const LoadCommandIterator = std.macho.LoadCommandIterator;
const LoadCommand = std.macho.LoadCommandIterator.LoadCommand;
const SegmentCommand64 = std.macho.segment_command_64;
const BuildVersionCommand = std.macho.build_version_command;
const SymbolTableCommand = std.macho.symtab_command;
const DynamicSymbolTableCommand = std.macho.dysymtab_command;
const UUIDCommand = std.macho.uuid_command;
const Section64 = std.macho.section_64;

pub const CPU_TYPE_64_MASK = 0x01000000;
pub const CPU_TYPE_64_32_PTRS_MASK = 0x02000000;

pub const CpuType = enum(std.macho.cpu_type_t) {
    NONE = 0x0,
    VAX = 0x1,
    ROMP = 0x2,
    NS32032 = 0x4,
    NS32332 = 0x5,
    MC680x0 = 0x6,
    x86 = 0x7,
    MIPS = 0x8,
    NS32352 = 0x9,
    @"HP-PA" = 0xb,
    ARM = 0xc,
    MC88000 = 0xd,
    SPARC = 0xe,
    i860_BIG = 0xf,
    i860_SMALL = 0x10,
    @"RS/6000" = 0x11,
    PowerPC = 0x12,
    @"RISC-V" = 0x18,
    _,
};

pub const CpuSubType = union(CpuType) {
    ARM: Arm64SubType,
    x86: X86SubType,
};

pub const Arm64SubType = enum(std.macho.cpu_subtype_t) {
    ARM64_ALL = 0,
    ARM64_V8 = 1,
    ARM64E = 2,
    _,
};

pub const X86SubType = enum(std.macho.cpu_subtype_t) {
    x86_ALL = 3,
    x86_ARCH1 = 1,
    /// Haswell feature subset
    x86_64_H = 2,
    _,
};

///
/// The layout of the file depends on the filetype.  For all but the MH_OBJECT
/// file type the segments are padded out and aligned on a segment alignment
/// boundary for efficient demand pageing.  The MH_EXECUTE, MH_FVMLIB, MH_DYLIB,
/// MH_DYLINKER and MH_BUNDLE file types also have the headers included as part
/// of their first segment.
///
/// The file type MH_OBJECT is a compact format intended as output of the
/// assembler and input (and possibly output) of the link editor (the .o
/// format).  All sections are in one unnamed segment with no segment padding.
/// This format is used as an executable format when the file is so small the
/// segment padding greatly increases its size.
///
/// The file type MH_PRELOAD is an executable format intended for things that
/// are not executed under the kernel (proms, stand alones, kernels, etc).  The
/// format can be executed under the kernel but may demand paged it and not
/// preload it before execution.
///
/// A core file is in MH_CORE format and can be any in an arbritray legal
/// Mach-O file.
///
/// Constants for the filetype field of the mach_header
///
const FileType = enum(u32) {
    /// relocatable object file
    OBJECT = 0x1,
    /// demand paged executable file
    EXECUTE = 0x2,
    /// fixed VM shared library file
    FVMLIB = 0x3,
    /// core file
    CORE = 0x4,
    /// preloaded executable file
    PRELOAD = 0x5,
    /// dynamically bound shared library
    DYLIB = 0x6,
    /// dynamic link editor
    DYLINKER = 0x7,
    /// dynamically bound bundle file
    BUNDLE = 0x8,
    /// shared library stub for static
    /// linking only, no section contents
    DYLIB_STUB = 0x9,
    /// companion file with only debug
    ///  sections
    DSYM = 0xa,
    /// x86_64 kexts
    KEXT_BUNDLE = 0xb,
    /// set of mach-o's
    FILESET = 0xc,
    _,
};

pub const Symbol64 = packed struct {
    nameoff: u32,
    type: u8,
    secnum: u8,
    datainfo: u16,
    symaddr: u64,
};

pub const Version = packed struct {
    patch: u8,
    minor: u8,
    major: u16,
};

pub const InitOptions = struct {
    endian: std.builtin.Endian = .native,
};

const MachoInitError = Io.Reader.LimitedAllocError;

pub fn init(allocator: std.mem.Allocator, reader: *Io.Reader) MachoInitError!MachO {
    const contents = try reader.allocRemaining(allocator, .unlimited);
    errdefer allocator.free(contents);

    return .{
        .contents = contents,
    };
}

pub fn deinit(self: *MachO, allocator: std.mem.Allocator) void {
    allocator.free(self.contents);
}

pub fn getHeader(self: *MachO) MachHeader64 {
    return std.mem.bytesToValue(MachHeader64, self.contents[0..@sizeOf(MachHeader64)]);
}

pub fn getLoadCommandIterator(self: *MachO) error{InvalidMachO}!LoadCommandIterator {
    const header = self.getHeader();
    return try .init(&header, self.contents[@sizeOf(MachHeader64)..][0..header.sizeofcmds]);
}

pub fn getCpuType(cputype: u32) ?CpuType {
    const bitVersionMask = 0xF0FFFFFF;
    return std.enums.fromInt(CpuType, bitVersionMask & cputype);
}

pub fn getFileType(filetype: u32) ?FileType {
    return std.enums.fromInt(FileType, filetype);
}

pub const PrintError = Io.Writer.Error || Io.File.Reader.SeekError || error{ InvalidMachO, NoSpaceLeft };

pub fn print(self: *MachO, w: *Io.Writer) PrintError!void {
    try printMachHeader64(self, w);

    var it = try self.getLoadCommandIterator();
    try w.print("Load Commands:\n", .{});
    while (try it.next()) |lc| {
        try w.print("* Command => {} (0x{x:0>8}), Size => {}\n", .{
            lc.hdr.cmd,
            lc.hdr.cmd,
            lc.hdr.cmdsize,
        });
        switch (lc.hdr.cmd) {
            .SEGMENT_64 => {
                const cmd = lc.cast(SegmentCommand64).?;
                try printSegmentCommand64(cmd, w);
                for (lc.getSections()) |section| {
                    try self.printSection64(section, w);
                }
            },
            .BUILD_VERSION => try printBuildVersionCommand(lc, w),
            .SYMTAB => try self.printSymbolTable(lc, w),
            .DYSYMTAB => try printDynamicSymbolTable(lc, w),
            .UUID => try printUUIDCommand(lc, w),
            else => {},
        }
    }
}

pub fn printMachHeader64(self: *MachO, w: *Io.Writer) PrintError!void {
    const hdr = self.getHeader();
    const rawcputype = @as(u32, @bitCast(hdr.cputype));
    const rawcpusubtype = @as(u32, @bitCast(hdr.cpusubtype));

    const cputype = getCpuType(rawcputype);
    const filetype = getFileType(hdr.filetype);

    var buf: [16]u8 = undefined;
    const cpusubtype = if (cputype != null) switch (cputype.?) {
        .ARM => try std.fmt.bufPrint(&buf, "{?}", .{std.enums.fromInt(Arm64SubType, hdr.cpusubtype)}),
        .x86 => try std.fmt.bufPrint(&buf, "{?}", .{std.enums.fromInt(X86SubType, hdr.cpusubtype)}),
        else => null,
    } else null;

    try w.print("Magic => 0x{x:0>8}\n", .{hdr.magic});
    try w.print("CPU Type => {?} (0x{x:0>8})\n", .{ cputype, rawcputype });
    try w.print("CPU Subtype => {?s} (0x{x:0>8})\n", .{ cpusubtype, rawcpusubtype });
    try w.print("File type => {?} (0x{x:0>8})\n", .{ filetype, hdr.filetype });
    try w.print("Number of load commands => {}\n", .{hdr.ncmds});
    try w.print("Load commands size => {}\n", .{hdr.sizeofcmds});
    try w.print("Flags => 0b{b:0>32}\n", .{hdr.flags});
    try w.print("\n", .{});
}

pub fn printSegmentCommand64(cmd: SegmentCommand64, w: *Io.Writer) Io.Writer.Error!void {
    try w.print("\t- Name => {s}\n", .{cmd.segName()});
    try w.print("\t- VM Address => 0x{x:0>16}\n", .{cmd.vmaddr});
    try w.print("\t- VM Size => {d}\n", .{cmd.vmsize});
    try w.print("\t- File Offset => {d}\n", .{cmd.fileoff});
    try w.print("\t- File Size => {d}\n", .{cmd.filesize});
    try w.print("\t- Max VM Protection => {}\n", .{cmd.maxprot});
    try w.print("\t- Initial VM Protection => {}\n", .{cmd.initprot});
    try w.print("\t- Number of Sections => {d}\n", .{cmd.nsects});
    try w.print("\t- Flags => 0b{b:0>32}\n", .{cmd.flags});
    try w.print("\t- Sections:\n", .{});
}

pub fn printSection64(self: *MachO, section: Section64, w: *Io.Writer) Io.Writer.Error!void {
    const name = section.sectName();
    try w.print("\t\t> Section Name => {s}\n", .{name});
    try w.print("\t\t> Segment Name => {s}\n", .{section.segName()});
    try w.print("\t\t> Section Address => 0x{x:0>16}\n", .{section.addr});
    try w.print("\t\t> Section Size => {d}\n", .{section.size});
    try w.print("\t\t> Section File Offset => {d}\n", .{section.offset});
    try w.print("\t\t> Alignment => {d}\n", .{section.@"align"});
    try w.print("\t\t> Relocations File Offset => {d}\n", .{section.reloff});
    try w.print("\t\t> Number of Relocations => {d}\n", .{section.nreloc});
    try w.print("\t\t> Flags/Type => 0b{b:0>32}\n", .{section.flags});
    try w.print("\t\t> Reserved1 => {d}\n", .{section.reserved1});
    try w.print("\t\t> Reserved2 => {d}\n", .{section.reserved2});
    try w.print("\t\t> Reserved3 => {d}\n", .{section.reserved3});
    try w.print("\n", .{});

    if (section.isCode()) {
        const instructions = std.mem.bytesAsSlice(u32, self.contents[section.offset..][0..section.size]);
        for (instructions) |ins| {
            try w.print("\t\t0x{x:0>8}\n", .{ins});
        }
        try w.print("\n", .{});
    }
}

pub fn printBuildVersionCommand(lc: LoadCommand, w: *Io.Writer) Io.Writer.Error!void {
    const cmd = lc.cast(BuildVersionCommand).?;
    const minos: Version = @bitCast(cmd.minos);
    const sdk: Version = @bitCast(cmd.sdk);

    try w.print("\t- Platform Type => {} (0x{x:0>8})\n", .{ cmd.platform, cmd.platform });
    const version = .{ minos.major, minos.minor, minos.patch };
    try w.print("\t- Minimum OS Version => v{}.{}.{}\n", version);
    try w.print("\t- SDK Version => v{}.{}.{}\n", .{ sdk.major, sdk.minor, sdk.patch });
    try w.print("\t- Number of Tools => {}\n", .{cmd.ntools});
    try w.print("\t- Tools:\n", .{});

    const tools = lc.getBuildVersionTools();
    for (tools) |t| {
        const v: Version = @bitCast(t.version);
        try w.print("\t\t> Tool => {} (v{}.{}.{})\n", .{ t.tool, v.major, v.minor, v.patch });
    }
}

pub fn printSymbolTable(self: *MachO, lc: LoadCommand, w: *Io.Writer) Io.Writer.Error!void {
    const cmd = lc.cast(SymbolTableCommand).?;
    try w.print("\t- Symbols offset => {d}\n", .{cmd.symoff});
    try w.print("\t- Number of symbols => {d}\n", .{cmd.nsyms});
    try w.print("\t- String table offset => {d}\n", .{cmd.stroff});
    try w.print("\t- String table size => {d}\n", .{cmd.strsize});
    try w.print("\t- Symbols:\n", .{});

    const symbolSlice = self.contents[cmd.symoff..(@sizeOf(Symbol64) * cmd.nsyms + cmd.symoff)];
    const symbols: []align(1) const Symbol64 = std.mem.bytesAsSlice(Symbol64, symbolSlice);
    for (symbols, 0..) |sym, i| {
        const offset = cmd.stroff + sym.nameoff;
        const name = std.mem.sliceTo(self.contents[offset..], 0);
        try w.print("\t\t> Name => {d}. {s}\n", .{ i, name });
        try w.print("\t\t> Name Offset => {d}\n", .{sym.nameoff});
        try w.print("\t\t> Type => 0b{b:0>8}\n", .{sym.type});
        try w.print("\t\t> Section Number => {d}\n", .{sym.secnum});
        try w.print("\t\t> Data info => {d}\n", .{sym.datainfo});
        try w.print("\t\t> Symbol address => 0x{x:0>16}\n", .{sym.symaddr});
        try w.print("\n", .{});
    }
}

pub fn printDynamicSymbolTable(lc: LoadCommand, w: *Io.Writer) Io.Writer.Error!void {
    const cmd = lc.cast(DynamicSymbolTableCommand).?;
    try w.print("\t- Index of local symbols => {}\n", .{cmd.ilocalsym});
    try w.print("\t- Number of local symbols => {}\n", .{cmd.nlocalsym});
    try w.print("\t- Index of external symbols => {}\n", .{cmd.iextdefsym});
    try w.print("\t- Number of external symbols => {}\n", .{cmd.nextdefsym});
    try w.print("\t- Index of undefined symbols => {}\n", .{cmd.iundefsym});
    try w.print("\t- Number of undefined symbols => {}\n", .{cmd.nundefsym});
    try w.print("\t- Table of contents offset => {}\n", .{cmd.tocoff});
    try w.print("\t- Number of table of contents entries => {}\n", .{cmd.ntoc});
    try w.print("\t- Module table offset => {}\n", .{cmd.modtaboff});
    try w.print("\t- Number of module table entries => {}\n", .{cmd.nmodtab});
    try w.print("\t- Referenced symbol table offset => {}\n", .{cmd.extrefsymoff});
    try w.print("\t- Number of referenced symbol table entries => {}\n", .{cmd.nextrefsyms});
    try w.print("\t- Indirect symbol table offset => {}\n", .{cmd.indirectsymoff});
    try w.print("\t- Number of indirect symbol table entries => {}\n", .{cmd.nindirectsyms});
    try w.print("\t- External relocation entries offset => {}\n", .{cmd.extreloff});
    try w.print("\t- Number of external relocation entries => {}\n", .{cmd.nextrel});
    try w.print("\t- Local relocation entries offset => {}\n", .{cmd.locreloff});
    try w.print("\t- Number of local relocation entries => {}\n", .{cmd.nlocrel});
}

pub fn printUUIDCommand(lc: LoadCommand, w: *Io.Writer) Io.Writer.Error!void {
    const cmd = lc.cast(UUIDCommand).?;
    const uuid = cmd.uuid;

    const timeLow = std.fmt.bytesToHex(uuid[0..4], .lower);
    const timeMid = std.fmt.bytesToHex(uuid[4..6], .lower);
    const timeHighAndVersion = std.fmt.bytesToHex(uuid[6..8], .lower);
    const clockSequence = std.fmt.bytesToHex(uuid[8..10], .lower);
    const node = std.fmt.bytesToHex(uuid[10..16], .lower);

    try w.print("\t- UUID => {s}-{s}-{s}-{s}-{s}\n", .{
        timeLow,
        timeMid,
        timeHighAndVersion,
        clockSequence,
        node,
    });
}
