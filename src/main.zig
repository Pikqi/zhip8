const std = @import("std");

const cpu = @import("cpu.zig");
const ram = @import("ram.zig");
const gpu = @import("gpu.zig");
const ibm = @embedFile("roms/IBM Logo.ch8");

pub fn main() !void {
    var prng = std.Random.DefaultPrng.init(blk: {
        var seed: u64 = undefined;
        try std.posix.getrandom(std.mem.asBytes(&seed));
        break :blk seed;
    });
    const rand = prng.random();
    var pc: usize = 0;

    var c = cpu.Cpu{};
    var r = ram.Ram{};
    r.load_font();
    pc = r.load(ibm);
    // std.debug.print("pc {d}", .{pc});

    r.print(.{});

    var g = gpu.Gpu{};

    while (true) {
        var jumped: bool = false;
        defer pc = if (pc < r.end_index and !jumped) pc + 2 else pc;
        var instruction: u16 = r.memory[pc];
        instruction <<= 8;
        instruction += r.memory[pc + 1];

        // std.debug.print(" instruction: {X:04}, pc: {d}\n", .{ instruction, pc });

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

                    // Exit from subroutine, pop pc from the stack
                    0x00EE => {
                        pc = try c.stack.pop();
                    },
                    else => {
                        not_implemented(instruction);
                    },
                }
            },
            // jump 0x1NNN
            0x1000 => {
                pc = NNN;
                jumped = true;
                // std.debug.print("jumped to {X:04} ps: {X:04} NNN: {X:04}", .{ pc, r.program_start, NNN });
            },
            // 2NNN Call subroutine at location NNN
            0x2000 => {
                try c.stack.push(@intCast(pc));
                pc = NNN;
                jumped = true;
                // std.debug.print("jumped to {X:04} ps: {X:04} NNN: {X:04}", .{ pc, r.program_start, NNN });
            },
            // 3XNN  skip one instruction if VX is equal to NN
            0x3000 => {
                if (c.V[X] == NN) {
                    pc += 2;
                }
            },
            // 4XNN  skip one instruction if VX is not equal to NN
            0x4000 => {
                if (c.V[X] != NN) {
                    pc += 2;
                }
            },
            // 5XY0  skip one instruction if VX is equal to VY
            0x5000 => {
                if (c.V[X] == c.V[Y]) {
                    pc += 2;
                }
            },
            // 6XNN Set register X to NN
            0x6000 => {
                c.V[X] = NN;
            },

            // 7XNN Add value NN to VX
            0x7000 => {
                c.V[X] +%= NN;
            },
            // Arthimetic operands, last nible indentifier
            0x8000 => {
                switch (instruction & 0x000F) {
                    // 8XY0 Set VX to value VY
                    0x0 => {
                        c.V[X] = c.V[Y];
                    },
                    // 8XY1 VX is set to bitwise OR of VX and VY
                    0x1 => {
                        c.V[X] |= c.V[Y];
                    },
                    // 8XY2 VX is set to bitwise AND of VX and VY
                    0x2 => {
                        c.V[X] &= c.V[Y];
                    },
                    // 8XY3 VX is set to bitwise XOR of VX and VY
                    0x3 => {
                        c.V[X] ^= c.V[Y];
                    },
                    // 8XY4 Add VX and VY to VX
                    0x4 => {
                        const result, const has_overflown = @addWithOverflow(c.V[X], c.V[Y]);
                        c.V[X] = result;
                        if (has_overflown > 0) {
                            c.V[0xF] = 1;
                        } else {
                            c.V[0xF] = 0;
                        }
                    },
                    // 8XY5 VX - VY
                    0x5 => {
                        const result, const has_overflown = @subWithOverflow(c.V[X], c.V[Y]);
                        c.V[X] = result;
                        if (has_overflown > 0) {
                            c.V[0xF] = 0;
                        } else {
                            c.V[0xF] = 1;
                        }
                    },
                    // modern apporach
                    //  8XY6 SHIFT left
                    0x6 => {
                        c.V[X] = c.V[Y];
                        if ((c.V[X] & 0b1) > 0) {
                            c.V[0xF] = 1;
                        } else {
                            c.V[0xF] = 0;
                        }
                        c.V[X] >>= 1;
                    },
                    // 8XY7 VY - VX
                    0x7 => {
                        const result, const has_overflown = @subWithOverflow(c.V[Y], c.V[X]);
                        c.V[X] = result;
                        if (has_overflown > 0) {
                            c.V[0xF] = 0;
                        } else {
                            c.V[0xF] = 1;
                        }
                    },

                    // modern apporach
                    //  8XYE SHIFT right
                    0xE => {
                        c.V[X] = c.V[Y];
                        if ((c.V[X] & 0b10000000) > 0) {
                            c.V[0xF] = 1;
                        } else {
                            c.V[0xF] = 0;
                        }
                        c.V[X] <<= 1;
                    },
                    else => {
                        not_implemented(instruction);
                    },
                }
            },
            // 9XY0  skip one instruction if VX is not equal to VY
            0x9000 => {
                if (c.V[X] != c.V[Y]) {
                    pc += 2;
                }
            },
            // ANNN set I to NNN
            0xA000 => {
                c.I = NNN;
            },
            // BNNN Jump with offset, not modern type
            0xB000 => {
                jumped = true;
                pc = NNN;
            },
            // CXNN Random
            0xC000 => {
                const random_byte = rand.intRangeAtMost(u8, 0, 0xFF);
                c.V[X] = random_byte & NN;
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
                        if (pixel_index >= gpu.NUMBER_OF_PIXELS) {
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
            0xF000 => {
                switch (instruction & 0x00FF) {
                    //Timers
                    0x07 => {
                        c.V[X] = c.delay_timer;
                    },
                    0x15 => {
                        c.delay_timer = c.V[X];
                    },
                    0x18 => {
                        c.sound_timer = c.V[X];
                    },
                    // FX1E Add to index
                    0x1E => {
                        c.I += c.V[X];
                        if (c.I > 0xFFF) {
                            c.V[0xF] = 1;
                        } else {
                            c.V[0xF] = 0;
                        }
                    },
                    // FX0A Get key input
                    0x0A => {
                        // std.debug.print("Get key\n", .{});
                    },
                    //FX29 Set Font character. set I to address of character X
                    0x29 => {
                        c.I = ram.font_start + c.V[X];
                    },
                    //FX33 Binary coded decimal conversion take a number from VX,
                    //and store its decimal digits at I, I+1 and I+2
                    0x33 => {
                        const num = c.V[X];
                        r.memory[c.I] = num / 100;
                        r.memory[c.I + 1] = (num - r.memory[c.I] * 100) / 10;
                        r.memory[c.I + 2] = (num - r.memory[c.I] * 100) - r.memory[c.I + 1] * 10;
                    },
                    //FX55 Store to memory from register V0 to VX
                    0x55 => {
                        for (0..X + 1) |i| {
                            r.memory[c.I + i] = c.V[i];
                        }
                    },
                    //FX65 Load from memory
                    0x65 => {
                        for (0..X + 1) |i| {
                            c.V[i] = r.memory[c.I + i];
                        }
                    },
                    else => {
                        not_implemented(instruction);
                    },
                }
            },
            else => {
                not_implemented(instruction);
            },
        }

        g.print();
        std.Thread.sleep(1000 * 1000 * 1);
    }
}
fn not_implemented(instruction: u16) void {
    std.debug.print("Not implemented {X:04}\n", .{instruction});
}
