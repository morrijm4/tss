const std = @import("std");
const segment = @import("./segment.zig");

pub const Builder = union(enum) {
    segment: segment.Builder,

    pub fn deinit(self: *Builder, allocator: std.mem.Allocator) void {
        switch (self.*) {
            .segment => |*cmd| cmd.deinit(allocator),
        }
    }

    /// Returns number of bytes to extend the offset
    pub fn writeCommand(self: *Builder, writer: *std.Io.Writer, offset: u64) std.Io.Writer.Error!u64 {
        switch (self.*) {
            .segment => |*cmd| return try cmd.writeCommand(writer, offset),
        }
    }

    pub fn writeData(self: *const Builder, writer: *std.Io.Writer) std.Io.Writer.Error!void {
        try switch (self.*) {
            .segment => |cmd| cmd.writeData(writer),
        };
    }

    pub fn getSize(self: *const Builder) u32 {
        switch (self.*) {
            .segment => |cmd| return cmd.header.cmdsize,
        }
    }

    pub fn reset(self: *Builder) void {
        switch (self.*) {
            .segment => self.*.segment = segment.init(),
        }
    }
};

// pub fn from(builder: anytype) Builder {
//     const B = @TypeOf(builder);
//     const fields = @typeInfo(Builder).@"union".fields;
//     inline for (fields) |field| {
//         if (field.type == B) return @unionInit(Builder, field.name, builder);
//     }
//     @compileError("Builder.from: no variant with type " ++ @typeName(B));
// }

pub fn from(builder_ptr: anytype) Builder {
    const P = @TypeOf(builder_ptr);
    const info = @typeInfo(P);
    if (info != .pointer or info.pointer.size != .one)
        @compileError("Builder.from expects a *pointer* to a builder (it consumes it)");
    const B = info.pointer.child;

    const fields = @typeInfo(Builder).@"union".fields;
    inline for (fields) |field| {
        if (field.type == B) {
            const result = @unionInit(Builder, field.name, builder_ptr.*);
            builder_ptr.* = B.init(); // consume: source no longer owns anything
            return result;
        }
    }
    @compileError("Builder.from: no variant with type " ++ @typeName(B));
}
