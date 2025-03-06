const std = @import("std");
const cpu = @import("cpu.zig");
const gpu = @import("gpu.zig");
const ram = @import("ram.zig");
const Random = std.Random;

pub const Zhip8 = struct {
    ram: ram.Ram,
    cpu: cpu.Cpu,
    gpu: gpu.Gpu,

    rng: Random,

    pc: usize = 0,
    init_pc: usize = 0,
    is_paused: bool = false,
    clock_speed: f32 = 700,

    step_count: u16 = 0,
    start_time: i128,

    debug_to_console: bool = true,

    pub fn init(rng: Random) Zhip8 {
        const start_time = std.time.nanoTimestamp();
        var zhip8Instance = Zhip8{ .ram = ram.Ram{}, .cpu = cpu.Cpu{}, .gpu = gpu.Gpu{}, .rng = rng, .start_time = start_time };
        zhip8Instance.ram.load_font();

        return zhip8Instance;
    }
    pub fn resetRom(self: *Zhip8) void {
        self.pc = self.init_pc;
        self.cpu = cpu.Cpu{};
        self.start_time = std.time.nanoTimestamp();
        self.gpu.clear();
        self.is_paused = false;
    }
    pub fn loadRomBytes(self: *Zhip8, rom: []const u8) void {
        self.resetRom();
        self.init_pc = self.ram.load(rom);
        self.pc = self.init_pc;
    }
    pub fn loadRomByPath(path_to_rom: []u8) void {
        _ = path_to_rom; // autofix
    }

    pub fn step_for(self: *Zhip8, step_count: u16) void {
        self.is_paused = true;
        self.step_count = step_count;
    }

    pub fn mainLoop(self: *Zhip8) !void {
        if (self.is_paused and self.step_count == 0) {
            return;
        }
        if (self.step_count > 0) {
            self.step_count -= 1;
        }

        const instructionTime = std.time.ns_per_s / @as(u64, @intFromFloat(self.clock_speed));
        const cycleStartTime: u64 = @intCast(std.time.nanoTimestamp() - self.start_time);
        var jumped: bool = false;
        defer self.pc = if (self.pc < self.ram.end_index and !jumped) self.pc + 2 else self.pc;
        var instruction: u16 = self.ram.memory[self.pc];
        instruction <<= 8;
        instruction += self.ram.memory[self.pc + 1];

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
                        self.gpu.clear();
                    },

                    // Exit from subroutine, pop pc from the stack
                    0x00EE => {
                        self.pc = try self.cpu.stack.pop();
                    },
                    else => {
                        not_implemented(instruction);
                    },
                }
            },
            // jump 0x1NNN
            0x1000 => {
                self.pc = NNN;
                jumped = true;
                // std.debug.print("jumped to {X:04} ps: {X:04} NNN: {X:04}", .{ pc, self.ram.program_start, NNN });
            },
            // 2NNN Call subroutine at location NNN
            0x2000 => {
                try self.cpu.stack.push(@intCast(self.pc));
                self.pc = NNN;
                jumped = true;
                // std.debug.print("jumped to {X:04} ps: {X:04} NNN: {X:04}", .{ pc, self.ram.program_start, NNN });
            },
            // 3XNN  skip one instruction if VX is equal to NN
            0x3000 => {
                if (self.cpu.V[X] == NN) {
                    self.pc += 2;
                }
            },
            // 4XNN  skip one instruction if VX is not equal to NN
            0x4000 => {
                if (self.cpu.V[X] != NN) {
                    self.pc += 2;
                }
            },
            // 5XY0  skip one instruction if VX is equal to VY
            0x5000 => {
                if (self.cpu.V[X] == self.cpu.V[Y]) {
                    self.pc += 2;
                }
            },
            // 6XNN Set register X to NN
            0x6000 => {
                self.cpu.V[X] = NN;
            },

            // 7XNN Add value NN to VX
            0x7000 => {
                self.cpu.V[X] +%= NN;
            },
            // Arthimetic operands, last nible indentifier
            0x8000 => {
                switch (instruction & 0x000F) {
                    // 8XY0 Set VX to value VY
                    0x0 => {
                        self.cpu.V[X] = self.cpu.V[Y];
                    },
                    // 8XY1 VX is set to bitwise OR of VX and VY
                    0x1 => {
                        self.cpu.V[X] |= self.cpu.V[Y];
                    },
                    // 8XY2 VX is set to bitwise AND of VX and VY
                    0x2 => {
                        self.cpu.V[X] &= self.cpu.V[Y];
                    },
                    // 8XY3 VX is set to bitwise XOR of VX and VY
                    0x3 => {
                        self.cpu.V[X] ^= self.cpu.V[Y];
                    },
                    // 8XY4 Add VX and VY to VX
                    0x4 => {
                        const result, const has_overflown = @addWithOverflow(self.cpu.V[X], self.cpu.V[Y]);
                        self.cpu.V[X] = result;
                        if (has_overflown > 0) {
                            self.cpu.V[0xF] = 1;
                        } else {
                            self.cpu.V[0xF] = 0;
                        }
                    },
                    // 8XY5 VX - VY
                    0x5 => {
                        const result, const has_overflown = @subWithOverflow(self.cpu.V[X], self.cpu.V[Y]);
                        self.cpu.V[X] = result;
                        if (has_overflown > 0) {
                            self.cpu.V[0xF] = 0;
                        } else {
                            self.cpu.V[0xF] = 1;
                        }
                    },
                    // modern apporach
                    //  8XY6 SHIFT left
                    0x6 => {
                        self.cpu.V[X] = self.cpu.V[Y];
                        if ((self.cpu.V[X] & 0b1) > 0) {
                            self.cpu.V[0xF] = 1;
                        } else {
                            self.cpu.V[0xF] = 0;
                        }
                        self.cpu.V[X] >>= 1;
                    },
                    // 8XY7 VY - VX
                    0x7 => {
                        const result, const has_overflown = @subWithOverflow(self.cpu.V[Y], self.cpu.V[X]);
                        self.cpu.V[X] = result;
                        if (has_overflown > 0) {
                            self.cpu.V[0xF] = 0;
                        } else {
                            self.cpu.V[0xF] = 1;
                        }
                    },

                    // modern apporach
                    //  8XYE SHIFT right
                    0xE => {
                        self.cpu.V[X] = self.cpu.V[Y];
                        if ((self.cpu.V[X] & 0b10000000) > 0) {
                            self.cpu.V[0xF] = 1;
                        } else {
                            self.cpu.V[0xF] = 0;
                        }
                        self.cpu.V[X] <<= 1;
                    },
                    else => {
                        not_implemented(instruction);
                    },
                }
            },
            // 9XY0  skip one instruction if VX is not equal to VY
            0x9000 => {
                if (self.cpu.V[X] != self.cpu.V[Y]) {
                    self.pc += 2;
                }
            },
            // ANNN set I to NNN
            0xA000 => {
                self.cpu.I = NNN;
            },
            // BNNN Jump with offset, not modern type
            0xB000 => {
                jumped = true;
                self.pc = NNN;
            },
            // CXNN Random
            0xC000 => {
                const random_byte = self.rng.intRangeAtMost(u8, 0, 0xFF);
                self.cpu.V[X] = random_byte & NN;
            },
            //draw DXYN
            0xD000 => {
                // defer draw_raylib(&self.gpu);

                var x_coord: usize = self.cpu.V[X] & (gpu.SCREEEN_WIDTH - 1);
                var y_coord: usize = self.cpu.V[Y] & (gpu.SCREEEN_HEIGHT - 1);
                // std.debug.print("x: {d} y: {d}\n", .{ x_coord, y_coord });
                self.cpu.V[0xF] = 0;
                out: for (0..N) |i| {
                    const row_pixels = self.ram.memory[self.cpu.I + i];
                    // std.debug.print("row pixels {b:08}\n", .{row_pixels});
                    inline for (0..8) |j| {
                        const pixel_index = y_coord * gpu.SCREEEN_WIDTH + x_coord;
                        if (pixel_index >= gpu.NUMBER_OF_PIXELS) {
                            // std.log.debug("out of the screen x: {d} y: {d} pxiel_index: {d}", .{ x_coord, y_coord, pixel_index });
                            continue :out;
                        }
                        const b: u8 = row_pixels & (0b10000000 >> j);
                        // std.log.debug("b: {d} row_pixels: {b:08} {b:08} \n", .{ b, row_pixels, 0b10000000 >> j });

                        if (self.gpu.display[pixel_index] and b > 0) {
                            self.gpu.display[pixel_index] = false;
                            self.cpu.V[0xF] = 1;
                        } else if (b > 0) {
                            self.gpu.display[pixel_index] = true;
                        }

                        x_coord += 1;
                    }
                    x_coord = self.cpu.V[X] & (gpu.SCREEEN_WIDTH - 1);
                    y_coord += 1;
                }
            },
            0xF000 => {
                switch (instruction & 0x00FF) {
                    //Timers
                    0x07 => {
                        self.cpu.V[X] = self.cpu.delay_timer;
                    },
                    0x15 => {
                        self.cpu.delay_timer = self.cpu.V[X];
                    },
                    0x18 => {
                        self.cpu.sound_timer = self.cpu.V[X];
                    },
                    // FX1E Add to index
                    0x1E => {
                        self.cpu.I += self.cpu.V[X];
                        if (self.cpu.I > 0xFFF) {
                            self.cpu.V[0xF] = 1;
                        } else {
                            self.cpu.V[0xF] = 0;
                        }
                    },
                    // FX0A Get key input
                    0x0A => {
                        // std.debug.print("Get key\n", .{});
                        jumped = true;
                    },
                    //FX29 Set Font character. set I to address of character X
                    0x29 => {
                        self.cpu.I = ram.font_start + self.cpu.V[X];
                    },
                    //FX33 Binary coded decimal conversion take a number from VX,
                    //and store its decimal digits at I, I+1 and I+2
                    0x33 => {
                        const num = self.cpu.V[X];
                        self.ram.memory[self.cpu.I] = num / 100;
                        self.ram.memory[self.cpu.I + 1] = (num - self.ram.memory[self.cpu.I] * 100) / 10;
                        self.ram.memory[self.cpu.I + 2] = (num - self.ram.memory[self.cpu.I] * 100) - self.ram.memory[self.cpu.I + 1] * 10;
                    },
                    //FX55 Store to memory from register V0 to VX
                    0x55 => {
                        for (0..X + 1) |i| {
                            self.ram.memory[self.cpu.I + i] = self.cpu.V[i];
                        }
                    },
                    //FX65 Load from memory
                    0x65 => {
                        for (0..X + 1) |i| {
                            self.cpu.V[i] = self.ram.memory[self.cpu.I + i];
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
        const endTime: u64 = @intCast(std.time.nanoTimestamp() - self.start_time);
        const delta = endTime - cycleStartTime;
        var sleep: u64 = 0;
        if (delta < instructionTime) {
            sleep = instructionTime - delta;
            std.time.sleep(sleep);
        }
        if (self.debug_to_console) {
            std.log.debug("pc: {d} instruction: {X:04}", .{ self.pc, instruction });
            std.log.debug("delta : {d}us delay: {d}us\n", .{ delta / std.time.ns_per_us, sleep / std.time.ns_per_us });
        }
    }

    fn not_implemented(instruction: u16) void {
        std.debug.print("Not implemented {X:04}\n", .{instruction});
    }
};
