const std = @import("std");
const options = @import("options");
const lua = @import("lua");
const WindowManager = @import("WindowManager.zig");
const zanyLua = @import("./lua.zig");

const log = std.log.scoped(.zany);

const Lua = lua.Lua;

const Zany = @This();

vm: *Lua,
wm: *WindowManager,
state: enum { running, stopping, stopped } = .stopped,
error_code: u8 = 0,

pub const Config = struct {
    version: bool = false,
    config: ?[:0]const u8 = null,
    force: bool = false,
    search: std.ArrayList([:0]const u8) = .empty,
    check: bool = false,
    no_argb: bool = false,
    api_level: std.SemanticVersion = .{ .major = 4, .minor = 3, .patch = 0 },
    screen: ScreenCreation = .on,
    replace: bool = false,
    pub const ScreenCreation = enum { on, off };
};

pub fn init(self: *Zany, gpa: std.mem.Allocator, config: Config) !void {
    const wm = try gpa.create(WindowManager);
    errdefer gpa.destroy(wm);
    try wm.init(gpa);
    const vm = try lua.Lua.init(gpa);
    errdefer vm.deinit();
    _ = vm.atPanic(lua.wrap(onPanic));
    vm.openLibs();
    try zanyLua.fixup(vm);

    try addPaths(vm, config);

    const awesome_lib: []const lua.FnReg = &.{
        .{ .name = "quit", .func = lua.wrap(quit) },
        .{ .name = "exec", .func = lua.wrap(exec) },
        .{ .name = "spawn", .func = lua.wrap(spawn) },
        // { "spawn", luaA_spawn },
        // { "restart", luaA_restart },
        // { "connect_signal", luaA_awesome_connect_signal },
        // { "disconnect_signal", luaA_awesome_disconnect_signal },
        // { "emit_signal", luaA_awesome_emit_signal },
        // { "systray", luaA_systray },
        // { "load_image", luaA_load_image },
        // { "pixbuf_to_surface", luaA_pixbuf_to_surface },
        // { "set_preferred_icon_size", luaA_set_preferred_icon_size },
        // { "register_xproperty", luaA_register_xproperty },
        // { "set_xproperty", luaA_set_xproperty },
        // { "get_xproperty", luaA_get_xproperty },
        // { "__index", luaA_awesome_index },
        // { "__newindex", luaA_default_newindex },
        // { "xkb_set_layout_group", luaA_xkb_set_layout_group},
        // { "xkb_get_layout_group", luaA_xkb_get_layout_group},
        // { "xkb_get_group_names", luaA_xkb_get_group_names},
        // { "xrdb_get_value", luaA_xrdb_get_value},
        // { "kill", luaA_kill},
        // { "sync", luaA_sync},
    };
    vm.pushLightUserdata(self);
    vm.setGlobal("__zany");
    try zanyLua.openLib(vm, "awesome", awesome_lib, awesome_lib);

    try zanyLua.initRng(vm);

    try zanyLua.loadRc(vm, config.config);

    self.* = .{
        .vm = vm,
        .wm = wm,
    };
}

pub fn onPanic(L: *Lua) i32 {
    log.warn("Lua panicked!!!!!", .{});
    _ = L;
    return 0;
}

pub fn deinit(zany: *Zany, gpa: std.mem.Allocator) void {
    zany.wm.deinit();
    gpa.destroy(zany.wm);
    zany.vm.deinit();
}

pub fn run(zany: *Zany) !void {
    zany.state = .running;
    log.info("Starting run loop", .{});
    while (zany.state != .running) {
        zany.wm.poll() catch |err| {
            log.err("Window Manager encountered an error: {t}", .{err});
            zany.state = .stopped;
        };
    }
}
pub fn check(gpa: std.mem.Allocator, file: []const u8) !void {
    _ = file;
    const vm = try lua.Lua.init(gpa);
    defer vm.deinit();
}

fn addPaths(state: *Lua, config: Config) !void {
    const pkg_type = try state.getGlobal("package");
    if (pkg_type != .table) {
        log.warn("`package` is not a table", .{});
        return;
    }
    const path_type = state.getField(1, "path");
    std.debug.assert(path_type == .string);
    addSearchPaths(state, config.search.items, .lua);
    state.setField(1, "path"); // update package.path to updated string

    const cpath_type = state.getField(1, "cpath");
    std.debug.assert(cpath_type == .string);
    addSearchPaths(state, config.search.items, .so);
    state.setField(1, "cpath"); // update package.cpath to updated string

    state.pop(1); // Remove `package` from stack
}

fn addSearchPaths(state: *Lua, paths: [][:0]const u8, kind: enum { lua, so }) void {
    if (state.typeOf(-1) != .string) {
        log.warn("`package.[c]path` is not a string", .{});
        return;
    }

    for (paths) |path| {
        _ = state.pushString(";");
        _ = state.pushStringZ(path);
        switch (kind) {
            .lua => _ = state.pushString("/?.lua"),
            .so => _ = state.pushString("/?.so"),
        }
        state.concat(3);

        switch (kind) {
            .lua => {
                _ = state.pushString(";");
                _ = state.pushStringZ(path);
                _ = state.pushString("/?/init.lua");
                state.concat(3);
            },
            .so => {},
        }
        state.concat(if (kind == .lua) 3 else 2);
    }

    // add Lua lib path (/usr/share/awesome/lib and /usr/share/zany/lib by default)
    switch (kind) {
        .lua => {
            _ = state.pushString(";" ++ options.awesome_lua_lib ++ "/?.lua");
            _ = state.pushString(";" ++ options.awesome_lua_lib ++ "/?/init.lua");
            _ = state.pushString(";" ++ options.zany_lua_lib ++ "/?.lua");
            _ = state.pushString(";" ++ options.zany_lua_lib ++ "/?/init.lua");
            _ = state.concat(5); // Concat onto the path string
        },
        .so => {
            _ = state.pushString(";" ++ options.awesome_lua_lib ++ "/?.so");
            _ = state.pushString(";" ++ options.zany_lua_lib ++ "/?.so");
            _ = state.concat(3); //concat onto the cpath string
        },
    }
}

fn quit(state: *Lua) i32 {
    const error_code = if (state.isNoneOrNil(1)) 0 else state.checkInteger(1);
    const global_type = state.getGlobal("__zany") catch |err| {
        std.process.fatal("Unable to get zany global. Something has gone terribly wrong. {t}", .{err});
    };
    std.debug.assert(global_type == .userdata);
    const zany: *Zany = state.toUserdata(Zany, -1) catch |err| {
        std.process.fatal("Zany global userdata error: {t}", .{err});
    };
    zany.state = .stopping;
    zany.error_code = @intCast(error_code);
    return 0;
}
fn exec(state: *Lua) i32 {
    _ = state;
    return 0;
}
fn spawn(state: *Lua) i32 {
    _ = state;
    return 0;
}
