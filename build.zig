const std = @import("std");
const build_glfw = @import("lib/build_glfw.zig");
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
    exe.addCSourceFile("stb_image-2.22/stb_image_impl.c", &[_][]const u8{"-std=c99"});
    exe.addIncludePath("stb_image-2.22");
    //exe.use_llvm = false;
    //exe.use_lld = false;

    const glfw_lib = build_glfw.buildLib(b, target, optimize);
    exe.linkLibrary(glfw_lib);
    build_glfw.addCSource(exe);
    exe.linkLibC();

    exe.linkSystemLibrary("c");
    exe.linkSystemLibrary("epoxy");
    b.installArtifact(exe);

    const play = b.step("play", "Play the game");
    const run = b.addRunArtifact(exe);
    run.step.dependOn(b.getInstallStep());
    play.dependOn(&run.step);
}
