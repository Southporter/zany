const std = @import("std");
const cairo = @import("cairo");
const Signals = @import("Signals.zig");
const Screen = @import("object/Screen.zig");
const Client = @import("object/Client.zig");
const Tag = @import("object/Tag.zig");

pub var signals: Signals = .{};
pub var primary_screen: ?*Screen = null;
pub var screens: std.ArrayList(*Screen) = .empty;
pub var clients: std.ArrayList(*Client) = .empty;
pub var tags: std.ArrayList(*Tag) = .empty;
pub var stack: std.ArrayList(*Client) = .empty;
pub var gpa: std.mem.Allocator = undefined;

pub var wallpaper: ?*cairo.cairo_surface_t = null;
