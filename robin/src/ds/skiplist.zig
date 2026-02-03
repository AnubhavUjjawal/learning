const std = @import("std");
const log = std.log;
const mem = std.mem;
const testing = std.testing;

const logger = log.scoped(.skiplist);

/// A thread safe skip list implementation
pub const SkipList = struct {
    allocator: mem.Allocator,
    const Self = @This();
    /// Init the skip list with the memory allocator.
    /// I think using a fixed buffer allocator here would
    /// increase cache hit. TODO: verify
    pub fn init(allocator: mem.Allocator) Self {
        logger.debug("initialising the skiplist", .{});
        return .{ .allocator = allocator };
    }

    pub fn deinit(_: *Self) !void {
        logger.debug("deinitialising the skiplist", .{});
    }

    // pub fn addEntry
};

test "init" {
    const allocator = testing.allocator;
    var l = SkipList.init(allocator);
    try l.deinit();
    try std.testing.expect(false);
}
