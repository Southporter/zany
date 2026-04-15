const std = @import("std");
const Scanner = @import("wayland").Scanner;

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const awesome_lua_lib_path = b.option([]const u8, "awesome_lib", "Path to awesome lua lib (i.e. /usr/share/awesome/lib)") orelse "/usr/share/awesome/lib";
    const zany_lua_lib_path = b.option([]const u8, "lib", "Path to zany lua lib (i.e. /usr/share/zany/lib)") orelse "/usr/share/zany/lib";
    const theme_path = b.option([]const u8, "themes", "Path to themes (i.e. /usr/share/zany/themes)") orelse "../awesome/themes";
    const icon_path = b.option([]const u8, "icon_path", "Path to themes (i.e. /usr/share/zany/icons)") orelse "../awesome/icons";

    const options = b.addOptions();
    options.addOption([]const u8, "awesome_lua_lib", awesome_lua_lib_path);
    options.addOption([]const u8, "zany_lua_lib", zany_lua_lib_path);
    options.addOption([]const u8, "themes_path", theme_path);
    options.addOption([]const u8, "icon_path", icon_path);

    const river = b.dependency("river", .{});

    const scanner = Scanner.create(b, .{});
    scanner.addSystemProtocol("stable/tablet/tablet-v2.xml");
    scanner.addSystemProtocol("staging/cursor-shape/cursor-shape-v1.xml");
    scanner.addCustomProtocol(river.path(
        "protocol/river-window-management-v1.xml",
    ));
    scanner.addCustomProtocol(river.path(
        "protocol/river-layer-shell-v1.xml",
    ));
    scanner.addCustomProtocol(river.path(
        "protocol/river-xkb-bindings-v1.xml",
    ));
    scanner.addCustomProtocol(river.path(
        "protocol/river-xkb-config-v1.xml",
    ));
    scanner.addCustomProtocol(river.path(
        "protocol/river-input-management-v1.xml",
    ));

    scanner.generate("wl_compositor", 6);
    scanner.generate("wl_seat", 9);
    scanner.generate("wl_shm", 2);
    scanner.generate("wl_output", 4);
    scanner.generate("wp_cursor_shape_manager_v1", 2);
    scanner.generate("river_window_manager_v1", 3);
    scanner.generate("river_layer_shell_v1", 1);
    scanner.generate("river_input_manager_v1", 1);
    scanner.generate("river_xkb_bindings_v1", 2);
    scanner.generate("river_xkb_config_v1", 1);

    const wayland = b.createModule(.{
        .root_source_file = scanner.result,
    });

    const awesome = b.dependency("awesome", .{});
    const awesome_lua = awesome.path("lib");

    const ziglua = b.dependency("zlua", .{
        .lang = .lua51,
        .shared = true,
    });

    const pixbuf = b.addTranslateC(.{
        .root_source_file = b.path("pkg/pixbuf.h"),
        .target = target,
        .optimize = optimize,
    });
    pixbuf.addSystemIncludePath(.{ .cwd_relative = "/usr/include/gdk-pixbuf-2.0/" });
    pixbuf.addSystemIncludePath(.{ .cwd_relative = "/usr/include/glib-2.0/" });
    pixbuf.addSystemIncludePath(.{ .cwd_relative = "/usr/lib64/glib-2.0/include/" });
    const cairo = b.addTranslateC(.{
        .root_source_file = b.path("pkg/cairo-zany.h"),
        .target = target,
        .optimize = optimize,
    });
    cairo.addSystemIncludePath(.{ .cwd_relative = "/usr/include/cairo/" });
    const mod = b.addModule("zanywm", .{
        .root_source_file = b.path("src/root.zig"),
        .target = target,
        .imports = &.{
            .{ .name = "lua", .module = ziglua.module("zlua") },
            .{ .name = "wayland", .module = wayland },
            .{ .name = "pixbuf", .module = pixbuf.createModule() },
            .{ .name = "cairo", .module = cairo.createModule() },
            .{ .name = "xkb", .module = b.dependency("xkbcommon", .{}).module("xkbcommon") },
        },
        .link_libc = true,
    });
    mod.addOptions("options", options);
    mod.linkSystemLibrary("wayland-client", .{});
    mod.linkSystemLibrary("cairo", .{});
    mod.linkSystemLibrary("gdk-pixbuf-2.0", .{});
    mod.linkSystemLibrary("xkbcommon", .{});

    const exe = b.addExecutable(.{
        .name = "zany",
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
    b.installDirectory(.{
        .install_dir = .lib,
        .source_dir = awesome_lua,
        .install_subdir = "awesome",
    });
    const rc = b.addInstallFile(awesome.path("awesomerc.lua"), "rc.lua");
    b.getInstallStep().dependOn(&rc.step);

    const run_step = b.step("run", "Run the app");

    const run_cmd = b.addRunArtifact(exe);
    run_step.dependOn(&run_cmd.step);

    run_cmd.step.dependOn(b.getInstallStep());

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
