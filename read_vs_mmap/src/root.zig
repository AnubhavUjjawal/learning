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
const sixteen_kb_in_bytes = 1024 * 16;

/// Assumption. I didn't have the patience to make it configurable for all systems.
/// Change according to your needs.
const os_page_size_in_bytes = sixteen_kb_in_bytes;

/// Only prints if we are NOT in a ReleaseFast or ReleaseSmall mode
pub fn debugPrint(comptime fmtstring: []const u8, args: anytype) void {
    if (builtin.mode != .ReleaseFast and builtin.mode != .ReleaseSmall) {
        std.debug.print("[debug]: ", .{});
        std.debug.print(fmtstring, args);
    }
}

pub const errors = error{ BlockMustEqualPageSize, InvalidCommand, NoFilenameOrSizeProvided, NoFilenameOrReadBlockSizeProvided, FileExists, ShortReadError };

/// This runner includes very basic command parsing
pub const Runner = struct {
    const generate_file_cmd = "generate-file";
    const read_file_mmap_cmd = "read-file-mmap";
    const read_file_pread_cmd = "read-file-pread";

    /// --aligned on generate-file command is a no op.
    /// When doing read tests, this flag reads from aligned pages
    /// So that when a page fault occurs for mmap test for 16KB block sizes, we read a single page instead of two
    /// In (Linux rpi1 6.12.62+rpt-rpi-2712 #1 SMP PREEMPT Debian 1:6.12.62-1+rpt1 (2025-12-18) aarch64 GNU/Linux) the page size is 16KB
    const aligned = "--aligned";

    pub fn run(allocator: mem.Allocator, cmd: []u8, args: [][:0]u8) !void {
        var is_aligned_test = false;
        var args_start_from: usize = 0;
        if (std.mem.eql(u8, args[0], aligned)) {
            is_aligned_test = true;
            args_start_from = 1;
        }
        if (std.mem.eql(u8, cmd, generate_file_cmd)) {
            debugPrint("generating a large file\n", .{});
            try generate_file(allocator, args);
        } else if (std.mem.eql(u8, cmd, read_file_mmap_cmd)) {
            debugPrint("reading the large file using mmap\n", .{});
            try read_file_mmap(allocator, args[args_start_from..], is_aligned_test);
        } else if (std.mem.eql(u8, cmd, read_file_pread_cmd)) {
            debugPrint("reading the large file using pread\n", .{});
            try read_file_pread(allocator, args[args_start_from..], is_aligned_test);
        } else {
            return errors.InvalidCommand;
        }
    }

    /// args[0] is filename, args[1] is the blocksize in KB
    /// args[2] is the number of iterations we want to do.
    pub fn read_file_pread(allocator: mem.Allocator, args: [][:0]u8, is_aligned_test: bool) !void {
        if (args.len < 3) {
            return errors.NoFilenameOrReadBlockSizeProvided;
        }

        const filepath = args[0];
        const blocksize = try fmt.parseInt(usize, args[1], 10);
        const iterations = try fmt.parseInt(usize, args[2], 10);
        debugPrint("filepath: {s}, blocksize: {d}, iterations: {d}\n", .{ filepath, blocksize, iterations });
        if (is_aligned_test and blocksize * 1024 != os_page_size_in_bytes) {
            return errors.BlockMustEqualPageSize;
        }
        const cwd = fs.cwd();
        const file_stat = try cwd.statFile(filepath);
        debugPrint("filestat: {any}\n", .{file_stat});
        const file = try cwd.openFile(filepath, .{
            .mode = .read_only,
            .lock = .exclusive,
        });
        defer file.close();
        var seed: u64 = undefined;
        try std.posix.getrandom(std.mem.asBytes(&seed));
        debugPrint("seed: {d}\n", .{seed});
        // now, we want to do random reads of size `blocksize` multiple times.
        var prng: Random.DefaultPrng = .init(seed);
        const rand = prng.random();
        var search_idx = rand.intRangeAtMost(u64, 0, file_stat.size - (1 + blocksize * 1024));
        if (is_aligned_test) {
            search_idx = (search_idx / os_page_size_in_bytes) * os_page_size_in_bytes;
        }
        const read_buffer = try allocator.alloc(u8, blocksize * 1024);
        var read: usize = 0;
        defer allocator.free(read_buffer);

        switch (builtin.target.os.tag) {
            .linux => {
                _ = os.linux.fadvise(file.handle, 0, @intCast(file_stat.size), os.linux.POSIX_FADV.RANDOM);
            },
            else => {},
        }
        for (0..iterations) |_| {
            read = try posix.pread(file.handle, read_buffer, search_idx);
            if (read != read_buffer.len) {
                return errors.ShortReadError;
            }
            search_idx = rand.intRangeAtMost(u64, 0, file_stat.size - (1 + blocksize * 1024));
            if (is_aligned_test) {
                search_idx = (search_idx / os_page_size_in_bytes) * os_page_size_in_bytes;
            }
        }
    }

    /// args[0] is filename, args[1] is the blocksize in KB
    /// args[2] is the number of iterations we want to do.
    pub fn read_file_mmap(allocator: mem.Allocator, args: [][:0]u8, is_aligned_test: bool) !void {
        if (args.len < 3) {
            return errors.NoFilenameOrReadBlockSizeProvided;
        }

        const filepath = args[0];
        const blocksize = try fmt.parseInt(usize, args[1], 10);
        const iterations = try fmt.parseInt(usize, args[2], 10);
        debugPrint("filepath: {s}, blocksize: {d}, iterations: {d}\n", .{ filepath, blocksize, iterations });
        if (is_aligned_test and blocksize * 1024 != os_page_size_in_bytes) {
            return errors.BlockMustEqualPageSize;
        }
        const cwd = fs.cwd();
        const file_stat = try cwd.statFile(filepath);
        debugPrint("filestat: {any}\n", .{file_stat});
        const file = try cwd.openFile(filepath, .{
            .mode = .read_only,
            .lock = .exclusive,
        });
        defer file.close();
        const mmap_p = try posix.mmap(null, file_stat.size, posix.PROT.READ, .{
            .TYPE = .PRIVATE,
        }, file.handle, 0);
        _ = try posix.madvise(mmap_p.ptr, mmap_p.len, posix.MADV.RANDOM);
        defer posix.munmap(mmap_p);
        debugPrint("initial byte: {s}, mmap len: {d}\n", .{ mmap_p[0..8], mmap_p.len });
        var seed: u64 = undefined;
        try std.posix.getrandom(std.mem.asBytes(&seed));
        debugPrint("seed: {d}\n", .{seed});
        // now, we want to do random reads of size `blocksize` multiple times.
        var prng: Random.DefaultPrng = .init(seed);
        const rand = prng.random();
        var search_idx = rand.intRangeAtMost(u64, 0, file_stat.size - (1 + blocksize * 1024));
        if (is_aligned_test) {
            search_idx = (search_idx / os_page_size_in_bytes) * os_page_size_in_bytes;
        }
        const read_buffer = try allocator.alloc(u8, blocksize * 1024);
        defer allocator.free(read_buffer);
        for (0..iterations) |_| {
            @memcpy(read_buffer, mmap_p[search_idx..(search_idx + (blocksize * 1024))]);
            search_idx = rand.intRangeAtMost(u64, 0, file_stat.size - (1 + blocksize * 1024));
            if (is_aligned_test) {
                search_idx = (search_idx / os_page_size_in_bytes) * os_page_size_in_bytes;
            }
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
