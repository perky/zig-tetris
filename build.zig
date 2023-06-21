const std = @import("std");
const build_glfw = @import("lib/build_glfw.zig");
const zopengl = @import("lib/zopengl/build.zig");
const Build = std.build;

pub fn build(b: *Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const exe = b.addExecutable(.{
        .name = "tetris",
        .root_source_file = .{ .path = "src/main.zig" },
        .optimize = optimize,
        .target = target,
    });
    

    const host = (std.zig.system.NativeTargetInfo.detect(target) catch unreachable).target;
    switch (host.os.tag) {
        .windows => {
            exe.addIncludePath("lib/epoxy/windows/include");
        },
        else => {},
    }

    // Lib: stb image.
    exe.addCSourceFile("lib/stb_image-2.22/stb_image_impl.c", &[_][]const u8{"-std=c99"});
    exe.addIncludePath("lib/stb_image-2.22");

    // Lib: GLFW.
    const glfw_lib = build_glfw.buildLib(b, target, optimize);
    exe.linkLibrary(glfw_lib);
    build_glfw.addCSource(exe);
    exe.linkLibC();

    // Lib: zOpenGL.
    const zopengl_pkg = zopengl.package(b, target, optimize, .{});
    zopengl_pkg.link(exe);

    // Lib: c.
    exe.linkLibC();

    b.installArtifact(exe);

    const play = b.step("run", "Play the game");
    const run = b.addRunArtifact(exe);
    run.step.dependOn(b.getInstallStep());
    play.dependOn(&run.step);
}
