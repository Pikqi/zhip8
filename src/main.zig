const std = @import("std");

const cpu = @import("cpu.zig");
const ram = @import("ram.zig");
const gpu = @import("gpu.zig");
const ibm = @embedFile("roms/IBM Logo.ch8");

pub fn main() !void {
    var pc: usize = 0;

    var c = cpu.Cpu{};
    var r = ram.Ram{};
    r.load_font();
    pc = r.load(ibm);
    std.debug.print("pc {d}", .{pc});

    r.print(.{});

    var g = gpu.Gpu{};

    while (true) {
        var jumped: bool = false;
        defer pc = if (pc < r.end_index and !jumped) pc + 2 else pc;
        var instruction: u16 = r.memory[pc];
        instruction <<= 8;
        instruction += r.memory[pc + 1];

        std.debug.print(" instruction: {X:04}, pc: {d}\n", .{ instruction, pc });

        const X: u8 = @intCast((instruction & 0x0F00) >> 8);
        const Y: u8 = @intCast((instruction & 0x00F0) >> 4);
        const N: u8 = @intCast(instruction & 0x000F);
        const NN: u8 = @intCast(instruction & 0x00FF);
        const NNN: u16 = @intCast(instruction & 0x0FFF);

        switch (instruction & 0xF000) {
            0x0000 => {
                switch (instruction) {
                    // clear screen
                    0x00E0 => {
                        g.clear();
                    },
                    else => {
                        std.debug.print("Not implemented", .{});
                    },
                }
            },
            // jump 0x1NNN
            0x1000 => {
                pc = NNN;
                jumped = true;
                std.debug.print("jumped to {X:04} ps: {X:04} NNN: {X:04}", .{ pc, r.program_start, NNN });
                g.print();
            },
            // 6XNN Set register X to NN
            0x6000 => {
                c.V[X] = NN;
            },

            // 7XNN Add value NN to VX
            0x7000 => {
                c.V[X] +%= NN;
            },
            // ANNN set I to NNN
            0xA000 => {
                c.I = NNN;
            },
            //draw DXYN
            0xD000 => {
                var x_coord: usize = c.V[X] & (gpu.SCREEEN_WIDTH - 1);
                var y_coord: usize = c.V[Y] & (gpu.SCREEEN_HEIGHT - 1);
                // std.debug.print("x: {d} y: {d}\n", .{ x_coord, y_coord });
                c.V[0xF] = 0;
                out: for (0..N) |i| {
                    const row_pixels = r.memory[c.I + i];
                    // std.debug.print("row pixels {b:08}\n", .{row_pixels});
                    inline for (0..8) |j| {
                        const pixel_index = y_coord * gpu.SCREEEN_WIDTH + x_coord;
                        if (pixel_index > gpu.NUMBER_OF_PIXELS) {
                            // std.log.debug("out of the screen x: {d} y: {d} pxiel_index: {d}", .{ x_coord, y_coord, pixel_index });
                            continue :out;
                        }
                        const b: u8 = row_pixels & (0b10000000 >> j);
                        // std.log.debug("b: {d} row_pixels: {b:08} {b:08} \n", .{ b, row_pixels, 0b10000000 >> j });

                        if (g.display[pixel_index] and b > 0) {
                            g.display[pixel_index] = false;
                            c.V[0xF] = 1;
                        } else if (b > 0) {
                            g.display[pixel_index] = true;
                        }

                        x_coord += 1;
                    }
                    x_coord = c.V[X] & (gpu.SCREEEN_WIDTH - 1);
                    y_coord += 1;
                }
            },
            else => {
                std.debug.print("Not implemented\n", .{});
            },
        }

        std.Thread.sleep(1000 * 1000 * 100);
    }
}
