//! By convention, root.zig is the root source file when making a library.
const std = @import("std");
const lua = @import("lua");
const WindowManager = @import("WindowManager.zig");

const Lua = lua.Lua;

const Zany = @This();

vm: *Lua,
wm: WindowManager,


pub fn init(gpa: std.mem.Allocator) !Zany {
    var wm = gpa.create()

}

pub fn test(gpa: std.mem.Allocator, file: []const u8) !void {
}

