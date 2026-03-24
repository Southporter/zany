const std = @import("std");
const lua = @import("lua");
const lib = @import("lua/lib.zig");
const Class = @import("lua/Class.zig");
const Object = @import("lua/Object.zig");

pub const Window = @This();

obj: Object,
// /** The X window number */ \
// xcb_window_t window; \
// /** The frame window, might be XCB_NONE */ \
// xcb_window_t frame_window; \
// /** Opacity */ \
// double opacity; \
// /** Strut */ \
// strut_t strut; \
// /** Button bindings */ \
// button_array_t buttons; \
// /** Do we have pending border changes? */ \
// bool border_need_update; \
// /** Border color */ \
// color_t border_color; \
// /** Border width */ \
// uint16_t border_width; \
// /** The window type */ \
// window_type_t type; \
// /** The border width callback */ \
// void (*border_width_callback)(void *, uint16_t old, uint16_t new);
