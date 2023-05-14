const std = @import("std");
const assert = std.debug.assert;
const pieces = @import("pieces.zig");
pub const Piece = pieces.Piece;
const c = @import("c.zig");

const lock_delay: f64 = 0.4;

const Vec3 = @import("math3d.zig").Vec3;
const Vec4 = @import("math3d.zig").Vec4;
const Mat4x4 = @import("math3d.zig").Mat4x4;
const PI = @import("math3d.zig").PI;

pub const InputState = packed struct {
    pause: bool = false,
    restart: bool = false,
    piece_rotate_pos: bool = false,
    piece_rotate_neg: bool = false,
    piece_drop: bool = false,
    piece_down: bool = false,
    piece_left: bool = false,
    piece_right: bool = false,
    piece_hold: bool = false,
    random_seed: u64 = 0,
};

pub const InputRecordMode = enum {
    none, no_record, record, playback, paused
};

pub const Tetris = struct {
    mutex: std.Thread.Mutex,
    piece_delay: f64,
    delay_left: f64,
    grid: [grid_height][grid_width]Cell,
    next_piece: *const Piece,
    hold_piece: ?*const Piece,
    hold_was_set: bool,
    cur_piece: *const Piece,
    cur_piece_x: i32,
    cur_piece_y: i32,
    cur_piece_rot: usize,
    score: c_int,
    game_over: bool,
    next_particle_index: usize,
    next_falling_block_index: usize,
    ghost_y: i32,
    screen_shake_timeout: f64,
    screen_shake_elapsed: f64,
    level: i32,
    time_till_next_level: f64,
    piece_pool: [pieces.pieces.len]i32,
    is_paused: bool,
    down_key_held: bool,
    down_move_time: f64,
    left_key_held: bool,
    left_move_time: f64,
    right_key_held: bool,
    right_move_time: f64,
    lock_until: f64 = -1,
    stage_width: f32,
    stage_height: f32,
    frame: u64,
    last_input_state: InputState,
    prng_impl: std.rand.DefaultPrng,
    prng: std.rand.Random,
    random_seed: u64,
    input_record_mode: InputRecordMode, // TODO: better place to put this?

    particles: [max_particle_count]?Particle,
    falling_blocks: [max_falling_block_count]?Particle,

    pub fn setStageSize(t: *Tetris, width: f32, height: f32) void {
        t.stage_width = width;
        t.stage_height = height;
    }

    pub fn restartGame(t: *Tetris, random_seed: u64) void {
        t.random_seed = random_seed;
        t.prng_impl = std.rand.DefaultPrng.init(t.random_seed);
        t.prng = t.prng_impl.random();
        t.frame = 0;
        t.last_input_state = InputState{};
        t.piece_delay = init_piece_delay;
        t.delay_left = init_piece_delay;
        t.score = 0;
        t.game_over = false;
        t.screen_shake_elapsed = 0.0;
        t.screen_shake_timeout = 0.0;
        t.level = 1;
        t.time_till_next_level = time_per_level;
        t.is_paused = false;
        t.hold_was_set = false;
        t.hold_piece = null;

        t.piece_pool = [_]i32{1} ** pieces.pieces.len;

        clearParticles(t);
        t.grid = empty_grid;

        populateNextPiece(t);
        dropNextPiece(t);
    }

    pub fn handleInput(t: *Tetris, now_time: f64, input_state: InputState) void {
        defer {
            t.last_input_state = input_state;
        }

        // Button inputs.
        if (input_state.piece_rotate_pos and !t.last_input_state.piece_rotate_pos) {
            t.userRotateCurPiece(1);
        }
        if (input_state.piece_rotate_neg and !t.last_input_state.piece_rotate_neg) {
            t.userRotateCurPiece(-1);
        }
        if (input_state.piece_drop and !t.last_input_state.piece_drop) {
            t.userDropCurPiece();
        }
        if (input_state.piece_hold and !t.last_input_state.piece_hold) {
            t.userSetHoldPiece();
        }
        if (input_state.pause and !t.last_input_state.pause) {
            t.userTogglePause();
        }
        if (input_state.restart and !t.last_input_state.restart) {
            t.restartGame(input_state.random_seed);
        }

        // Repeat inputs.
        const first_move_delay: f64 = 0.4;
        const next_move_delay: f64 = 0.045;
        while (input_state.piece_down and t.down_move_time <= now_time) {
            userCurPieceFall(t);
            const delay = if (t.last_input_state.piece_down) next_move_delay else first_move_delay;
            t.down_move_time = now_time + delay;
        }
        while (input_state.piece_left and t.left_move_time <= now_time) {
            userMoveCurPiece(t, -1);
            const delay = if (t.last_input_state.piece_left) next_move_delay else first_move_delay;
            t.left_move_time = now_time + delay;
        }
        while (input_state.piece_right and t.right_move_time <= now_time) {
            userMoveCurPiece(t, 1);
            const delay = if (t.last_input_state.piece_right) next_move_delay else first_move_delay;
            t.right_move_time = now_time + delay;
        }
        if (!input_state.piece_down) {
            t.down_move_time = 0;
        }
        if (!input_state.piece_left) {
            t.left_move_time = 0;
        }
        if (!input_state.piece_right) {
            t.right_move_time = 0;
        }
    }

    pub fn nextFrame(t: *Tetris, elapsed: f64) void {
        if (t.is_paused) return;

        updateKineticMotion(t, elapsed*0.1, t.falling_blocks[0..]);
        updateKineticMotion(t, elapsed*0.1, t.particles[0..]);

        if (!t.game_over) {
            t.delay_left -= elapsed;

            if (t.delay_left <= 0) {
                _ = curPieceFall(t);

                t.delay_left = t.piece_delay;
            }

            t.time_till_next_level -= elapsed;
            if (t.time_till_next_level <= 0.0) {
                levelUp(t);
            }

            computeGhost(t);
        }

        if (t.screen_shake_elapsed < t.screen_shake_timeout) {
            t.screen_shake_elapsed += elapsed;
        }

        t.frame += 1;
    }

    fn updateKineticMotion(t: *Tetris, elapsed: f64, some_particles: []?Particle) void {
        for (some_particles) |*maybe_p| {
            if (maybe_p.*) |*p| {
                p.pos.data[1] += @floatCast(f32, elapsed) * p.vel.data[1];
                p.vel.data[1] += @floatCast(f32, elapsed) * gravity;

                p.angle += p.angle_vel;

                if (p.pos.data[1] > t.stage_height) {
                    maybe_p.* = null;
                }
            }
        }
    }

    fn levelUp(t: *Tetris) void {
        t.level += 1;
        t.time_till_next_level = time_per_level;

        const new_piece_delay = t.piece_delay - level_delay_increment;
        t.piece_delay = if (new_piece_delay >= min_piece_delay) new_piece_delay else min_piece_delay;

        activateScreenShake(t, 0.08);

        const max_lines_to_fill = 4;
        const proposed_lines_to_fill = @divTrunc(t.level + 2, 3);
        const lines_to_fill = if (proposed_lines_to_fill > max_lines_to_fill)
            max_lines_to_fill
        else
            proposed_lines_to_fill;

        {
            var i: i32 = 0;
            while (i < lines_to_fill) : (i += 1) {
                insertGarbageRowAtBottom(t);
            }
        }
    }

    fn insertGarbageRowAtBottom(t: *Tetris) void {
        // move everything up to make room at the bottom
        {
            var y: usize = 1;
            while (y < t.grid.len) : (y += 1) {
                t.grid[y - 1] = t.grid[y];
            }
        }

        // populate bottom row with garbage and make sure it fills at least
        // one and leaves at least one empty
        while (true) {
            var all_empty = true;
            var all_filled = true;
            const bottom_y = grid_height - 1;
            for (t.grid[bottom_y], 0..) |_, x| {
                const filled = t.prng.boolean();
                if (filled) {
                    const index = t.prng.intRangeLessThan(usize, 0, pieces.pieces.len);
                    t.grid[bottom_y][x] = Cell{ .Color = pieces.pieces[index].color };
                    all_empty = false;
                } else {
                    t.grid[bottom_y][x] = Cell{ .Empty = {} };
                    all_filled = false;
                }
            }
            if (!all_empty and !all_filled) break;
        }

        if (pieceWouldCollide(t, t.cur_piece.*, t.cur_piece_x, t.cur_piece_y, t.cur_piece_rot)) {
            t.cur_piece_y -= 1;
        }
    }

    fn computeGhost(t: *Tetris) void {
        var off_y: i32 = 1;
        while (!pieceWouldCollide(t, t.cur_piece.*, t.cur_piece_x, t.cur_piece_y + off_y, t.cur_piece_rot)) {
            off_y += 1;
        }
        t.ghost_y = (t.cur_piece_y + off_y - 1);
    }

    pub fn userCurPieceFall(t: *Tetris) void {
        if (t.game_over or t.is_paused) return;
        _ = curPieceFall(t);
    }

    fn curPieceFall(t: *Tetris) bool {
        // if it would hit something, make it stop instead
        if (pieceWouldCollide(t, t.cur_piece.*, t.cur_piece_x, t.cur_piece_y + 1, t.cur_piece_rot)) {
            if (t.lock_until < 0) {
                t.lock_until = c.glfwGetTime() + lock_delay;
                return false;
            } else if (c.glfwGetTime() < t.lock_until) {
                return false;
            } else {
                lockPiece(t);
                dropNextPiece(t);
                return true;
            }
        } else {
            t.cur_piece_y += 1;
            t.lock_until = -1;
            return false;
        }
    }

    pub fn userDropCurPiece(t: *Tetris) void {
        if (t.game_over or t.is_paused) return;
        t.lock_until = 0;
        while (!curPieceFall(t)) {
            t.score += 1;
            t.lock_until = 0;
        }
    }

    pub fn userMoveCurPiece(t: *Tetris, dir: i8) void {
        if (t.game_over or t.is_paused) return;
        if (pieceWouldCollide(t, t.cur_piece.*, t.cur_piece_x + dir, t.cur_piece_y, t.cur_piece_rot)) {
            return;
        }
        t.cur_piece_x += dir;
    }

    pub fn userRotateCurPiece(t: *Tetris, rot: i8) void {
        if (t.game_over or t.is_paused) return;
        const new_rot = @intCast(usize, @rem(@intCast(isize, t.cur_piece_rot) + rot + 4, 4));
        const old_x = t.cur_piece_x;

        if (pieceWouldCollide(t, t.cur_piece.*, t.cur_piece_x, t.cur_piece_y, new_rot)) {
            switch (pieceWouldCollideWithWalls(t.cur_piece.*, t.cur_piece_x, t.cur_piece_y, new_rot)) {
                .left => {
                    t.cur_piece_x += 1;
                    while (pieceWouldCollideWithWalls(t.cur_piece.*, t.cur_piece_x, t.cur_piece_y, new_rot) == Wall.left) t.cur_piece_x += 1;
                },
                .right => {
                    t.cur_piece_x -= 1;
                    while (pieceWouldCollideWithWalls(t.cur_piece.*, t.cur_piece_x, t.cur_piece_y, new_rot) == Wall.right) t.cur_piece_x -= 1;
                },
                else => {},
            }
        }
        if (pieceWouldCollide(t, t.cur_piece.*, t.cur_piece_x, t.cur_piece_y, new_rot)) {
            t.cur_piece_x = old_x;
            return;
        }
        t.cur_piece_rot = new_rot;
    }

    pub fn userTogglePause(t: *Tetris) void {
        if (t.game_over) return;

        t.is_paused = !t.is_paused;
    }

    fn lockPiece(t: *Tetris) void {
        t.score += 1;

        for (t.cur_piece.layout[t.cur_piece_rot], 0..) |row, y| {
            for (row, 0..) |is_filled, x| {
                if (!is_filled) {
                    continue;
                }
                const abs_x = t.cur_piece_x + @intCast(i32, x);
                const abs_y = t.cur_piece_y + @intCast(i32, y);
                if (abs_x >= 0 and abs_y >= 0 and abs_x < grid_width and abs_y < grid_height) {
                    t.grid[@intCast(usize, abs_y)][@intCast(usize, abs_x)] = Cell{ .Color = t.cur_piece.color };
                }
            }
        }

        // find lines once and spawn explosions
        for (t.grid, 0..) |row, y| {
            _ = row;
            var all_filled = true;
            for (t.grid[y]) |cell| {
                const filled = switch (cell) {
                    Cell.Empty => false,
                    else => true,
                };
                if (!filled) {
                    all_filled = false;
                    break;
                }
            }
            if (all_filled) {
                for (t.grid[y], 0..) |cell, x| {
                    const color = switch (cell) {
                        Cell.Empty => continue,
                        Cell.Color => |col| col,
                    };
                    addExplosion(t, color, @intToFloat(f32, x), @intToFloat(f32, y));
                }
            }
        }

        // test for line
        var rows_deleted: usize = 0;
        var y: i32 = grid_height - 1;
        while (y >= 0) {
            var all_filled: bool = true;
            for (t.grid[@intCast(usize, y)]) |cell| {
                const filled = switch (cell) {
                    Cell.Empty => false,
                    else => true,
                };
                if (!filled) {
                    all_filled = false;
                    break;
                }
            }
            if (all_filled) {
                rows_deleted += 1;
                deleteRow(t, @intCast(usize, y));
            } else {
                y -= 1;
            }
        }

        const score_per_rows_deleted = [_]c_int{ 0, 10, 30, 50, 70 };
        t.score += score_per_rows_deleted[rows_deleted];

        if (rows_deleted > 0) {
            activateScreenShake(t, 0.1);
        }
    }

    fn activateScreenShake(t: *Tetris, duration: f64) void {
        t.screen_shake_elapsed = 0.0;
        t.screen_shake_timeout = duration;
    }

    fn deleteRow(t: *Tetris, del_index: usize) void {
        var y: usize = del_index;
        while (y >= 1) {
            t.grid[y] = t.grid[y - 1];
            y -= 1;
        }
        t.grid[y] = empty_row;
    }

    fn cellEmpty(t: *Tetris, x: i32, y: i32) bool {
        return switch (t.grid[@intCast(usize, y)][@intCast(usize, x)]) {
            Cell.Empty => true,
            else => false,
        };
    }

    fn pieceWouldCollide(t: *Tetris, piece: Piece, grid_x: i32, grid_y: i32, rot: usize) bool {
        for (piece.layout[rot], 0..) |row, y| {
            for (row, 0..) |is_filled, x| {
                if (!is_filled) {
                    continue;
                }
                const abs_x = grid_x + @intCast(i32, x);
                const abs_y = grid_y + @intCast(i32, y);
                if (abs_x >= 0 and abs_y >= 0 and abs_x < grid_width and abs_y < grid_height) {
                    if (!cellEmpty(t, abs_x, abs_y)) {
                        return true;
                    }
                } else if (abs_y >= 0) {
                    return true;
                }
            }
        }
        return false;
    }

    fn populateNextPiece(t: *Tetris) void {
        // Let's turn Gambler's Fallacy into Gambler's Accurate Model of Reality.
        var upper_bound: i32 = 0;
        for (t.piece_pool) |count| {
            if (count == 0) unreachable;
            upper_bound += count;
        }

        const rand_val = t.prng.intRangeLessThan(i32, 0, upper_bound);
        var this_piece_upper_bound: i32 = 0;
        var any_zero = false;
        for (t.piece_pool, 0..) |count, piece_index| {
            this_piece_upper_bound += count;
            if (rand_val < this_piece_upper_bound) {
                t.next_piece = &pieces.pieces[piece_index];
                t.piece_pool[piece_index] -= 1;
                if (count <= 1) {
                    any_zero = true;
                }
                break;
            }
        }

        // if any of the pieces are 0, add 1 to all of them
        if (any_zero) {
            for (t.piece_pool, 0..) |_, i| {
                t.piece_pool[i] += 1;
            }
        }
    }

    const Wall = enum {
        left,
        right,
        top,
        bottom,
        none,
    };

    fn pieceWouldCollideWithWalls(piece: Piece, grid_x: i32, grid_y: i32, rot: usize) Wall {
        for (piece.layout[rot], 0..) |row, y| {
            for (row, 0..) |is_filled, x| {
                if (!is_filled) {
                    continue;
                }
                const abs_x = grid_x + @intCast(i32, x);
                const abs_y = grid_y + @intCast(i32, y);
                if (abs_x < 0) {
                    return Wall.left;
                } else if (abs_x >= grid_width) {
                    return Wall.right;
                } else if (abs_y < 0) {
                    return Wall.top;
                } else if (abs_y >= grid_height) {
                    return Wall.top;
                }
            }
        }
        return Wall.none;
    }

    fn doGameOver(t: *Tetris) void {
        t.game_over = true;

        // turn every piece into a falling object
        for (t.grid, 0..) |row, y| {
            for (row, 0..) |cell, x| {
                const color = switch (cell) {
                    Cell.Empty => continue,
                    Cell.Color => |col| col,
                };
                const left = @intToFloat(f32, x);
                const top = @intToFloat(f32, y);
                t.falling_blocks[getNextFallingBlockIndex(t)] = createBlockParticle(&t.prng, color, Vec3.init(left, top, 0.0));
            }
        }
    }

    pub fn userSetHoldPiece(t: *Tetris) void {
        if (t.game_over or t.is_paused or t.hold_was_set) return;
        var next_cur: *const Piece = undefined;
        if (t.hold_piece) |hold_piece| {
            next_cur = hold_piece;
        } else {
            next_cur = t.next_piece;
            populateNextPiece(t);
        }
        t.hold_piece = t.cur_piece;
        t.hold_was_set = true;
        dropNewPiece(t, next_cur);
    }

    fn dropNewPiece(t: *Tetris, p: *const Piece) void {
        const start_x = 4;
        const start_y = -1;
        const start_rot = 0;

        t.lock_until = -1;

        if (pieceWouldCollide(t, p.*, start_x, start_y, start_rot)) {
            doGameOver(t);
            return;
        }

        t.delay_left = t.piece_delay;

        t.cur_piece = p;
        t.cur_piece_x = start_x;
        t.cur_piece_y = start_y;
        t.cur_piece_rot = start_rot;
    }

    fn dropNextPiece(t: *Tetris) void {
        t.hold_was_set = false;
        dropNewPiece(t, t.next_piece);
        populateNextPiece(t);
    }

    fn clearParticles(t: *Tetris) void {
        for (&t.particles) |*p| {
            p.* = null;
        }
        t.next_particle_index = 0;

        for (&t.falling_blocks) |*fb| {
            fb.* = null;
        }
        t.next_falling_block_index = 0;
    }

    fn getNextParticleIndex(t: *Tetris) usize {
        const result = t.next_particle_index;
        t.next_particle_index = (t.next_particle_index + 1) % max_particle_count;
        return result;
    }

    fn getNextFallingBlockIndex(t: *Tetris) usize {
        const result = t.next_falling_block_index;
        t.next_falling_block_index = (t.next_falling_block_index + 1) % max_falling_block_count;
        return result;
    }

    fn addExplosion(t: *Tetris, color: Vec4, center_x: f32, center_y: f32) void {
        const particle_count = 12;
        const particle_size = 1.0 / 3.0;
        {
            var i: i32 = 0;
            while (i < particle_count) : (i += 1) {
                const off_x = t.prng.float(f32) * 0.5;
                const off_y = t.prng.float(f32) * 0.5;
                const pos = Vec3.init(center_x + off_x, center_y + off_y, 0.0);
                t.particles[getNextParticleIndex(t)] = createParticle(&t.prng, color, particle_size, pos);
            }
        }
    }

    fn createParticle(prng: *std.rand.Random, color: Vec4, size: f32, pos: Vec3) Particle {
        var p: Particle = undefined;

        p.angle_vel = prng.float(f32) * 0.1 - 0.05;
        p.angle = prng.float(f32) * 2.0 * PI;
        p.axis = Vec3.init(0.0, 0.0, 1.0);
        p.scale_w = size * (0.8 + prng.float(f32) * 0.4);
        p.scale_h = size * (0.8 + prng.float(f32) * 0.4);
        p.color = color;
        p.pos = pos;

        const vel_x = prng.float(f32) * 2.0 - 1.0;
        const vel_y = -(2.0 + prng.float(f32) * 1.0);
        p.vel = Vec3.init(vel_x, vel_y, 0.0);

        return p;
    }

    fn createBlockParticle(prng: *std.rand.Random, color: Vec4, pos: Vec3) Particle {
        var p: Particle = undefined;

        p.angle_vel = prng.float(f32) * 0.05 - 0.025;
        p.angle = 0;
        p.axis = Vec3.init(0.0, 0.0, 1.0);
        p.scale_w = 1;
        p.scale_h = 1;
        p.color = color;
        p.pos = pos;

        const vel_x = prng.float(f32) * 0.5 - 0.25;
        const vel_y = -prng.float(f32) * 0.5;
        p.vel = Vec3.init(vel_x, vel_y, 0.0);

        return p;
    }

    pub const Cell = union(enum) {
        Empty,
        Color: Vec4,
    };

    pub const Particle = struct {
        color: Vec4,
        pos: Vec3,
        vel: Vec3,
        axis: Vec3,
        scale_w: f32,
        scale_h: f32,
        angle: f32,
        angle_vel: f32,
    };

    const max_particle_count = 500;
    pub const grid_width = 10;
    pub const grid_height = 20;
    const max_falling_block_count = grid_width * grid_height;

    const init_piece_delay = 0.5;
    const min_piece_delay = 0.05;
    const level_delay_increment = 0.05;

    const gravity = 1000.0;
    const time_per_level = 60.0;

    const empty_row = [_]Cell{Cell{ .Empty = {} }} ** grid_width;
    const empty_grid = [_][grid_width]Cell{empty_row} ** grid_height;
};
