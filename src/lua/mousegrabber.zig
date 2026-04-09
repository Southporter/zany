const std = @import("std");
const lua = @import("lua");
const defaults = @import("../defaults.zig");

pub const lib = [_]lua.FnReg{
    .{ .name = "run", .func = lua.wrap(run) },
    .{ .name = "stop", .func = lua.wrap(stop) },
    .{ .name = "isrunning", .func = lua.wrap(isrunning) },
    .{ .name = "__index", .func = lua.wrap(defaults.index) },
    .{ .name = "__newindex", .func = lua.wrap(defaults.newindex) },
};
fn run(state: *lua.Lua) i32 {
    _ = state;
    std.debug.panic("Mousegrabber run not implemented", .{});
    return 0;
}
fn stop(state: *lua.Lua) i32 {
    _ = state;
    std.debug.panic("Mousegrabber stop not implemented", .{});
    return 0;
}
fn isrunning(state: *lua.Lua) i32 {
    _ = state;
    std.debug.panic("Mousegrabber isrunning not implemented", .{});
    return 0;
}
