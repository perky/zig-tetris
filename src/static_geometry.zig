const c = @import("c.zig");
const gl = @import("zopengl");

pub const StaticGeometry = struct {
    rect_2d_vertex_buffer: c.GLuint,
    rect_2d_tex_coord_buffer: c.GLuint,

    triangle_2d_vertex_buffer: c.GLuint,
    triangle_2d_tex_coord_buffer: c.GLuint,

    pub fn create() StaticGeometry {
        var sg: StaticGeometry = undefined;

        const rect_2d_vertexes = [_][3]c.GLfloat{
            [_]c.GLfloat{ 0.0, 0.0, 0.0 },
            [_]c.GLfloat{ 0.0, 1.0, 0.0 },
            [_]c.GLfloat{ 1.0, 0.0, 0.0 },
            [_]c.GLfloat{ 1.0, 1.0, 0.0 },
        };
        gl.genBuffers(1, &sg.rect_2d_vertex_buffer);
        gl.bindBuffer(gl.ARRAY_BUFFER, sg.rect_2d_vertex_buffer);
        gl.bufferData(gl.ARRAY_BUFFER, 4 * 3 * @sizeOf(c.GLfloat), @ptrCast(*const anyopaque, &rect_2d_vertexes[0][0]), gl.STATIC_DRAW);

        const rect_2d_tex_coords = [_][2]c.GLfloat{
            [_]c.GLfloat{ 0, 0 },
            [_]c.GLfloat{ 0, 1 },
            [_]c.GLfloat{ 1, 0 },
            [_]c.GLfloat{ 1, 1 },
        };
        gl.genBuffers(1, &sg.rect_2d_tex_coord_buffer);
        gl.bindBuffer(gl.ARRAY_BUFFER, sg.rect_2d_tex_coord_buffer);
        gl.bufferData(gl.ARRAY_BUFFER, 4 * 2 * @sizeOf(c.GLfloat), @ptrCast(*const anyopaque, &rect_2d_tex_coords[0][0]), gl.STATIC_DRAW);

        const triangle_2d_vertexes = [_][3]c.GLfloat{
            [_]c.GLfloat{ 0.0, 0.0, 0.0 },
            [_]c.GLfloat{ 0.0, 1.0, 0.0 },
            [_]c.GLfloat{ 1.0, 0.0, 0.0 },
        };
        gl.genBuffers(1, &sg.triangle_2d_vertex_buffer);
        gl.bindBuffer(gl.ARRAY_BUFFER, sg.triangle_2d_vertex_buffer);
        gl.bufferData(gl.ARRAY_BUFFER, 3 * 3 * @sizeOf(c.GLfloat), @ptrCast(*const anyopaque, &triangle_2d_vertexes[0][0]), gl.STATIC_DRAW);

        const triangle_2d_tex_coords = [_][2]c.GLfloat{
            [_]c.GLfloat{ 0, 0 },
            [_]c.GLfloat{ 0, 1 },
            [_]c.GLfloat{ 1, 0 },
        };
        gl.genBuffers(1, &sg.triangle_2d_tex_coord_buffer);
        gl.bindBuffer(gl.ARRAY_BUFFER, sg.triangle_2d_tex_coord_buffer);
        gl.bufferData(gl.ARRAY_BUFFER, 3 * 2 * @sizeOf(c.GLfloat), @ptrCast(*const anyopaque, &triangle_2d_tex_coords[0][0]), gl.STATIC_DRAW);

        return sg;
    }

    pub fn destroy(sg: *StaticGeometry) void {
        gl.deleteBuffers(1, &sg.rect_2d_tex_coord_buffer);
        gl.deleteBuffers(1, &sg.rect_2d_vertex_buffer);

        gl.deleteBuffers(1, &sg.triangle_2d_vertex_buffer);
        gl.deleteBuffers(1, &sg.triangle_2d_tex_coord_buffer);
    }
};
