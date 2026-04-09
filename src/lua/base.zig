const std = @import("std");
const lua = @import("lua");
const zanylib = @import("lib.zig");
const luaZ = @import("../lua.zig");
const cursorlib = @import("./cursor.zig");
const CursorShape = @import("wayland").client.wp.CursorShapeDeviceV1.Shape;
const log = std.log.scoped(.root);

pub const lib = [_]lua.FnReg{
    .{ .name = "_buttons", .func = lua.wrap(buttons) },
    .{ .name = "_keys", .func = lua.wrap(keys) },
    .{ .name = "cursor", .func = lua.wrap(cursor) },
    .{ .name = "fake_input", .func = lua.wrap(fake_input) },
    .{ .name = "drawins", .func = lua.wrap(drawins) },
    .{ .name = "_wallpaper", .func = lua.wrap(wallpaper) },
    .{ .name = "content", .func = lua.wrap(get_content) },
    .{ .name = "size", .func = lua.wrap(size) },
    .{ .name = "size_mm", .func = lua.wrap(size_mm) },
    .{ .name = "tags", .func = lua.wrap(tags) },
    .{ .name = "__index", .func = lua.wrap(index) },
    .{ .name = "__newindex", .func = lua.wrap(newindex) },
    .{ .name = "set_index_miss_handler", .func = lua.wrap(set_index_miss_handler) },
    .{ .name = "set_call_handler", .func = lua.wrap(set_call_handler) },
    .{ .name = "set_newindex_miss_handler", .func = lua.wrap(set_newindex_miss_handler) },
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

fn wallpaper(state: *lua.Lua) i32 {
    _ = state;
    std.debug.panic("root.wallpaper not implemented", .{});
    return 0;
}

fn get_content(state: *lua.Lua) i32 {
    _ = state;
    std.debug.panic("root.get_content not implemented", .{});
    return 0;
}

fn size(state: *lua.Lua) i32 {
    const zany = zanylib.getZany(state);
    const root = zany.wm.outputs.first() orelse {
        std.debug.panic("No outputs found", .{});
    };
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

fn tags(state: *lua.Lua) i32 {
    _ = state;
    std.debug.panic("root.tags not implemented", .{});
    return 0;
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
