const std = @import("std");

pub const font_start = 0x50;
pub const memory_size = 4096;

pub const Ram = struct {
    memory: [memory_size]u8 = undefined,
    end_index: usize = 0,

    pub fn load_font(self: *Ram) void {
        std.mem.copyForwards(u8, self.memory[font_start .. font_start + font.len], &font);
        self.end_index = font_start + font.len;
    }

    pub fn print(self: *const Ram, config: PrintConfig) void {
        const width = config.width;
        const from = config.from;
        const to: usize = if (config.to != null) @intCast(config.to.?) else self.end_index;

        const out = std.io.getStdOut();
        var buf = std.io.bufferedWriter(out.writer());
        const bw = buf.writer();

        var i: usize = @intCast(from);
        while (i <= to - width) : (i += width) {
            std.fmt.format(bw, "\n0x{X:03}: ", .{i}) catch unreachable;
            for (0..width) |j| {
                std.fmt.format(bw, "{X} ", .{self.memory[i + j]}) catch unreachable;
            }
        }
        buf.flush() catch unreachable;
    }
};

test "font loaded" {
    var r = Ram{};
    r.load_font();

    try std.testing.expect(r.memory[font_start] == font[0]);
    try std.testing.expect(r.memory[font_start] != font[1]);

    try std.testing.expect(r.memory[font_start + font.len - 1] == font[font.len - 1]);
}

const font = [_]u8{
    0xF0, 0x90, 0x90, 0x90, 0xF0, // 0
    0x20, 0x60, 0x20, 0x20, 0x70, // 1
    0xF0, 0x10, 0xF0, 0x80, 0xF0, // 2
    0xF0, 0x10, 0xF0, 0x10, 0xF0, // 3
    0x90, 0x90, 0xF0, 0x10, 0x10, // 4
    0xF0, 0x80, 0xF0, 0x10, 0xF0, // 5
    0xF0, 0x80, 0xF0, 0x90, 0xF0, // 6
    0xF0, 0x10, 0x20, 0x40, 0x40, // 7
    0xF0, 0x90, 0xF0, 0x90, 0xF0, // 8
    0xF0, 0x90, 0xF0, 0x10, 0xF0, // 9
    0xF0, 0x90, 0xF0, 0x90, 0x90, // A
    0xE0, 0x90, 0xE0, 0x90, 0xE0, // B
    0xF0, 0x80, 0x80, 0x80, 0xF0, // C
    0xE0, 0x90, 0x90, 0x90, 0xE0, // D
    0xF0, 0x80, 0xF0, 0x80, 0xF0, // E
    0xF0, 0x80, 0xF0, 0x80, 0x80, // F
};

const PrintConfig = struct { width: usize = 8, from: usize = 0, to: ?isize = null };
