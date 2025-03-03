//! By convention, main.zig is where your main function lives in the case that
//! you are building an executable. If you are making a library, the convention
//! is to delete this file and start with root.zig instead.

const cpu = @import("cpu.zig");
const ram = @import("ram.zig");
const std = @import("std");

pub fn main() !void {
    var r = ram.Ram{};
    r.load_font();
}
