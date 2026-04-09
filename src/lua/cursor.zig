const std = @import("std");
const CursorShape = @import("wayland").client.wp.CursorShapeDeviceV1.Shape;

// Translate Xname to Wayland cursor shape
pub fn nameToShape(name: []const u8) !CursorShape {
    if (std.mem.eql(u8, name, "left_ptr")) {
        return .default;
    }
    if (std.mem.eql(u8, name, "watch")) {
        return .wait;
    }
    return error.UnknownCursorName;
}
