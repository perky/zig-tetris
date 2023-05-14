const math3d = @import("math3d.zig");
const Mat4x4 = math3d.Mat4x4;
const Vec3 = math3d.Vec3;
const Vec4 = math3d.Vec4;

const Tetris = @import("tetris.zig").Tetris;
const InputState = @import("tetris.zig").InputState;
const InputRecordMode = @import("tetris.zig").InputRecordMode;
const tetris_render = @import("tetris_render.zig");

const std = @import("std");
const assert = std.debug.assert;
const bufPrint = std.fmt.bufPrint;
const c = @import("c.zig");
const debug_gl = @import("debug_gl.zig");
const ArrayList = std.ArrayList;

var g_input_state = InputState{};
var g_input_mutex = std.Thread.Mutex{};
var g_sim_run: bool = true;
var g_sim_desired_mode: InputRecordMode = .record;

fn errorCallback(err: c_int, description: [*c]const u8) callconv(.C) void {
    _ = err;
    _ = c.printf("Error: %s\n", description);
    c.abort();
}

fn keyCallback(
    window: ?*c.GLFWwindow,
    key: c_int,
    scancode: c_int,
    action: c_int,
    mods: c_int,
) callconv(.C) void {
    _ = mods;
    _ = scancode;
    g_input_mutex.lock();
    defer g_input_mutex.unlock();
    if (action == c.GLFW_PRESS or action == c.GLFW_RELEASE) {
        const is_down: bool = (action == c.GLFW_PRESS);
        switch (key) {
            c.GLFW_KEY_ESCAPE => {
                c.glfwSetWindowShouldClose(window, c.GL_TRUE);
                @atomicStore(bool, &g_sim_run, false, .Release);
            },
            c.GLFW_KEY_L => @atomicStore(InputRecordMode, &g_sim_desired_mode, .playback, .Release),
            c.GLFW_KEY_K => @atomicStore(InputRecordMode, &g_sim_desired_mode, .no_record, .Release),
            c.GLFW_KEY_J => @atomicStore(InputRecordMode, &g_sim_desired_mode, .record, .Release),
            c.GLFW_KEY_SPACE => g_input_state.piece_drop = is_down,
            c.GLFW_KEY_DOWN => g_input_state.piece_down = is_down,
            c.GLFW_KEY_LEFT => g_input_state.piece_left = is_down,
            c.GLFW_KEY_RIGHT => g_input_state.piece_right = is_down,
            c.GLFW_KEY_UP => g_input_state.piece_rotate_pos = is_down,
            c.GLFW_KEY_LEFT_SHIFT, c.GLFW_KEY_RIGHT_SHIFT => g_input_state.piece_rotate_neg = is_down,
            c.GLFW_KEY_R => g_input_state.restart = is_down,
            c.GLFW_KEY_P => g_input_state.pause = is_down,
            c.GLFW_KEY_LEFT_CONTROL, c.GLFW_KEY_RIGHT_CONTROL => g_input_state.piece_hold = is_down,
            else => {}
        }
    }
}

fn makeRandSeed() u64 {
    var seed: u64 = undefined;
    std.os.getrandom(std.mem.asBytes(&seed)) catch {
        return @intCast(u64, c.time(null));
    };
    return seed;
}

pub fn main() !void {
    var rand_seed: u64 = makeRandSeed();

    var tetris_state: Tetris = undefined;
    tetris_state.mutex = std.Thread.Mutex{};
    tetris_state.restartGame(rand_seed);

    try eventAndRenderMain(&tetris_state);
}

fn eventAndRenderMain(tetris: *Tetris) !void {
    _ = c.glfwSetErrorCallback(errorCallback);

    if (c.glfwInit() == c.GL_FALSE) @panic("GLFW init failure");
    defer c.glfwTerminate();

    c.glfwWindowHint(c.GLFW_CONTEXT_VERSION_MAJOR, 3);
    c.glfwWindowHint(c.GLFW_CONTEXT_VERSION_MINOR, 2);
    c.glfwWindowHint(c.GLFW_OPENGL_FORWARD_COMPAT, c.GL_TRUE);
    c.glfwWindowHint(c.GLFW_OPENGL_DEBUG_CONTEXT, debug_gl.is_on);
    c.glfwWindowHint(c.GLFW_OPENGL_PROFILE, c.GLFW_OPENGL_CORE_PROFILE);
    c.glfwWindowHint(c.GLFW_DEPTH_BITS, 0);
    c.glfwWindowHint(c.GLFW_STENCIL_BITS, 8);
    c.glfwWindowHint(c.GLFW_RESIZABLE, c.GL_FALSE);

    var monitor: ?*c.GLFWmonitor = c.glfwGetPrimaryMonitor();
    var dpi_x: f32 = 1;
    var dpi_y: f32 = 1;
    c.glfwGetMonitorContentScale(monitor, &dpi_x, &dpi_y);
    const desired_w_w = @floatToInt(c_int, tetris_render.window_width/dpi_x);
    const desired_w_h = @floatToInt(c_int, tetris_render.window_height/dpi_y);
    var window: *c.GLFWwindow = c.glfwCreateWindow(desired_w_w, desired_w_h, "Tetris", null, null) orelse
        @panic("unable to create window");
    defer c.glfwDestroyWindow(window);
    _ = c.glfwSetKeyCallback(window, keyCallback);
    debug_gl.assertNoError();

    c.glfwMakeContextCurrent(window);
    var framebuffer_width: c_int = undefined;
    var framebuffer_height: c_int = undefined;
    c.glfwGetFramebufferSize(window, &framebuffer_width, &framebuffer_height);
    assert(framebuffer_width >= desired_w_w);
    assert(framebuffer_height >= desired_w_h);

    tetris_render.init(framebuffer_width, framebuffer_height);
    defer tetris_render.deinit();
    tetris_render.resetProjection();
    tetris.setStageSize(
        @intToFloat(f32, framebuffer_width), 
        @intToFloat(f32, framebuffer_height)
    );

    var render_thread = try std.Thread.spawn(.{}, renderLoop, .{window, tetris});
    var sim_thread = try std.Thread.spawn(.{}, simulationLoop, .{tetris});
    // Event loop.
    while (c.glfwWindowShouldClose(window) == c.GL_FALSE) {
        { // Attach a new random seed to input, so the simulation can choose to restart with a new seed.
            g_input_mutex.lock();
            defer g_input_mutex.unlock();
            g_input_state.random_seed = makeRandSeed();
        }
        c.glfwPollEvents();
    }
    _ = sim_thread;
    render_thread.join();
}

fn simulationLoop(tetris: *Tetris) !void {
    const start_time = c.glfwGetTime();
    var last_frame_time: f64 = start_time;
    var prev_time = start_time;
    var dt: f64 = 1.0 / 60.0;
    var game_time: f64 = 0.0;
    var input_recording = ArrayList(InputState).init(std.heap.c_allocator);
    defer input_recording.deinit();
    var input_record_mode = InputRecordMode.record;
    var playback_rate: u16 = 1;
    var is_recording_from_file: bool = false;

    blk: { // Attempt to load recording.
        var args = try std.process.argsAlloc(std.heap.c_allocator);
        defer std.process.argsFree(std.heap.c_allocator, args);
        if (args.len < 2) break :blk;
        const recording_file_path = args[1];

        var file = try std.fs.cwd().openFile(recording_file_path, .{ .mode = .read_only });
        defer file.close();
        var reader = file.reader();
        const rand_seed = try reader.readInt(u64, .Little);
        const num_frames = try reader.readInt(u64, .Little);
        for (0..num_frames) |_| {
            const input_frame = try reader.readStruct(InputState);
            try input_recording.append(input_frame);
        }
        is_recording_from_file = true;

        tetris.mutex.lock();
        defer tetris.mutex.unlock(); 
        g_sim_desired_mode = .playback;
        tetris.random_seed = rand_seed;
        std.log.info("loaded tetris recording: {s}", .{recording_file_path});
    }

    while(@atomicLoad(bool, &g_sim_run, .Acquire)) {
        const now_time = c.glfwGetTime();
        prev_time = now_time;

        // Change input mode via the user-controlled desired mode.
        switch (@atomicLoad(InputRecordMode, &g_sim_desired_mode, .Acquire)) {
            .playback => {
                if (input_record_mode != .playback) {
                    input_record_mode = .playback;
                    tetris.restartGame(tetris.random_seed);
                    game_time = 0;
                    playback_rate = 8;
                }
                @atomicStore(InputRecordMode, &g_sim_desired_mode, .none, .Release);
            },
            .record => {
                if (input_record_mode != .record) {
                    input_record_mode = .record;
                    input_recording.clearAndFree();
                    tetris.restartGame(tetris.random_seed);
                    game_time = 0;
                    playback_rate = 1;
                    is_recording_from_file = false;
                }
                @atomicStore(InputRecordMode, &g_sim_desired_mode, .none, .Release);
            },
            .no_record => {
                if (input_record_mode != .no_record) {
                    input_record_mode = .no_record;
                    input_recording.clearAndFree();
                    playback_rate = 1;
                }
                @atomicStore(InputRecordMode, &g_sim_desired_mode, .none, .Release);
            },
            .none, .paused => {}
        }

        if ((now_time - last_frame_time) >= dt) {   
            for (0..playback_rate) |_| {     
                g_input_mutex.lock();
                defer g_input_mutex.unlock();
                tetris.mutex.lock();
                defer tetris.mutex.unlock();  

                // Handle input recording.
                switch (input_record_mode) {
                    .none, .no_record, .paused => {},
                    .record => {
                        try input_recording.append(g_input_state);
                    },
                    .playback => {
                        if (tetris.frame < input_recording.items.len) {
                            g_input_state = input_recording.items[tetris.frame];
                        } else {
                            input_record_mode = .paused;
                        }
                    }
                }
                tetris.input_record_mode = input_record_mode;              

                // Tetris update.
                if (input_record_mode != .paused) {
                    tetris.handleInput(game_time, g_input_state);
                    tetris.nextFrame(dt);
                }

                game_time += dt;
                last_frame_time = now_time;
            }
        }
        std.time.sleep(10_000);
    }

    { // Save recording to file.
        std.log.info("sim thread stopping...", .{});
        if (input_recording.items.len > 0 and !is_recording_from_file) {
            const time = c.time(null);
            const local_time = c.localtime(&time);
            const time_fmt = "record_%Y_%m_%d_%H%M%S.tetris";
            var time_str_buf: [128]u8 = undefined;
            const time_str_len = c.strftime(&time_str_buf, time_str_buf.len, time_fmt, local_time);
            const file_path = time_str_buf[0..time_str_len];

            var file = try std.fs.cwd().createFile(file_path, std.fs.File.CreateFlags{});
            defer file.close();
            var writer = file.writer();
            try writer.writeInt(u64, tetris.random_seed, .Little);
            try writer.writeInt(u64, input_recording.items.len, .Little);
            for (input_recording.items) |input_frame| {
                try writer.writeStruct(input_frame);
            }
            std.log.info("saved tetris recording: {s}", .{file_path});
        }
    }
}

pub fn renderLoop(window: *c.GLFWwindow, tetris: *Tetris) !void {
    c.glfwMakeContextCurrent(window);

    c.glfwSwapInterval(1);
    c.glClearColor(0.0, 0.0, 0.0, 1.0);
    c.glEnable(c.GL_BLEND);
    c.glBlendFunc(c.GL_SRC_ALPHA, c.GL_ONE_MINUS_SRC_ALPHA);
    c.glPixelStorei(c.GL_UNPACK_ALIGNMENT, 1);

    c.glViewport(0, 0, tetris_render.framebuffer_width, tetris_render.framebuffer_height);
    c.glfwSetWindowUserPointer(window, @ptrCast(*anyopaque, tetris));

    var tetris_state_copy: Tetris = undefined;
    tetris_state_copy.frame = 0;

    const start_time = c.glfwGetTime();
    var prev_time = start_time;
    while (c.glfwWindowShouldClose(window) == c.GL_FALSE) {
        const now_time = c.glfwGetTime();
        prev_time = now_time;

        c.glClear(c.GL_COLOR_BUFFER_BIT | c.GL_DEPTH_BUFFER_BIT | c.GL_STENCIL_BUFFER_BIT);
        
        if (tetris.mutex.tryLock()) {
            defer tetris.mutex.unlock();
            tetris_state_copy = tetris.*;
        }

        if (tetris_state_copy.frame != 0) {
            tetris_render.drawTetris(&tetris_state_copy);
        }
        c.glfwSwapBuffers(window);
    }

    debug_gl.assertNoError();
}

