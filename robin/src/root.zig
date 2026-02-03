//! By convention, root.zig is the root source file when making a library.
const std = @import("std");
const builtin = @import("builtin");
const ds = @import("ds/root.zig");

pub const std_options: std.Options = .{
    .log_level = if (builtin.is_test) .debug else std.log.default_level,
};

test {
    _ = ds;
}
