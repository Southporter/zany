const std = @import("std");
const Scanner = @import("wayland").Scanner;

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const river = b.dependency("river", .{});

    const scanner = Scanner.create(b, .{});
    scanner.addCustomProtocol(river.path(
        "protocol/river-window-management-v1.xml",
    ));
    scanner.addCustomProtocol(river.path(
        "protocol/river-layer-shell-v1.xml",
    ));
    scanner.addCustomProtocol(river.path(
        "protocol/river-xkb-bindings-v1.xml",
    ));

    scanner.generate("wl_compositor", 6);
    scanner.generate("wl_shm", 2);
    scanner.generate("wl_output", 4);
    scanner.generate("river_window_manager_v1", 3);
    scanner.generate("river_layer_shell_v1", 1);
    scanner.generate("river_xkb_bindings_v1", 2);

    const wayland = b.createModule(.{
        .root_source_file = scanner.result,
    });

    const awesome = b.dependency("awesome", .{});
    const awesome_lua = awesome.path("lib");

    const ziglua = b.dependency("zlua", .{});

    const mod = b.addModule("zanywm", .{ .root_source_file = b.path("src/root.zig"), .target = target, .imports = &.{
        .{ .name = "lua", .module = ziglua.module("zlua") },
        .{ .name = "wayland", .module = wayland },
    } });

    const exe = b.addExecutable(.{
        .name = "zanywm",
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/main.zig"),
            .target = target,
            .optimize = optimize,
            .imports = &.{
                .{ .name = "zanywm", .module = mod },
            },
        }),
    });

    b.installArtifact(exe);

    const run_step = b.step("run", "Run the app");

    const run_cmd = b.addRunArtifact(exe);
    run_step.dependOn(&run_cmd.step);

    run_cmd.step.dependOn(b.getInstallStep());
    run_cmd.addDirectoryArg(awesome_lua);

    if (b.args) |args| {
        run_cmd.addArgs(args);
    }

    const mod_tests = b.addTest(.{
        .root_module = mod,
    });

    const run_mod_tests = b.addRunArtifact(mod_tests);

    const exe_tests = b.addTest(.{
        .root_module = exe.root_module,
    });

    const run_exe_tests = b.addRunArtifact(exe_tests);

    const test_step = b.step("test", "Run tests");
    test_step.dependOn(&run_mod_tests.step);
    test_step.dependOn(&run_exe_tests.step);
}
