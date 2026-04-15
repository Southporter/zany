const std = @import("std");
const lua = @import("lua");
const cairo = @import("cairo");
const zanylib = @import("lib.zig");
const luaZ = @import("../lua.zig");
const cursorlib = @import("./cursor.zig");
const CursorShape = @import("wayland").client.wp.CursorShapeDeviceV1.Shape;
const Area = @import("../common/Area.zig");
const globals = @import("../globals.zig");
const Object = @import("../object/Object.zig");
const log = std.log.scoped(.root);

pub const lib = [_]lua.FnReg{
    .{ .name = "buttons", .func = lua.wrap(buttons) },
    .{ .name = "keys", .func = lua.wrap(keys) },
    .{ .name = "cursor", .func = lua.wrap(cursor) },
    .{ .name = "fake_input", .func = lua.wrap(fake_input) },
    .{ .name = "drawins", .func = lua.wrap(drawins) },
    .{ .name = "wallpaper", .func = lua.wrap(wallpaper) },
    .{ .name = "size", .func = lua.wrap(size) },
    .{ .name = "size_mm", .func = lua.wrap(size_mm) },
    .{ .name = "tags", .func = lua.wrap(tags) },
    .{ .name = "__index", .func = lua.wrap(index) },
    .{ .name = "__newindex", .func = lua.wrap(newindex) },
    // .{ .name = "set_index_miss_handler", .func = lua.wrap(set_index_miss_handler) },
    // .{ .name = "set_call_handler", .func = lua.wrap(set_call_handler) },
    // .{ .name = "set_newindex_miss_handler", .func = lua.wrap(set_newindex_miss_handler) },
};

fn buttons(state: *lua.Lua) i32 {
    _ = state;
    std.debug.panic("root.buttons not implemented", .{});
    return 0;
}
fn keys(state: *lua.Lua) i32 {
    _ = state;
    std.debug.panic("root.keys not implemented", .{});
    return 0;
}

// Set the root cursor
//
// The possible values are:
//
//@DOC_cursor_c_COMMON@
//
// @param cursor_name A X cursor name.
// @function cursor
//
fn cursor(state: *lua.Lua) i32 {
    const cursor_name = state.checkString(1);
    // TODO: add translation from awesome cursors to CursorShape
    const cursor_shape = cursorlib.nameToShape(cursor_name) catch {
        luaZ.warn(state, "invalid cursor {s}", .{cursor_name});
        return 0;
    };

    log.debug("Changing cursor shape to {t}", .{cursor_shape});
    const zany = zanylib.getZany(state);
    var seat_iter = zany.wm.seats.iterator(.forward);
    while (seat_iter.next()) |seat| {
        if (seat.cursor) |device| {
            const id = device.pointer.getVersion();
            device.shape_device.setShape(id, cursor_shape);
        }
    }
    return 0;
}

fn fake_input(state: *lua.Lua) i32 {
    _ = state;
    std.debug.panic("root.fake_input not implemented", .{});
    return 0;
}

fn drawins(state: *lua.Lua) i32 {
    _ = state;
    std.debug.panic("root.drawins not implemented", .{});
    return 0;
}

fn setWallpaper(state: *lua.Lua, pattern: *cairo.cairo_pattern_t) bool {
    const zany = zanylib.getZany(state);
    const shell = zany.wm.root_shell;

    const surface = cairo.cairo_image_surface_create_for_data(shell.buffer.data.ptr, cairo.CAIRO_FORMAT_ARGB32, @intCast(shell.width), @intCast(shell.height), @intCast(shell.width * 4));
    const cr = cairo.cairo_create(surface);
    cairo.cairo_set_source(cr, pattern);
    cairo.cairo_set_operator(cr, cairo.CAIRO_OPERATOR_SOURCE);
    cairo.cairo_paint(cr);
    cairo.cairo_destroy(cr);
    cairo.cairo_surface_flush(surface);

    shell.surface.attach(shell.buffer.handle, 0, 0);
    shell.surface.commit();

    cairo.cairo_surface_destroy(globals.wallpaper);
    globals.wallpaper = surface;
    globals.signals.emit(state, "wallpaper_changed", 0);
    return true;
}

/// Get the wallpaper as a cairo surface or set it as a cairo pattern.
///
/// @param pattern A cairo pattern as light userdata
/// @return A cairo surface or nothing.
/// @function wallpaper
///
fn wallpaper(state: *lua.Lua) i32 {
    @breakpoint();
    if (state.getTop() == 1) {
        const pattern = state.toUserdata(cairo.cairo_pattern_t, -1) catch |err| {
            log.warn("Error getting wallpaper userdata: {t}", .{err});
            return 0;
        };
        state.pushBoolean(setWallpaper(state, pattern));
        return 1;
    }

    if (globals.wallpaper) |wp| {
        state.pushLightUserdata(cairo.cairo_surface_reference(wp));
        return 1;
    }
    return 0;
}

fn get_content(state: *lua.Lua) i32 {
    _ = state;
    std.debug.panic("root.get_content not implemented", .{});
    return 0;
}

fn getRootSize(state: *lua.Lua) Area {
    const zany = zanylib.getZany(state);
    const shell = zany.wm.root_shell;
    return .{
        .x = 0,
        .y = 0,
        .width = shell.width,
        .height = shell.height,
    };
}

fn size(state: *lua.Lua) i32 {
    const root = getRootSize(state);
    state.pushInteger(root.width);
    state.pushInteger(root.height);
    return 2;
}

fn size_mm(state: *lua.Lua) i32 {
    // TODO: Figure out how to get this from river
    // For now, push 0 as the MM for width and height
    state.pushInteger(0);
    state.pushInteger(0);
    return 2;
}

/// Get the attached tags.
/// @return A table with all tags.
/// @function tags
///
fn tags(state: *lua.Lua) i32 {
    state.createTable(@intCast(globals.tags.items.len), 0);
    for (globals.tags.items, 1..) |tag, i| {
        _ = Object.push(state, tag);
        state.rawSetIndex(-2, @intCast(i));
    }
    return 1;
}

fn index(state: *lua.Lua) i32 {
    _ = state;
    std.debug.panic("root.index not implemented", .{});
    return 0;
}

fn newindex(state: *lua.Lua) i32 {
    _ = state;
    std.debug.panic("root.newindex not implemented", .{});
    return 0;
}

fn set_index_miss_handler(state: *lua.Lua) i32 {
    _ = state;
    std.debug.panic("root.set_index_miss_handler not implemented", .{});
    return 0;
}

fn set_call_handler(state: *lua.Lua) i32 {
    _ = state;
    std.debug.panic("root.set_call_handler not implemented", .{});
    return 0;
}

fn set_newindex_miss_handler(state: *lua.Lua) i32 {
    _ = state;
    std.debug.panic("root.set_newindex_miss_handler not implemented", .{});
    return 0;
}
