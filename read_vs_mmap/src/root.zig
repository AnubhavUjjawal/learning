const std = @import("std");
const builtin = @import("builtin");
const mem = std.mem;
const heap = std.heap;
const debug = std.debug;
const fs = std.fs;
const posix = std.posix;
const os = std.os;
const fmt = std.fmt;

const Random = std.Random;

/// Only prints if we are NOT in a ReleaseFast or ReleaseSmall mode
pub fn debugPrint(comptime fmtstring: []const u8, args: anytype) void {
    if (builtin.mode != .ReleaseFast and builtin.mode != .ReleaseSmall) {
        std.debug.print("[debug]: ", .{});
        std.debug.print(fmtstring, args);
    }
}

pub const errors = error{ InvalidCommand, NoFilenameOrSizeProvided, NoFilenameOrReadBlockSizeProvided, FileExists };

/// This runner includes very basic command parsing
pub const Runner = struct {
    const generate_file_cmd = "generate-file";
    const read_file_mmap_cmd = "read-file-mmap";

    pub fn run(allocator: mem.Allocator, cmd: []u8, args: [][:0]u8) !void {
        if (std.mem.eql(u8, cmd, generate_file_cmd)) {
            debugPrint("generating a large file\n", .{});
            try generate_file(allocator, args);
        } else if (std.mem.eql(u8, cmd, read_file_mmap_cmd)) {
            debugPrint("reading the large file using mmap\n", .{});
            try read_file_mmap(allocator, args);
        } else {
            return errors.InvalidCommand;
        }
    }

    /// args[0] is filename, args[1] is the blocksize in KB
    /// args[2] is the number of iterations we want to do.
    pub fn read_file_mmap(allocator: mem.Allocator, args: [][:0]u8) !void {
        if (args.len != 3) {
            return errors.NoFilenameOrReadBlockSizeProvided;
        }

        const filepath = args[0];
        const blocksize = try fmt.parseInt(usize, args[1], 10);
        const iterations = try fmt.parseInt(usize, args[2], 10);
        debugPrint("filepath: {s}, blocksize: {d}, iterations: {d}\n", .{ filepath, blocksize, iterations });
        const cwd = fs.cwd();
        const file_stat = try cwd.statFile(filepath);
        debugPrint("filestat: {any}\n", .{file_stat});
        const file = try cwd.openFile(filepath, .{
            .mode = .read_only,
            .lock = .exclusive,
        });
        const mmap_p = try posix.mmap(null, file_stat.size, posix.PROT.READ, .{
            .TYPE = .PRIVATE,
        }, file.handle, 0);
        defer posix.munmap(mmap_p);
        debugPrint("initial byte: {s}, mmap len: {d}\n", .{ mmap_p[0..8], mmap_p.len });
        var seed: u64 = undefined;
        try std.posix.getrandom(std.mem.asBytes(&seed));
        debugPrint("seed: {d}\n", .{seed});
        // now, we want to do random reads of size `blocksize` multiple times.
        var prng: Random.DefaultPrng = .init(seed);
        const rand = prng.random();
        var search_idx = rand.intRangeAtMost(u64, 0, file_stat.size - (1 + blocksize * 1024));
        const read_buffer = try allocator.alloc(u8, blocksize * 1024);
        defer allocator.free(read_buffer);
        for (0..iterations) |_| {
            @memcpy(read_buffer, mmap_p[search_idx..(search_idx + (blocksize * 1024))]);
            search_idx = rand.intRangeAtMost(u64, 0, file_stat.size - (1 + blocksize * 1024));
        }
    }

    /// args[0] is filename, args[1] is filesize in mb
    pub fn generate_file(allocator: mem.Allocator, args: [][:0]u8) !void {
        if (args.len != 2) {
            return errors.NoFilenameOrSizeProvided;
        }
        const filepath = args[0];
        const filesize_wanted_in_kb = (try fmt.parseInt(u64, args[1], 10)) * 1024;
        const cwd = fs.cwd();
        const cwd_path = try cwd.realpathAlloc(allocator, ".");
        defer allocator.free(cwd_path);
        debugPrint("cwd: {s}, filepath: {s} filesize(in kb): {d}\n", .{ cwd_path, filepath, filesize_wanted_in_kb });

        var eight_kb_buffer: [1024 * 8]u8 = [_]u8{ 'A', 'n', 'u', 'b', 'h', 'a', 'v', '.' } ** 1024;
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
