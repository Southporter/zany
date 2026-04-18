const std = @import("std");
const c = @import("deps");
const Signals = @import("Signals.zig");
const Screen = @import("object/Screen.zig");
const Client = @import("object/Client.zig");
const Button = @import("object/Button.zig");
const Key = @import("object/Key.zig");
const Tag = @import("object/Tag.zig");

pub var signals: Signals = .{};
pub var primary_screen: ?*Screen = null;
pub var screens: std.ArrayList(*Screen) = .empty;
pub var clients: std.ArrayList(*Client) = .empty;
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
