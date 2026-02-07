const std = @import("std");
const log = std.log;
const mem = std.mem;
const math = std.math;
const thread = std.Thread;
const testing = std.testing;

const logger = log.scoped(.skiplist);

/// A thread safe skip list implementation
/// TODO:
/// - We can potentially make it lock free
pub fn SkipList(
    comptime T: type,
    comptime max_levels: u8,
    // should include pointer tie breaking in cases of equality
    comptime cmp: fn (a: *const T, b: *const T) math.Order,
) type {

    // A Node in SkipList. Has the following characteristics:
    // - Stores its next pointers in memory.
    // - If the data is a slice, it copies it using @memcpy and keeps it in memory. Does not support
    //   deep copy yet.
    // Data layout
    // [node] + [padding if needed] + [node.data child if node.data is slice] + [padding] + [node next pointers]
    const Node = struct {
        const Self = @This();

        const self_alignment_needed = @alignOf(Self);
        const self_ptrs_alignment_needed = @alignOf(*Self);

        data: ?T,
        levels: u8,

        fn nexts(self: *Self) []?*Self {
            const ptr_addr = @intFromPtr(self) + Self._get_header_size(self.data) + Self._get_data_size(self.data);
            const ptr: [*]align(self_ptrs_alignment_needed) ?*Self =
                @ptrFromInt(ptr_addr);
            const aligned: [*]?*Self = @ptrCast(@alignCast(ptr));
            return aligned[0..self.levels];
        }

        fn setNext(self: *Self, level: u8, next: ?*Self) void {
            self.nexts()[level] = next;
        }

        fn getNext(self: *Self, level: u8) ?*Self {
            return self.nexts()[level];
        }

        fn insertNext(self: *Self, level: u8, next: *Self) void {
            const current_next = self.getNext(level);
            self.setNext(level, next);
            next.setNext(level, current_next);
        }

        inline fn _get_header_size(data: ?T) usize {
            // ideally, we don't need to copy data, unless it is a slice.
            // We could have just taken ownership of passed slices and called it a day, but that doesn't
            // improve cache locality
            if (data != null and (comptime @typeInfo(T) == .pointer and @typeInfo(T).pointer.size == .slice)) {
                const self_data_alignment_needed = @alignOf(@typeInfo(T).pointer.child);
                // since we store child the data is pointing to as well, we need to update header alignment.
                return mem.alignForward(usize, @sizeOf(Self), @max(self_data_alignment_needed, self_ptrs_alignment_needed));
            }
            return mem.alignForward(usize, @sizeOf(Self), self_ptrs_alignment_needed);
        }

        inline fn _get_data_size(data: ?T) usize {
            if (data != null and (comptime @typeInfo(T) == .pointer and @typeInfo(T).pointer.size == .slice)) {
                // since we store our pointers after data, we need to add padding for alignment purposes.
                return mem.alignForward(usize, data.?.len * @sizeOf(@typeInfo(T).pointer.child), self_ptrs_alignment_needed);
            }
            return 0;
        }

        inline fn _get_node_size(levels: u8, data: ?T) usize {
            var data_size: usize = 0;
            if (comptime @typeInfo(T) == .pointer and @typeInfo(T).pointer.size == .slice) {
                // since we store our pointers after data, we need to add padding for alignment purposes.
                data_size = Self._get_data_size(data);
            }

            const node_size = Self._get_header_size(data) + data_size + (@sizeOf(*Self) * levels);
            return node_size;
        }

        inline fn _get_total_alignment_needed() comptime_int {
            const data_alignment_needed = comptime blk: {
                const info = @typeInfo(T);
                if (info == .pointer and info.pointer.size == .slice) break :blk @alignOf(info.pointer.child);
                break :blk 1;
            };
            return @max(self_alignment_needed, self_ptrs_alignment_needed, data_alignment_needed);
        }

        fn create(allocator: mem.Allocator, data: ?T, levels: u8) !*Self {
            if (levels == 0) return error.ZERO_LEVELS_NOT_ALLOWED;
            const node_size = _get_node_size(levels, data);
            logger.debug("node size in bytes: {d}, data: {any}", .{ node_size, data });
            const bytes = try allocator
                .alignedAlloc(u8, comptime mem.Alignment.fromByteUnits(Self._get_total_alignment_needed()), node_size);
            const node: *Self = @ptrCast(@alignCast(bytes.ptr));

            node.* = .{ .data = data, .levels = levels };

            const header_size = Self._get_header_size(data);

            if (data != null and (comptime @typeInfo(T) == .pointer and @typeInfo(T).pointer.size == .slice)) {
                // since we store child the data is pointing to as well, we need to update header alignment.
                const child_data: [*]@typeInfo(T).pointer.child = @ptrFromInt(@intFromPtr(bytes.ptr) + header_size);
                const dest = child_data[0..data.?.len];
                @memcpy(dest, data.?);
                node.data = dest;
            }

            // Initialize the trailing pointers to null
            for (0..node.levels) |i| {
                node.setNext(@as(u8, @intCast(i)), null);
            }
            return node;
        }

        fn destroy(allocator: mem.Allocator, node: *Self) void {
            const node_size = _get_node_size(node.levels, node.data);
            const bytes_ptr: [*]align(Self._get_total_alignment_needed()) u8 = @ptrCast(@alignCast(node));
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
            const head = try Node.create(allocator, null, max_levels);
            errdefer Node.destroy(allocator, head);
            return .{ .allocator = allocator, .head = head, .lock = .{}, .prng = prng };
        }

        pub fn len(self: *const Self) usize {
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
        pub fn insert(self: *Self, element: T) !void {
            logger.debug("adding item: {any}", .{element});
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
                const cmp_result: ?math.Order = if (next != null) compare(&next.?.data.?, &element) else null;
                if (next != null and (cmp_result == .lt or cmp_result == .eq)) {
                    curr_node = next.?;
                } else {
                    curr_level -= 1;
                    stack_idx += 1;
                    stack[@as(usize, @intCast(stack_idx))] = curr_node;
                }
            }

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
            const node = try Node.create(self.allocator, element, levels);
            errdefer Node.destroy(self.allocator, node);

            for (0..levels) |level| {
                const elem = stack[@as(usize, @intCast(stack_idx))];
                stack_idx -= 1;
                elem.insertNext(@as(u8, @intCast(level)), node);
            }

            self._len += 1;
        }

        /// A very basic debug print
        /// We need to improve it
        pub fn debugPrint(self: *const Self) void {
            var curr: ?*Node = self.head;
            var current_level = max_levels;
            while (current_level > 0) {
                curr = self.head;
                while (curr != null) {
                    std.debug.print("{any} -> ", .{curr.?.data});
                    curr = curr.?.getNext(current_level - 1);
                }
                std.debug.print("\n", .{});

                current_level -= 1;
            }
        }
    };
}

pub fn bytesCompare(a: *const []const u8, b: *const []const u8) math.Order {
    // switch (mem.order(u8, a.*, b.*)) {
    //     .gt => return false,
    //     .eq => return @intFromPtr(a.ptr) < @intFromPtr(b.ptr),
    //     .lt => return true,
    // }
    return mem.order(u8, a.*, b.*);
}

pub fn u32Compare(a: *const u32, b: *const u32) math.Order {
    return math.order(a.*, b.*);
}

test "sanity test insert int" {
    const allocator = testing.allocator;
    var prng = std.Random.DefaultPrng.init(@as(u64, testing.random_seed));
    var random = prng.random();
    var l = try SkipList(u32, 12, u32Compare).init(allocator, random);
    defer l.deinit();

    const num_inserts = 10_000;
    for (0..num_inserts) |_| {
        const num = random.int(u32);
        try l.insert(num);
    }

    var curr: ?@TypeOf(l.head) = l.head;
    const current_level = 0;
    var total_count: u32 = 0;
    var prev: ?@TypeOf(l.head) = null;
    while (curr != null) {
        if (prev != null and prev != l.head) {
            try testing.expect(prev.?.data.? <= curr.?.data.?);
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
    var l = try SkipList([]const u8, 12, bytesCompare).init(allocator, random);
    defer l.deinit();

    var str: [100]u8 = undefined;
    const num_inserts = 10_000;
    for (0..num_inserts) |_| {
        random.bytes(&str);
        try l.insert(&str);
    }
    var curr: ?@TypeOf(l.head) = l.head;
    const current_level = 0;
    var total_count: u32 = 0;
    var prev: ?@TypeOf(l.head) = null;
    while (curr != null) {
        if (prev != null and prev != l.head) {
            try testing.expect(bytesCompare(&prev.?.data.?, &curr.?.data.?) == .lt or bytesCompare(&prev.?.data.?, &curr.?.data.?) == .eq);
        }
        prev = curr;
        curr = curr.?.getNext(current_level);
        total_count += 1;
    }
    // -1 for head
    try testing.expect(total_count - 1 == num_inserts);
    // l.debugPrint();
}
