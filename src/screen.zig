const std = @import("std");
const lua = @import("lua");
const lib = @import("lua/lib.zig");
const Class = @import("lua/Class.zig");
const Object = @import("lua/Object.zig");
const zany = @import("root.zig");
const zanylua = @import("./lua.zig");
const globals = @import("globals.zig");
const wm = @import("WindowManager.zig");
const Viewport = wm.Viewport;

const Screen = @This();

const Area = struct {
    x: i32 = 0,
    y: i32 = 0,
    width: u32 = 0,
    height: u32 = 0,
};

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
        .{ .name = "_viewports", .func = lua.wrap(viewports) },
        .{ .name = "_scan_quiet", .func = lua.wrap(quietScan) },
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
        std.heap.c_allocator.free(name);
    }
    std.heap.c_allocator.destroy(screen);
}

pub fn count(state: *lua.Lua) i32 {
    _ = state;
    std.debug.panic("screen.count not implemented", .{});
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
pub fn moduleIndex(state: *lua.Lua) i32 {
    _ = state;
    std.debug.panic("screen[index] not implemented", .{});
    return 0;
}
pub fn moduleNewindex(state: *lua.Lua) i32 {
    _ = state;
    std.debug.panic("screen[newindex] not implemented", .{});
    return 0;
}
pub fn call(state: *lua.Lua) i32 {
    _ = state;
    std.debug.panic("screen(call) not implemented", .{});
    return 0;
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
pub fn getIndex(state: *lua.Lua, obj: *Object) i32 {
    _ = state;
    _ = obj;
    std.debug.panic("screen.index not implemented", .{});
    return 0;
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
    const obj = new(state) orelse return null;
    const screen: *Screen = @fieldParentPtr("obj", obj);
    _ = Object.ref(state, -1);
    try globals.screens.append(globals.gpa, screen);
    screen.xid = .none;
    screen.lifecycle = .user;
    return screen;
}
