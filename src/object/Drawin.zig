const std = @import("std");
const lua = @import("lua");
const c = @import("deps");
const lib = @import("../lua/lib.zig");
const cursor_lib = @import("../lua/cursor.zig");
const Class = @import("Class.zig");
const Object = @import("Object.zig");
const zany = @import("../zany.zig");
const zanylua = @import("../lua.zig");
const globals = @import("../globals.zig");
const Drawable = @import("Drawable.zig");
const Window = @import("Window.zig");
const Screen = @import("Screen.zig");
const Strut = @import("../common/Strut.zig");
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

fn refreshPixmap(obj: *Object) void {
    const drawin = fromObj(obj);
    drawin.refreshPixmapPartial(0, 0, drawin.geometry.width, drawin.geometry.height);
}

fn wipe(obj: *Object) void {
    const window: *Window = @fieldParentPtr("obj", obj);
    const drawin: *Drawin = @fieldParentPtr("window", window);
    _ = drawin;
}

/// Get all drawins into a table.
/// @treturn table A table with drawins.
/// @function get
///
/// From: luaA_drawin_get
fn get(state: *lua.Lua) i32 {
    state.newTable();

    for (globals.drawins.items, 1..) |d, i| {
        _ = Object.push(state, d);
        state.rawSetIndex(-2, @intCast(i));
    }
    return 1;
}
fn call(state: *lua.Lua) i32 {
    return drawin_class.new(state);
}

fn fromObj(obj: *Object) *Drawin {
    const win: *Window = @fieldParentPtr("obj", obj);
    return @fieldParentPtr("window", win);
}

fn handleGeometry(state: *lua.Lua) i32 {
    const object = drawin_class.checkudata(state, 1) orelse {
        return 0;
    };
    const window: *Window = @fieldParentPtr("obj", object);
    const drawin: *Drawin = @fieldParentPtr("window", window);

    if (state.getTop() == 2) {
        lib.checkTable(state, 2);
        const wingeom = Area{
            .x = @intFromFloat(@round(lib.getOptNumberRange(state, 2, "x", @floatFromInt(drawin.geometry.x), Window.min_x11_coordinate, Window.max_x11_coordinate))),
            .y = @intFromFloat(@round(lib.getOptNumberRange(state, 2, "y", @floatFromInt(drawin.geometry.y), Window.min_x11_coordinate, Window.max_x11_coordinate))),
            .width = @intFromFloat(@ceil(lib.getOptNumberRange(state, 2, "width", @floatFromInt(drawin.geometry.width), Window.min_x11_size, Window.max_x11_size))),
            .height = @intFromFloat(@ceil(lib.getOptNumberRange(state, 2, "height", @floatFromInt(drawin.geometry.height), Window.min_x11_size, Window.max_x11_size))),
        };

        if (wingeom.width > 0 and wingeom.height > 0) {
            drawin.moveResize(state, 1, wingeom);
        }
    }
    return drawin.geometry.push(state);
}
/// Move and/or resize a drawin
/// \param L The Lua VM state.
/// \param udx The index of the drawin.
/// \param geometry The new geometry.
///
/// drawin_moveresize
fn moveResize(drawin: *Drawin, state: *lua.Lua, udx: c_int, geometry: Area) void {
    const old_geometry = drawin.geometry;

    drawin.geometry = geometry;
    if (drawin.geometry.width <= 0)
        drawin.geometry.width = old_geometry.width;
    if (drawin.geometry.height <= 0)
        drawin.geometry.height = old_geometry.height;

    drawin.geometry_dirty = true;
    drawin.updateDrawing(state, udx);

    if (!old_geometry.eql(drawin.geometry)) {
        Object.emitSignal(state, udx, "property::geometry", 0);
    }
    if (old_geometry.x != drawin.geometry.x)
        Object.emitSignal(state, udx, "property::x", 0);
    if (old_geometry.y != drawin.geometry.y)
        Object.emitSignal(state, udx, "property::y", 0);
    if (old_geometry.width != drawin.geometry.width)
        Object.emitSignal(state, udx, "property::width", 0);
    if (old_geometry.height != drawin.geometry.height)
        Object.emitSignal(state, udx, "property::height", 0);

    const old_screen = Screen.getByCoord(old_geometry.x, old_geometry.y);
    const new_screen = Screen.getByCoord(drawin.geometry.x, drawin.geometry.y);
    if (old_screen != new_screen and drawin.window.strut.hasValue()) {
        old_screen.?.updateWorkarea(state);
        new_screen.?.updateWorkarea(state);
    }
}

fn applyMoveResize(drawin: *Drawin) void {
    if (!drawin.geometry_dirty) {
        return;
    }

    drawin.geometry_dirty = false;

    {
        const state = globals.getLuaState();
        zanylua.warn(state, "Need to finish implementation in drawin.applyMoveResize", .{});
    }
    // client_ignore_enterleave_events();
    // xcb_configure_window(globalconf.connection, w->window,
    //                      XCB_CONFIG_WINDOW_X | XCB_CONFIG_WINDOW_Y
    //                      | XCB_CONFIG_WINDOW_WIDTH | XCB_CONFIG_WINDOW_HEIGHT,
    //                      (const uint32_t [])
    //                      {
    //                          w->geometry.x,
    //                          w->geometry.y,
    //                          w->geometry.width,
    //                          w->geometry.height
    //                      });
    // client_restore_enterleave_events();
}

fn updateDrawing(w: *Drawin, state: *lua.Lua, widx: c_int) void {
    const pushed = Object.pushItem(state, widx, w.drawable);
    defer state.pop(pushed);

    w.drawable.setGeometry(state, -1, w.geometry);
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
    const new_x = @ceil(lib.checkNumberRange(state, -1, Window.min_x11_coordinate, Window.max_x11_coordinate));
    drawin.moveResize(state, -3, .{
        .x = @intFromFloat(new_x),
        .y = drawin.geometry.y,
        .height = drawin.geometry.height,
        .width = drawin.geometry.width,
    });
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
    const new_y = @ceil(lib.checkNumberRange(state, -1, Window.min_x11_coordinate, Window.max_x11_coordinate));
    drawin.moveResize(state, -3, .{
        .x = drawin.geometry.x,
        .y = @intFromFloat(new_y),
        .height = drawin.geometry.height,
        .width = drawin.geometry.width,
    });
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
    const new_width = @ceil(lib.checkNumberRange(state, -1, Window.min_x11_size, Window.max_x11_size));
    drawin.moveResize(state, -3, .{
        .x = drawin.geometry.x,
        .y = drawin.geometry.y,
        .height = drawin.geometry.height,
        .width = @intFromFloat(new_width),
    });
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
    const new_height = @ceil(lib.checkNumberRange(state, -1, Window.min_x11_size, Window.max_x11_size));
    drawin.moveResize(state, -3, .{
        .x = drawin.geometry.x,
        .y = drawin.geometry.y,
        .width = drawin.geometry.width,
        .height = @intFromFloat(new_height),
    });
    return 0;
}

///* Get the drawin's clip shape.
/// \param L The Lua VM state.
/// \param drawin The drawin object.
/// \return The number of elements pushed on stack.
////
fn get_shape_bounding(state: *lua.Lua, obj: *Object) i32 {
    _ = state;
    _ = obj;
    std.debug.panic("drawin `get_shape_bounding` not implemented", .{});
    return 0;
}
///* Set the drawin's bounding shape.
/// \param L The Lua VM state.
/// \param drawin The drawin object.
/// \return The number of elements pushed on stack.
fn set_shape_bounding(state: *lua.Lua, obj: *Object) i32 {
    if (!state.isNil(-1)) {
        const surf = state.toUserdata(*c.cairo_surface_t, -1) catch null;
        std.debug.panic("Got a surface. Don't know what to do with it: {*}", .{surf});
    }
    // The drawin might have been resized to a larger size. Apply that.
    const win: *Window = @fieldParentPtr("obj", obj);
    const drawin: *Drawin = @fieldParentPtr("window", win);
    drawin.applyMoveResize();
    zanylua.warn(state, "resizing not implemented in set_shape_bounding", .{});
    //  Update the wl.Surface buffer for this drawin.
    // xwindow_set_shape(drawin->window,
    //         drawin->geometry.width + 2*drawin->border_width,
    //         drawin->geometry.height + 2*drawin->border_width,
    //         XCB_SHAPE_SK_BOUNDING, surf, -drawin->border_width);
    Object.emitSignal(state, -3, "property::shape_bounding", 0);
    return 0;
}
/// Get the drawin's clip shape.
/// \param L The Lua VM state.
/// \param drawin The drawin object.
/// \return The number of elements pushed on stack.
///
fn get_shape_clip(state: *lua.Lua, obj: *Object) i32 {
    // cairo_surface_t *surf = xwindow_get_shape(drawin->window, XCB_SHAPE_SK_CLIP);
    // if (!surf)
    _ = state;
    _ = obj;
    return 0;
    // /* lua has to make sure to free the ref or we have a leak */
    // lua_pushlightuserdata(L, surf);
    // return 1;
}
/// Set the drawin's clip shape.
/// \param L The Lua VM state.
/// \param drawin The drawin object.
/// \return The number of elements pushed on stack.
fn set_shape_clip(state: *lua.Lua, obj: *Object) i32 {
    var surf: ?*c.cairo_surface_t = null;
    if (!state.isNil(-1)) {
        surf = state.toUserdata(c.cairo_surface_t, -1) catch unreachable;
    }

    const win: *Window = @fieldParentPtr("obj", obj);
    const drawin: *Drawin = @fieldParentPtr("window", win);

    // The drawin might have been resized to a larger size. Apply that.
    drawin.applyMoveResize();

    zanylua.warn(state, "xwindow_set_shape not implemented in drawin.set_shape_clip", .{});
    // xwindow_set_shape(drawin->window, drawin->geometry.width, drawin->geometry.height,
    //         XCB_SHAPE_SK_CLIP, surf, 0);
    Object.emitSignal(state, -3, "property::shape_clip", 0);
    return 0;
}

/// Get the drawin's input shape.
/// \param L The Lua VM state.
/// \param drawin The drawin object.
/// \return The number of elements pushed on stack.
fn get_shape_input(state: *lua.Lua, obj: *Object) i32 {
    _ = state;
    _ = obj;
    // cairo_surface_t *surf = xwindow_get_shape(drawin->window, XCB_SHAPE_SK_INPUT);
    // if (!surf)
    //     return 0;
    // /* lua has to make sure to free the ref or we have a leak */
    // lua_pushlightuserdata(L, surf);
    // return 1;

    log.warn("darwin.get_shape_input is missing xwindow translation", .{});
    return 0;
}
/// Set the drawin's input shape.
/// \param L The Lua VM state.
/// \param drawin The drawin object.
/// \return The number of elements pushed on stack.
fn set_shape_input(state: *lua.Lua, obj: *Object) i32 {
    var surf: ?*c.cairo_surface_t = null;
    if (!state.isNil(-1)) {
        surf = state.toUserdata(c.cairo_surface_t, -1) catch unreachable;
    }

    const drawin = fromObj(obj);
    // The drawin might have been resized to a larger size. Apply that.
    drawin.applyMoveResize();

    log.warn("drawin.set_shape_input is missing xwindow translation", .{});
    // xwindow_set_shape(drawin->window,
    //         drawin->geometry.width + 2*drawin->border_width,
    //         drawin->geometry.height + 2*drawin->border_width,
    //         XCB_SHAPE_SK_INPUT, surf, -drawin->border_width);
    _ = Object.emitSignal(state, -3, "property::shape_input", 0);
    return 0;
}

fn getDrawable(state: *lua.Lua, obj: *Object) i32 {
    const drawin = fromObj(obj);
    return Object.pushItem(state, -2, drawin.drawable);
}
fn get_visible(state: *lua.Lua, obj: *Object) i32 {
    const drawin = fromObj(obj);
    state.pushBoolean(drawin.visible);
    return 1;
}
/// Set a drawin visible or not.
/// \param L The Lua VM state.
/// \param udx The drawin.
/// \param v The visible value.
fn set_visible(state: *lua.Lua, obj: *Object) i32 {
    const drawin = fromObj(obj);
    const v = state.toBoolean(-1);
    const udx: i32 = -3;
    if (v != drawin.visible) {
        drawin.visible = v;

        if (drawin.visible) {
            map(drawin, state, udx);
            // duplicate drawin
            state.pushValue(udx);
            // ref it
            _ = Object.refClass(state, -1, &drawin_class);
        } else {
            // Active BMA */
            // client_ignore_enterleave_events();
            // Unmap window */
            drawin.unmap();
            // Active BMA */
            // client_restore_enterleave_events();
            // unref it */
            Object.unref(state, drawin);
        }

        Object.emitSignal(state, udx, "property::visible", 0);
        if (drawin.window.strut.hasValue()) {
            Screen.updateWorkarea(Screen.getByCoord(drawin.geometry.x, drawin.geometry.y) orelse unreachable, state);
        }
    }
    return 0;
}
fn get_ontop(state: *lua.Lua, obj: *Object) i32 {
    const drawin = fromObj(obj);
    state.pushBoolean(drawin.ontop);
    return 1;
}
/// Set the drawin on top status.
/// \param L The Lua VM state.
/// \param drawin The drawin object.
/// \return The number of elements pushed on stack.
///
fn set_ontop(state: *lua.Lua, obj: *Object) i32 {
    const drawin = fromObj(obj);
    const b = lib.checkBoolean(state, -1);
    if (b != drawin.ontop) {
        drawin.ontop = b;
        log.warn("drawin.set_ontop missing translation for `stack_windows`", .{});
        // stack_windows();
        Object.emitSignal(state, -3, "property::ontop", 0);
    }
    return 0;
}
fn get_cursor(state: *lua.Lua, obj: *Object) i32 {
    const drawin = fromObj(obj);
    _ = state.pushString(drawin.cursor);
    return 1;
}
/// Set the drawin cursor.
/// \param L The Lua VM state.
/// \param drawin The drawin object.
/// \return The number of elements pushed on stack.
///
fn set_cursor(state: *lua.Lua, obj: *Object) i32 {
    const drawin = fromObj(obj);
    const buf = state.checkString(-1);
    const cursor_font = cursor_lib.fontFromStr(buf);
    if (cursor_font) |_| {
        globals.gpa.free(drawin.cursor);
        drawin.cursor = globals.gpa.dupe(u8, buf) catch {
            log.err("OOM: Duping cursor name", .{});
            std.process.exit(242);
        };
        Object.emitSignal(state, -3, "property::cursor", 0);
    }
    return 0;
}

fn map(drawin: *Drawin, state: *lua.Lua, widx: i32) void {

    // Apply any pending changes */
    drawin.applyMoveResize();
    // Activate BMA */
    zanylua.warn(state, "Missing implementation inside drawin.map", .{});
    // client_ignore_enterleave_events();
    // Map the drawin */
    // xcb_map_window(globalconf.connection, drawin.window);
    // Deactivate BMA */
    // client_restore_enterleave_events();
    // Stack this drawin correctly */
    // stack_windows();
    // Add it to the list of visible drawins */
    globals.drawins.append(globals.gpa, drawin) catch {
        log.err("OOM: cannot append drawin", .{});
        std.process.exit(242);
    };
    // Make sure it has a surface */
    if (drawin.drawable.surface == null) drawin.updateDrawing(state, widx);
}

fn unmap(drawin: *Drawin) void {
    // xcb_unmap_window(globalconf.connection, drawin->window);
    for (globals.drawins.items, 0..) |d, i| {
        if (d == drawin) {
            _ = globals.drawins.swapRemove(i);
            break;
        }
    }
}

/// Refresh the window content by copying its pixmap data to its window.
/// \param drawin The drawin to refresh.
/// \param x The copy starting point x component.
/// \param y The copy starting point y component.
/// \param w The copy width from the x component.
/// \param h The copy height from the y component.
///
/// From: drawin_refresh_pixmap_partial
fn refreshPixmapPartial(drawin: *Drawin, x: i32, y: i32, w: u32, h: u32) void {
    _ = x;
    _ = y;
    _ = w;
    _ = h;
    // if (!drawin->drawable || !drawin->drawable->pixmap || !drawin->drawable->refreshed)
    if (!drawin.drawable.refreshed)
        return;

    // Make sure it really has the size it should have
    drawin.applyMoveResize();

    // Make cairo do all pending drawing
    @breakpoint();
    zanylua.warn(globals.getLuaState(), "Need to implement flushing and copying in `refreshPixmapPartial`", .{});
    // cairo_surface_flush(drawin->drawable->surface);
    // xcb_copy_area(globalconf.connection, drawin->drawable->pixmap,
    //               drawin->window, globalconf.gc, x, y, x, y,
    //               w, h);
}
