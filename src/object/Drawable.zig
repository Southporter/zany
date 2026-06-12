const std = @import("std");
const lua = @import("lua");
const c = @import("deps");
const Area = @import("../common/Area.zig");
const lib = @import("../lua/lib.zig");
const Class = @import("Class.zig");
const Object = @import("Object.zig");
const zany = @import("../zany.zig");
const zanylua = @import("../lua.zig");
const globals = @import("../globals.zig");

const Drawable = @This();

const Callback = *const fn (*Object) void;

obj: Object = .{},
refresh_callback: Callback = undefined,
refresh_data: *anyopaque = undefined,
refreshed: bool = false,
surface: ?*c.cairo_surface_t = null,
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
    _ = drawable;
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
pub fn setGeometry(d: *Drawable, state: *lua.Lua, didx: c_int, geom: Area) void {
    const old = d.geometry;
    d.geometry = geom;

    const size_changed = (old.width != geom.width) or (old.height != geom.height);
    if (size_changed) {
        d.unsetSurface();
    }
    if (size_changed and geom.width > 0 and geom.height > 0) {
        zanylua.warn(state, "Need to handle geometry change in drawable.setGeometry", .{});
        // d->pixmap = xcb_generate_id(globalconf.connection);
        // xcb_create_pixmap(globalconf.connection, globalconf.default_depth, d->pixmap,
        //                   globalconf.screen->root, geom.width, geom.height);
        // d->surface = cairo_xcb_surface_create(globalconf.connection,
        //                                       d->pixmap, globalconf.visual,
        //                                       geom.width, geom.height);
        Object.emitSignal(state, didx, "property::surface", 0);
    }

    if (!old.eql(geom))
        Object.emitSignal(state, didx, "property::geometry", 0);
    if (old.x != geom.x)
        Object.emitSignal(state, didx, "property::x", 0);
    if (old.y != geom.y)
        Object.emitSignal(state, didx, "property::y", 0);
    if (old.width != geom.width)
        Object.emitSignal(state, didx, "property::width", 0);
    if (old.height != geom.height)
        Object.emitSignal(state, didx, "property::height", 0);
}

fn unsetSurface(d: *Drawable) void {
    c.cairo_surface_finish(d.surface);
    c.cairo_surface_destroy(d.surface);

    // if (d->pixmap)
    //     xcb_free_pixmap(globalconf.connection, d->pixmap);
    d.refreshed = false;
    d.surface = null;
    // d->pixmap = XCB_NONE;
}

fn getSurface(state: *lua.Lua, obj: *Object) i32 {
    _ = state;
    _ = obj;
    std.debug.panic("drawable.surface `get` not implemented", .{});
    return 0;
}
