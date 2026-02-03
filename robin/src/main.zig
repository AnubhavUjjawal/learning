const std = @import("std");
const builtin = @import("builtin");
const robin = @import("robin");

const log = std.log;

pub const std_options = robin.std_options;

pub fn main() !void {
    // Prints to stderr, ignoring potential errors.
    log.debug("All your {s} are belong to us.\n", .{"codebase"});
}
