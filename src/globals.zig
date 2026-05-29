const std = @import("std");
const lua = @import("lua");
const c = @import("deps");
const Signals = @import("Signals.zig");
const Screen = @import("object/Screen.zig");
const Client = @import("object/Client.zig");
const Drawin = @import("object/Drawin.zig");
const Button = @import("object/Button.zig");
const Key = @import("object/Key.zig");
const Tag = @import("object/Tag.zig");

pub var signals: Signals = .{};
pub var primary_screen: ?*Screen = null;
pub var screens: std.ArrayList(*Screen) = .empty;
pub var clients: std.ArrayList(*Client) = .empty;
pub var drawins: std.ArrayList(*Drawin) = .empty;
pub var tags: std.ArrayList(*Tag) = .empty;
pub var buttons: std.ArrayList(*Button) = .empty;
pub var keys: std.ArrayList(*Key) = .empty;
pub var stack: std.ArrayList(*Client) = .empty;
pub var gpa: std.mem.Allocator = undefined;

pub var wallpaper: ?*c.cairo_surface_t = null;
pub var focus: struct {
    client: ?*Client = null,
    need_update: bool = false,
} = .{};

var lua_state: struct {
    real_state_dont_use_directly: *lua.Lua = undefined,
} = .{};

/// You should always use this as lua_State *L = globalconf_get_lua_State().
/// That way it becomes harder to introduce coroutine-related problems.
pub fn getLuaState() *lua.Lua {
    return lua_state.real_state_dont_use_directly;
}
