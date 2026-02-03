const std = @import("std");
const builtin = @import("builtin");
const heap = std.heap;
const process = std.process;
const debug = std.debug;

const read_vs_mmap = @import("read_vs_mmap");

var gpa = std.heap.GeneralPurposeAllocator(.{}){};

fn getAllocator() std.mem.Allocator {
    // Switch logic based on the build mode
    return switch (builtin.mode) {
        .Debug,
        => {
            read_vs_mmap.debugPrint("using debug allocator \n", .{});
            return gpa.allocator();
        },
        // Use a faster, less safe allocator for performance modes
        .ReleaseFast, .ReleaseSmall, .ReleaseSafe => std.heap.c_allocator,
    };
}

pub fn main() !void {
    const allocator = getAllocator();
    // Remember to deinit the GPA if you are in a safe mode
    defer if (builtin.mode == .Debug or builtin.mode == .ReleaseSafe) {
        const no_leaks = gpa.deinit();
        debug.assert(no_leaks == .ok);
    };

    const args = try process.argsAlloc(allocator);
    defer process.argsFree(allocator, args);

    if (args.len < 2) {
        return error.NoCommandFound;
    }

    try read_vs_mmap.Runner.run(allocator, args[1], args[2..]);
}
