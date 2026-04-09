const std = @import("std");
const wayland = @import("wayland");
const DecorationHint = wayland.client.river.WindowV1.DecorationHint;

min_width: i32 = 0,
max_width: i32 = std.math.maxInt(i32),

min_height: i32 = 0,
max_height: i32 = std.math.maxInt(i32),
decoration: DecorationHint = .no_preference,
