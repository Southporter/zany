const std = @import("std");
const lua = @import("lua");
const lib = @import("../lua/lib.zig");
const zanylua = @import("../lua.zig");
const globals = @import("../globals.zig");
const wm = @import("../WindowManager.zig");
const Window = @import("Window.zig");
const Screen = @import("Screen.zig");
const Class = @import("Class.zig");
const Object = @import("Object.zig");
const Area = @import("../common/Area.zig");
const Hints = @import("../common/Hints.zig");
const Drawable = @import("Drawable.zig");
const log = std.log.scoped(.Client);

const Client = @This();

const max_x11_size = std.math.maxInt(u16);
const min_x11_size = 1;

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
hints: Hints = .{},
// /** The visualtype that c->window uses */
// xcb_visualtype_t *visualtype;
// /** Do we honor the client's size hints? */
size_hints_honor: bool = true,
// /** Machine the client is running on. */
// char *machine;
// /** Role of the client */
// char *role;
// /** Client pid */
pid: i32 = -1,
// /** Window it is transient for */
// client_t *transient_for;
// /** Value of WM_TRANSIENT_FOR */
// xcb_window_t transient_for_window;
// /** Titelbar information */
titlebar: std.EnumArray(Titlebar.Kind, Titlebar) = .init(.{
    .top = .{},
    .bottom = .{},
    .right = .{},
    .left = .{},
}),
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
    log.info("Creating new client", .{});
    const client = client_class.create(Client, state) orelse return null;
    return &client.window.obj;
}

fn wipe(obj: *Object) void {
    log.info("destroying client", .{});
    globals.gpa.destroy(from(obj));
}

fn checker(obj: *Object) bool {
    const client = from(obj);
    return client.window.window != null;
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

pub fn manage(state: *lua.Lua, win: *wm.Window) void {
    var client = Client.client_class.create(Client, state) orelse unreachable;
    client.window.window = win;
    client.isbanned = true;
    // client.visual_type = draw.findVisual();
    // client.frame_window =

    // Duplicate client and push it in client list
    state.pushValue(-1);
    _ = Object.ref(state, -1);
    globals.clients.append(globals.gpa, client) catch {
        std.process.cleanExit();
    };

    // Set the right screen */
    // screen_client_moveto(c, screen_getbycoord(win.handle.x, wgeom->y), false);

    // Store initial geometry and emits signals so we inform that geometry have
    // been set.
    // c->geometry.x = wgeom->x;
    // c->geometry.y = wgeom->y;
    // c->geometry.width = wgeom->width;
    // c->geometry.height = wgeom->height;
    client.geometry = win.area;

    Object.emitSignal(state, -1, "property::x", 0);
    Object.emitSignal(state, -1, "property::y", 0);
    Object.emitSignal(state, -1, "property::width", 0);
    Object.emitSignal(state, -1, "property::height", 0);
    Object.emitSignal(state, -1, "property::window", 0);
    Object.emitSignal(state, -1, "property::geometry", 0);

    // /* Set border width */
    // window_set_border_width(L, -1, wgeom->border_width);
    //
    // /* we honor size hints by default */
    client.size_hints_honor = true;
    Object.emitSignal(state, -1, "property::size_hints_honor", 0);
    //
    // /* update all properties */
    // client_update_properties(L, -1, c);
    //
    // /* check if this is a TRANSIENT_FOR of another client */
    // foreach(oc, globalconf.clients)
    //     if ((*oc)->transient_for_window == w)
    //         client_find_transient_for(*oc);
    //
    // /* Put the window in normal state. */
    // xwindow_set_state(c->window, XCB_ICCCM_WM_STATE_NORMAL);
    //
    // /* Then check clients hints */
    // ewmh_client_check_hints(c);
    //
    // /* Push client in stack */
    // stack_client_push(c);
    //
    // /* Request our response */
    // xcb_get_property_reply_t *reply =
    //     xcb_get_property_reply(globalconf.connection, startup_id_q, NULL);
    // /* Say spawn that a client has been started, with startup id as argument */
    // char *startup_id = xutil_get_text_property_from_reply(reply);
    // p_delete(&reply);
    //
    // if (startup_id == NULL && c->leader_window != XCB_NONE) {
    //     /* GTK hides this property elsewhere. No idea why. */
    //     startup_id_q = xcb_get_property(globalconf.connection, false,
    //                                     c->leader_window, _NET_STARTUP_ID,
    //                                     XCB_GET_PROPERTY_TYPE_ANY, 0, UINT_MAX);
    //     reply = xcb_get_property_reply(globalconf.connection, startup_id_q, NULL);
    //     startup_id = xutil_get_text_property_from_reply(reply);
    //     p_delete(&reply);
    // }
    // c->startup_id = startup_id;
    //
    // spawn_start_notify(c, startup_id);
    //
    client_class.signals.emit(state, "list", 0);

    // client is still on top of the stack; emit signal */
    Object.emitSignal(state, -1, "manage", 0);
    //
    // xcb_generic_error_t *error = xcb_request_check(globalconf.connection, reparent_cookie);
    // if (error != NULL) {
    //     warn("Failed to manage window with name '%s', class '%s', instance '%s', because reparenting failed.",
    //             NONULL(c->name), NONULL(c->class), NONULL(c->instance));
    //     event_handle((xcb_generic_event_t *) error);
    //     p_delete(&error);
    //     client_unmanage(c, true);
    // }
    //
    // pop client
    state.pop(1);
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
/// Check if a client has fixed size.
/// \param c A client.
/// \return A boolean value, true if the client has a fixed size.
///
/// From: client_isfixed
fn isfixed(c: *Client) bool {
    // return (c.hints.flags & XCB_ICCCM_SIZE_HINT_P_MAX_SIZE
    //         and c.size_hints.flags & XCB_ICCCM_SIZE_HINT_P_MIN_SIZE
    //         and c.size_hints.max_width == c.size_hints.min_width
    //         and c.size_hints.max_height == c.size_hints.min_height
    //         and c.size_hints.max_width
    //         and c.size_hints.max_height
    //         and c.size_hints_honor);
    return c.hints.max_width == c.hints.min_width and c.hints.max_height == c.hints.min_height and c.size_hints_honor;
}
/// Returns true if a client is tagged with one of the tags of the
/// specified screen and is not hidden. Note that "banned" clients are included.
/// \param c The client to check.
/// \param screen Virtual screen number.
/// \return true if the client is visible, false otherwise.
///
/// From: client_isvisible
fn isvisible(state: *lua.Lua) i32 {
    const obj = client_class.checkudata(state, 1) orelse unreachable;
    const win: *Window = @fieldParentPtr("obj", obj);
    const client: *Client = @fieldParentPtr("window", win);
    state.pushBoolean(client.isVisible());
    return 1;
}
pub fn isVisible(c: *Client) bool {
    return (!c.hidden and !c.minimized and c.onSelectedTags());
}

///* Returns true if a client is tagged with one of the active tags.
/// \param c The client to check.
/// \return true if the client is visible, false otherwise.
fn onSelectedTags(c: *Client) bool {
    if (c.sticky)
        return true;

    for (globals.tags.items) |tag| {
        if (tag.isSelected() and tag.isTagged(c)) {
            return true;
        }
    }
    return false;
}
fn handleGeometry(state: *lua.Lua) i32 {
    _ = state;
    std.debug.panic("client `geometry` not implemented", .{});
    return 0;
}

/// Apply size hints to a size.
///
/// @param width Desired width of client
/// @param height Desired height of client
/// @return Actual width of client
/// @return Actual height of client
/// @function apply_size_hints
///
/// From: luaA_client_apply_size_hints
fn apply_size_hints(state: *lua.Lua) i32 {
    const obj = client_class.checkudata(state, 1);
    const c: *Client = from(obj.?);
    var geometry = c.geometry;
    if (!c.isfixed()) {
        geometry.width = @intFromFloat(@ceil(lib.checkNumberRange(state, 2, min_x11_size, max_x11_size)));
        geometry.height = @intFromFloat(@ceil(lib.checkNumberRange(state, 3, min_x11_size, max_x11_size)));
    }

    if (c.size_hints_honor)
        geometry = c.applySizeHints(geometry);

    state.pushInteger(geometry.width);
    state.pushInteger(geometry.height);
    return 2;
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
    _ = obj;
    client_set_urgent(state, -3, lib.checkBoolean(state, -1));
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
/// Give focus to client, or to first client if client is NULL.
/// \param c The client.
pub fn focus(client: *Client) void {
    // We have to set focus on first client */
    // if(!c && globalconf.clients.len && !(c = globalconf.clients.tab[0]))
    if (globals.clients.items.len > 0 and client != globals.clients.items[0]) {
        return;
    }

    if (client.focusUpdate()) {
        globals.focus.need_update = true;
    }
}

/// Record that a client got focus.
/// \param c The client.
/// \return true if the client focus changed, false otherwise.
pub fn focusUpdate(client: *Client) bool {
    const state = globals.getLuaState();

    if (globals.focus.client != null and globals.focus.client != client) {
        // When we are called due to a FocusIn event (=old focused client
        // already unfocused), we don't want to cause a SetInputFocus,
        // because the client which has focus now could be using globally
        // active input model (or 'no input').
        globals.focus.client.?.unfocusInternal();
    }

    const focused_new = globals.focus.client != client;
    globals.focus.client = client;

    // According to EWMH, we have to remove the urgent state from a client.
    // This should be done also for the current/focused client (FS#1310). */
    _ = Object.push(state, client);
    client_set_urgent(state, -1, false);

    if (focused_new)
        Object.emitSignal(state, -1, "focus", 0);

    state.pop(1);

    return focused_new;
}

/// Unfocus a client (internal).
/// \param c The client.
fn unfocusInternal(client: *Client) void {
    const state = globals.getLuaState();
    globals.focus.client = null;

    _ = Object.push(state, client);
    Object.emitSignal(state, -1, "unfocus", 0);
    state.pop(1);
}

/// Change the clients urgency flag.
/// \param L The Lua VM state.
/// \param cidx The client index on the stack.
/// \param urgent The new flag state.
///
///
fn client_set_urgent(state: *lua.Lua, cidx: i32, urgent: bool) void {
    const obj = client_class.checkudata(state, cidx);
    const c = from(obj.?);

    if (c.urgent != urgent) {
        c.urgent = urgent;

        Object.emitSignal(state, cidx, "property::urgent", 0);
    }
}

/// Resize client window.
/// The sizes given as parameters are with borders!
/// \param c Client to resize.
/// \param geometry New window geometry.
/// \param honor_hints Use size hints.
/// \return true if an actual resize occurred.
pub fn resize(c: *Client, geo: Area, honor_hints: bool) bool {
    var geometry = geo;
    if (honor_hints) {
        // We could get integer underflows in client_remove_titlebar_geometry()
        // without these checks here.
        if (geometry.width < c.titlebar.get(.left).size + c.titlebar.get(.right).size)
            return false;
        if (geometry.height < c.titlebar.get(.top).size + c.titlebar.get(.bottom).size)
            return false;
        geometry = c.applySizeHints(geometry);
    }

    if (geometry.width < c.titlebar.get(.left).size + c.titlebar.get(.right).size)
        return false;
    if (geometry.height < c.titlebar.get(.top).size + c.titlebar.get(.bottom).size)
        return false;

    if (geometry.width == 0 or geometry.height == 0)
        return false;

    if (!c.geometry.eql(geometry)) {
        c.resizeDo(geometry);
        return true;
    }

    return false;
}

fn resizeDo(c: *Client, geometry: Area) void {
    const state = globals.getLuaState();

    var new_screen = c.screen;
    if (!new_screen.?.includesArea(geometry))
        new_screen = Screen.getByCoord(geometry.x, geometry.y);

    // Also store geometry including border
    const old_geometry = c.geometry;
    c.geometry = geometry;

    _ = Object.push(state, c);
    if (!old_geometry.eql(geometry))
        Object.emitSignal(state, -1, "property::geometry", 0);
    if (old_geometry.x != geometry.x or old_geometry.y != geometry.y) {
        Object.emitSignal(state, -1, "property::position", 0);
        if (old_geometry.x != geometry.x) {
            Object.emitSignal(state, -1, "property::x", 0);
        } else {
            Object.emitSignal(state, -1, "property::y", 0);
        }
    }
    if (old_geometry.width != geometry.width or old_geometry.height != geometry.height) {
        Object.emitSignal(state, -1, "property::size", 0);
        if (old_geometry.width != geometry.width) {
            Object.emitSignal(state, -1, "property::width", 0);
        } else {
            Object.emitSignal(state, -1, "property::height", 0);
        }
    }
    state.pop(1);

    new_screen.?.moveClientTo(c, state, false);

    // Update all titlebars */
    var iter = c.titlebar.iterator();
    while (iter.next()) |entry| {
        const bar = entry.value;
        if (bar.drawable == null and bar.size == 0) {
            continue;
        }

        _ = Object.push(state, c);
        // was titlebar_get_drawable
        var drawable = bar.getDrawable(entry.key, state, -1, c);
        _ = Object.pushItem(state, -1, drawable);

        // was titlebar_get_area
        var area = bar.getArea(entry.key, c);

        // Convert to global coordinates */
        area.x += geometry.x;
        area.y += geometry.y;
        if (c.fullscreen) {
            area.width = 0;
            area.height = 0;
        }
        // drawable_set_geometry(L, -1, area);
        drawable.setGeometry(state, -1, area);

        // Pop the client and the drawable */
        state.pop(2);
    }
}

/// Apply size hints to the client's new geometry.
///
/// From: client_apply_size_hints
fn applySizeHints(c: *Client, target_geo: Area) Area {
    const minw: i32 = 0;
    const minh: i32 = 0;
    // var basew: i32 = 0;
    // var baseh: i32 = 0;
    // var real_basew: i32 = 0;
    // var real_baseh: i32 = 0;
    var geometry = target_geo;

    if (c.fullscreen)
        return geometry;

    // Size hints are applied to the window without any decoration */
    c.removeTitlebarGeometry(&geometry);

    @breakpoint();
    // TODO: Figure out the size hints flag
    // if(c->size_hints.flags & XCB_ICCCM_SIZE_HINT_BASE_SIZE)
    // {
    //     basew = c->size_hints.base_width;
    //     baseh = c->size_hints.base_height;
    //     real_basew = basew;
    //     real_baseh = baseh;
    // }
    // else if(c->size_hints.flags & XCB_ICCCM_SIZE_HINT_P_MIN_SIZE)
    // {
    //     /* base size is substituted with min size if not specified */
    //     basew = c->size_hints.min_width;
    //     baseh = c->size_hints.min_height;
    // }
    //
    // if(c->size_hints.flags & XCB_ICCCM_SIZE_HINT_P_MIN_SIZE)
    // {
    //     minw = c->size_hints.min_width;
    //     minh = c->size_hints.min_height;
    // }
    // else if(c->size_hints.flags & XCB_ICCCM_SIZE_HINT_BASE_SIZE)
    // {
    //     /* min size is substituted with base size if not specified */
    //     minw = c->size_hints.base_width;
    //     minh = c->size_hints.base_height;
    // }
    //
    // /* Handle the size aspect ratio */
    // if(c->size_hints.flags & XCB_ICCCM_SIZE_HINT_P_ASPECT
    //         && c->size_hints.min_aspect_den > 0
    //         && c->size_hints.max_aspect_den > 0
    //         && geometry.height > real_baseh
    //         && geometry.width > real_basew)
    // {
    //     /* ICCCM mandates:
    //      * If a base size is provided along with the aspect ratio fields, the base size should be subtracted from the
    //      * window size prior to checking that the aspect ratio falls in range. If a base size is not provided, nothing
    //      * should be subtracted from the window size. (The minimum size is not to be used in place of the base size for
    //      * this purpose.)
    //      */
    //      double dx = geometry.width - real_basew;
    //      double dy = geometry.height - real_baseh;
    //      double ratio = dx / dy;
    //      double min = c->size_hints.min_aspect_num / (double) c->size_hints.min_aspect_den;
    //      double max = c->size_hints.max_aspect_num / (double) c->size_hints.max_aspect_den;
    //
    //      if(max > 0 && min > 0 && ratio > 0)
    //      {
    //          if(ratio < min)
    //          {
    //              /* dx is lower than allowed, make dy lower to compensate this (+ 0.5 to force proper rounding). */
    //              dy = dx / min + 0.5;
    //              geometry.width  = dx + real_basew;
    //              geometry.height = dy + real_baseh;
    //          } else if(ratio > max)
    //          {
    //              /* dx is too high, lower it (+0.5 for proper rounding) */
    //              dx = dy * max + 0.5;
    //              geometry.width  = dx + real_basew;
    //              geometry.height = dy + real_baseh;
    //          }
    //      }
    // }

    // Handle the minimum size
    geometry.width = @max(geometry.width, minw);
    geometry.height = @max(geometry.height, minh);

    // // Handle the maximum size */
    // if(c->size_hints.flags & XCB_ICCCM_SIZE_HINT_P_MAX_SIZE)
    // {
    //     if(c->size_hints.max_width)
    //         geometry.width = MIN(geometry.width, c->size_hints.max_width);
    //     if(c->size_hints.max_height)
    //         geometry.height = MIN(geometry.height, c->size_hints.max_height);
    // }

    // Handle the size increment */
    // if(c->size_hints.flags & (XCB_ICCCM_SIZE_HINT_P_RESIZE_INC | XCB_ICCCM_SIZE_HINT_BASE_SIZE)
    //    && c->size_hints.width_inc && c->size_hints.height_inc)
    // {
    //     uint16_t t1 = geometry.width, t2 = geometry.height;
    //     unsigned_subtract(t1, basew);
    //     unsigned_subtract(t2, baseh);
    //     geometry.width -= t1 % c->size_hints.width_inc;
    //     geometry.height -= t2 % c->size_hints.height_inc;
    // }

    c.addTitlebarGeometry(&geometry);
    return geometry;
}

fn removeTitlebarGeometry(c: *Client, geometry: *Area) void {
    geometry.x += c.titlebar.get(.left).size;
    geometry.y += c.titlebar.get(.top).size;
    geometry.width -= c.titlebar.get(.left).size;
    geometry.width -= c.titlebar.get(.right).size;
    geometry.height -= c.titlebar.get(.top).size;
    geometry.height -= c.titlebar.get(.bottom).size;
}

fn addTitlebarGeometry(c: *Client, geometry: *Area) void {
    geometry.x -= c.titlebar.get(.left).size;
    geometry.y -= c.titlebar.get(.top).size;
    geometry.width += c.titlebar.get(.left).size;
    geometry.width += c.titlebar.get(.right).size;
    geometry.height += c.titlebar.get(.top).size;
    geometry.height += c.titlebar.get(.bottom).size;
}

const Titlebar = struct {
    size: u16 = 0,
    drawable: ?*Drawable = null,

    const Kind = enum {
        top,
        bottom,
        left,
        right,
    };

    pub fn getDrawable(bar: *Titlebar, kind: Kind, state: *lua.Lua, client_idx: i32, c: *Client) *Drawable {
        var cl_idx = client_idx;
        if (bar.drawable == null) {
            cl_idx = lib.absindex(state, cl_idx);
            bar.drawable = switch (kind) {
                .top => Drawable.allocator(state, refreshTitlebarTop, c),
                .bottom => Drawable.allocator(state, refreshTitlebarBottom, c),
                .left => Drawable.allocator(state, refreshTitlebarLeft, c),
                .right => Drawable.allocator(state, refreshTitlebarRight, c),
            };
            _ = Object.refItem(state, cl_idx, -1);
        }

        return bar.drawable.?;
    }

    fn getArea(bar: Titlebar, kind: Kind, c: *Client) Area {
        var result = c.geometry;
        result.x = 0;
        result.y = 0;

        // Let's try some ascii art:
        // ---------------------------
        // |         Top             |
        // |-------------------------|
        // |L|                     |R|
        // |e|                     |i|
        // |f|                     |g|
        // |t|                     |h|
        // | |                     |t|
        // |-------------------------|
        // |        Bottom           |
        // ---------------------------

        k: switch (kind) {
            .bottom => {
                result.y = @as(i32, @intCast(c.geometry.height)) - bar.size;
                // Mimic fallthrough
                continue :k .top;
            },
            .top => {
                result.height = bar.size;
            },
            .right => {
                result.x = @as(i32, @intCast(c.geometry.width)) - bar.size;
                // Mimic fallthrough
                continue :k .left;
            },
            .left => {
                const top = c.titlebar.get(.top);
                result.y = top.size;
                result.width = bar.size;
                result.height -= top.size;
                result.height -= c.titlebar.get(.bottom).size;
            },
        }

        return result;
    }

    fn refreshTitlebarTop(obj: *Object) void {
        const c = from(obj);
        const bar = c.titlebar.get(.top);
        const area = bar.getArea(.top, c);
        c.refreshTitlebarPartial(bar, .top, area.x, area.y, area.width, area.height);
    }
    fn refreshTitlebarBottom(obj: *Object) void {
        const c = from(obj);
        const bar = c.titlebar.get(.bottom);
        const area = bar.getArea(.bottom, c);
        c.refreshTitlebarPartial(bar, .bottom, area.x, area.y, area.width, area.height);
    }
    fn refreshTitlebarLeft(obj: *Object) void {
        const c = from(obj);
        const bar = c.titlebar.get(.left);
        const area = bar.getArea(.left, c);
        c.refreshTitlebarPartial(bar, .left, area.x, area.y, area.width, area.height);
    }
    fn refreshTitlebarRight(obj: *Object) void {
        const c = from(obj);
        const bar = c.titlebar.get(.right);
        const area = bar.getArea(.right, c);
        c.refreshTitlebarPartial(bar, .right, area.x, area.y, area.width, area.height);
    }
};

fn refreshTitlebarPartial(c: *Client, bar: Titlebar, kind: Titlebar.Kind, x: i32, y: i32, width: u32, height: u32) void {
    if (bar.drawable == null
        // or bar.drawable.?.pixmap == XCB_NONE
    or !bar.drawable.?.refreshed)
        return;

    // Is the titlebar part of the area that should get redrawn? */
    const area = bar.getArea(kind, c);
    if (area.left() >= x + @as(i32, @intCast(width)) or area.right() <= x)
        return;
    if (area.top() >= y + @as(i32, @intCast(height)) or area.bottom() <= y)
        return;

    // Redraw the affected parts
    @breakpoint();
    // cairo_surface_flush(c->titlebar[bar].drawable->surface);
    // xcb_copy_area(globalconf.connection, c->titlebar[bar].drawable->pixmap, c->frame_window,
    // globalconf.gc, x - area.x, y - area.y, x, y, width, height);
}
