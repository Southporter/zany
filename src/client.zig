const std = @import("std");
const lua = @import("lua");
const lib = @import("lua/lib.zig");
const Window = @import("window.zig");
const Screen = @import("screen.zig");
const Class = @import("lua/Class.zig");
const Object = @import("lua/Object.zig");

const Client = @This();

// WINDOW_OBJECT_HEADER
window: Window,

// Client logical screen
screen: *Screen,
// Client name
name: ?[:0]const u8 = null,
alt_name: ?[:0]const u8 = null,
icon_name: ?[:0]const u8 = null,
alt_icon_name: ?[:0]const u8 = null,
// WM_CLASS stuff
class: ?[:0]const u8 = null,
instance: ?[:0]const u8 = null,
// /** Window we use for input focus and no-input clients
// xcb_window_t nofocus_window;
// /** Window geometry
// area_t geometry;
// /** Old window geometry currently configured in X11
// area_t x11_client_geometry;
// area_t x11_frame_geometry;
// /** Got a configure request and have to call client_send_configure() if its ignored?
got_configure_request: bool = false,
// Startup ID
startup_id: ?[:0]const u8 = null,
// True if the client is sticky
sticky: bool = false,
// Has urgency hint
urgent: bool = false,
// True if the client is hidden
hidden: bool = false,
// True if the client is minimized
minimized: bool = false,
// True if the client is fullscreen
fullscreen: bool = false,
// True if the client is maximized horizontally
maximized_horizontal: bool = false,
// True if the client is maximized vertically
maximized_vertical: bool = false,
// True if the client is maximized both horizontally and vertically by the the user
maximized: bool = false,
// True if the client is above others
above: bool = false,
// True if the client is below others
below: bool = false,
// True if the client is modal
modal: bool = false,
// True if the client is on top
ontop: bool = false,
// True if a client is banned to a position outside the viewport.
// Note that the geometry remains unchanged and that the window is still mapped.

isbanned: bool = false,
// true if the client must be skipped from task bar client list
skip_taskbar: bool = false,
// True if the client cannot have focus
nofocus: bool = false,
// True if the client is focusable.  Overrides nofocus, and can be set from Lua.
focusable: bool = false,
focusable_set: bool = false,
// True if the client window has a _NET_WM_WINDOW_TYPE proeprty
has_NET_WM_WINDOW_TYPE: bool = false,
// /** Window of the group leader */
// xcb_window_t group_window;
// /** Window holding command needed to start it (session management related) */
// xcb_window_t leader_window;
// /** Client's WM_PROTOCOLS property */
// xcb_icccm_get_wm_protocols_reply_t protocols;
// /** Key bindings */
// key_array_t keys;
// /** Icons */
// cairo_surface_array_t icons;
// /** True if we ever got an icon from _NET_WM_ICON */
// bool have_ewmh_icon;
// /** Size hints */
// xcb_size_hints_t size_hints;
// /** The visualtype that c->window uses */
// xcb_visualtype_t *visualtype;
// /** Do we honor the client's size hints? */
// bool size_hints_honor;
// /** Machine the client is running on. */
// char *machine;
// /** Role of the client */
// char *role;
// /** Client pid */
// uint32_t pid;
// /** Window it is transient for */
// client_t *transient_for;
// /** Value of WM_TRANSIENT_FOR */
// xcb_window_t transient_for_window;
// /** Titelbar information */
// struct {
//     /** The size of this bar. */
//     uint16_t size;
//     /** The drawable for this bar. */
//     drawable_t *drawable;
// } titlebar[CLIENT_TITLEBAR_COUNT];
// /** Motif WM hints, with an additional MWM_HINTS_AWESOME_SET bit */
// motif_wm_hints_t motif_wm_hints;

var client_class: Class = .{
    .allocator = new,
    .collector = wipe,
    .checker = checker,
    .parent = window.window_class,
};

pub fn setup(state: *lua.Lua) !void {
    const methods = [_]lua.FnReg{
        .{ .name = "get", .func = lua.wrap(get) },
        .{ .name = "__index", .func = lua.wrap(moduleIndex) },
        .{ .name = "__newindex", .func = lua.wrap(moduleNewindex) },
    };
    const meta = [_]lua.FnReg{
        .{ .name = "_keys", .func = lua.wrap(keys) },
        .{ .name = "isvisible", .func = lua.wrap(isvisible) },
        .{ .name = "geometry", .func = lua.wrap(geometry) },
        .{ .name = "apply_size_hints", .func = lua.wrap(apply_size_hints) },
        .{ .name = "tags", .func = lua.wrap(tags) },
        .{ .name = "kill", .func = lua.wrap(kill) },
        .{ .name = "swap", .func = lua.wrap(swap) },
        .{ .name = "raise", .func = lua.wrap(raise) },
        .{ .name = "lower", .func = lua.wrap(lower) },
        .{ .name = "unmanage", .func = lua.wrap(unmanage) },
        .{ .name = "titlebar_top", .func = lua.wrap(titlebar_top) },
        .{ .name = "titlebar_right", .func = lua.wrap(titlebar_right) },
        .{ .name = "titlebar_bottom", .func = lua.wrap(titlebar_bottom) },
        .{ .name = "titlebar_left", .func = lua.wrap(titlebar_left) },
        .{ .name = "get_icon", .func = lua.wrap(get_some_icon) },
    };
    return client_class.setup(state, &methods, &meta);
}

fn new(state: *lua.Lua) ?*Object {
    return client_class.create(Client, state);
}

fn wipe(obj: *Object) void {}

fn get(state: *lua.Lua) i32 {
    _ = state;
    std.debug.panic("client `get` not implemented", .{});
    return 0;
}

fn moduleIndex(state: *lua.Lua) i32 {
    _ = state;
    std.debug.panic("client `index` not implemented", .{});
    return 0;
}
fn moduleNewindex(state: *lua.Lua) i32 {
    _ = state;
    std.debug.panic("client `newindex` not implemented", .{});
    return 0;
}
fn keys(state: *lua.Lua) i32 {
    _ = state;
    std.debug.panic("client `keys` not implemented", .{});
    return 0;
}
fn isvisible(state: *lua.Lua) i32 {
    _ = state;
    std.debug.panic("client `isvisible` not implemented", .{});
    return 0;
}
fn geometry(state: *lua.Lua) i32 {
    _ = state;
    std.debug.panic("client `geometry` not implemented", .{});
    return 0;
}
fn apply_size_hints(state: *lua.Lua) i32 {
    _ = state;
    std.debug.panic("client `apply_size_hints` not implemented", .{});
    return 0;
}
fn tags(state: *lua.Lua) i32 {
    _ = state;
    std.debug.panic("client `tags` not implemented", .{});
    return 0;
}
fn kill(state: *lua.Lua) i32 {
    _ = state;
    std.debug.panic("client `kill` not implemented", .{});
    return 0;
}
fn swap(state: *lua.Lua) i32 {
    _ = state;
    std.debug.panic("client `swap` not implemented", .{});
    return 0;
}
fn raise(state: *lua.Lua) i32 {
    _ = state;
    std.debug.panic("client `raise` not implemented", .{});
    return 0;
}
fn lower(state: *lua.Lua) i32 {
    _ = state;
    std.debug.panic("client `lower` not implemented", .{});
    return 0;
}
fn unmanage(state: *lua.Lua) i32 {
    _ = state;
    std.debug.panic("client `unmanage` not implemented", .{});
    return 0;
}
fn titlebar_top(state: *lua.Lua) i32 {
    _ = state;
    std.debug.panic("client `titlebar_top` not implemented", .{});
    return 0;
}
fn titlebar_right(state: *lua.Lua) i32 {
    _ = state;
    std.debug.panic("client `titlebar_right` not implemented", .{});
    return 0;
}
fn titlebar_bottom(state: *lua.Lua) i32 {
    _ = state;
    std.debug.panic("client `titlebar_bottom` not implemented", .{});
    return 0;
}
fn titlebar_left(state: *lua.Lua) i32 {
    _ = state;
    std.debug.panic("client `titlebar_left` not implemented", .{});
    return 0;
}
fn get_some_icon(state: *lua.Lua) i32 {
    _ = state;
    std.debug.panic("client `get_some_icon` not implemented", .{});
    return 0;
}
