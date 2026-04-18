const std = @import("std");
const lua = @import("lua");
const lib = @import("lib.zig");
const defaults = @import("../defaults.zig");
const globals = @import("../globals.zig");
const Object = @import("../object/Object.zig");
const Screen = @import("../object/Screen.zig");

var miss_index_handler = lua.ref_nil;
var miss_newindex_handler = lua.ref_nil;

pub const methods = [_]lua.FnReg{
    .{ .name = "__index", .func = lua.wrap(index) },
    .{ .name = "__newindex", .func = lua.wrap(newindex) },
    .{ .name = "coords", .func = lua.wrap(coords) },
    .{ .name = "object_under_pointer", .func = lua.wrap(object_under_pointer) },
    .{ .name = "set_index_miss_handler", .func = lua.wrap(set_index_miss_handler) },
    .{ .name = "set_newindex_miss_handler", .func = lua.wrap(set_newindex_miss_handler) },
};
pub const meta = [_]lua.FnReg{};

///* Mouse library.
/// \param L The Lua VM state.
/// \return The number of elements pushed on stack.
/// \luastack
/// \lfield coords Mouse coordinates.
/// \lfield screen Mouse screen.
///
fn index(state: *lua.Lua) i32 {
    const attr = state.checkString(2);
    //attr is not "screen"?!
    if (!std.mem.eql(u8, attr, "screen")) {
        if (miss_index_handler != lua.ref_nil) {
            return lib.callHandler(state, miss_index_handler);
        } else {
            return defaults.index(state);
        }
    }
    const pointer = queryPointerRoot(state) catch {
        // Nothing ever handles mouse.screen being nil. Lying is better than
        // having lots of lua errors in this case.
        if (globals.focus.client) |client| {
            _ = Object.push(state, client.screen.?);
        } else {
            _ = Object.push(state, Screen.getPrimary(state).?);
        }

        return 1;
    };
    return Object.push(state, Screen.getByCoord(pointer.x, pointer.y).?);
}
fn newindex(state: *lua.Lua) i32 {
    _ = state;
    std.debug.panic("mouse.__newindex not implemented", .{});
    return 0;
}
fn coords(state: *lua.Lua) i32 {
    _ = state;
    std.debug.panic("mouse.coords not implemented", .{});
    return 0;
}
fn object_under_pointer(state: *lua.Lua) i32 {
    _ = state;
    std.debug.panic("mouse.object_under_pointer not implemented", .{});
    return 0;
}
fn set_index_miss_handler(state: *lua.Lua) i32 {
    return lib.registerFct(state, 1, &miss_index_handler);
}
fn set_newindex_miss_handler(state: *lua.Lua) i32 {
    return lib.registerFct(state, 1, &miss_newindex_handler);
}

const MouseState = struct {
    x: i16,
    y: i16,
    buttons: u32 = 0,
};

///* Get the pointer position on the screen.
/// \param x This will be set to the Pointer-x-coordinate relative to window.
/// \param y This will be set to the Pointer-y-coordinate relative to window.
/// \param child This will be set to the window under the pointer.
/// \param mask This will be set to the current buttons state.
/// \return True on success, false if an error occurred.
////
fn queryPointerRoot(state: *lua.Lua) !MouseState {
    const zany = lib.getZany(state);
    var seat_iter = zany.wm.seats.iterator(.forward);
    while (seat_iter.next()) |seat| {
        if (seat.cursor) |cursor| {
            return .{
                .x = @intCast(cursor.position.x),
                .y = @intCast(cursor.position.y),
            };
        }
    }
    return error.NoPointerFound;
}
