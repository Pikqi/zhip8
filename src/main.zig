const std = @import("std");

const zhip = @import("zhip8.zig");
const gpu = @import("gpu.zig");
const rom = @embedFile("roms/RPS.ch8");

const rl = @cImport({
    @cInclude("raylib.h");
    @cInclude("raymath.h");
    @cInclude("rlgl.h");
    @cInclude("raygui.h");
});

const PIXEL_SCALE = 15;

const WINDOW_WIDTH = GUI_WIDHT + PIXEL_SCALE * gpu.SCREEEN_WIDTH;
const WINDOW_HEIGHT = PIXEL_SCALE * gpu.SCREEEN_HEIGHT;

const BACKGROUND_COLOR = rl.WHITE;
const PIXEL_COLOR = rl.GREEN;

const debug = true;

var GUI_ENABLE = false;

const TEXT_SIZE = 20;

pub fn main() !void {
    var prng = std.Random.DefaultPrng.init(blk: {
        var seed: u64 = undefined;
        try std.posix.getrandom(std.mem.asBytes(&seed));
        break :blk seed;
    });
    const rand = prng.random();
    var zhip8 = zhip.Zhip8.init(rand);
    zhip8.loadRomBytes(rom);

    rl.SetTargetFPS(60);
    rl.InitWindow(WINDOW_WIDTH, WINDOW_HEIGHT, "zhip8");
    rl.GuiSetStyle(rl.DEFAULT, rl.TEXT_SIZE, TEXT_SIZE);

    while (!rl.WindowShouldClose()) {
        try zhip8.mainLoop();
        try draw_raylib(&zhip8);
        // g.print();
    }
}

const GUI_WIDHT = 400;
const GUI_MARGIN = 20;
const GUI_BASE_HEIGHT = 20;

var gridVec = rl.Vector2{ .x = 0, .y = 0 };
fn draw_raylib(zhip8: *zhip.Zhip8) !void {
    rl.BeginDrawing();
    defer rl.EndDrawing();
    rl.ClearBackground(BACKGROUND_COLOR);
    rl.DrawFPS(10, WINDOW_HEIGHT - 30);

    if (rl.IsKeyPressed(rl.KEY_T)) {
        if (GUI_ENABLE) {
            rl.GuiDisable();
            rl.GuiSetAlpha(0.0);
            GUI_ENABLE = false;
        } else {
            rl.GuiEnable();
            rl.GuiSetAlpha(1.0);
            GUI_ENABLE = true;
        }
    }

    for (zhip8.gpu.display, 0..) |pixel, i| {
        const x = GUI_WIDHT + (i & (gpu.SCREEEN_WIDTH - 1)) * PIXEL_SCALE;
        const y = (i / gpu.SCREEEN_WIDTH) * PIXEL_SCALE;
        if (pixel) {
            rl.DrawRectangle(@intCast(x), @intCast(y), PIXEL_SCALE, PIXEL_SCALE, PIXEL_COLOR);
        }
    }

    var y: f32 = GUI_MARGIN;

    _ = rl.GuiLabel(.{ .x = GUI_MARGIN, .y = y, .height = GUI_BASE_HEIGHT, .width = GUI_WIDHT }, "Clock speed 200-1000Mhz");
    new_row(&y);
    _ = rl.GuiSlider(.{
        .x = GUI_MARGIN,
        .y = y,
        .width = GUI_WIDHT - GUI_MARGIN * 2,
        .height = GUI_BASE_HEIGHT,
    }, "", "", &zhip8.clock_speed, 200, 1000);
    new_row(&y);

    _ = rl.GuiCheckBox(.{
        .x = GUI_MARGIN,
        .y = y,
        .height = GUI_BASE_HEIGHT,
        .width = GUI_BASE_HEIGHT,
    }, "Pause", &zhip8.is_paused);

    new_row(&y);
    if (rl.GuiButton(.{
        .x = GUI_MARGIN,
        .y = y,
        .width = GUI_BASE_HEIGHT * 5,
        .height = GUI_BASE_HEIGHT * 2,
    }, "Restart") > 0) {
        zhip8.resetRom();
    }
    if (rl.GuiButton(.{
        .x = GUI_MARGIN + GUI_BASE_HEIGHT * 6,
        .y = y,
        .width = GUI_BASE_HEIGHT * 5,
        .height = GUI_BASE_HEIGHT * 2,
    }, "Step +1") > 0) {
        zhip8.step_for(1);
    }
    if (rl.GuiButton(.{
        .x = GUI_MARGIN + GUI_BASE_HEIGHT * 13,
        .y = y,
        .width = GUI_BASE_HEIGHT * 5,
        .height = GUI_BASE_HEIGHT * 2,
    }, "Step +10") > 0) {
        zhip8.step_for(1);
    }

    new_row(&y);
    new_row(&y);

    const registerWidth = TEXT_SIZE * 5;
    var reg_x: f32 = -registerWidth + GUI_MARGIN;
    var str: [8]u8 = undefined;
    for (zhip8.cpu.V, 0..) |value, i| {
        _ = try std.fmt.bufPrintZ(&str, "{X:01}:{X:04}", .{ i, value });
        const row = (registerWidth * i) / GUI_WIDHT;
        const reg_y = y + @as(f32, @floatFromInt(GUI_BASE_HEIGHT * row));
        reg_x += registerWidth;
        if (reg_x > GUI_WIDHT) {
            reg_x = GUI_MARGIN;
        }

        _ = rl.GuiLabel(.{ .x = reg_x, .y = reg_y, .width = registerWidth, .height = GUI_BASE_HEIGHT }, &str);
    }
}
fn new_row(y: *f32) void {
    y.* += GUI_BASE_HEIGHT + 5;
}
