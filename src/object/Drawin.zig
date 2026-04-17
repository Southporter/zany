const std = @import("std");
const lua = @import("lua");
const lib = @import("../lua/lib.zig");
const Class = @import("Class.zig");
const Object = @import("Object.zig");
const zany = @import("../zany.zig");
const zanylua = @import("../lua.zig");
const globals = @import("../globals.zig");
const Drawable = @import("Drawable.zig");
const Window = @import("Window.zig");
const Area = @import("../common/Area.zig");

const log = std.log.scoped(.drawin);

const Drawin = @This();

window: Window = .{},

ontop: bool = false,
visible: bool = false,
// /** Cursor */
cursor: []const u8 = "left_ptr",
drawable: *Drawable = undefined,
// The window geometry.
geometry: Area = .{
    .width = 1,
    .height = 1,
},
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
    .parent = &Window.window_class,
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
    drawin.drawable = Drawable.allocator(state, refreshPixmap, drawin) orelse unreachable;
    _ = Object.refItem(state, -2, -1);
    drawin.window.opacity = -1;
    drawin.window.kind = .normal;
    // w->window = xcb_generate_id(globalconf.connection);
    // xcb_create_window(globalconf.connection, globalconf.default_depth, w->window, s->root,
    //                   w->geometry.x, w->geometry.y,
    //                   w->geometry.width, w->geometry.height,
    //                   w->border_width, XCB_COPY_FROM_PARENT, globalconf.visual->visual_id,
    //                   XCB_CW_BORDER_PIXEL | XCB_CW_BIT_GRAVITY
    //                   | XCB_CW_OVERRIDE_REDIRECT | XCB_CW_EVENT_MASK | XCB_CW_COLORMAP
    //                   | XCB_CW_CURSOR,
    //                   (const uint32_t [])
    //                   {
    //                       w->border_color.pixel,
    //                       XCB_GRAVITY_NORTH_WEST,
    //                       1,
    //                       XCB_EVENT_MASK_SUBSTRUCTURE_REDIRECT
    //                       | XCB_EVENT_MASK_SUBSTRUCTURE_NOTIFY | XCB_EVENT_MASK_ENTER_WINDOW
    //                       | XCB_EVENT_MASK_LEAVE_WINDOW | XCB_EVENT_MASK_STRUCTURE_NOTIFY
    //                       | XCB_EVENT_MASK_POINTER_MOTION | XCB_EVENT_MASK_BUTTON_PRESS
    //                       | XCB_EVENT_MASK_BUTTON_RELEASE | XCB_EVENT_MASK_EXPOSURE
    //                       | XCB_EVENT_MASK_PROPERTY_CHANGE,
    //                       globalconf.default_cmap,
    //                       xcursor_new(globalconf.cursor_ctx, xcursor_font_fromstr(w->cursor))
    //                   });
    // xwindow_set_class_instance(w->window);
    // xwindow_set_name_static(w->window, "Awesome drawin");
    //
    // /* Set the right properties */
    // ewmh_update_window_type(w->window, window_translate_type(w->type));
    // ewmh_update_strut(w->window, &w->strut);
    return &drawin.window.obj;
}

fn refreshPixmap() void {
    std.debug.panic("drawin refreshPixmap not implemented", .{});
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
    return drawin_class.new(state);
}

fn handleGeometry(state: *lua.Lua) i32 {
    const object = drawin_class.checkudata(state, 1) orelse {
        return 0;
    };
    const window: *Window = @fieldParentPtr("obj", object);
    const drawin: *Drawin = @fieldParentPtr("window", window);

    if (state.getTop() == 2) {
        lib.checkTable(state, 2);
        std.debug.panic("handleGeometry set not implemented", .{});
        // luaA_checktable(L, 2);
        // wingeom.x = round(luaA_getopt_number_range(L, 2, "x", drawin->geometry.x, MIN_X11_COORDINATE, MAX_X11_COORDINATE));
        // wingeom.y = round(luaA_getopt_number_range(L, 2, "y", drawin->geometry.y, MIN_X11_COORDINATE, MAX_X11_COORDINATE));
        // wingeom.width = ceil(luaA_getopt_number_range(L, 2, "width", drawin->geometry.width, MIN_X11_SIZE, MAX_X11_SIZE));
        // wingeom.height = ceil(luaA_getopt_number_range(L, 2, "height", drawin->geometry.height, MIN_X11_SIZE, MAX_X11_SIZE));
        //
        // if(wingeom.width > 0 && wingeom.height > 0)
        //     drawin_moveresize(L, 1, wingeom);
    }
    return drawin.geometry.push(state);
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
    return Object.pushItem(state, -2, drawin.drawable);
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
