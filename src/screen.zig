const std = @import("std");
const lua = @import("lua");
const lib = @import("lua/lib.zig");
const Class = @import("lua/Class.zig");
const Object = @import("lua/Object.zig");

const Screen = @This();

const Area = struct {
    x: i32 = 0,
    y: i32 = 0,
    width: u32 = 0,
    height: u32 = 0,
};

obj: Object = .{},
valid: bool = false,
// /** Who manages the screen lifecycle */
// screen_lifecycle_t lifecycle;
// /** Screen geometry */
geometry: Area = .{},
// /** Screen workarea */
workarea: Area = .{},
// /** The name of the screen */
name: ?[]const u8 = null,
// /** Opaque pointer to the viewport */
// struct viewport_t *viewport;
// /** Some XID identifying this screen */
// uint32_t xid;

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

var screen_class: Class = .{
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
    return screen_class.create(Screen, state);
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
