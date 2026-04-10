const std = @import("std");
const lua = @import("lua");
const cairo = @import("cairo");
const Area = @import("../common/Area.zig");
const lib = @import("../lua/lib.zig");
const Class = @import("Class.zig");
const Object = @import("Object.zig");
const zany = @import("../root.zig");
const zanylua = @import("../lua.zig");
const globals = @import("../globals.zig");

const Drawable = @This();

const Callback = *const fn () void;

obj: Object = .{},
refresh_callback: Callback = undefined,
refresh_data: *anyopaque = undefined,
refreshed: bool = false,
surface: ?*cairo.cairo_surface_t = null,
geometry: Area = .{},
// pixmap: Pixmap,

var props = [_]Class.Property{
    .{ .name = "surface", .index = getSurface },
};

var drawable_class: Class = .{
    .name = "drawable",
    .properties = props[0..],
    .allocator = new,
    .collector = wipe,
};

pub fn setup(state: *lua.Lua) !void {
    const methods = [_]lua.FnReg{};
    const meta = [_]lua.FnReg{
        .{ .name = "refresh", .func = lua.wrap(refresh) },
        .{ .name = "geometry", .func = lua.wrap(getGeometry) },
    };

    return drawable_class.setup(state, &methods, &meta);
}

pub fn new(state: *lua.Lua) ?*Object {
    const drawable = drawable_class.create(Drawable, state) orelse return null;
    return &drawable.obj;
}
pub fn allocator(state: *lua.Lua, callback: Callback, data: *anyopaque) ?*Drawable {
    const d = drawable_class.create(Drawable, state) orelse return null;
    d.* = .{
        .refresh_callback = callback,
        .refresh_data = data,
    };
    return d;
}

fn wipe(obj: *Object) void {
    const drawable: *Drawable = @fieldParentPtr("obj", obj);
    globals.gpa.destroy(drawable);
}

fn refresh(state: *lua.Lua) i32 {
    _ = state;
    std.debug.panic("drawable.refresh not implemented", .{});
    return 0;
}

fn getGeometry(state: *lua.Lua) i32 {
    _ = state;
    std.debug.panic("drawable.geometry not implemented", .{});
    return 0;
}

fn getSurface(state: *lua.Lua, obj: *Object) i32 {
    _ = state;
    _ = obj;
    std.debug.panic("drawable.surface `get` not implemented", .{});
    return 0;
}
