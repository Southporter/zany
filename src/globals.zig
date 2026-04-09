const std = @import("std");
const Signals = @import("Signals.zig");
const Screen = @import("object/Screen.zig");
const Client = @import("object/Client.zig");

pub var signals: Signals = .{};
pub var primary_screen: ?*Screen = null;
pub var screens: std.ArrayList(*Screen) = .empty;
pub var clients: std.ArrayList(*Client) = .empty;
pub var stack: std.ArrayList(*Client) = .empty;
pub var gpa: std.mem.Allocator = undefined;
