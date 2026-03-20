const std = @import("std");
const lua = @import("lua");
const Class = @import("lua/Class.zig");
const Object = @import("lua/Object.zig");

const Screen = @This();

obj: Object,
// bool valid;
// /** Who manages the screen lifecycle */
// screen_lifecycle_t lifecycle;
// /** Screen geometry */
// area_t geometry;
// /** Screen workarea */
// area_t workarea;
// /** The name of the screen */
name: []const u8,
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
    // luaA_class_add_property(&screen_class, "_outputs",
    //                         NULL,
    //                         (lua_class_propfunc_t) luaA_screen_get_outputs,
    //                         NULL);
    // luaA_class_add_property(&screen_class, "_managed",
    //                         NULL,
    //                         (lua_class_propfunc_t) luaA_screen_get_managed,
    //                         NULL);
    // luaA_class_add_property(&screen_class, "workarea",
    //                         NULL,
    //                         (lua_class_propfunc_t) luaA_screen_get_workarea,
    //                         NULL);
    // luaA_class_add_property(&screen_class, "name",
    //                         (lua_class_propfunc_t) luaA_screen_set_name,
    //                         (lua_class_propfunc_t) luaA_screen_get_name,
    //                         (lua_class_propfunc_t) luaA_screen_set_name);
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
        // .{ .name = "_viewports", .func = viewports },
        // .{ .name = "_scan_quiet", .func = quietScan },
        // .{ .name = "__index", .func = moduleIndex },
        // .{ .name = "__newindex", .func = moduleNewIndex },
        // .{ .name = "__call", .func = call },
        // .{ .name = "fake_add", .func = fakeAdd },
    };
    const meta = [_]lua.FnReg{
        // .{ .name = "fake_remove", .func = luaA_screen_fake_remove },
        // .{ .name = "fake_resize", .func = luaA_screen_fake_resize },
        // .{ .name = "swap", .func = luaA_screen_swap },
    };
    return screen_class.setup(state, &methods, &meta);
}

fn new(_: *lua.Lua) ?*Object {
    const screen = std.heap.c_allocator.create(Screen) catch return null;
    return &screen.obj;
}

fn wipe(obj: *Object) void {
    const screen: *Screen = @fieldParentPtr("obj", obj);
    std.heap.c_allocator.destroy(screen);
}

pub fn count(state: *lua.Lua) i32 {
    _ = state;
    return 0;
}

pub fn getGeometry(state: *lua.Lua, obj: *Object) i32 {
    _ = state;
    _ = obj;
    return 0;
}
pub fn getIndex(state: *lua.Lua, obj: *Object) i32 {
    _ = state;
    _ = obj;
    return 0;
}
