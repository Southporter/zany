const std = @import("std");
const lua = @import("lua");
const lib = @import("lua/lib.zig");
const Class = @import("lua/Class.zig");
const Object = @import("lua/Object.zig");
const zany = @import("root.zig");
const zanylua = @import("./lua.zig");
const globals = @import("globals.zig");
const Drawable = @import("drawable.zig");
const Window = @import("window.zig");
const Area = @import("common/Area.zig");

const log = std.log.scoped(.drawin);

const Drawin = @This();

window: Window = .{},

ontop: bool = false,
visible: bool = false,
// /** Cursor */
// char *cursor;
drawable: ?*Drawable = null,
// The window geometry.
geometry: Area = .{},
// Do we have a pending geometry change that still needs to be applied?
geometry_dirty: bool = false,

var props = [_]Class.Property{
    .{
        .name = "drawable",
        .index = getDrawable,
    },
    .{
        .name = "visible",
        .new = set_visible,
        .index = get_visible,
        .newindex = set_visible,
    },
    .{
        .name = "ontop",
        .new = set_ontop,
        .index = get_ontop,
        .newindex = set_ontop,
    },
    .{
        .name = "cursor",
        .new = set_cursor,
        .index = get_cursor,
        .newindex = set_cursor,
    },
    .{
        .name = "x",
        .new = set_x,
        .index = get_x,
        .newindex = set_x,
    },
    .{
        .name = "y",
        .new = set_y,
        .index = get_y,
        .newindex = set_y,
    },
    .{
        .name = "width",
        .new = set_width,
        .index = get_width,
        .newindex = set_width,
    },
    .{
        .name = "height",
        .new = set_height,
        .index = get_height,
        .newindex = set_height,
    },
    .{
        .name = "type",
        .new = Window.set_type,
        .index = Window.get_type,
        .newindex = Window.set_type,
    },
    .{
        .name = "shape_bounding",
        .new = set_shape_bounding,
        .index = get_shape_bounding,
        .newindex = set_shape_bounding,
    },
    .{
        .name = "shape_clip",
        .new = set_shape_clip,
        .index = get_shape_clip,
        .newindex = set_shape_clip,
    },
    .{
        .name = "shape_input",
        .new = set_shape_input,
        .index = get_shape_input,
        .newindex = set_shape_input,
    },
};
var drawin_class: Class = .{
    .name = "drawin",
    .properties = props[0..],
    .allocator = new,
    .collector = wipe,
};

pub fn setup(state: *lua.Lua) !void {
    const methods = [_]lua.FnReg{
        .{ .name = "get", .func = lua.wrap(get) },
        .{ .name = "__call", .func = lua.wrap(call) },
    };
    const meta = [_]lua.FnReg{
        .{ .name = "geometry", .func = lua.wrap(handleGeometry) },
    };

    return drawin_class.setup(state, &methods, &meta);
}

fn new(state: *lua.Lua) ?*Object {
    const drawin = drawin_class.create(Drawin, state) orelse return null;
    return &drawin.window.obj;
}

fn wipe(obj: *Object) void {
    const window: *Window = @fieldParentPtr("obj", obj);
    const drawin: *Drawin = @fieldParentPtr("window", window);
    globals.gpa.destroy(drawin);
}

fn get(state: *lua.Lua) i32 {
    _ = state;
    std.debug.panic("drawin.get not impemented", .{});
    return 0;
}
fn call(state: *lua.Lua) i32 {
    _ = state;
    std.debug.panic("drawin.__call not impemented", .{});
    return 0;
}

fn handleGeometry(state: *lua.Lua) i32 {
    _ = state;
    std.debug.panic("drawin.geometry not implemented", .{});
}

fn get_x(state: *lua.Lua, obj: *Object) i32 {
    const window: *Window = @fieldParentPtr("obj", obj);
    const drawin: *Drawin = @fieldParentPtr("window", window);
    state.pushInteger(drawin.geometry.x);
    return 1;
}
fn set_x(state: *lua.Lua, obj: *Object) i32 {
    const window: *Window = @fieldParentPtr("obj", obj);
    const drawin: *Drawin = @fieldParentPtr("window", window);
    const new_x = state.toInteger(1) catch {
        log.warn("Tried to set drawin.geometry.x to non-integer: {t}", .{state.typeOf(1)});
        return 0;
    };
    drawin.geometry.x = @intCast(new_x);
    drawin.geometry_dirty = true;
    return 0;
}
fn get_y(state: *lua.Lua, obj: *Object) i32 {
    const window: *Window = @fieldParentPtr("obj", obj);
    const drawin: *Drawin = @fieldParentPtr("window", window);
    state.pushInteger(drawin.geometry.y);
    return 1;
}
fn set_y(state: *lua.Lua, obj: *Object) i32 {
    const window: *Window = @fieldParentPtr("obj", obj);
    const drawin: *Drawin = @fieldParentPtr("window", window);
    const new_y = state.toInteger(1) catch {
        log.warn("Tried to set drawin.geometry.y to non-integer: {t}", .{state.typeOf(1)});
        return 0;
    };
    drawin.geometry.y = @intCast(new_y);
    drawin.geometry_dirty = true;
    return 0;
}
fn get_width(state: *lua.Lua, obj: *Object) i32 {
    const window: *Window = @fieldParentPtr("obj", obj);
    const drawin: *Drawin = @fieldParentPtr("window", window);
    state.pushInteger(drawin.geometry.width);
    return 1;
}
fn set_width(state: *lua.Lua, obj: *Object) i32 {
    const window: *Window = @fieldParentPtr("obj", obj);
    const drawin: *Drawin = @fieldParentPtr("window", window);
    const new_width = state.toInteger(1) catch {
        log.warn("Tried to set drawin.geometry.width to non-integer: {t}", .{state.typeOf(1)});
        return 0;
    };
    drawin.geometry.width = @intCast(new_width);
    drawin.geometry_dirty = true;
    return 0;
}
fn get_height(state: *lua.Lua, obj: *Object) i32 {
    const window: *Window = @fieldParentPtr("obj", obj);
    const drawin: *Drawin = @fieldParentPtr("window", window);
    state.pushInteger(drawin.geometry.height);
    return 1;
}
fn set_height(state: *lua.Lua, obj: *Object) i32 {
    const window: *Window = @fieldParentPtr("obj", obj);
    const drawin: *Drawin = @fieldParentPtr("window", window);
    const new_height = state.toInteger(1) catch {
        log.warn("Tried to set drawin.geometry.height to non-integer: {t}", .{state.typeOf(1)});
        return 0;
    };
    drawin.geometry.height = @intCast(new_height);
    drawin.geometry_dirty = true;
    return 0;
}

fn get_shape_bounding(state: *lua.Lua, obj: *Object) i32 {
    _ = state;
    _ = obj;
    std.debug.panic("drawin `get_shape_bounding` not implemented", .{});
    return 0;
}
fn set_shape_bounding(state: *lua.Lua, obj: *Object) i32 {
    _ = state;
    _ = obj;
    std.debug.panic("drawin `set_shape_bounding` not implemented", .{});
    return 0;
}
fn get_shape_clip(state: *lua.Lua, obj: *Object) i32 {
    _ = state;
    _ = obj;
    std.debug.panic("drawin `get_shape_clip` not implemented", .{});
    return 0;
}
fn set_shape_clip(state: *lua.Lua, obj: *Object) i32 {
    _ = state;
    _ = obj;
    std.debug.panic("drawin `set_shape_clip` not implemented", .{});
    return 0;
}
fn get_shape_input(state: *lua.Lua, obj: *Object) i32 {
    _ = state;
    _ = obj;
    std.debug.panic("drawin `get_shape_input` not implemented", .{});
    return 0;
}
fn set_shape_input(state: *lua.Lua, obj: *Object) i32 {
    _ = state;
    _ = obj;
    std.debug.panic("drawin `set_shape_input` not implemented", .{});
    return 0;
}

fn getDrawable(state: *lua.Lua, obj: *Object) i32 {
    const window: *Window = @fieldParentPtr("obj", obj);
    const drawin: *Drawin = @fieldParentPtr("window", window);
    if (drawin.drawable) |drawable| {
        state.pushLightUserdata(drawable);
    } else {
        state.pushNil();
    }
    return 1;
}
fn get_visible(state: *lua.Lua, obj: *Object) i32 {
    const window: *Window = @fieldParentPtr("obj", obj);
    const drawin: *Drawin = @fieldParentPtr("window", window);
    state.pushBoolean(drawin.visible);
    return 1;
}
fn set_visible(state: *lua.Lua, obj: *Object) i32 {
    const window: *Window = @fieldParentPtr("obj", obj);
    const drawin: *Drawin = @fieldParentPtr("window", window);
    drawin.visible = state.toBoolean(1);
    return 0;
}
fn get_ontop(state: *lua.Lua, obj: *Object) i32 {
    const window: *Window = @fieldParentPtr("obj", obj);
    const drawin: *Drawin = @fieldParentPtr("window", window);
    state.pushBoolean(drawin.ontop);
    return 1;
}
fn set_ontop(state: *lua.Lua, obj: *Object) i32 {
    const window: *Window = @fieldParentPtr("obj", obj);
    const drawin: *Drawin = @fieldParentPtr("window", window);
    drawin.ontop = state.toBoolean(1);
    return 0;
}
fn get_cursor(state: *lua.Lua, obj: *Object) i32 {
    _ = state;
    _ = obj;
    std.debug.panic("cursor index property of drawin not implemented", .{});
    return 0;
}
fn set_cursor(state: *lua.Lua, obj: *Object) i32 {
    _ = state;
    _ = obj;
    std.debug.panic("cursor new[index] property of drawin not implemented", .{});
    return 0;
}
