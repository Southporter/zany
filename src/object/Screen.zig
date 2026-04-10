const std = @import("std");
const lua = @import("lua");
const lib = @import("../lua/lib.zig");
const Class = @import("Class.zig");
const Object = @import("Object.zig");
const zany = @import("../root.zig");
const zanylua = @import("../lua.zig");
const globals = @import("../globals.zig");
const wm = @import("../WindowManager.zig");
const Viewport = wm.Viewport;
const Area = @import("../common/Area.zig");
const log = std.log.scoped(.screen);

const Screen = @This();

const Xid = enum(u32) {
    none = 0,
    fake = 0xffffffff,
    _,
};
const Lifecycle = enum(u8) {
    user = 0,
    lua = 1,
    c = 2,
};

obj: Object = .{},
valid: bool = false,
// /** Who manages the screen lifecycle */
lifecycle: Lifecycle = .user,
// /** Screen geometry */
geometry: Area = .{},
// /** Screen workarea */
workarea: Area = .{},
// /** The name of the screen */
name: ?[]const u8 = null,
// /** Opaque pointer to the viewport */
viewport: *Viewport = undefined,
// Some XID identifying this screen */
xid: Xid = .none,

var props = [_]Class.Property{
    .{
        .name = "geometry",
        .index = getGeometry,
    },
    .{
        .name = "index",
        .index = getIndex,
    },
    .{
        .name = "_outputs",
        .index = getOutputs,
    },
    .{
        .name = "managed",
        .index = getManaged,
    },
    .{
        .name = "workarea",
        .index = getWorkarea,
    },
    .{
        .name = "name",
        .new = setName,
        .index = getName,
        .newindex = setName,
    },
};

pub var screen_class: Class = .{
    .name = "screen",
    .properties = props[0..],
    .allocator = new,
    .collector = wipe,
};

pub fn setup(state: *lua.Lua) !void {
    const methods = [_]lua.FnReg{
        .{ .name = "count", .func = lua.wrap(count) },
        // .{ .name = "_viewports", .func = lua.wrap(viewports) },
        // .{ .name = "_scan_quiet", .func = lua.wrap(quietScan) },
        .{ .name = "__index", .func = lua.wrap(moduleIndex) },
        .{ .name = "__newindex", .func = lua.wrap(moduleNewindex) },
        .{ .name = "__call", .func = lua.wrap(call) },
        .{ .name = "fake_add", .func = lua.wrap(fakeAdd) },
    };
    const meta = [_]lua.FnReg{
        .{ .name = "fake_remove", .func = lua.wrap(fakeRemove) },
        .{ .name = "fake_resize", .func = lua.wrap(fakeResize) },
        .{ .name = "swap", .func = lua.wrap(swap) },
    };
    return screen_class.setup(state, &methods, &meta);
}

fn new(state: *lua.Lua) ?*Object {
    const screen = screen_class.create(Screen, state) orelse return null;
    return &screen.obj;
}

fn wipe(obj: *Object) void {
    const screen: *Screen = @fieldParentPtr("obj", obj);
    if (screen.name) |name| {
        globals.gpa.free(name);
    }
    globals.gpa.destroy(screen);
}
/// Get a screen's index.
/// screen_get_index
fn index(screen: *Screen) usize {
    // Lua is 1 indexed, so start from 1
    for (globals.screens.items, 1..) |s, res| {
        if (screen == s) {
            return res;
        }
    }
    return 0;
}

pub fn count(state: *lua.Lua) i32 {
    state.pushInteger(@intCast(globals.screens.items.len));
    return 0;
}
pub fn viewports(state: *lua.Lua) i32 {
    _ = state;
    std.debug.panic("screen.viewports not implemented", .{});
    return 0;
}
pub fn quietScan(state: *lua.Lua) i32 {
    _ = state;
    std.debug.panic("screen._scan_quiet not implemented", .{});
    return 0;
}
// Screen module.
// \param L The Lua VM state.
// \return The number of elements pushed on stack.
// \luastack
// \lfield number The screen number, to get a screen.
//
pub fn moduleIndex(state: *lua.Lua) i32 {
    const kind = state.typeOf(2);
    if (kind == .string) {
        const name = state.toString(2) catch unreachable;
        if (std.mem.eql(u8, name, "primary")) {
            return Object.push(state, @ptrCast(getPrimary(state)));
        }
        for (globals.screens.items) |screen| {
            if (screen.name) |screen_name| {
                if (std.mem.eql(u8, name, screen_name)) {
                    return Object.push(state, screen);
                }
            }
        }

        zanylua.warn(state, "Unknown screen output name: {s}", .{name});
        state.pushNil();
        return 1;
    }

    return Object.push(state, @ptrCast(checkscreen(state, 2)));
}
pub fn moduleNewindex(state: *lua.Lua) i32 {
    _ = state;
    std.debug.panic("screen[newindex] not implemented", .{});
    return 0;
}

// Iterate over screens.
// @usage
// for s in screen do
//     print("Oh, wow, we have screen " .. tostring(s))
// end
// @function screen
//
pub fn call(state: *lua.Lua) i32 {
    // TODO: Is there a way to do this without the index juggling?
    var idx: usize = std.math.maxInt(usize);
    if (state.isNoneOrNil(3)) {
        idx = 0;
    } else {
        const screen = checkscreen(state, 3);
        if (screen) |s| {
            idx = @intCast(s.index());
        }
    }

    std.log.debug("Idx for screens: {d}", .{idx});
    if (idx < globals.screens.items.len) {
        _ = Object.push(state, globals.screens.items[@intCast(idx)]);
    } else {
        state.pushNil();
    }
    return 1;
}
pub fn fakeAdd(state: *lua.Lua) i32 {
    _ = state;
    std.debug.panic("screen.fake_add not implemented", .{});
    return 0;
}
pub fn fakeRemove(state: *lua.Lua) i32 {
    _ = state;
    std.debug.panic("screen meta fake_remove not implemented", .{});
    return 0;
}
pub fn fakeResize(state: *lua.Lua) i32 {
    _ = state;
    std.debug.panic("screen.meta fake_resize not implemented", .{});
    return 0;
}
pub fn swap(state: *lua.Lua) i32 {
    _ = state;
    std.debug.panic("screen.swap not implemented", .{});
    return 0;
}

pub fn getGeometry(state: *lua.Lua, obj: *Object) i32 {
    _ = state;
    _ = obj;
    std.debug.panic("screen.geometry not implemented", .{});
    return 0;
}
// luaA_screen_get_index
pub fn getIndex(state: *lua.Lua, obj: *Object) i32 {
    const screen: *Screen = @fieldParentPtr("obj", obj);
    state.pushInteger(@intCast(screen.index()));
    return 1;
}
pub fn getOutputs(state: *lua.Lua, obj: *Object) i32 {
    _ = state;
    _ = obj;
    std.debug.panic("screen._outputs not implemented", .{});
    return 0;
}
pub fn getManaged(state: *lua.Lua, obj: *Object) i32 {
    _ = state;
    _ = obj;
    std.debug.panic("screen.managed not implemented", .{});
    return 0;
}
pub fn getWorkarea(state: *lua.Lua, obj: *Object) i32 {
    _ = state;
    _ = obj;
    std.debug.panic("screen.workarea not implemented", .{});
    return 0;
}
pub fn getName(state: *lua.Lua, obj: *Object) i32 {
    _ = state;
    _ = obj;
    std.debug.panic("screen.name not implemented", .{});
    return 0;
}
pub fn setName(state: *lua.Lua, obj: *Object) i32 {
    _ = state;
    _ = obj;
    std.debug.panic("`screen.name = x` not implemented", .{});
    return 0;
}

// Get a screen argument from the lua stack
pub fn checkscreen(state: *lua.Lua, sidx: i32) ?*Screen {
    if (state.isNumber(sidx)) {
        const screen = state.toInteger(sidx) catch unreachable;
        if (screen < 1 or screen > globals.screens.items.len) {
            zanylua.warn(state, "invalid screen number: {d} (of {d} existing)", .{ screen, globals.screens.items.len });
            state.pushNil();
            return null;
        }
        return globals.screens.items[@intCast(screen - 1)];
    } else {
        const obj = screen_class.checkudata(state, sidx) orelse return null;
        return @fieldParentPtr("obj", obj);
    }
}

pub fn add(state: *lua.Lua) !?*Screen {
    const screen = screen_class.create(Screen, state) orelse return null;
    _ = Object.ref(state, -1);
    try globals.screens.append(globals.gpa, screen);
    screen.xid = .none;
    screen.lifecycle = .user;
    return screen;
}

fn getPrimary(state: *lua.Lua) ?*Screen {
    if (globals.primary_screen == null and globals.screens.items.len > 0) {
        globals.primary_screen = globals.screens.items[0];
        _ = Object.push(state, globals.primary_screen.?);
        Object.emitSignal(state, -1, "primary_changed", 0);
        state.pop(1);
    }
    return globals.primary_screen;
}
