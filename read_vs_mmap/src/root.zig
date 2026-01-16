const std = @import("std");
const builtin = @import("builtin");
const mem = std.mem;
const heap = std.heap;
const debug = std.debug;
const fs = std.fs;
const crypto = std.crypto;
const fmt = std.fmt;

/// Only prints if we are NOT in a ReleaseFast or ReleaseSmall mode
pub fn debugPrint(comptime fmtstring: []const u8, args: anytype) void {
    if (builtin.mode != .ReleaseFast and builtin.mode != .ReleaseSmall) {
        std.debug.print("[debug]: ", .{});
        std.debug.print(fmtstring, args);
    }
}

pub const errors = error{ InvalidCommand, NoFilenameProvided, FileExists };

/// This runner includes very basic command parsing
pub const Runner = struct {
    const generate_file_cmd = "generate-file";

    pub fn run(allocator: mem.Allocator, cmd: []u8, args: [][:0]u8) !void {
        if (std.mem.eql(u8, cmd, generate_file_cmd)) {
            debugPrint("generating a large file\n", .{});
            try generate_file(allocator, args);
        } else {
            return errors.InvalidCommand;
        }
    }

    /// args[0] is filename, args[1] is filesize in mb
    pub fn generate_file(allocator: mem.Allocator, args: [][:0]u8) !void {
        if (args.len != 2) {
            return errors.NoFilenameProvided;
        }
        const filepath = args[0];
        const filesize_wanted_in_kb = (try fmt.parseInt(u64, args[1], 10)) * 1024;
        const cwd = fs.cwd();
        const cwd_path = try cwd.realpathAlloc(allocator, ".");
        defer allocator.free(cwd_path);
        debugPrint("cwd: {s}, filepath: {s} filesize(in kb): {d}\n", .{ cwd_path, filepath, filesize_wanted_in_kb });

        var eight_kb_buffer: [1024 * 8]u8 = [_]u8{ '1', '2', '3', '4', '5', '6', '7', '8' } ** 1024;
        // crypto.random.bytes(eight_kb_buffer[0..]);
        debugPrint("random string slice check: {any}\n", .{eight_kb_buffer[0..5]});

        const new_file = try cwd.createFile(filepath, .{
            .exclusive = true,
            .lock = .exclusive,
        });
        var written_kb: u64 = 0;
        while (written_kb < filesize_wanted_in_kb) {
            // crypto.random.bytes(eight_kb_buffer[0..]);
            _ = try new_file.write(&eight_kb_buffer);
            written_kb += 8;
        }
        debugPrint("file generated\n", .{});
    }
};
