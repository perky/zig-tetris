const std = @import("std");
const AllShaders = @import("all_shaders.zig").AllShaders;
const StaticGeometry = @import("static_geometry.zig").StaticGeometry;
const Spritesheet = @import("spritesheet.zig").Spritesheet;
const Vec3 = @import("math3d.zig").Vec3;
const Vec4 = @import("math3d.zig").Vec4;
const Mat4x4 = @import("math3d.zig").Mat4x4;
const PI = @import("math3d.zig").PI;
const Tetris = @import("tetris.zig").Tetris;
const Piece = @import("tetris.zig").Piece;
const c = @import("c.zig");
const assert = std.debug.assert;

const font_png = @embedFile("assets/font.png");

var projection: Mat4x4 = undefined;
var vertex_array_object: c.GLuint = undefined;
var all_shaders: AllShaders = undefined;
var static_geometry: StaticGeometry = undefined;
var font: Spritesheet = undefined;
pub var framebuffer_width: c_int = undefined;
pub var framebuffer_height: c_int = undefined;

const font_char_width = 18;
const font_char_height = 32;
const margin_size = 10;
pub const cell_size = 32;
const board_width = Tetris.grid_width * cell_size;
const board_height = Tetris.grid_height * cell_size;
const board_left = margin_size;
const board_top = margin_size;

const next_piece_width = margin_size + 4 * cell_size + margin_size;
const next_piece_height = next_piece_width;
const next_piece_left = board_left + board_width + margin_size;
const next_piece_top = board_top + board_height - next_piece_height;

const score_width = next_piece_width;
const score_height = next_piece_height;
const score_left = next_piece_left;
const score_top = next_piece_top - margin_size - score_height;

const level_display_width = next_piece_width;
const level_display_height = next_piece_height;
const level_display_left = next_piece_left;
const level_display_top = score_top - margin_size - level_display_height;

const hold_piece_width = next_piece_width;
const hold_piece_height = next_piece_height;
const hold_piece_left = next_piece_left;
const hold_piece_top = level_display_top - margin_size - hold_piece_height;

pub const window_width = next_piece_left + next_piece_width + margin_size;
pub const window_height = board_top + board_height + margin_size;
const board_color = Vec4{ .data = [_]f32{ 72.0 / 255.0, 72.0 / 255.0, 72.0 / 255.0, 1.0 } };

pub fn init(width: c_int, height: c_int) void {
    framebuffer_width = width;
    framebuffer_height = height;
    // create and bind exactly one vertex array per context and use
    // glVertexAttribPointer etc every frame.
    c.glGenVertexArrays(1, &vertex_array_object);
    c.glBindVertexArray(vertex_array_object);
    all_shaders = AllShaders.create() catch @panic("Failed to create shaders");
    static_geometry = StaticGeometry.create();
    font.init(font_png, font_char_width, font_char_height) catch @panic("Unable to read fonts");
}

pub fn deinit() void {
    c.glDeleteVertexArrays(1, &vertex_array_object);
    all_shaders.destroy();
    static_geometry.destroy();
    font.deinit();
}

pub fn resetProjection() void {
    projection = Mat4x4.ortho(
        0.0,
        @intToFloat(f32, framebuffer_width),
        @intToFloat(f32, framebuffer_height),
        0.0,
    );
}

pub fn fillRectMvp(color: Vec4, mvp: Mat4x4) void {
    all_shaders.primitive.bind();
    all_shaders.primitive.setUniformVec4(all_shaders.primitive_uniform_color, color);
    all_shaders.primitive.setUniformMat4x4(all_shaders.primitive_uniform_mvp, mvp);

    c.glBindBuffer(c.GL_ARRAY_BUFFER, static_geometry.rect_2d_vertex_buffer);
    c.glEnableVertexAttribArray(@intCast(c.GLuint, all_shaders.primitive_attrib_position));
    c.glVertexAttribPointer(@intCast(c.GLuint, all_shaders.primitive_attrib_position), 3, c.GL_FLOAT, c.GL_FALSE, 0, null);

    c.glDrawArrays(c.GL_TRIANGLE_STRIP, 0, 4);
}

pub fn drawParticle(p: Tetris.Particle) void {
    const f_cell_size = @intToFloat(f32, cell_size);
    const pos_x = @intToFloat(f32, board_left) + (p.pos.data[0] * f_cell_size) + f_cell_size / 2.0;
    const pos_y = @intToFloat(f32, board_top)  + (p.pos.data[1] * f_cell_size) + f_cell_size / 2.0;
    const pos = Vec3.init(pos_x, pos_y, 0.0);
    const scale_w = p.scale_w * @as(f32, cell_size);
    const scale_h = p.scale_h * @as(f32, cell_size);
    const model = Mat4x4.identity.translateByVec(pos).rotate(p.angle, p.axis).scale(scale_w, scale_h, 0.0);

    const mvp = projection.mult(model);

    all_shaders.primitive.bind();
    all_shaders.primitive.setUniformVec4(all_shaders.primitive_uniform_color, p.color);
    all_shaders.primitive.setUniformMat4x4(all_shaders.primitive_uniform_mvp, mvp);

    c.glBindBuffer(c.GL_ARRAY_BUFFER, static_geometry.triangle_2d_vertex_buffer);
    c.glEnableVertexAttribArray(@intCast(c.GLuint, all_shaders.primitive_attrib_position));
    c.glVertexAttribPointer(@intCast(c.GLuint, all_shaders.primitive_attrib_position), 3, c.GL_FLOAT, c.GL_FALSE, 0, null);

    c.glDrawArrays(c.GL_TRIANGLE_STRIP, 0, 3);
}

pub fn drawText(text: []const u8, left: i32, top: i32, size: f32) void {
    for (text, 0..) |col, i| {
        if (col <= '~') {
            const char_left = @intToFloat(f32, left) + @intToFloat(f32, i * font_char_width) * size;
            const model = Mat4x4.identity.translate(char_left, @intToFloat(f32, top), 0.0).scale(size, size, 0.0);
            const mvp = projection.mult(model);

            font.draw(all_shaders, col, mvp);
        } else {
            unreachable;
        }
    }
}

pub fn drawCenteredText(text: []const u8) void {
    const label_width = font_char_width * @intCast(i32, text.len);
    const draw_left = board_left + board_width / 2 - @divExact(label_width, 2);
    const draw_top = board_top + board_height / 2 - font_char_height / 2;
    drawText(text, draw_left, draw_top, 1.0);
}

pub fn fillRect(color: Vec4, x: f32, y: f32, w: f32, h: f32) void {
    const model = Mat4x4.identity.translate(x, y, 0.0).scale(w, h, 0.0);
    const mvp = projection.mult(model);
    fillRectMvp(color, mvp);
}

pub fn drawFallingBlock(p: Tetris.Particle) void {
    const model = Mat4x4.identity.translateByVec(p.pos).rotate(p.angle, p.axis).scale(p.scale_w, p.scale_h, 0.0);
    const mvp = projection.mult(model);
    fillRectMvp(p.color, mvp);
}

pub fn drawPiece(piece: Piece, left: i32, top: i32, rot: usize) void {
    drawPieceWithColor(piece, left, top, rot, piece.color);
}

pub fn drawPieceWithColor(piece: Piece, left: i32, top: i32, rot: usize, color: Vec4) void {
    for (piece.layout[rot], 0..) |row, y| {
        for (row, 0..) |is_filled, x| {
            if (!is_filled) continue;
            const abs_x = @intToFloat(f32, left + @intCast(i32, x) * cell_size);
            const abs_y = @intToFloat(f32, top + @intCast(i32, y) * cell_size);
            fillRect(color, abs_x, abs_y, cell_size, cell_size);
        }
    }
}

pub fn drawTetris(t: *const Tetris) void {
    if (t.screen_shake_elapsed < t.screen_shake_timeout) {
        if (t.screen_shake_elapsed >= t.screen_shake_timeout) {
            resetProjection();
        } else {
            const rate = 8; // oscillations per sec
            const amplitude = 4; // pixels
            const offset = @floatCast(f32, amplitude * -c.sin(2.0 * PI * t.screen_shake_elapsed * rate));
            projection = Mat4x4.ortho(
                0.0,
                @intToFloat(f32, framebuffer_width),
                @intToFloat(f32, framebuffer_height) + offset,
                offset,
            );
        }
    }

    fillRect(board_color, board_left, board_top, board_width, board_height);
    fillRect(board_color, next_piece_left, next_piece_top, next_piece_width, next_piece_height);
    fillRect(board_color, score_left, score_top, score_width, score_height);
    fillRect(board_color, level_display_left, level_display_top, level_display_width, level_display_height);
    fillRect(board_color, hold_piece_left, hold_piece_top, hold_piece_width, hold_piece_height);

    if (t.game_over) {
        drawCenteredText("GAME OVER");
    } else if (t.is_paused) {
        drawCenteredText("PAUSED");
    } else {
        const abs_x = board_left + t.cur_piece_x * cell_size;
        const abs_y = board_top + t.cur_piece_y * cell_size;
        drawPiece(t.cur_piece.*, abs_x, abs_y, t.cur_piece_rot);

        { // draw ghost
            const ghost_color = Vec4.init(t.cur_piece.color.data[0], t.cur_piece.color.data[1], t.cur_piece.color.data[2], 0.2);
            const ghost_y = board_top + cell_size * t.ghost_y;
            drawPieceWithColor(t.cur_piece.*, abs_x, ghost_y, t.cur_piece_rot, ghost_color);
        }

        drawPiece(t.next_piece.*, next_piece_left + margin_size, next_piece_top + margin_size, 0);
        if (t.hold_piece) |piece| {
            if (!t.hold_was_set) {
                drawPiece(piece.*, hold_piece_left + margin_size, hold_piece_top + margin_size, 0);
            } else {
                const grey = Vec4.init(0.65, 0.65, 0.65, 1.0);
                drawPieceWithColor(piece.*, hold_piece_left + margin_size, hold_piece_top + margin_size, 0, grey);
            }
        }

        for (t.grid, 0..) |row, y| {
            for (row, 0..) |cell, x| {
                switch (cell) {
                    Tetris.Cell.Color => |color| {
                        const cell_left = board_left + @intCast(i32, x) * cell_size;
                        const cell_top = board_top + @intCast(i32, y) * cell_size;
                        fillRect(
                            color,
                            @intToFloat(f32, cell_left),
                            @intToFloat(f32, cell_top),
                            cell_size,
                            cell_size,
                        );
                    },
                    else => {},
                }
            }
        }
    }

    switch (t.input_record_mode) {
        .playback => {
            drawCenteredText("PLAYBACK");
        },
        .paused => {
            drawCenteredText("PLAYBACK END");
        },
        else => {}
    }

    {
        const score_text = "SCORE:";
        const score_label_width = font_char_width * @intCast(i32, score_text.len);
        drawText(
            score_text,
            score_left + score_width / 2 - score_label_width / 2,
            score_top + margin_size,
            1.0,
        );
    }
    {
        var score_text_buf: [20]u8 = undefined;
        const len = @intCast(usize, c.sprintf(&score_text_buf, "%d", t.score));
        const score_text = score_text_buf[0..len];
        const score_label_width = font_char_width * @intCast(i32, score_text.len);
        drawText(score_text, score_left + score_width / 2 - @divExact(score_label_width, 2), score_top + score_height / 2, 1.0);
    }
    {
        const text = "LEVEL:";
        const text_width = font_char_width * @intCast(i32, text.len);
        drawText(text, level_display_left + level_display_width / 2 - text_width / 2, level_display_top + margin_size, 1.0);
    }
    {
        var text_buf: [20]u8 = undefined;
        const len = @intCast(usize, c.sprintf(&text_buf, "%d", t.level));
        const text = text_buf[0..len];
        const text_width = font_char_width * @intCast(i32, text.len);
        drawText(text, level_display_left + level_display_width / 2 - @divExact(text_width, 2), level_display_top + level_display_height / 2, 1.0);
    }
    {
        const text = "HOLD:";
        const text_width = font_char_width * @intCast(i32, text.len);
        drawText(text, hold_piece_left + hold_piece_width / 2 - text_width / 2, hold_piece_top + margin_size, 1.0);
    }

    for (t.falling_blocks) |maybe_particle| {
        if (maybe_particle) |particle| {
            drawFallingBlock(particle);
        }
    }

    for (t.particles) |maybe_particle| {
        if (maybe_particle) |particle| {
            drawParticle(particle);
        }
    }
}