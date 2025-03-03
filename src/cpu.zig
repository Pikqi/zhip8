const std = @import("std");

pub const Cpu = struct {
    pub fn print(s: Cpu) void {
        std.debug.print("cpu: {}", .{s});
    }
    I: u16 = undefined,
    r: [16]u8 = undefined,
    // s: std.
};

const StackError = error{ StackEmpty, StackFull };

pub fn Stack(comptime stack_size: usize, comptime stack_type: type) type {
    return struct {
        arr: [stack_size]stack_type = undefined,
        end: usize = 0,

        const Self = @This();
        pub fn push(self: *Self, el: u16) StackError!void {
            if (self.end < self.arr.len) {
                self.arr[self.end] = el;
                self.end += 1;
                return;
            }
            return StackError.StackFull;
        }
        pub fn pop(self: *Self) StackError!u16 {
            if (self.end > 0) {
                self.end -= 1;
                const el = self.arr[self.end];
                return el;
            } else {
                return StackError.StackEmpty;
            }
        }
    };
}

test "stack" {
    var s = Stack(16, u16){};
    try s.push(1);
    try s.push(2);
    try std.testing.expect(try s.pop() == 2);
    try std.testing.expect(try s.pop() == 1);
    try s.push(3);
    try std.testing.expect(try s.pop() == 3);
}
