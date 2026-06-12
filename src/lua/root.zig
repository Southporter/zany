const std = @import("std");
const lua = @import("lua");
const c = @import("deps");
const zanylib = @import("lib.zig");
const luaZ = @import("../lua.zig");
const defaults = @import("../defaults.zig");
const cursorlib = @import("./cursor.zig");
const CursorShape = @import("wayland").client.wp.CursorShapeDeviceV1.Shape;
const Area = @import("../common/Area.zig");
const globals = @import("../globals.zig");
const Object = @import("../object/Object.zig");
const Button = @import("../object/Button.zig");
const Key = @import("../object/Key.zig");
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
    .{ .name = "__index", .func = lua.wrap(defaults.index) },
    .{ .name = "__newindex", .func = lua.wrap(defaults.newindex) },
    // .{ .name = "set_index_miss_handler", .func = lua.wrap(set_index_miss_handler) },
    // .{ .name = "set_call_handler", .func = lua.wrap(set_call_handler) },
    // .{ .name = "set_newindex_miss_handler", .func = lua.wrap(set_newindex_miss_handler) },
};

/// Get or set global mouse bindings.
/// This binding will be available when you click on the root window.
///
/// @param button_table An array of mouse button bindings objects, or nothing.
/// @return The array of mouse button bindings objects.
/// @function buttons
///
fn buttons(state: *lua.Lua) i32 {
    if (state.getTop() == 1) {
        zanylib.checkTable(state, 1);

        for (globals.buttons.items) |button| {
            Object.unref(state, button);
        }
        globals.buttons.clearRetainingCapacity();
        state.pushNil();

        while (state.next(1)) {
            const button_raw = Object.ref(state, -1) orelse unreachable;
            const button: *Button = @ptrCast(@alignCast(button_raw));
            globals.buttons.append(globals.gpa, button) catch {
                std.debug.panic("OOM in root.buttons", .{});
            };
        }
        return 1;
    }

    state.createTable(@intCast(globals.buttons.items.len), 0);
    for (globals.buttons.items, 1..) |button, i| {
        _ = Object.push(state, button);
        state.rawSetIndex(-2, @intCast(i));
    }
    return 1;
}

/// Get or set global key bindings.
/// These bindings will be available when you press keys on the root window.
///
/// @tparam table|nil keys_array An array of key binding objects, or nothing.
/// @return The array of key bindings objects of this client.
/// @function keys
///
fn keys(state: *lua.Lua) i32 {
    // if(lua_gettop(L) == 1)
    if (state.getTop() == 1) {
        zanylib.checkTable(state, 1);

        for (globals.keys.items) |key| {
            Object.unref(state, key);
        }
        globals.keys.clearRetainingCapacity();
        state.pushNil();
        while (state.next(1)) {
            const key_raw = Object.refClass(state, -1, &Key.key_class) orelse unreachable;
            const key: *Key = @ptrCast(@alignCast(key_raw));
            globals.keys.append(globals.gpa, key) catch {
                log.err("OOM: Failed to add global keybind: {any}", .{key});
            };
        }

        const zany = zanylib.getZany(state);
        zany.wm.unbindAll();
        for (globals.keys.items) |k| {
            zany.wm.bind(k.*) catch {
                log.err("OOM: Failed to bind key: {any}", .{k});
            };
        }

        return 1;
    }

    state.createTable(@intCast(globals.keys.items.len), 0);
    for (globals.keys.items, 1..) |key, i| {
        _ = Object.push(state, key);
        state.rawSetIndex(-2, @intCast(i));
    }
    return 1;
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

fn setWallpaper(state: *lua.Lua, pattern: *c.cairo_pattern_t) bool {
    const zany = zanylib.getZany(state);
    const shell = zany.wm.root_shell;
    const s = shell.size();

    const surface = c.cairo_image_surface_create_for_data(shell.buffer.data.ptr, c.CAIRO_FORMAT_ARGB32, @intCast(s.width), @intCast(s.height), @intCast(s.width * 4));
    const cr = c.cairo_create(surface);
    c.cairo_set_source(cr, pattern);
    c.cairo_set_operator(cr, c.CAIRO_OPERATOR_SOURCE);
    c.cairo_paint(cr);
    c.cairo_destroy(cr);
    c.cairo_surface_flush(surface);

    shell.surface.attach(shell.buffer.handle, 0, 0);
    shell.surface.commit();

    c.cairo_surface_destroy(globals.wallpaper);
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
    if (state.getTop() == 1) {
        const pattern = state.toUserdata(c.cairo_pattern_t, -1) catch |err| {
            log.warn("Error getting wallpaper userdata: {t}", .{err});
            return 0;
        };
        state.pushBoolean(setWallpaper(state, pattern));
        return 1;
    }

    if (globals.wallpaper) |wp| {
        state.pushLightUserdata(c.cairo_surface_reference(wp).?);
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
    const s = shell.size();
    return .{
        .x = 0,
        .y = 0,
        .width = @intCast(s.width),
        .height = @intCast(s.height),
    };
}

fn size(state: *lua.Lua) i32 {
    const root = getRootSize(state);
    state.pushInteger(root.width);
    state.pushInteger(root.height);
    return 2;
}

fn size_mm(state: *lua.Lua) i32 {
    const zany = zanylib.getZany(state);
    var total_height: i32 = 0;
    var total_width: i32 = 0;
    var iter = zany.wm.outputs.iterator(.forward);
    while (iter.next()) |viewport| {
        total_height += viewport.size.height_mm;
        total_width += viewport.size.width_mm;
    }
    state.pushInteger(total_width);
    state.pushInteger(total_height);
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
