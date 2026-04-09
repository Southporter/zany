const std = @import("std");
const lua = @import("lua");
const lib = @import("lib.zig");

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

fn index(state: *lua.Lua) i32 {
    _ = state;
    std.debug.panic("mouse.__index not implemented", .{});
    return 0;
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
