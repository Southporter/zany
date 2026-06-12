const std = @import("std");
const lua = @import("lua");
const lib = @import("../lua/lib.zig");
const Strut = @This();

left: u16 = 0,
right: u16 = 0,
top: u16 = 0,
bottom: u16 = 0,

left_start_y: u16 = 0,
left_end_y: u16 = 0,
right_start_y: u16 = 0,
right_end_y: u16 = 0,

top_start_x: u16 = 0,
top_end_x: u16 = 0,

bottom_start_x: u16 = 0,
bottom_end_x: u16 = 0,

///* Push a strut type to a table on stack.
/// \param L The Lua VM state.
/// \param strut The strut to push.
/// \return The number of elements pushed on stack.
pub fn push(strut: *Strut, state: *lua.Lua) i32 {
    state.createTable(4, 0);
    state.pushInteger(strut.left);
    state.setField(-2, "left");
    state.pushInteger(strut.right);
    state.setField(-2, "right");
    state.pushInteger(strut.top);
    state.setField(-2, "top");
    state.pushInteger(strut.bottom);
    state.setField(-2, "bottom");
    return 1;
}

pub fn load(strut: *Strut, state: *lua.Lua, idx: i32) void {
    lib.checkTable(state, idx);
    const max: f32 = @floatFromInt(std.math.maxInt(u16));
    strut.left = @intFromFloat(@ceil(lib.getOptNumberRange(state, idx, "left", @floatFromInt(strut.left), 0, max)));
    strut.right = @intFromFloat(@ceil(lib.getOptNumberRange(state, idx, "right", @floatFromInt(strut.right), 0, max)));
    strut.top = @intFromFloat(@ceil(lib.getOptNumberRange(state, idx, "top", @floatFromInt(strut.top), 0, max)));
    strut.bottom = @intFromFloat(@ceil(lib.getOptNumberRange(state, idx, "bottom", @floatFromInt(strut.bottom), 0, max)));
}

pub fn hasValue(strut: *Strut) bool {
    var non_zero = false;
    inline for (std.meta.fields(Strut)) |field| {
        if (@field(strut, field.name) == 0) {
            non_zero = true;
            break;
        }
    }
    return non_zero;
}
