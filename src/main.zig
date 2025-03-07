const std = @import("std");

const zhip = @import("zhip8.zig");
const gpu = @import("gpu.zig");
const rom = @embedFile("roms/IBM Logo.ch8");

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
const RomList = std.ArrayList([]const u8);

const RomSelection = struct {
    rom_loaded: ?[]const u8 = null,
    romList: RomList,
    pub fn deinit(self: *RomSelection) void {
        self.romList.deinit();
    }
};

pub fn main() !void {
    // var romLoaded = false;
    var prng = std.Random.DefaultPrng.init(blk: {
        var seed: u64 = undefined;
        try std.posix.getrandom(std.mem.asBytes(&seed));
        break :blk seed;
    });
    const rand = prng.random();

    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const alloc = gpa.allocator();
    defer _ = gpa.deinit();

    var rom_selection = RomSelection{ .romList = RomList.init(alloc) };
    defer rom_selection.deinit();
    var zhip8 = zhip.Zhip8.init(rand);
    zhip8.loadRomBytes(rom);

    rl.SetTargetFPS(60);
    rl.InitWindow(WINDOW_WIDTH, WINDOW_HEIGHT, "zhip8");
    rl.GuiSetStyle(rl.DEFAULT, rl.TEXT_SIZE, TEXT_SIZE);

    const iter_dir = try std.fs.cwd().openDir("roms", .{ .iterate = true });
    var iter = iter_dir.iterate();
    while (try iter.next()) |file| {
        if (file.kind == .file) {
            std.debug.print("filename: {s}\n", .{file.name});
            try rom_selection.romList.append(file.name);
        }
    }

    while (!rl.WindowShouldClose()) {
        if (rom_selection.rom_loaded == null) {
            try draw_select_roms(&rom_selection, alloc);
            if (rom_selection.rom_loaded != null) {
                var buff: [200]u8 = undefined;
                const path = try std.mem.concat(alloc, u8, &.{ "roms/", rom_selection.rom_loaded.? });
                try zhip8.loadRomByPath(try std.fs.cwd().realpath(path, &buff));
                alloc.free(path);
                zhip8.resetRom();
            }
        } else {
            try zhip8.mainLoop();
            try draw_raylib(&zhip8, &rom_selection);
            // g.print();
        }
    }
}

const GUI_WIDHT = 400;
const GUI_MARGIN = 20;
const GUI_BASE_HEIGHT = 20;

fn draw_select_roms(romSelection: *RomSelection, alloc: std.mem.Allocator) !void {
    rl.BeginDrawing();
    defer rl.EndDrawing();
    rl.ClearBackground(BACKGROUND_COLOR);
    rl.DrawFPS(10, WINDOW_HEIGHT - 30);
    var y: f32 = 10;

    for (romSelection.romList.items, 0..) |value, i| {
        _ = i; // autofix
        const valueZ = try alloc.dupeZ(u8, value);
        defer alloc.free(valueZ);

        if (rl.GuiButton(.{ .x = 100, .y = y, .width = WINDOW_WIDTH / 2, .height = 50 }, valueZ) > 0) {
            romSelection.rom_loaded = value;
        }
        y += 50;
    }
}

var gridVec = rl.Vector2{ .x = 0, .y = 0 };
fn draw_raylib(zhip8: *zhip.Zhip8, rom_selection: *RomSelection) !void {
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
    if (rl.GuiButton(.{
        .x = GUI_MARGIN,
        .y = y,
        .width = GUI_BASE_HEIGHT * 5,
        .height = GUI_BASE_HEIGHT * 2,
    }, "Eject") > 0) {
        rom_selection.rom_loaded = null;
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
