const std = @import("std");

const zhip = @import("zhip8.zig");
const gpu = @import("gpu.zig");

const rl = @cImport({
    @cInclude("raylib.h");
    @cInclude("raymath.h");
    @cInclude("rlgl.h");
    @cInclude("raygui.h");
});

const PIXEL_SCALE = 20;

var GUI_ENABLE = false;
const BACKGROUND_COLOR = rl.WHITE;
const WINDOW_HEIGHT = PIXEL_SCALE * gpu.SCREEEN_HEIGHT;

const PIXEL_COLOR = rl.GREEN;

const TEXT_SIZE = 20;
const RomList = std.ArrayList([]const u8);

const RomSelectionError = error{ NoRomsFolder, EmptyRomsFolder } || std.fs.Dir.OpenError;
const RomSelection = struct {
    rom_loaded: ?[]const u8 = null,
    romList: RomList,
    error_message: ?[]const u8 = null,

    pub fn init(alloc: std.mem.Allocator) RomSelection {
        return RomSelection{ .romList = RomList.init(alloc) };
    }
    pub fn deinit(self: *RomSelection) void {
        for (self.romList.items, 0..) |_, i| {
            self.romList.allocator.free(self.romList.items[i]);
        }
        self.romList.deinit();
    }
    pub fn load_rom_list(self: *RomSelection, alloc: std.mem.Allocator) !void {
        const iter_dir = std.fs.cwd().openDir("roms", .{ .iterate = true });
        const dir = iter_dir catch |err| switch (err) {
            std.fs.Dir.OpenError.FileNotFound => {
                self.error_message = "Roms folder not found.";
                return;
            },
            else => {
                return err;
            },
        };
        self.error_message = null;
        var iter = dir.iterate();
        while (try iter.next()) |file| {
            if (file.kind == .file) {
                std.debug.print("filename: {s}\n", .{file.name});
                const fileNameZ = try alloc.dupe(u8, file.name);
                self.romList.append(fileNameZ) catch unreachable;
            }
        }
    }
    pub fn unload_rom(self: *RomSelection) void {
        rl.SetTargetFPS(60);
        self.rom_loaded = null;
    }
    pub fn load_rom(self: *RomSelection, rom_path: []const u8) void {
        self.rom_loaded = rom_path;

        rl.SetTargetFPS(0);
    }
};

const frame_time = std.time.ns_per_s / 70;

var window_should_close: bool = false;
pub fn main() !void {
    const WINDOW_WIDTH = get_window_width();
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

    var rom_selection = RomSelection.init(alloc);
    defer rom_selection.deinit();
    var zhip8 = zhip.Zhip8.init(rand);
    try rom_selection.load_rom_list(alloc);
    std.debug.print("{s}", .{rom_selection.romList.items});

    rl.SetTargetFPS(60);
    rl.InitWindow(@intCast(WINDOW_WIDTH), WINDOW_HEIGHT, "zhip8");
    rl.GuiSetStyle(rl.DEFAULT, rl.TEXT_SIZE, TEXT_SIZE);
    rl.SetExitKey(rl.KEY_NULL);
    defer rl.CloseWindow();

    var previous_frame_start = std.time.nanoTimestamp();

    while (!window_should_close) {
        if (rom_selection.rom_loaded == null) {
            try draw_select_roms(&rom_selection, alloc);
            if (rom_selection.rom_loaded != null) {
                var buff: [200]u8 = undefined;
                std.log.debug("rom: {s}", .{rom_selection.rom_loaded.?});
                const path = try std.mem.concat(alloc, u8, &.{ "roms/", rom_selection.rom_loaded.? });
                try zhip8.loadRomByPath(try std.fs.cwd().realpath(path, &buff));
                alloc.free(path);
                zhip8.resetRom();
            }
        } else {
            try zhip8.mainLoop();
            const current_time_stamp = std.time.nanoTimestamp();
            const delta = current_time_stamp - previous_frame_start;
            if (delta > frame_time) {
                previous_frame_start = current_time_stamp;
                try draw_raylib(&zhip8, &rom_selection);
            }

            // g.print();
        }
    }
}

const GUI_WIDHT = 400;
const GUI_MARGIN = 20;
const GUI_BASE_HEIGHT = 20;

fn draw_select_roms(romSelection: *RomSelection, alloc: std.mem.Allocator) !void {
    if (rl.IsKeyPressed(rl.KEY_ESCAPE)) {
        window_should_close = true;
        return;
    }

    rl.BeginDrawing();
    defer rl.EndDrawing();
    rl.ClearBackground(BACKGROUND_COLOR);
    rl.DrawFPS(10, get_window_width() - 30);

    var y: f32 = 10;

    if (romSelection.error_message != null) {
        rl.DrawText(romSelection.error_message.?.ptr, 100, 100, 20, rl.BLACK);
    }

    for (romSelection.romList.items, 0..) |value, i| {
        _ = i; // autofix
        const valueZ = try alloc.dupeZ(u8, value);
        defer alloc.free(valueZ);

        if (rl.GuiButton(.{ .x = 100, .y = y, .width = @floatFromInt(@divFloor(get_window_width(), 2)), .height = 50 }, valueZ) > 0) {
            romSelection.load_rom(value);
        }
        y += 50;
    }
}

var gridVec = rl.Vector2{ .x = 0, .y = 0 };

const input_map = [_]c_int{
    rl.KEY_X,
    rl.KEY_ONE,
    rl.KEY_TWO,
    rl.KEY_THREE,
    rl.KEY_Q,
    rl.KEY_W,
    rl.KEY_E,
    rl.KEY_A,
    rl.KEY_S,
    rl.KEY_D,
    rl.KEY_Z,
    rl.KEY_C,
    rl.KEY_FOUR,
    rl.KEY_R,
    rl.KEY_F,
    rl.KEY_V,
};

fn draw_raylib(zhip8: *zhip.Zhip8, rom_selection: *RomSelection) !void {
    if (rl.IsKeyPressed(rl.KEY_ESCAPE)) {
        rom_selection.unload_rom();
    }
    inline for (input_map, 0..) |value, i| {
        if (rl.IsKeyDown(value)) {
            zhip8.input = @intCast(i);
            zhip8.is_input_pressed = true;
        }
    }
    rl.BeginDrawing();
    defer rl.EndDrawing();
    rl.ClearBackground(BACKGROUND_COLOR);
    rl.DrawFPS(10, WINDOW_HEIGHT - 30);

    if (rl.IsKeyPressed(rl.KEY_GRAVE)) {
        if (GUI_ENABLE) {
            rl.GuiDisable();
            rl.GuiSetAlpha(0.0);
            GUI_ENABLE = false;
            rl.SetWindowSize(get_window_width(), WINDOW_HEIGHT);
        } else {
            rl.GuiEnable();
            rl.GuiSetAlpha(1.0);
            GUI_ENABLE = true;
            rl.SetWindowSize(get_window_width(), WINDOW_HEIGHT);
        }
    }

    if (zhip8.gpu.need_to_render) {
        const x_offset: usize = if (GUI_ENABLE) GUI_WIDHT else 0;
        for (zhip8.gpu.display, 0..) |pixel, i| {
            const x = x_offset + (i & (gpu.SCREEEN_WIDTH - 1)) * PIXEL_SCALE;
            const y = (i / gpu.SCREEEN_WIDTH) * PIXEL_SCALE;
            if (pixel) {
                rl.DrawRectangle(@intCast(x), @intCast(y), PIXEL_SCALE, PIXEL_SCALE, PIXEL_COLOR);
            }
        }
    }

    if (!GUI_ENABLE) return;
    var y: f32 = GUI_MARGIN;

    _ = rl.GuiLabel(.{ .x = GUI_MARGIN, .y = y, .height = GUI_BASE_HEIGHT, .width = GUI_WIDHT }, "Clock speed 200-1000Mhz");
    new_row(&y);
    _ = rl.GuiSlider(.{
        .x = GUI_MARGIN,
        .y = y,
        .width = GUI_WIDHT - GUI_MARGIN * 2,
        .height = GUI_BASE_HEIGHT,
    }, "", "", &zhip8.clock_speed, 200, 1_000);
    new_row(&y);

    _ = rl.GuiCheckBox(.{
        .x = GUI_MARGIN,
        .y = y,
        .height = GUI_BASE_HEIGHT,
        .width = GUI_BASE_HEIGHT,
    }, "Pause", &zhip8.is_paused);

    _ = rl.GuiCheckBox(.{
        .x = GUI_MARGIN * 3 + GUI_BASE_HEIGHT * 3,
        .y = y,
        .height = GUI_BASE_HEIGHT,
        .width = GUI_BASE_HEIGHT,
    }, "Print debug", &zhip8.debug_to_console);

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
        rom_selection.unload_rom();
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

inline fn get_window_width() c_int {
    if (!GUI_ENABLE) {
        return PIXEL_SCALE * gpu.SCREEEN_WIDTH;
    }
    return PIXEL_SCALE * gpu.SCREEEN_WIDTH + GUI_WIDHT;
}

inline fn new_row(y: *f32) void {
    y.* += GUI_BASE_HEIGHT + 5;
}
