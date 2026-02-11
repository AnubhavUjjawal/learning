const std = @import("std");
const log = std.log;
const mem = std.mem;
const math = std.math;
const thread = std.Thread;
const testing = std.testing;
const assert = std.debug.assert;

const logger = log.scoped(.skiplist);

/// A thread safe skip list implementation
///
/// TODO:
/// - We can potentially make it lock free. But before going lockfree, add a benchmark setup
/// - Make sure we support single item pointers as keys (copied during insert), and not only slices
/// - Add get and delete
/// - Add prefetch when we are iterating through a node
pub fn SkipList(
    comptime K: type,
    comptime V: type,
    comptime max_levels: u8,
    comptime cmp: fn (a: *const K, b: *const K) math.Order,
) type {

    // A Node in SkipList. Has the following characteristics:
    // - Stores its next pointers in memory.
    // - If the data is a slice, it copies it using @memcpy and keeps it in memory. Does not support
    //   deep copy yet.
    // Data layout
    // [node] + [padding if needed] + [node.key child if node.key is slice] + [padding] + [node next pointers] + [padding] + [node.value if node.value is slice]
    const Node = struct {
        const Self = @This();

        const self_alignment_needed = @alignOf(Self);
        const self_ptrs_alignment_needed = @alignOf(*Self);
        const key_is_slice = @typeInfo(K) == .pointer and @typeInfo(K).pointer.size == .slice;
        const value_is_slice = @typeInfo(V) == .pointer and @typeInfo(V).pointer.size == .slice;

        key: ?K,
        value: ?V,
        levels: u8,

        fn _get_nexts_size(levels: u8) usize {
            return mem.alignForward(usize, levels * @sizeOf(*Self), _get_value_alignment_needed());
        }

        fn nexts(self: *Self) []?*Self {
            const ptr_addr = @intFromPtr(self) +
                _get_header_size(self.key) +
                _get_key_size(self.key);
            const ptr: [*]align(self_ptrs_alignment_needed) ?*Self = @ptrFromInt(ptr_addr);
            const aligned: [*]?*Self = @ptrCast(@alignCast(ptr));
            return aligned[0..self.levels];
        }

        /// levels is 0 indexed.
        fn setNext(self: *Self, level: u8, next: ?*Self) void {
            self.nexts()[level] = next;
        }

        /// levels is 0 indexed.
        fn getNext(self: *Self, level: u8) ?*Self {
            return self.nexts()[level];
        }

        /// levels is 0 indexed.
        fn insertNext(self: *Self, level: u8, next: *Self) void {
            const current_next = self.getNext(level);
            self.setNext(level, next);
            next.setNext(level, current_next);
        }

        inline fn _get_header_size(key: ?K) usize {
            // ideally, we don't need to copy data, unless it is a slice.
            // We could have just taken ownership of passed slices and called it a day, but that doesn't
            // improve cache locality
            const self_value_alignment_needed = _get_value_alignment_needed();

            if (key != null and key_is_slice) {
                const self_key_alignment_needed = _get_key_alignment_needed();
                // since we store child the data is pointing to as well, we need to update header alignment.
                return mem.alignForward(usize, @sizeOf(Self), @max(self_key_alignment_needed, self_ptrs_alignment_needed, self_value_alignment_needed));
            }
            return mem.alignForward(usize, @sizeOf(Self), @max(self_ptrs_alignment_needed, self_value_alignment_needed));
        }

        inline fn _get_key_size(data: ?K) usize {
            if (data != null and key_is_slice) {
                // since we store our pointers after data, we need to add padding for alignment purposes.
                return mem.alignForward(usize, data.?.len * @sizeOf(@typeInfo(K).pointer.child), self_ptrs_alignment_needed);
            }
            return 0;
        }

        inline fn _get_value_size(data: ?V) usize {
            if (data != null and value_is_slice) {
                return data.?.len * @sizeOf(@typeInfo(V).pointer.child);
            }
            return 0;
        }

        inline fn _get_node_size(levels: u8, key: ?K, value: ?V) usize {
            var key_size: usize = 0;
            if (key_is_slice) {
                // since we store our pointers after data, we need to add padding for alignment purposes.
                key_size = _get_key_size(key);
            }
            var value_size: usize = 0;
            if (value_is_slice) {
                // since we store our pointers after data, we need to add padding for alignment purposes.
                value_size = _get_value_size(value);
            }

            const node_size = _get_header_size(key) + key_size + value_size + _get_nexts_size(levels);
            return node_size;
        }

        fn _get_key_alignment_needed() comptime_int {
            const info = @typeInfo(K);
            if (key_is_slice) return @alignOf(info.pointer.child);
            return 1;
        }

        fn _get_value_alignment_needed() comptime_int {
            const info = @typeInfo(V);
            if (value_is_slice) return @alignOf(info.pointer.child);
            return 1;
        }

        inline fn _get_total_alignment_needed() comptime_int {
            const key_alignment_needed = _get_key_alignment_needed();
            const value_alignment_needed = _get_value_alignment_needed();
            return @max(self_alignment_needed, self_ptrs_alignment_needed, key_alignment_needed, value_alignment_needed);
        }

        fn create(allocator: mem.Allocator, key: ?K, value: ?V, levels: u8) !*Self {
            if (levels == 0) return error.ZERO_LEVELS_NOT_ALLOWED;
            const node_size = _get_node_size(levels, key, value);
            logger.debug("node size in bytes: {d}, data: {any}", .{ node_size, key });
            const bytes = try allocator
                .alignedAlloc(u8, comptime mem.Alignment.fromByteUnits(_get_total_alignment_needed()), node_size);
            const node: *Self = @ptrCast(@alignCast(bytes.ptr));

            node.* = .{ .key = key, .levels = levels, .value = value };

            const header_size = _get_header_size(key);
            if (key != null and key_is_slice) {
                const child_data: [*]@typeInfo(K).pointer.child = @ptrFromInt(@intFromPtr(bytes.ptr) + header_size);
                const dest = child_data[0..key.?.len];
                @memcpy(dest, key.?);
                node.key = dest;
            }

            if (value != null and value_is_slice) {
                const body_size = header_size + _get_key_size(key) + _get_nexts_size(levels);
                const child_data: [*]@typeInfo(V).pointer.child = @ptrFromInt(@intFromPtr(bytes.ptr) + body_size);
                const dest = child_data[0..value.?.len];
                @memcpy(dest, value.?);
                node.value = dest;
            }

            // Initialize the trailing pointers to null
            for (0..node.levels) |i| {
                node.setNext(@as(u8, @intCast(i)), null);
            }
            return node;
        }

        fn destroy(allocator: mem.Allocator, node: *Self) void {
            const node_size = _get_node_size(node.levels, node.key, node.value);
            const bytes_ptr: [*]align(_get_total_alignment_needed()) u8 = @ptrCast(@alignCast(node));
            const original_allocation = bytes_ptr[0..node_size];
            allocator.free(original_allocation);
        }
    };
    return struct {
        allocator: mem.Allocator,
        head: *Node,
        lock: thread.RwLock,
        prng: std.Random,
        _len: usize = 0,
        const Self = @This();
        const compare = cmp;

        /// Init(create) a new skip list with the memory allocator.
        ///
        /// TODO(verify): I think using a fixed buffer allocator here would increase cache hit rate.
        pub fn init(allocator: mem.Allocator, prng: std.Random) !Self {
            logger.debug("initialising the skiplist", .{});
            const head = try Node.create(allocator, null, null, max_levels);
            errdefer Node.destroy(allocator, head);
            return .{ .allocator = allocator, .head = head, .lock = .{}, .prng = prng };
        }

        // consider making len return an atomic load
        pub fn len(self: *Self) usize {
            self.lock.lockShared();
            defer self.lock.unlockShared();
            return self._len;
        }

        pub fn deinit(self: *Self) void {
            logger.debug("deinitialising the skiplist", .{});

            var curr: ?*Node = self.head;
            while (curr != null) {
                const old = curr;
                curr = curr.?.getNext(0);
                Node.destroy(self.allocator, old.?);
            }
        }

        /// insert element into the skip list.
        pub fn insert(self: *Self, key: K, value: V) !void {
            logger.debug("adding item: {any}", .{key});
            self.lock.lock();
            defer self.lock.unlock();

            // the search algorithm here:
            // 1. start from the highest level of head
            // 2. push the current element to a stack. keep moving forward until next element is not tail,
            //    or you find an element larger than current element.
            // 3. if you cannot go down, you need to insert the element here.
            // 4. go down. goto step 2.
            var stack: [max_levels]*Node = undefined;
            var stack_idx: i16 = -1;
            var curr_node = self.head;

            var curr_level = max_levels;
            while (curr_level > 0) {
                const next = curr_node.getNext(curr_level - 1);
                const cmp_result: ?math.Order = if (next != null) compare(&next.?.key.?, &key) else null;
                if (next != null and (cmp_result == .lt or cmp_result == .eq)) {
                    curr_node = next.?;
                } else {
                    curr_level -= 1;
                    stack_idx += 1;
                    stack[@as(usize, @intCast(stack_idx))] = curr_node;
                }
            }
            assert(stack_idx == max_levels - 1);

            // insertion logic:
            // while elements in stack
            // last element in the stack, insert element after it
            // run prng, if > 0.5, pop last element and continue else break
            //
            var levels: u8 = 1;
            while (levels < max_levels) {
                const should_insert = self.prng.boolean();
                if (!should_insert) break;
                levels += 1;
            }
            const node = try Node.create(self.allocator, key, value, levels);
            errdefer Node.destroy(self.allocator, node);

            for (0..levels) |level| {
                const elem = stack[@as(usize, @intCast(stack_idx))];
                stack_idx -= 1;
                elem.insertNext(@as(u8, @intCast(level)), node);
            }

            self._len += 1;
        }

        /// A very basic debug print, not thread safe
        /// We need to improve it
        pub fn debugPrint(self: *const Self) void {
            var curr: ?*Node = self.head;
            var current_level = max_levels;
            while (current_level > 0) {
                curr = self.head;
                while (curr != null) {
                    std.debug.print("{any} -> ", .{curr.?.key});
                    curr = curr.?.getNext(current_level - 1);
                }
                std.debug.print("\n", .{});

                current_level -= 1;
            }
        }
    };
}

pub fn bytesCompare(a: *const []const u8, b: *const []const u8) math.Order {
    return mem.order(u8, a.*, b.*);
}

pub fn u32Compare(a: *const u32, b: *const u32) math.Order {
    return math.order(a.*, b.*);
}

test "sanity test insert int" {
    const allocator = testing.allocator;
    var prng = std.Random.DefaultPrng.init(@as(u64, testing.random_seed));
    var random = prng.random();
    var l = try SkipList(u32, u32, 12, u32Compare).init(allocator, random);
    defer l.deinit();

    const num_inserts = 10_000;
    for (0..num_inserts) |_| {
        const num = random.int(u32);
        try l.insert(num, num % 100);
    }

    var curr: ?@TypeOf(l.head) = l.head;
    const current_level = 0;
    var total_count: u32 = 0;
    var prev: ?@TypeOf(l.head) = null;
    try testing.expect(l.len() == num_inserts);
    while (curr != null) {
        if (prev != null and prev != l.head) {
            try testing.expect(prev.?.key.? <= curr.?.key.?);
            try testing.expect(curr.?.key.? % 100 == curr.?.value.?);
        }
        prev = curr;
        curr = curr.?.getNext(current_level);
        total_count += 1;
    }

    // -1 for head
    try testing.expect(total_count - 1 == num_inserts);
    // l.debugPrint();
}

test "sanity test insert string" {
    const allocator = testing.allocator;
    var prng = std.Random.DefaultPrng.init(@as(u64, testing.random_seed));
    var random = prng.random();
    var l = try SkipList([]const u8, []const u8, 12, bytesCompare).init(allocator, random);
    defer l.deinit();

    var key: [100]u8 = undefined;
    const num_inserts = 10_000;
    for (0..num_inserts) |_| {
        random.bytes(&key);
        // being lazy and inserting the same in both, sorries, bad test
        try l.insert(&key, &key);
    }
    var curr: ?@TypeOf(l.head) = l.head;
    const current_level = 0;
    var total_count: u32 = 0;
    var prev: ?@TypeOf(l.head) = null;
    var c: usize = 0;
    try testing.expect(l.len() == num_inserts);
    while (curr != null) {
        c += 1;
        if (prev != null and prev != l.head) {
            try testing.expect(bytesCompare(&prev.?.key.?, &curr.?.key.?) == .lt or bytesCompare(&prev.?.key.?, &curr.?.key.?) == .eq);
            try testing.expect(bytesCompare(&curr.?.key.?, &curr.?.value.?) == .eq);
        }
        prev = curr;
        curr = curr.?.getNext(current_level);
        total_count += 1;
    }
    // -1 for head
    try testing.expect(total_count - 1 == num_inserts);
    // l.debugPrint();
}
