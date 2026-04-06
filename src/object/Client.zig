const std = @import("std");
const lua = @import("lua");
const lib = @import("../lua/lib.zig");
const globals = @import("../globals.zig");
const Window = @import("Window.zig");
const Screen = @import("Screen.zig");
const Class = @import("Class.zig");
const Object = @import("Object.zig");
const Area = @import("../common/Area.zig");

const Client = @This();

// WINDOW_OBJECT_HEADER
window: Window = .{},

// Client logical screen
screen: ?*Screen = null,
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
geometry: Area = .{},
// /** Old window geometry currently configured in X11
window_geometry: Area = .{},
frame_geometry: Area = .{},
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
//

var props = [_]Class.Property{
    .{ .name = "name", .new = set_name, .index = get_name, .newindex = set_name },
    .{
        .name = "transient_for",
        .index = get_transient_for,
    },
    .{ .name = "skip_taskbar", .new = set_skip_taskbar, .index = get_skip_taskbar, .newindex = set_skip_taskbar },
    .{
        .name = "content",
        .index = get_content,
    },
    .{
        .name = "type",
        .index = Window.get_type,
    },
    .{
        .name = "class",
        .index = get_class,
    },
    .{
        .name = "instance",
        .index = get_instance,
    },
    .{
        .name = "role",
        .index = get_role,
    },
    .{
        .name = "pid",
        .index = get_pid,
    },
    .{
        .name = "leader_window",
        .index = get_leader_window,
    },
    .{
        .name = "machine",
        .index = get_machine,
    },
    .{
        .name = "icon_name",
        .index = get_icon_name,
    },
    .{
        .name = "screen",
        .index = get_screen,
        .newindex = set_screen,
    },
    .{
        .name = "hidden",
        .new = set_hidden,
        .index = get_hidden,
        .newindex = set_hidden,
    },
    .{
        .name = "minimized",
        .new = set_minimized,
        .index = get_minimized,
        .newindex = set_minimized,
    },
    .{
        .name = "fullscreen",
        .new = set_fullscreen,
        .index = get_fullscreen,
        .newindex = set_fullscreen,
    },
    .{
        .name = "modal",
        .new = set_modal,
        .index = get_modal,
        .newindex = set_modal,
    },
    .{
        .name = "motif_wm_hints",
        .index = get_motif_wm_hints,
    },
    .{
        .name = "group_window",
        .index = get_group_window,
    },
    .{
        .name = "maximized",
        .new = set_maximized,
        .index = get_maximized,
        .newindex = set_maximized,
    },
    .{
        .name = "maximized_horizontal",
        .new = set_maximized_horizontal,
        .index = get_maximized_horizontal,
        .newindex = set_maximized_horizontal,
    },
    .{
        .name = "maximized_vertical",
        .new = set_maximized_vertical,
        .index = get_maximized_vertical,
        .newindex = set_maximized_vertical,
    },
    .{
        .name = "icon",
        .new = set_icon,
        .index = get_icon,
        .newindex = set_icon,
    },
    .{
        .name = "icon_sizes",
        .index = get_icon_sizes,
    },
    .{
        .name = "ontop",
        .new = set_ontop,
        .index = get_ontop,
        .newindex = set_ontop,
    },
    .{
        .name = "above",
        .new = set_above,
        .index = get_above,
        .newindex = set_above,
    },
    .{
        .name = "below",
        .new = set_below,
        .index = get_below,
        .newindex = set_below,
    },
    .{
        .name = "sticky",
        .new = set_sticky,
        .index = get_sticky,
        .newindex = set_sticky,
    },
    .{
        .name = "size_hints_honor",
        .new = set_size_hints_honor,
        .index = get_size_hints_honor,
        .newindex = set_size_hints_honor,
    },
    .{
        .name = "urgent",
        .new = set_urgent,
        .index = get_urgent,
        .newindex = set_urgent,
    },
    .{
        .name = "size_hints",
        .index = get_size_hints,
    },
    .{
        .name = "focusable",
        .new = set_focusable,
        .index = get_focusable,
        .newindex = set_focusable,
    },
    .{
        .name = "shape_bounding",
        .new = set_shape_bounding,
        .index = get_shape_bounding,
        .newindex = set_shape_bounding,
    },
    .{
        .name = "shape_clip",
        .new = set_shape_clip,
        .index = get_shape_clip,
        .newindex = set_shape_clip,
    },
    .{
        .name = "shape_input",
        .new = set_shape_input,
        .index = get_shape_input,
        .newindex = set_shape_input,
    },
    .{
        .name = "startup_id",
        .new = set_startup_id,
        .index = get_startup_id,
        .newindex = set_startup_id,
    },
    .{
        .name = "client_shape_bounding",
        .index = get_client_shape_bounding,
    },
    .{
        .name = "client_shape_clip",
        .index = get_client_shape_clip,
    },
    .{
        .name = "client_shape_input",
        .index = get_client_shape_input,
    },
    .{
        .name = "first_tag",
        .index = get_first_tag,
    },
};

pub var client_class: Class = .{
    .name = "client",
    .allocator = new,
    .collector = wipe,
    .checker = checker,
    .parent = &Window.window_class,
    .properties = props[0..],
    .tostring = toString,
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
        .{ .name = "geometry", .func = lua.wrap(handleGeometry) },
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
    const client = client_class.create(Client, state) orelse return null;
    return &client.window.obj;
}

fn wipe(obj: *Object) void {
    globals.gpa.destroy(from(obj));
}

fn checker(obj: *Object) bool {
    const client = from(obj);
    return client.window.window == Window.none;
}

fn toString(state: *lua.Lua, obj: *Object) i32 {
    const client = from(obj);
    const name = client.name orelse client.alt_name;
    if (name) |n| {
        if (n.len > 20) {
            _ = state.pushString(n[0..20]);
            _ = state.pushString("...");
            return 2;
        } else {
            _ = state.pushString(n);
            return 1;
        }
    } else {
        _ = state.pushString("Unknown");
        return 1;
    }
}

pub fn from(obj: *Object) *Client {
    const window: *Window = @fieldParentPtr("obj", obj);
    const client: *Client = @fieldParentPtr("window", window);
    return client;
}
// Get all clients into a table.
//
// @tparam[opt] integer|screen screen A screen number to filter clients on.
// @tparam[opt] boolean stacked Return clients in stacking order? (ordered from
//   top to bottom).
// @treturn table A table with clients.
// @staticfct get
// @usage for _, c in ipairs(client.get()) do
//     -- do something
// end
fn get(state: *lua.Lua) i32 {
    var i: i32 = 1;
    var screen: ?*Screen = null;
    var stacked = false;

    if (!state.isNoneOrNil(1)) {
        screen = Screen.checkscreen(state, 1);
    }

    if (!state.isNoneOrNil(2)) {
        stacked = lib.checkBoolean(state, 2);
    }

    state.newTable();
    if (stacked) {
        const max = globals.stack.items.len;
        for (0..max) |j| {
            const c = globals.stack.items[max - j - 1];
            if (screen == null or c.screen == screen) {
                _ = Object.push(state, c);
                state.rawSetIndex(-2, i);
                i += 1;
            }
        }
    } else {
        for (globals.clients.items) |c| {
            if (screen == null or c.screen == screen) {
                _ = Object.push(state, c);
                state.rawSetIndex(-2, i);
                i += 1;
            }
        }
    }

    return 1;
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
fn handleGeometry(state: *lua.Lua) i32 {
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

fn get_name(state: *lua.Lua, obj: *Object) i32 {
    _ = state;
    _ = obj;

    std.debug.panic("client `get_name` not implemented", .{});
    return 0;
}
fn set_name(state: *lua.Lua, obj: *Object) i32 {
    _ = state;
    _ = obj;

    std.debug.panic("client `set_name` not implemented", .{});
    return 0;
}
fn get_transient_for(state: *lua.Lua, obj: *Object) i32 {
    _ = state;
    _ = obj;

    std.debug.panic("client `get_transient_for` not implemented", .{});
    return 0;
}
fn get_skip_taskbar(state: *lua.Lua, obj: *Object) i32 {
    _ = state;
    _ = obj;

    std.debug.panic("client `get_skip_taskbar` not implemented", .{});
    return 0;
}
fn set_skip_taskbar(state: *lua.Lua, obj: *Object) i32 {
    _ = state;
    _ = obj;

    std.debug.panic("client `set_skip_taskbar` not implemented", .{});
    return 0;
}
fn get_content(state: *lua.Lua, obj: *Object) i32 {
    _ = state;
    _ = obj;

    std.debug.panic("client `get_content` not implemented", .{});
    return 0;
}
fn get_class(state: *lua.Lua, obj: *Object) i32 {
    _ = state;
    _ = obj;

    std.debug.panic("client `get_class` not implemented", .{});
    return 0;
}
fn get_instance(state: *lua.Lua, obj: *Object) i32 {
    _ = state;
    _ = obj;

    std.debug.panic("client `get_instance` not implemented", .{});
    return 0;
}
fn get_role(state: *lua.Lua, obj: *Object) i32 {
    _ = state;
    _ = obj;

    std.debug.panic("client `get_role` not implemented", .{});
    return 0;
}
fn get_pid(state: *lua.Lua, obj: *Object) i32 {
    _ = state;
    _ = obj;

    std.debug.panic("client `get_pid` not implemented", .{});
    return 0;
}
fn get_leader_window(state: *lua.Lua, obj: *Object) i32 {
    _ = state;
    _ = obj;

    std.debug.panic("client `get_leader_window` not implemented", .{});
    return 0;
}
fn get_machine(state: *lua.Lua, obj: *Object) i32 {
    _ = state;
    _ = obj;

    std.debug.panic("client `get_machine` not implemented", .{});
    return 0;
}
fn get_icon_name(state: *lua.Lua, obj: *Object) i32 {
    _ = state;
    _ = obj;

    std.debug.panic("client `get_icon_name` not implemented", .{});
    return 0;
}
fn get_screen(state: *lua.Lua, obj: *Object) i32 {
    _ = state;
    _ = obj;

    std.debug.panic("client `get_screen` not implemented", .{});
    return 0;
}
fn set_screen(state: *lua.Lua, obj: *Object) i32 {
    _ = state;
    _ = obj;

    std.debug.panic("client `set_screen` not implemented", .{});
    return 0;
}
fn get_hidden(state: *lua.Lua, obj: *Object) i32 {
    _ = state;
    _ = obj;

    std.debug.panic("client `get_hidden` not implemented", .{});
    return 0;
}
fn set_hidden(state: *lua.Lua, obj: *Object) i32 {
    _ = state;
    _ = obj;

    std.debug.panic("client `set_hidden` not implemented", .{});
    return 0;
}
fn get_minimized(state: *lua.Lua, obj: *Object) i32 {
    _ = state;
    _ = obj;

    std.debug.panic("client `get_minimized` not implemented", .{});
    return 0;
}
fn set_minimized(state: *lua.Lua, obj: *Object) i32 {
    _ = state;
    _ = obj;

    std.debug.panic("client `set_minimized` not implemented", .{});
    return 0;
}
fn get_fullscreen(state: *lua.Lua, obj: *Object) i32 {
    _ = state;
    _ = obj;

    std.debug.panic("client `get_fullscreen` not implemented", .{});
    return 0;
}
fn set_fullscreen(state: *lua.Lua, obj: *Object) i32 {
    _ = state;
    _ = obj;

    std.debug.panic("client `set_fullscreen` not implemented", .{});
    return 0;
}
fn get_modal(state: *lua.Lua, obj: *Object) i32 {
    _ = state;
    _ = obj;

    std.debug.panic("client `get_modal` not implemented", .{});
    return 0;
}
fn set_modal(state: *lua.Lua, obj: *Object) i32 {
    _ = state;
    _ = obj;

    std.debug.panic("client `set_modal` not implemented", .{});
    return 0;
}
fn get_motif_wm_hints(state: *lua.Lua, obj: *Object) i32 {
    _ = state;
    _ = obj;

    std.debug.panic("client `get_motif_wm_hints` not implemented", .{});
    return 0;
}
fn get_group_window(state: *lua.Lua, obj: *Object) i32 {
    _ = state;
    _ = obj;

    std.debug.panic("client `get_group_window` not implemented", .{});
    return 0;
}
fn get_maximized(state: *lua.Lua, obj: *Object) i32 {
    _ = state;
    _ = obj;

    std.debug.panic("client `get_maximized` not implemented", .{});
    return 0;
}
fn set_maximized(state: *lua.Lua, obj: *Object) i32 {
    _ = state;
    _ = obj;

    std.debug.panic("client `set_maximized` not implemented", .{});
    return 0;
}
fn get_maximized_horizontal(state: *lua.Lua, obj: *Object) i32 {
    _ = state;
    _ = obj;

    std.debug.panic("client `get_maximized_horizontal` not implemented", .{});
    return 0;
}
fn set_maximized_horizontal(state: *lua.Lua, obj: *Object) i32 {
    _ = state;
    _ = obj;

    std.debug.panic("client `set_maximized_horizontal` not implemented", .{});
    return 0;
}
fn get_maximized_vertical(state: *lua.Lua, obj: *Object) i32 {
    _ = state;
    _ = obj;

    std.debug.panic("client `get_maximized_vertical` not implemented", .{});
    return 0;
}
fn set_maximized_vertical(state: *lua.Lua, obj: *Object) i32 {
    _ = state;
    _ = obj;

    std.debug.panic("client `set_maximized_vertical` not implemented", .{});
    return 0;
}
fn get_icon(state: *lua.Lua, obj: *Object) i32 {
    _ = state;
    _ = obj;

    std.debug.panic("client `get_icon` not implemented", .{});
    return 0;
}
fn set_icon(state: *lua.Lua, obj: *Object) i32 {
    _ = state;
    _ = obj;

    std.debug.panic("client `set_icon` not implemented", .{});
    return 0;
}
fn get_icon_sizes(state: *lua.Lua, obj: *Object) i32 {
    _ = state;
    _ = obj;

    std.debug.panic("client `get_icon_sizes` not implemented", .{});
    return 0;
}
fn get_ontop(state: *lua.Lua, obj: *Object) i32 {
    _ = state;
    _ = obj;

    std.debug.panic("client `get_ontop` not implemented", .{});
    return 0;
}
fn set_ontop(state: *lua.Lua, obj: *Object) i32 {
    _ = state;
    _ = obj;

    std.debug.panic("client `set_ontop` not implemented", .{});
    return 0;
}
fn get_above(state: *lua.Lua, obj: *Object) i32 {
    _ = state;
    _ = obj;

    std.debug.panic("client `get_above` not implemented", .{});
    return 0;
}
fn set_above(state: *lua.Lua, obj: *Object) i32 {
    _ = state;
    _ = obj;

    std.debug.panic("client `set_above` not implemented", .{});
    return 0;
}
fn get_below(state: *lua.Lua, obj: *Object) i32 {
    _ = state;
    _ = obj;

    std.debug.panic("client `get_below` not implemented", .{});
    return 0;
}
fn set_below(state: *lua.Lua, obj: *Object) i32 {
    _ = state;
    _ = obj;

    std.debug.panic("client `set_below` not implemented", .{});
    return 0;
}
fn get_sticky(state: *lua.Lua, obj: *Object) i32 {
    _ = state;
    _ = obj;

    std.debug.panic("client `get_sticky` not implemented", .{});
    return 0;
}
fn set_sticky(state: *lua.Lua, obj: *Object) i32 {
    _ = state;
    _ = obj;

    std.debug.panic("client `set_sticky` not implemented", .{});
    return 0;
}
fn get_size_hints_honor(state: *lua.Lua, obj: *Object) i32 {
    _ = state;
    _ = obj;

    std.debug.panic("client `get_size_hints_honor` not implemented", .{});
    return 0;
}
fn set_size_hints_honor(state: *lua.Lua, obj: *Object) i32 {
    _ = state;
    _ = obj;

    std.debug.panic("client `set_size_hints_honor` not implemented", .{});
    return 0;
}
fn get_urgent(state: *lua.Lua, obj: *Object) i32 {
    _ = state;
    _ = obj;

    std.debug.panic("client `get_urgent` not implemented", .{});
    return 0;
}
fn set_urgent(state: *lua.Lua, obj: *Object) i32 {
    _ = state;
    _ = obj;

    std.debug.panic("client `set_urgent` not implemented", .{});
    return 0;
}
fn get_size_hints(state: *lua.Lua, obj: *Object) i32 {
    _ = state;
    _ = obj;

    std.debug.panic("client `get_size_hints` not implemented", .{});
    return 0;
}
fn get_focusable(state: *lua.Lua, obj: *Object) i32 {
    _ = state;
    _ = obj;

    std.debug.panic("client `get_focusable` not implemented", .{});
    return 0;
}
fn set_focusable(state: *lua.Lua, obj: *Object) i32 {
    _ = state;
    _ = obj;

    std.debug.panic("client `set_focusable` not implemented", .{});
    return 0;
}
fn get_shape_bounding(state: *lua.Lua, obj: *Object) i32 {
    _ = state;
    _ = obj;

    std.debug.panic("client `get_shape_bounding` not implemented", .{});
    return 0;
}
fn set_shape_bounding(state: *lua.Lua, obj: *Object) i32 {
    _ = state;
    _ = obj;

    std.debug.panic("client `set_shape_bounding` not implemented", .{});
    return 0;
}
fn get_shape_clip(state: *lua.Lua, obj: *Object) i32 {
    _ = state;
    _ = obj;

    std.debug.panic("client `get_shape_clip` not implemented", .{});
    return 0;
}
fn set_shape_clip(state: *lua.Lua, obj: *Object) i32 {
    _ = state;
    _ = obj;

    std.debug.panic("client `set_shape_clip` not implemented", .{});
    return 0;
}
fn get_shape_input(state: *lua.Lua, obj: *Object) i32 {
    _ = state;
    _ = obj;

    std.debug.panic("client `get_shape_input` not implemented", .{});
    return 0;
}
fn set_shape_input(state: *lua.Lua, obj: *Object) i32 {
    _ = state;
    _ = obj;

    std.debug.panic("client `set_shape_input` not implemented", .{});
    return 0;
}
fn get_startup_id(state: *lua.Lua, obj: *Object) i32 {
    _ = state;
    _ = obj;

    std.debug.panic("client `get_startup_id` not implemented", .{});
    return 0;
}
fn set_startup_id(state: *lua.Lua, obj: *Object) i32 {
    _ = state;
    _ = obj;

    std.debug.panic("client `set_startup_id` not implemented", .{});
    return 0;
}
fn get_client_shape_bounding(state: *lua.Lua, obj: *Object) i32 {
    _ = state;
    _ = obj;

    std.debug.panic("client `get_client_shape_bounding` not implemented", .{});
    return 0;
}
fn get_client_shape_clip(state: *lua.Lua, obj: *Object) i32 {
    _ = state;
    _ = obj;

    std.debug.panic("client `get_client_shape_clip` not implemented", .{});
    return 0;
}
fn get_client_shape_input(state: *lua.Lua, obj: *Object) i32 {
    _ = state;
    _ = obj;

    std.debug.panic("client `get_client_shape_input` not implemented", .{});
    return 0;
}
fn get_first_tag(state: *lua.Lua, obj: *Object) i32 {
    _ = state;
    _ = obj;

    std.debug.panic("client `get_first_tag` not implemented", .{});
    return 0;
}
