const std = @import("std");
const c = @import("c.zig");
const gl = @import("zopengl");
const AllShaders = @import("all_shaders.zig").AllShaders;
const Mat4x4 = @import("math3d.zig").Mat4x4;
const PngImage = @import("png.zig").PngImage;

pub const Spritesheet = struct {
    img: PngImage,
    count: usize,
    texture_id: c.GLuint,
    vertex_buffer: c.GLuint,
    tex_coord_buffers: []c.GLuint,

    pub fn draw(s: *Spritesheet, as: AllShaders, index: usize, mvp: Mat4x4) void {
        as.texture.bind();
        as.texture.setUniformMat4x4(as.texture_uniform_mvp, mvp);
        as.texture.setUniformInt(as.texture_uniform_tex, 0);

        gl.bindBuffer(gl.ARRAY_BUFFER, s.vertex_buffer);
        gl.enableVertexAttribArray(@intCast(c.GLuint, as.texture_attrib_position));
        gl.vertexAttribPointer(@intCast(c.GLuint, as.texture_attrib_position), 3, gl.FLOAT, gl.FALSE, 0, null);

        gl.bindBuffer(gl.ARRAY_BUFFER, s.tex_coord_buffers[index]);
        gl.enableVertexAttribArray(@intCast(c.GLuint, as.texture_attrib_tex_coord));
        gl.vertexAttribPointer(@intCast(c.GLuint, as.texture_attrib_tex_coord), 2, gl.FLOAT, gl.FALSE, 0, null);

        gl.activeTexture(gl.TEXTURE0);
        gl.bindTexture(gl.TEXTURE_2D, s.texture_id);

        gl.drawArrays(gl.TRIANGLE_STRIP, 0, 4);
    }

    pub fn init(s: *Spritesheet, compressed_bytes: []const u8, w: usize, h: usize) !void {
        s.img = try PngImage.create(compressed_bytes);
        const col_count = s.img.width / w;
        const row_count = s.img.height / h;
        s.count = col_count * row_count;

        gl.genTextures(1, &s.texture_id);
        errdefer gl.deleteTextures(1, &s.texture_id);

        gl.bindTexture(gl.TEXTURE_2D, s.texture_id);
        gl.texParameteri(gl.TEXTURE_2D, gl.TEXTURE_MAG_FILTER, gl.NEAREST);
        gl.texParameteri(gl.TEXTURE_2D, gl.TEXTURE_MIN_FILTER, gl.NEAREST);
        gl.texParameteri(gl.TEXTURE_2D, gl.TEXTURE_WRAP_S, gl.CLAMP_TO_EDGE);
        gl.texParameteri(gl.TEXTURE_2D, gl.TEXTURE_WRAP_T, gl.CLAMP_TO_EDGE);
        gl.pixelStorei(gl.PACK_ALIGNMENT, 4);
        gl.texImage2D(
            gl.TEXTURE_2D,
            0,
            gl.RGBA,
            @intCast(c_int, s.img.width),
            @intCast(c_int, s.img.height),
            0,
            gl.RGBA,
            gl.UNSIGNED_BYTE,
            @ptrCast(*anyopaque, &s.img.raw[0]),
        );

        gl.genBuffers(1, &s.vertex_buffer);
        errdefer gl.deleteBuffers(1, &s.vertex_buffer);

        const vertexes = [_][3]c.GLfloat{
            [_]c.GLfloat{ 0.0, 0.0, 0.0 },
            [_]c.GLfloat{ 0.0, @intToFloat(c.GLfloat, h), 0.0 },
            [_]c.GLfloat{ @intToFloat(c.GLfloat, w), 0.0, 0.0 },
            [_]c.GLfloat{ @intToFloat(c.GLfloat, w), @intToFloat(c.GLfloat, h), 0.0 },
        };

        gl.bindBuffer(gl.ARRAY_BUFFER, s.vertex_buffer);
        gl.bufferData(gl.ARRAY_BUFFER, 4 * 3 * @sizeOf(c.GLfloat), @ptrCast(*const anyopaque, &vertexes[0][0]), gl.STATIC_DRAW);

        s.tex_coord_buffers = try alloc(c.GLuint, s.count);
        //s.tex_coord_buffers = try c_allocator.alloc(c.GLuint, s.count);
        //errdefer c_allocator.free(s.tex_coord_buffers);

        gl.genBuffers(@intCast(c.GLint, s.tex_coord_buffers.len), s.tex_coord_buffers.ptr);
        errdefer gl.deleteBuffers(@intCast(c.GLint, s.tex_coord_buffers.len), &s.tex_coord_buffers[0]);

        for (s.tex_coord_buffers, 0..) |tex_coord_buffer, i| {
            const upside_down_row = i / col_count;
            const col = i % col_count;
            const row = row_count - upside_down_row - 1;

            const x = @intToFloat(f32, col * w);
            const y = @intToFloat(f32, row * h);

            const img_w = @intToFloat(f32, s.img.width);
            const img_h = @intToFloat(f32, s.img.height);
            const tex_coords = [_][2]c.GLfloat{
                [_]c.GLfloat{
                    x / img_w,
                    (y + @intToFloat(f32, h)) / img_h,
                },
                [_]c.GLfloat{
                    x / img_w,
                    y / img_h,
                },
                [_]c.GLfloat{
                    (x + @intToFloat(f32, w)) / img_w,
                    (y + @intToFloat(f32, h)) / img_h,
                },
                [_]c.GLfloat{
                    (x + @intToFloat(f32, w)) / img_w,
                    y / img_h,
                },
            };

            gl.bindBuffer(gl.ARRAY_BUFFER, tex_coord_buffer);
            gl.bufferData(gl.ARRAY_BUFFER, 4 * 2 * @sizeOf(c.GLfloat), @ptrCast(*const anyopaque, &tex_coords[0][0]), gl.STATIC_DRAW);
        }
    }

    pub fn deinit(s: *Spritesheet) void {
        gl.deleteBuffers(@intCast(c.GLint, s.tex_coord_buffers.len), s.tex_coord_buffers.ptr);
        //c_allocator.free(s.tex_coord_buffers);
        gl.deleteBuffers(1, &s.vertex_buffer);
        gl.deleteTextures(1, &s.texture_id);

        s.img.destroy();
    }
};

fn alloc(comptime T: type, n: usize) ![]T {
    const ptr = c.malloc(@sizeOf(T) * n) orelse return error.OutOfMemory;
    return @ptrCast([*]T, @alignCast(@alignOf(T), ptr))[0..n];
}
