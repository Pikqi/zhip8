const std = @import("std");
pub const SCREEEN_WIDTH = 64;
pub const SCREEEN_HEIGHT = 32;
pub const NUMBER_OF_PIXELS = SCREEEN_WIDTH * SCREEEN_HEIGHT;

const PIXEL_STATE = enum(u3) { OFF, FADING, ON };
const DISPLAY = [NUMBER_OF_PIXELS]PIXEL_STATE;

pub const Gpu = struct {
    display: DISPLAY = std.mem.zeroes(DISPLAY),
    need_to_render: bool = false,

    pub fn clear(self: *Gpu) void {
        std.log.debug("Display cleared \n", .{});
        self.display = std.mem.zeroes(DISPLAY);
    }

    pub fn print(self: *const Gpu) void {
        const width = SCREEEN_WIDTH;
        const from = 0;
        const to: usize = NUMBER_OF_PIXELS;

        const out = std.io.getStdOut();
        var buf = std.io.bufferedWriter(out.writer());
        const bw = buf.writer();

        var i: usize = @intCast(from);
        while (i <= to - width) : (i += width) {
            std.fmt.format(bw, "\n0x{X:03}: ", .{i}) catch unreachable;
            for (0..width) |j| {
                const b: u8 = if (self.display[i + @as(usize, @intCast(j))]) '#' else ' ';
                std.fmt.format(bw, "{u} ", .{b}) catch unreachable;
            }
        }
        buf.flush() catch unreachable;
    }
};
