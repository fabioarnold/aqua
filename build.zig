const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const zig_objc = b.dependency("zig_objc", .{
        .target = target,
        .optimize = optimize,
    });

    const exe = b.addExecutable(.{
        .name = "aqua",
        .root_source_file = .{ .path = "src/main.zig" },
        .target = target,
        .optimize = optimize,
    });

    exe.root_module.addImport("zig-objc", zig_objc.module("objc"));
    exe.linkFramework("Cocoa");
    exe.linkFramework("Metal");
    exe.linkFramework("MetalKit");

    const install_exe = b.addInstallArtifact(exe, .{.dest_dir = .{.override = .{.custom = "Aqua.app/Contents/MacOS"}}});
    const install_plist = b.addInstallFile(.{ .path = "res/Info.plist" }, "Aqua.app/Contents/Info.plist");
    const install_step = b.getInstallStep();
    install_exe.step.dependOn(&install_plist.step);
    install_step.dependOn(&install_exe.step);
}
