const std = @import("std");
const options = @import("options");
const lua = @import("lua");
const WindowManager = @import("WindowManager.zig");
const zany_lua = @import("./lua.zig");
const zany_lib = @import("./lua/lib.zig");
const globals = @import("globals.zig");
const util = @import("./util.zig");
const screen = @import("screen.zig");
const button = @import("button.zig");
const tag = @import("tag.zig");
const window = @import("window.zig");
const client = @import("client.zig");
const Object = @import("lua/Object.zig");
const base = @import("lua/base.zig");

const log = std.log.scoped(.zany);

const Lua = lua.Lua;

const Zany = @This();
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

vm: *Lua,
wm: WindowManager,
state: enum { running, stopping, stopped } = .stopped,
error_code: u8 = 0,

pub fn init(self: *Zany, gpa: std.mem.Allocator, config: Config) !void {
    globals.gpa = gpa;
    try self.wm.init(gpa);
    errdefer self.wm.deinit();
    const vm = try lua.Lua.init(gpa);
    errdefer vm.deinit();
    _ = vm.atPanic(lua.wrap(onPanic));
    vm.openLibs();
    try zany_lua.fixup(vm);

    try addPaths(vm, config);

    const awesome_lib: []const lua.FnReg = &.{
        .{ .name = "quit", .func = lua.wrap(quit) },
        .{ .name = "exec", .func = lua.wrap(exec) },
        .{ .name = "spawn", .func = lua.wrap(spawn) },
        .{ .name = "restart", .func = lua.wrap(restart) },
        .{ .name = "connect_signal", .func = lua.wrap(connect_signal) },
        .{ .name = "disconnect_signal", .func = lua.wrap(disconnect_signal) },
        .{ .name = "emit_signal", .func = lua.wrap(emit_signal) },
        .{ .name = "systray", .func = lua.wrap(systray) },
        .{ .name = "load_image", .func = lua.wrap(load_image) },
        .{ .name = "pixbuf_to_surface", .func = lua.wrap(pixbuf_to_surface) },
        .{ .name = "set_preferred_icon_size", .func = lua.wrap(set_preferred_icon_size) },
        .{ .name = "register_xproperty", .func = lua.wrap(register_xproperty) },
        .{ .name = "set_xproperty", .func = lua.wrap(set_xproperty) },
        .{ .name = "get_xproperty", .func = lua.wrap(get_xproperty) },
        .{ .name = "__index", .func = lua.wrap(index) },
        .{ .name = "__newindex", .func = lua.wrap(default_newindex) },
        .{ .name = "xkb_set_layout_group", .func = lua.wrap(xkb_set_layout_group) },
        .{ .name = "xkb_get_layout_group", .func = lua.wrap(xkb_get_layout_group) },
        .{ .name = "xkb_get_group_names", .func = lua.wrap(xkb_get_group_names) },
        .{ .name = "xrdb_get_value", .func = lua.wrap(xrdb_get_value) },
        .{ .name = "kill", .func = lua.wrap(kill) },
        .{ .name = "sync", .func = lua.wrap(sync) },
    };
    vm.pushLightUserdata(self);
    vm.setGlobal("__zany");
    try zany_lua.openLib(vm, "awesome", awesome_lib, awesome_lib);
    try zany_lua.openLib(vm, "root", &base.methods, &base.meta);
    Object.setup(vm);

    try screen.setup(vm);
    try button.setup(vm);
    try tag.setup(vm);
    try window.setup(vm);
    // try drawable.setup(vm);
    // try drawin.setup(vm);
    try client.setup(vm);
    // /* Export selection getter */
    // selection_getter_class_setup(L);
    //
    // /* Export keys */
    // key_class_setup(L);
    //
    // /* Export selection acquire */
    // selection_acquire_class_setup(L);
    //
    // /* Export selection transfer */
    // selection_transfer_class_setup(L);
    //
    // /* Export selection watcher */
    // selection_watcher_class_setup(L);
    //
    // /* Setup the selection interface */
    // selection_setup(L);

    try zany_lua.initRng(vm);

    screen.screen_class.emitSignal(vm, "scanning", 0);
    // for (wm.outputs.items, 0..) |output, id| {
    //     const s = try gpa.create(screen);
    //     s.* = .{
    //         .valid = true,
    //         .output_id = id,
    //     };
    //     globals.screens.append(gpa, s);
    //     screen.screen_class.emitSignal(vm, "")
    // }
    screen.screen_class.emitSignal(vm, "scanned", 0);

    try zany_lua.loadRc(vm, config.config);

    self.vm = vm;
}

pub fn onPanic(L: *Lua) i32 {
    log.warn("Lua panicked!!!!!", .{});
    _ = L;
    return 0;
}

pub fn deinit(zany: *Zany) void {
    zany.wm.deinit();
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
    std.debug.panic("awesome.exec not implemented", .{});
    return 0;
}
fn spawn(state: *Lua) i32 {
    _ = state;
    std.debug.panic("awesome.spawn not implemented", .{});
    return 0;
}
fn kill(state: *Lua) i32 {
    _ = state;
    std.debug.panic("awesome.kill not implemented", .{});
    return 0;
}
fn sync(state: *Lua) i32 {
    _ = state;
    std.debug.panic("awesome.sync not implemented", .{});
    return 0;
}
fn restart(state: *Lua) i32 {
    _ = state;
    std.debug.panic("awesome.restart not implemented", .{});
    return 0;
}
// Add a global signal.
//
// @tparam string name A string with the event name.
// @tparam function func The function to call.
// @staticfct connect_signal
// @noreturn
fn connect_signal(state: *Lua) i32 {
    const name = state.checkString(1);
    zany_lib.checkFunction(state, 2);

    const func = Object.ref(state, 2) orelse return 0;

    const id = util.strhash(name);
    for (globals.signals.items) |*signal| {
        if (signal.id == id) {
            signal.funcs.append(std.heap.c_allocator, func) catch {};
        }
    }
    return 0;
}
fn disconnect_signal(state: *Lua) i32 {
    _ = state;
    std.debug.panic("awesome.disconnect_signal not implemented", .{});
    return 0;
}
fn emit_signal(state: *Lua) i32 {
    _ = state;
    std.debug.panic("awesome.emit_signal not implemented", .{});
    return 0;
}
fn systray(state: *Lua) i32 {
    _ = state;
    std.debug.panic("awesome.systray not implemented", .{});
    return 0;
}
fn load_image(state: *Lua) i32 {
    _ = state;
    std.debug.panic("awesome.load_image not implemented", .{});
    return 0;
}
fn pixbuf_to_surface(state: *Lua) i32 {
    _ = state;
    std.debug.panic("awesome.pixbuf_to_surface not implemented", .{});
    return 0;
}
fn set_preferred_icon_size(state: *Lua) i32 {
    _ = state;
    std.debug.panic("awesome.set_preferred_icon_size not implemented", .{});
    return 0;
}

// Register a new xproperty.
// \param L The Lua VM state.
// \return The number of elements pushed on stack.
// \luastack
// \lparam The name of the X11 property
// \lparam One of "string", "number" or "boolean"
fn register_xproperty(state: *Lua) i32 {
    // const char *name;
    // struct xproperty property;
    // struct xproperty *found;
    // const char *const args[] = { "string", "number", "boolean" };
    const args = enum {
        string,
        number,
        boolean,
    };
    const name = state.checkString(1);
    const kind = state.checkOption(args, 2, null);
    log.info("Registering property {s} of kind {t}", .{ name, kind });
    // xcb_intern_atom_reply_t *atom_r;
    // int type;
    //
    // name = luaL_checkstring(L, 1);
    // type = luaL_checkoption(L, 2, NULL, args);
    // if (type == 0)
    //     property.type = PROP_STRING;
    // else if (type == 1)
    //     property.type = PROP_NUMBER;
    // else
    //     property.type = PROP_BOOLEAN;
    //
    // atom_r = xcb_intern_atom_reply(globalconf.connection,
    //                                xcb_intern_atom_unchecked(globalconf.connection, false,
    //                                                          a_strlen(name), name),
    //                                NULL);
    // if(!atom_r)
    //     return 0;
    //
    // property.atom = atom_r->atom;
    // p_delete(&atom_r);
    //
    // found = xproperty_array_lookup(&globalconf.xproperties, &property);
    // if(found)
    // {
    //     /* Property already registered */
    //     if(found->type != property.type)
    //         return luaL_error(L, "xproperty '%s' already registered with different type", name);
    // }
    // else
    // {
    //     property.name = a_strdup(name);
    //     xproperty_array_insert(&globalconf.xproperties, property);
    // }
    //
    return 0;
}

fn set_xproperty(state: *Lua) i32 {
    _ = state;
    std.debug.panic("awesome.set_xproperty not implemented", .{});
    return 0;
}
fn get_xproperty(state: *Lua) i32 {
    _ = state;
    std.debug.panic("awesome.get_xproperty not implemented", .{});
    return 0;
}
fn index(state: *Lua) i32 {
    _ = state;
    std.debug.panic("awesome.index not implemented", .{});
    return 0;
}
fn default_newindex(state: *Lua) i32 {
    _ = state;
    std.debug.panic("awesome.default_newindex not implemented", .{});
    return 0;
}
fn xkb_set_layout_group(state: *Lua) i32 {
    _ = state;
    std.debug.panic("awesome.default_newindex not implemented", .{});
    return 0;
}
fn xkb_get_layout_group(state: *Lua) i32 {
    _ = state;
    std.debug.panic("awesome.default_newindex not implemented", .{});
    return 0;
}
fn xkb_get_group_names(state: *Lua) i32 {
    _ = state;
    std.debug.panic("awesome.default_newindex not implemented", .{});
    return 0;
}
fn xrdb_get_value(state: *Lua) i32 {
    _ = state;
    std.debug.panic("awesome.default_newindex not implemented", .{});
    return 0;
}
