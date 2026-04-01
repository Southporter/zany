const std = @import("std");
const lua = @import("lua");
const lib = @import("lua/lib.zig");
const Class = @import("lua/Class.zig");
const Object = @import("lua/Object.zig");
const zany = @import("root.zig");
const zanylua = @import("./lua.zig");
const globals = @import("globals.zig");

const Drawable = @This();

obj: Object = .{},

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
        .{ .name = "geometry", .func = lua.wrap(geometry) },
    };

    return drawable_class.setup(state, &methods, &meta);
}

fn new(state: *lua.Lua) ?*Object {
    const drawable = drawable_class.create(Drawable, state) orelse return null;
    return &drawable.obj;
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

fn geometry(state: *lua.Lua) i32 {
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
