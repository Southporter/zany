const std = @import("std");
const options = @import("options");
const lua = @import("lua");
const c = @import("deps");
const xkb = @import("xkb");
const WindowManager = @import("WindowManager.zig");
const zany_lua = @import("./lua.zig");
const zany_lib = @import("./lua/lib.zig");
const globals = @import("globals.zig");
const defaults = @import("defaults.zig");
const util = @import("./util.zig");
const draw = @import("draw.zig");
const Screen = @import("object/Screen.zig");
const Button = @import("object/Button.zig");
const Tag = @import("object/Tag.zig");
const Window = @import("object/Window.zig");
const Client = @import("object/Client.zig");
const Object = @import("object/Object.zig");
const root = @import("lua/root.zig");
const mouse = @import("lua/mouse.zig");
const Drawable = @import("object/Drawable.zig");
const Drawin = @import("object/Drawin.zig");
const Key = @import("object/Key.zig");
const keygrabber = @import("lua/keygrabber.zig");
const mousegrabber = @import("lua/mousegrabber.zig");

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
    auto_screen: ScreenCreation = .on,
    replace: bool = false,
    ignore_screens: bool = false,
    startup_errors: []const u8 = "",
    pub const ScreenCreation = enum { on, off };
};
var config: Config = undefined;

vm: *Lua,
wm: WindowManager,
state: enum { starting, running, stopping, stopped } = .starting,
error_code: u8 = 0,

pub fn init(self: *Zany, gpa: std.mem.Allocator, user_config: Config) !void {
    globals.gpa = gpa;
    self.state = .starting;
    try self.wm.init(gpa);
    errdefer self.wm.deinit();
    const vm = try lua.Lua.init(gpa);
    errdefer vm.deinit();
    self.vm = vm;
    _ = vm.atPanic(lua.wrap(onPanic));
    zany_lib.dofunction_on_error = onError;
    vm.openLibs();
    try zany_lua.fixup(vm);
    config = user_config;

    try addPaths(vm);

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
        .{ .name = "__newindex", .func = lua.wrap(defaults.newindex) },
        .{ .name = "xkb_set_layout_group", .func = lua.wrap(xkb_set_layout_group) },
        .{ .name = "xkb_get_layout_group", .func = lua.wrap(xkb_get_layout_group) },
        .{ .name = "xkb_get_group_names", .func = lua.wrap(xkb_get_group_names) },
        .{ .name = "xrdb_get_value", .func = lua.wrap(xrdb_get_value) },
        .{ .name = "kill", .func = lua.wrap(kill) },
        .{ .name = "sync", .func = lua.wrap(sync) },
    };
    vm.pushLightUserdata(self);
    vm.setGlobal("__zany");
    Object.setup(vm);

    {
        vm.pushFunction(lua.wrap(print));
        vm.setGlobal("print");
    }

    try zany_lua.openLib(vm, "awesome", awesome_lib, awesome_lib);
    try zany_lua.setupSignals(vm, "awesome");
    zany_lua.registerLib(vm, "root", &root.lib);
    vm.pop(1);
    zany_lua.registerLib(vm, "keygrabber", &keygrabber.lib);
    vm.pop(1);
    zany_lua.registerLib(vm, "mousegrabber", &mousegrabber.lib);
    vm.pop(1);
    try zany_lua.openLib(vm, "mouse", &mouse.methods, &mouse.meta);

    try Screen.setup(vm);
    try Button.setup(vm);
    try Tag.setup(vm);
    try Window.setup(vm);
    try Drawable.setup(vm);
    try Drawin.setup(vm);
    try Client.setup(vm);
    // /* Export selection getter */
    // selection_getter_class_setup(L);
    //
    try Key.setup(vm);

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
    // Request initial window/output/seat messages
    try self.wm.poll();

    // Parse and run configuration file before adding the screens */
    if (config.auto_screen == .off) {
        // Disable automatic screen creation, awful.screen has a fallback */
        config.ignore_screens = true;

        zany_lua.loadRc(vm, config.config) catch |err| {
            std.process.fatal("couldn't load rc file: {t}", .{err});
        };
    }

    // init screens information */
    try self.screen_scan();

    // Parse and run configuration file after adding the screens */
    if (config.auto_screen == .on) {
        zany_lua.loadRc(vm, config.config) catch |err| {
            std.process.fatal("couldn't load any rc file: {t}", .{err});
        };
    }

    // Both screen scanning mode have this signal, it cannot be in screen_scan
    //   since the automatic screen generation don't have executed rc.lua yet.
    Screen.screen_class.signals.emit(vm, "scanned", 0);

    // Exit if the user doesn't read the instructions properly
    if (config.auto_screen == .off and globals.screens.items.len == 0)
        std.debug.panic(
            \\When -m/--screen is set to \"off\", you **must** create a \
            \\screen object before or inside the screen \"scanned\" \
            \\signal. Using AwesomeWM with no screen is **not supported**.
            \\
        , .{});

    try zany_lua.loadRc(vm, config.config);

    self.client_scan();
    self.emit_startup();

    self.state = .running;
}

pub fn onPanic(state: *Lua) i32 {
    zany_lua.warn(state, "unprotected error in call to Lua API ({s})", .{state.toString(-1) catch "unknown"});
    std.debug.dumpCurrentStackTrace(null);
    zany_lua.warn(state, "restarting awesome", .{});
    _ = restart(state);
    return 0;
}

pub fn deinit(zany: *Zany) void {
    zany.wm.deinit();
    zany.vm.deinit();
}

fn print(state: *lua.Lua) i32 {
    const print_log = std.log.scoped(.print);
    var content = std.Io.Writer.Allocating.initCapacity(globals.gpa, 256) catch |err| {
        print_log.err("Out of memory: {t}", .{err});
        return 0;
    };
    defer content.deinit();
    const top: usize = @intCast(state.getTop());
    for (0..top + 1) |i| {
        const offset: i32 = @intCast(i + 1);
        if (state.isNoneOrNil(offset)) {
            continue;
        }
        if (state.isBoolean(offset)) {
            content.writer.print("{any}", .{state.toBoolean(offset)}) catch {};
        }

        const s = state.toString(offset) catch "unknown";
        content.writer.writeAll(s) catch {};
    }
    content.writer.flush() catch {};
    print_log.info("{s}", .{content.written()});
    return 0;
}

pub fn run(zany: *Zany) !void {
    zany.state = .running;
    log.info("Starting run loop", .{});
    while (zany.state != .running) {
        log.info("Run loop", .{});
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

fn addPaths(state: *Lua) !void {
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

    globals.signals.connect(name, func);
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
    const buf = state.toUserdata(c.GdkPixbuf, 1) catch {
        log.warn("Unable to turn param into GdkPixbuf, not userdata", .{});
        state.pushNil();
        return 1;
    };
    const surface = draw.surfaceFromPixbuf(buf);
    state.pushLightUserdata(surface);
    return 1;
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
///
/// The AwesomeWM version.
//  * @tfield string version
//  */
//
// /**
//  * The AwesomeWM release name.
//  * @tfield string release
//  */
//
// /**
//  * The AwesomeWM API level.
//  *
//  * By default, this matches the major version (first component of the version).
//  *
//  * API levels are used to allow newer version of AwesomeWM to alter the behavior
//  * and subset deprecated APIs. Using an older API level than the current major
//  * version allows to use legacy `rc.lua` with little porting. However, they won't
//  * be able to use all the new features. Attempting to use a newer feature along
//  * with an older API level is not and will not be supported, even if it almost
//  * works. Keeping up to date with the newer API levels is highly recommended.
//  *
//  * Going the other direction, setting an higher API level allows to take
//  * advantage of experimental feature. It will also be much harsher when it comes
//  * to deprecation. Setting the API level value beyond `current+3` will treat
//  * using APIs currently pending deprecation as fatal errors. All new code
//  * submitted to the upstream AwesomeWM codebase is forbidden to use deprecated
//  * APIs. Testing your patches with mode and the default config is recommended
//  * before submitting a patch.
//  *
//  * You can use the `-l` command line option or `api-level` modeline key to set
//  * the API level for your `rc.lua`. This setting is global and read only,
//  * individual modules cannot set their own API level.
//  *
//  * @tfield string api_level
//  */
//
// /**
//  * The configuration file which has been loaded.
//  * @tfield string conffile
//  */
//
// /**
//  * True if we are still in startup, false otherwise.
//  * @tfield boolean startup
//  */
//
// /**
//  * Error message for errors that occurred during
//  *  startup.
//  * @tfield string startup_errors
//  */
//
// /**
//  * True if a composite manager is running.
//  * @tfield boolean composite_manager_running
//  */
//
// /**
//  * Table mapping between signal numbers and signal identifiers.
//  * @tfield table unix_signal
//  */
//
// /**
//  * The hostname of the computer on which we are running.
//  * @tfield string hostname
//  */
//
// /**
//  * The path where themes were installed to.
//  * @tfield string themes_path
//  */
//
// /**
//  * The path where icons were installed to.
//  * @tfield string icon_path
//  */
fn index(state: *Lua) i32 {
    const zany_type = state.getGlobal("__zany") catch unreachable;
    std.debug.assert(zany_type == .light_userdata);
    const zany: *Zany = state.toUserdata(Zany, -1) catch unreachable;
    state.pop(1);

    // if(luaA_usemetatable(L, 1, 2))
    //     return 1;
    if (zany_lib.useMetatable(state, 1, 2) != 0) {
        return 1;
    }

    const buf = state.checkString(2);
    if (std.mem.eql(u8, "conffile", buf)) {
        // Should NOT be null at this point
        _ = state.pushString(config.config.?);
        return 1;
    }
    if (std.mem.eql(u8, "version", buf)) {
        // TODO: Figure out how to do this from build time
        _ = state.pushString("devel");
        return 1;
    }
    if (std.mem.eql(u8, "release", buf)) {
        // TODO: Figure out how to do this from build time
        _ = state.pushString("devel");
        return 1;
    }

    if (std.mem.eql(u8, "api_level", buf)) {
        state.pushInteger(@intCast(config.api_level.major));
        return 1;
    }
    if (std.mem.eql(u8, "startup", buf)) {
        state.pushBoolean(zany.state == .starting);
        return 1;
    }
    if (std.mem.eql(u8, "_modifiers", buf)) {
        std.debug.panic("awesome._modifiers not implemented", .{});
        // luaA_get_modifiers(L);
    }
    if (std.mem.eql(u8, "_active_modifiers", buf)) {
        std.debug.panic("awesome._active_modifiers not implemented", .{});
        // luaA_get_active_modifiers(L);
    }
    if (std.mem.eql(u8, "startup_errors", buf)) {
        if (config.startup_errors.len == 0) {
            return 0;
        }
        _ = state.pushString(config.startup_errors);
        return 1;
    }
    //
    // if(A_STREQ(buf, "composite_manager_running"))
    // {
    //     lua_pushboolean(L, composite_manager_running());
    //     return 1;
    // }
    //
    if (std.mem.eql(u8, "hostname", buf)) {
        var hostname_buf: [64]u8 = undefined;
        const hostname = std.posix.gethostname(&hostname_buf) catch return 0;
        _ = state.pushString(hostname);
        return 1;
    }
    if (std.mem.eql(u8, "themes_path", buf)) {
        _ = state.pushString(options.themes_path);
        return 1;
    }
    if (std.mem.eql(u8, "icon_path", buf)) {
        _ = state.pushString(options.icon_path);
        return 1;
    }

    return defaults.index(state);
}

fn xkb_set_layout_group(state: *Lua) i32 {
    _ = state;
    std.debug.panic("awesome.xkb_set_layout_group not implemented", .{});
    return 0;
}

///
/// Get current layout number.
///
/// @function xkb_get_layout_group
/// @treturn integer num Current layout number, integer from 0 to 3.
///
fn xkb_get_layout_group(state: *Lua) i32 {
    const zany = zany_lib.getZany(state);
    state.pushInteger(zany.wm.keyboard.idx);
    return 1;
}

fn groupNameFromLayout(name: []const u8) []const u8 {
    if (std.ascii.eqlIgnoreCase("english (us)", name)) {
        return "us";
    }
    log.warn("Unknown Layout name: \"{s}\"", .{name});
    return name;
}

///
/// Get layout short names.
///
/// @function xkb_get_group_names
/// @treturn string A string describing the current layout settings,
///   e.g.: 'pc+us+de:2+inet(evdev)+group(alt_shift_toggle)+ctrl(nocaps)'
///
fn xkb_get_group_names(state: *Lua) i32 {
    const zany = zany_lib.getZany(state);
    const kb = zany.wm.keyboard;
    var buf: [256]u8 = undefined;
    const name = std.fmt.bufPrintZ(&buf, "{s}:{d}", .{
        //kb.name,
        groupNameFromLayout(kb.name),
        kb.idx,
    }) catch unreachable;
    log.debug("Sending group name: ({s})", .{name});
    _ = state.pushStringZ(name);
    return 1;
}
fn xrdb_get_value(state: *Lua) i32 {
    zany_lua.deprecate(@src(), state, "awesome.xrdb_get_value");
    state.pushNil();
    return 1;
}

test {
    _ = @import("WindowManager.zig");
    _ = @import("lua/lib.zig");
}

fn screen_scan(zany: *Zany) !void {
    Screen.screen_class.signals.emit(zany.vm, "scanning", 0);
    defer Screen.screen_class.signals.emit(zany.vm, "scanned", 0);
    if (config.ignore_screens) return;
    var iter = zany.wm.outputs.iterator(.forward);
    while (iter.next()) |viewport| {
        if (try Screen.add(zany.vm)) |s| {
            viewport.screen = s;
            s.viewport = viewport;
            s.lifecycle = .c;
            s.geometry = viewport.geometry;
        }
    }
}

fn client_scan(zany: *Zany) void {
    Client.client_class.signals.emit(zany.vm, "scanning", 0);
    defer Client.client_class.signals.emit(zany.vm, "scanned", 0);
    var iter = zany.wm.windows.iterator(.forward);
    while (iter.next()) |win| {
        log.debug("Scanning Win: {*}", .{win});
        Client.manage(zany.vm, win);
    }
}
fn emit_startup(zany: *Zany) void {
    globals.signals.emit(zany.vm, "startup", 0);
}
fn emit_refresh(zany: *Zany) void {
    globals.signals.emit(zany.vm, "refresh", 0);
}

fn onError(state: *lua.Lua) i32 {
    // Convert error to string, to prevent a follow-up error with lua_concat. */
    const str = state.toString(-1) catch "";
    log.err("Error: {s}", .{str});
    // duplicate string error */
    state.pushValue(-1);
    // emit error signal */
    globals.signals.emit(state, "debug::error", 1);

    state.doString("return debug.traceback(\"error while running function!\", 3)") catch {
        return 1;
    };
    state.insert(-2);
    _ = state.pushStringZ("\nerror: ");
    state.insert(-2);
    state.concat(3);
    return 1;
}
