const std = @import("std");
const Signal = @import("Signal.zig");
const Screen = @import("screen.zig");
const Client = @import("client.zig");

pub var signals: std.ArrayList(Signal) = .empty;
pub var screens: std.ArrayList(*Screen) = .empty;
pub var clients: std.ArrayList(*Client) = .empty;
pub var stack: std.ArrayList(*Client) = .empty;
pub var gpa: std.mem.Allocator = undefined;
