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
state: enum { running, stopped } = .stopped,

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

pub fn init(gpa: std.mem.Allocator, config: Config) !Zany {
    _ = config;
    const wm = try gpa.create(WindowManager);
    errdefer gpa.destroy(wm);
    try wm.init(gpa);
    const vm = try lua.Lua.init(gpa);
    _ = vm.atPanic(lua.wrap(onPanic));
    vm.openLibs();
    try zanyLua.fixup(vm);

    return .{
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
    gpa.destroy(zany.wm);
    zany.vm.deinit();
}

pub fn run(zany: *Zany) !void {
    zany.state = .running;
    log.info("Starting run loop", .{});
    while (zany.state == .running) {
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
    state.getGlobal("package");
    if (state.typeOf(1) != .table) {
        log.warn("`package` is not a table", .{});
        return;
    }
    state.getField(1, "path");
    addSearchPaths(state, config.search.items, .lua);
    state.setField(1, "path"); // update package.path to updated string

    state.getField(1, "cpath");
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
            state.pushString(";" ++ options.awesome_lua_lib ++ "/?.lua");
            state.pushString(";" ++ options.awesome_lua_lib ++ "/?/init.lua");
            state.pushString(";" ++ options.zany_lua_lib ++ "/?.lua");
            state.pushString(";" ++ options.zany_lua_lib ++ "/?/init.lua");
            state.concat(5); // Concat onto the path string
        },
        .so => {
            state.pushString(";" ++ options.awesome_lua_lib ++ "/?.so");
            state.pushString(";" ++ options.zany_lua_lib ++ "/?.so");
            state.concat(3); //concat onto the cpath string
        },
    }
}
