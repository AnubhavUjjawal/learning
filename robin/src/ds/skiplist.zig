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
/// - We are wasting memory (fixed number of max_levels)
/// - copy T when inserting
pub fn SkipList(
    comptime T: type,
    comptime max_levels: u8,
    /// should return true when a < b
    comptime cmp: fn (a: *const T, b: *const T) bool,
) type {

    // A Node in SkipList. Stores its next pointers
    // in memory
    const Node = struct {
        const Self = @This();

        const alignment = mem.Alignment.of(Self);
        const ptr_alignment = @alignOf(?*Self);
        const header_size = mem.alignForward(usize, @sizeOf(Self), ptr_alignment);

        data: ?T,
        height: u8,

        fn nexts(self: *Self) []?*Self {
            const ptr_addr = @intFromPtr(self) + header_size;
            const ptr: [*]?*Self = @ptrFromInt(ptr_addr);
            return ptr[0..self.height];
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

        fn create(allocator: mem.Allocator, data: ?T, height: u8) !*Self {
            const node_size = header_size + (@sizeOf(?*Self) * height);
            const bytes = try allocator.alignedAlloc(u8, alignment, node_size);
            const node: *Self = @ptrCast(@alignCast(bytes.ptr));

            node.* = .{ .data = data, .height = height };
            // Initialize the trailing pointers to null
            for (0..node.height) |i| {
                // std.debug.print("here\n", .{});
                node.setNext(@as(u8, @intCast(i)), null);
            }
            return node;
        }

        fn destroy(allocator: mem.Allocator, node: *Self) void {
            const node_size = header_size + (@sizeOf(?*Self) * node.height);
            const bytes_ptr: [*]align(alignment.toByteUnits()) u8 = @ptrCast(node);
            const original_allocation = bytes_ptr[0..node_size];
            allocator.free(original_allocation);
        }
    };
    return struct {
        allocator: mem.Allocator,
        head: *Node,
        lock: thread.RwLock,
        prng: std.Random,
        len: usize = 2,
        const Self = @This();
        const compare = cmp;

        /// Init(create) a new skip list with the memory allocator.
        ///
        /// TODO(verify): I think using a fixed buffer allocator here would increase cache hit rate.
        pub fn init(allocator: mem.Allocator, prng: std.Random) !Self {
            logger.debug("initialising the skiplist", .{});
            const head = try Node.create(allocator, null, max_levels);
            errdefer allocator.destroy(head);
            return .{ .allocator = allocator, .head = head, .lock = .{}, .prng = prng };
        }

        pub fn deinit(self: *Self) void {
            logger.debug("deinitialising the skiplist", .{});

            var curr: ?*Node = self.head;
            while (curr != null) {
                const old = curr.?;
                curr = curr.?.getNext(0);
                Node.destroy(self.allocator, old);
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
            var stack_unmanaged = std.ArrayList(*Node){};
            var stack = stack_unmanaged.toManaged(self.allocator);
            defer stack.deinit();

            try stack.ensureTotalCapacity(math.log2_int(usize, self.len));
            var curr_node = self.head;

            var curr_level = max_levels;
            while (curr_level > 0) {
                const next = curr_node.getNext(curr_level - 1);
                if (next != null and compare(&next.?.data.?, &element)) {
                    curr_node = next.?;
                } else {
                    _ = try stack.append(curr_node);
                    curr_level -= 1;
                }
            }

            // insertion logic:
            // while elements in stack
            // last element in the stack, insert element after it
            // run prng, if > 0.5, pop last element and continue else break
            //
            curr_level = 0;
            const node = try Node.create(self.allocator, element, max_levels);
            errdefer self.allocator.destroy(node);

            while (stack.items.len > 0) {
                const elem = stack.pop().?;
                const should_insert = if (curr_level == 0) true else self.prng.boolean();
                if (!should_insert) break;

                elem.insertNext(curr_level, node);
                curr_level += 1;
            }

            self.len += 1;
        }

        /// A very basic debug print
        /// We need to improve it
        pub fn debugPrint(self: *const Self) void {
            var curr: ?*Node = self.head;
            var current_level = max_levels - 1;
            while (current_level > 0) {
                curr = self.head;
                while (curr != null) {
                    std.debug.print("{any} -> ", .{curr.?.data});
                    curr = curr.?.next[current_level - 1];
                }
                std.debug.print("\n", .{});

                current_level -= 1;
            }
        }
    };
}

pub fn bytesCompare(a: *const []const u8, b: *const []const u8) bool {
    switch (mem.order(u8, a.*, b.*)) {
        .gt => return false,
        .eq => return false,
        .lt => return true,
    }
}

pub fn u32Compare(a: *const u32, b: *const u32) bool {
    return a.* < b.*;
}

test "sanity test insert int" {
    const allocator = testing.allocator;
    var prng = std.Random.DefaultPrng.init(@as(u64, testing.random_seed));
    var random = prng.random();
    var l = try SkipList(u32, 12, u32Compare).init(allocator, random);
    defer l.deinit();

    for (0..1000) |_| {
        const num = random.int(u32);
        try l.insert(num);
    }

    var curr: ?@TypeOf(l.head) = l.head;
    const current_level = 0;
    var prev: ?@TypeOf(l.head) = null;
    while (curr != null) {
        if (prev != null and curr.?.data != null and prev.?.data != null) {
            try testing.expect(prev.?.data.? <= curr.?.data.?);
        }
        prev = curr;
        curr = curr.?.getNext(current_level);
    }
    // l.debugPrint();
}

test "sanity test insert string" {
    const allocator = testing.allocator;
    var prng = std.Random.DefaultPrng.init(@as(u64, testing.random_seed));
    var random = prng.random();
    var l = try SkipList([]const u8, 12, bytesCompare).init(allocator, random);
    defer l.deinit();

    var arraylist_unmanaged = std.ArrayList([]u8){};
    var managed = arraylist_unmanaged.toManaged(allocator);
    defer managed.deinit();
    defer {
        for (managed.items) |item| {
            allocator.free(item);
        }
    }

    var str: []u8 = undefined;
    for (0..1000) |_| {
        str = try allocator.create([10]u8);
        random.bytes(str);
        try managed.append(str);
        try l.insert(str);
    }
    var curr: ?@TypeOf(l.head) = l.head;
    const current_level = 0;
    var prev: ?@TypeOf(l.head) = null;
    while (curr != null) {
        if (prev != null and curr.?.data != null and prev.?.data != null) {
            try testing.expect(bytesCompare(&prev.?.data.?, &curr.?.data.?) or
                (mem.eql(u8, prev.?.data.?, curr.?.data.?) and prev.?.data.?.ptr != curr.?.data.?.ptr));
        }
        prev = curr;
        curr = curr.?.getNext(current_level);
    }
    // l.debugPrint();
}
