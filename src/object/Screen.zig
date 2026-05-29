const std = @import("std");
const lua = @import("lua");
const lib = @import("../lua/lib.zig");
const Class = @import("Class.zig");
const Object = @import("Object.zig");
const Client = @import("Client.zig");
const zany = @import("../zany.zig");
const zanylua = @import("../lua.zig");
const globals = @import("../globals.zig");
const wm = @import("../WindowManager.zig");
const Viewport = wm.Viewport;
const Area = @import("../common/Area.zig");
const Strut = @import("../common/Strut.zig");
const log = std.log.scoped(.screen);

const Screen = @This();

const Xid = enum(u32) {
    none = 0,
    fake = 0xffffffff,
    _,
};
const Lifecycle = enum(u8) {
    user = 0,
    lua = 1,
    c = 2,
};

obj: Object = .{},
valid: bool = false,
// /** Who manages the screen lifecycle */
lifecycle: Lifecycle = .user,
// /** Screen geometry */
geometry: Area = .{},
// /** Screen workarea */
workarea: Area = .{},
// /** The name of the screen */
name: ?[]const u8 = null,
// /** Opaque pointer to the viewport */
viewport: *Viewport = undefined,
// Some XID identifying this screen */
xid: Xid = .none,

var props = [_]Class.Property{
    .{
        .name = "geometry",
        .index = getGeometry,
    },
    .{
        .name = "index",
        .index = getIndex,
    },
    .{
        .name = "_outputs",
        .index = getOutputs,
    },
    .{
        .name = "managed",
        .index = getManaged,
    },
    .{
        .name = "workarea",
        .index = getWorkarea,
    },
    .{
        .name = "name",
        .new = setName,
        .index = getName,
        .newindex = setName,
    },
};

pub var screen_class: Class = .{
    .name = "screen",
    .properties = props[0..],
    .allocator = new,
    .collector = wipe,
};

pub fn setup(state: *lua.Lua) !void {
    const methods = [_]lua.FnReg{
        .{ .name = "count", .func = lua.wrap(count) },
        // .{ .name = "_viewports", .func = lua.wrap(viewports) },
        // .{ .name = "_scan_quiet", .func = lua.wrap(quietScan) },
        .{ .name = "__index", .func = lua.wrap(moduleIndex) },
        .{ .name = "__newindex", .func = lua.wrap(moduleNewindex) },
        .{ .name = "__call", .func = lua.wrap(call) },
        .{ .name = "fake_add", .func = lua.wrap(fakeAdd) },
    };
    const meta = [_]lua.FnReg{
        .{ .name = "fake_remove", .func = lua.wrap(fakeRemove) },
        .{ .name = "fake_resize", .func = lua.wrap(fakeResize) },
        .{ .name = "swap", .func = lua.wrap(swap) },
    };
    return screen_class.setup(state, &methods, &meta);
}

fn new(state: *lua.Lua) ?*Object {
    const screen = screen_class.create(Screen, state) orelse return null;
    return &screen.obj;
}

fn wipe(obj: *Object) void {
    const screen: *Screen = @fieldParentPtr("obj", obj);
    if (screen.name) |name| {
        globals.gpa.free(name);
    }
    globals.gpa.destroy(screen);
}
/// Get a screen's index.
/// screen_get_index
fn index(screen: *Screen) usize {
    // Lua is 1 indexed, so start from 1
    for (globals.screens.items, 1..) |s, res| {
        if (screen == s) {
            return res;
        }
    }
    return 0;
}

pub fn count(state: *lua.Lua) i32 {
    state.pushInteger(@intCast(globals.screens.items.len));
    return 1;
}
pub fn viewports(state: *lua.Lua) i32 {
    _ = state;
    std.debug.panic("screen.viewports not implemented", .{});
    return 0;
}
pub fn quietScan(state: *lua.Lua) i32 {
    _ = state;
    std.debug.panic("screen._scan_quiet not implemented", .{});
    return 0;
}
// Screen module.
// \param L The Lua VM state.
// \return The number of elements pushed on stack.
// \luastack
// \lfield number The screen number, to get a screen.
//
pub fn moduleIndex(state: *lua.Lua) i32 {
    const kind = state.typeOf(2);
    if (kind == .string) {
        const name = state.toString(2) catch unreachable;
        if (std.mem.eql(u8, name, "primary")) {
            return Object.push(state, @ptrCast(getPrimary(state)));
        }
        for (globals.screens.items) |screen| {
            if (screen.name) |screen_name| {
                if (std.mem.eql(u8, name, screen_name)) {
                    return Object.push(state, screen);
                }
            }
        }

        zanylua.warn(state, "Unknown screen output name: {s}", .{name});
        state.pushNil();
        return 1;
    }

    return Object.push(state, @ptrCast(checkscreen(state, 2)));
}
pub fn moduleNewindex(state: *lua.Lua) i32 {
    _ = state;
    std.debug.panic("screen[newindex] not implemented", .{});
    return 0;
}

// Iterate over screens.
// @usage
// for s in screen do
//     print("Oh, wow, we have screen " .. tostring(s))
// end
// @function screen
//
pub fn call(state: *lua.Lua) i32 {
    // TODO: Is there a way to do this without the index juggling?
    var idx: usize = std.math.maxInt(usize);
    if (state.isNoneOrNil(3)) {
        idx = 0;
    } else {
        const screen = checkscreen(state, 3);
        if (screen) |s| {
            idx = @intCast(s.index());
        }
    }

    std.log.debug("Idx for screens: {d}", .{idx});
    if (idx < globals.screens.items.len) {
        _ = Object.push(state, globals.screens.items[@intCast(idx)]);
    } else {
        state.pushNil();
    }
    return 1;
}

/// Add a fake screen.
///
/// To vertically split the first screen in 2 equal parts, use:
///
///    local geo = screen[1].geometry
///    local new_width = math.ceil(geo.width/2)
///    local new_width2 = geo.width - new_width
///    screen[1]:fake_resize(geo.x, geo.y, new_width, geo.height)
///    screen.fake_add(geo.x + new_width, geo.y, new_width2, geo.height)
///
/// Both virtual screens will have their own taglist and wibars.
///
/// @tparam integer x X-coordinate for screen.
/// @tparam integer y Y-coordinate for screen.
/// @tparam integer width width for screen.
/// @tparam integer height height for screen.
/// @return The new screen.
/// @function fake_add
pub fn fakeAdd(state: *lua.Lua) i32 {
    const x = state.checkInteger(1);
    const y = state.checkInteger(2);
    const width = state.checkInteger(3);
    const height = state.checkInteger(4);

    const s = add(state) catch {
        log.err("OOM: Unable to fake add a screen", .{});
        std.process.exit(242);
    } orelse unreachable;

    s.geometry.x = @intCast(x);
    s.geometry.y = @intCast(y);
    s.geometry.width = @intCast(width);
    s.geometry.height = @intCast(height);
    s.xid = .fake;

    s.markAdded(state);
    screen_class.signals.emit(state, "list", 0);
    _ = Object.push(state, s);

    return 1;
}

fn markAdded(screen: *Screen, state: *lua.Lua) void {
    screen.workarea = screen.geometry;
    screen.valid = true;
    _ = Object.push(state, screen);
    Object.emitSignal(state, -1, "added", 0);
    state.pop(1);
}
// Called when a screen is removed, removes references to the old screen */
fn removed(screen: *Screen, state: *lua.Lua, sidx: i32) void {
    Object.emitSignal(state, sidx, "removed", 0);

    if (globals.primary_screen == screen)
        globals.primary_screen = null;

    for (globals.clients.items) |c| {
        if (c.screen == screen) {
            const new_screen = Screen.getByCoord(c.geometry.x, c.geometry.y) orelse {
                log.err("Unable to get new screen after screen removed", .{});
                return;
            };
            new_screen.moveClientTo(c, state, false);
        }
    }
}

/// Remove a screen.
/// @function fake_remove
pub fn fakeRemove(state: *lua.Lua) i32 {
    const obj = screen_class.checkudata(state, 1) orelse unreachable;
    const screen: *Screen = @fieldParentPtr("obj", obj);
    const idx = screen.index() - 1;
    if (idx < 0)
        // WTF?
        return 0;

    if (globals.screens.items.len == 1) {
        zanylua.warn(state, "Removing last screen through fake_remove(). " ++
            "This is a very, very, very bad idea!", .{});
    }

    _ = globals.screens.orderedRemove(idx);
    _ = Object.push(state, screen);
    screen.removed(state, -1);
    state.pop(1);
    screen_class.signals.emit(state, "list", 0);
    Object.unref(state, screen);
    screen.valid = false;

    return 0;
}
pub fn fakeResize(state: *lua.Lua) i32 {
    _ = state;
    std.debug.panic("screen.meta fake_resize not implemented", .{});
    return 0;
}
pub fn swap(state: *lua.Lua) i32 {
    _ = state;
    std.debug.panic("screen.swap not implemented", .{});
    return 0;
}

pub fn getGeometry(state: *lua.Lua, obj: *Object) i32 {
    const screen: *Screen = @fieldParentPtr("obj", obj);
    return screen.geometry.push(state);
}
// luaA_screen_get_index
pub fn getIndex(state: *lua.Lua, obj: *Object) i32 {
    const screen: *Screen = @fieldParentPtr("obj", obj);
    state.pushInteger(@intCast(screen.index()));
    return 1;
}
pub fn getOutputs(state: *lua.Lua, obj: *Object) i32 {
    _ = state;
    _ = obj;
    std.debug.panic("screen._outputs not implemented", .{});
    return 0;
}
pub fn getManaged(state: *lua.Lua, obj: *Object) i32 {
    _ = state;
    _ = obj;
    std.debug.panic("screen.managed not implemented", .{});
    return 0;
}
pub fn getWorkarea(state: *lua.Lua, obj: *Object) i32 {
    const screen: *Screen = @fieldParentPtr("obj", obj);
    return screen.workarea.push(state);
}
pub fn getName(state: *lua.Lua, obj: *Object) i32 {
    _ = state;
    _ = obj;
    std.debug.panic("screen.name not implemented", .{});
    return 0;
}
pub fn setName(state: *lua.Lua, obj: *Object) i32 {
    _ = state;
    _ = obj;
    std.debug.panic("`screen.name = x` not implemented", .{});
    return 0;
}

// Get a screen argument from the lua stack
pub fn checkscreen(state: *lua.Lua, sidx: i32) ?*Screen {
    if (state.isNumber(sidx)) {
        const screen = state.toInteger(sidx) catch unreachable;
        if (screen < 1 or screen > globals.screens.items.len) {
            zanylua.warn(state, "invalid screen number: {d} (of {d} existing)", .{ screen, globals.screens.items.len });
            state.pushNil();
            return null;
        }
        return globals.screens.items[@intCast(screen - 1)];
    } else {
        const obj = screen_class.checkudata(state, sidx) orelse return null;
        return @fieldParentPtr("obj", obj);
    }
}

pub fn add(state: *lua.Lua) !?*Screen {
    const screen = screen_class.create(Screen, state) orelse return null;
    _ = Object.ref(state, -1);
    try globals.screens.append(globals.gpa, screen);
    screen.xid = .none;
    screen.lifecycle = .user;
    return screen;
}

pub fn getPrimary(state: *lua.Lua) ?*Screen {
    if (globals.primary_screen == null and globals.screens.items.len > 0) {
        globals.primary_screen = globals.screens.items[0];
        _ = Object.push(state, globals.primary_screen.?);
        Object.emitSignal(state, -1, "primary_changed", 0);
        state.pop(1);
    }
    return globals.primary_screen;
}

///* Return the first screen number where the coordinates belong to.
/// \param x X coordinate
/// \param y Y coordinate
/// \return Screen pointer or screen param if no match or no multi-head.
pub fn getByCoord(x: c_int, y: c_int) ?*Screen {
    for (globals.screens.items) |screen| {
        if (screen.containsCoord(x, y)) {
            return screen;
        }
    }

    var nearest_screen: ?*Screen = null;
    var nearest_dist: u32 = std.math.maxInt(u32);
    for (globals.screens.items) |screen| {
        const dist_sq = screen.getDistanceSquared(x, y);
        if (dist_sq < nearest_dist) {
            nearest_dist = dist_sq;
            nearest_screen = screen;
        }
    }
    return nearest_screen;
}

///* Are the given coordinates in a given screen?
/// \param screen The logical screen number.
/// \param x X coordinate
/// \param y Y coordinate
/// \return True if the X/Y coordinates are in the given screen.
///
/// From: screen_coord_in_screen
fn containsCoord(s: *Screen, x: c_int, y: c_int) bool {
    return (x >= s.geometry.x and x < s.geometry.x + @as(i32, @intCast(s.geometry.width))) and
        (y >= s.geometry.y and y < s.geometry.y + @as(i32, @intCast(s.geometry.height)));
}

///* Return the squared distance of the given screen to the coordinates.
/// \param screen The screen
/// \param x X coordinate
/// \param y Y coordinate
/// \return Squared distance of the point to the screen.
///
/// From: screen_get_distance_squared
fn getDistanceSquared(s: *Screen, x: c_int, y: c_int) u32 {
    const sx = s.geometry.x;
    const sy = s.geometry.y;
    const sheight: i32 = @intCast(s.geometry.height);
    const swidth: i32 = @intCast(s.geometry.width);

    //Calculate distance in X coordinate
    const dist_x = blk: {
        if (x < sx) break :blk sx - x;
        if (x < sx + swidth) break :blk 0;
        break :blk x - sx - swidth;
    };

    // Calculate distance in Y coordinate
    const dist_y = blk: {
        if (y < sy) break :blk sy - y;
        if (y < sy + sheight) break :blk 0;
        break :blk y - sy - sheight;
    };

    return @intCast(dist_x * dist_x + dist_y * dist_y);
}

/// From COMPUTE_STRUT macro
fn computeStrut(s: Strut, geo: Area, area: Area, accum: *Strut) void {
    if (s.top_start_x > 0 or s.top_end_x > 0 or s.top > 0) {
        if (s.top > 0) {
            accum.top = @max(accum.top, s.top);
        } else {
            const y: u32 = @intCast(geo.y - area.y);
            const new_top: u16 = @intCast(y + geo.height);
            accum.top = @max(accum.top, new_top);
        }
    }
    if (s.bottom_start_x > 0 or s.bottom_end_x > 0 or s.bottom > 0) {
        if (s.bottom > 0) {
            accum.bottom = @max(accum.bottom, s.bottom);
        } else {
            const area_height: i32 = @intCast(area.height);
            const y = area.y + area_height;
            const new_bottom: u16 = @intCast(y - geo.y);
            accum.bottom = @max(accum.bottom, new_bottom);
        }
    }
    if (s.left_start_y > 0 or s.left_end_y > 0 or s.left > 0) {
        if (s.left > 0) {
            accum.left = @max(accum.left, s.left);
        } else {
            const geo_width: i32 = @intCast(geo.width);
            const new_left: u16 = @intCast((geo.x - area.x) + geo_width);
            accum.left = @max(accum.left, new_left);
        }
    }
    if (s.right_start_y > 0 or s.right_end_y > 0 or s.right > 0) {
        if (s.right > 0) {
            accum.right = @max(accum.right, s.right);
        } else {
            const area_width: i32 = @intCast(area.width);
            const x = area.x + area_width;
            const new_right: u16 = @intCast(x - geo.x);
            accum.right = @max(accum.right, new_right);
        }
    }
}

pub fn updateWorkarea(screen: *Screen) void {
    var area = screen.geometry;
    var strut = Strut{};

    for (globals.clients.items) |client| {
        if (client.screen == screen and client.isVisible()) {
            computeStrut(client.window.strut, client.geometry, area, &strut);
        }
    }
    for (globals.drawins.items) |drawin| {
        if (drawin.visible) {
            const d_screen = Screen.getByCoord(drawin.geometry.x, drawin.geometry.y);
            if (screen == d_screen) {
                computeStrut(drawin.window.strut, drawin.geometry, area, &strut);
            }
        }
    }

    area.x += strut.left;
    area.y += strut.top;
    area.width -= @min(area.width, strut.left + strut.right);
    area.height -= @min(area.height, strut.top + strut.bottom);

    if (area.eql(screen.workarea))
        return;

    // const old_workarea = screen.workarea;
    screen.workarea = area;
    @breakpoint();
    // lua_State *L = globalconf_get_lua_State();
    // luaA_object_push(L, screen);
    // luaA_pusharea(L, old_workarea);
    // luaA_object_emit_signal(L, -2, "property::workarea", 1);
    // lua_pop(L, 1);
}

/// Move a client to a virtual screen.
/// \param c The client to move.
/// \param new_screen The destination screen.
/// \param doresize Set to true if we also move the client to the new x and
///        y of the new screen.
///
/// From: screen_client_moveto
pub fn moveClientTo(screen: *Screen, c: *Client, state: *lua.Lua, doresize: bool) void {
    const old_screen = c.screen;
    var had_focus = false;

    if (screen == c.screen)
        return;

    if (globals.focus.client == c)
        had_focus = true;

    c.screen = screen;

    if (!doresize) {
        _ = Object.push(state, c);
        if (old_screen) |s| {
            _ = Object.push(state, s);
        } else {
            state.pushNil();
        }
        Object.emitSignal(state, -2, "property::screen", 1);
        state.pop(1);
        if (had_focus) {
            c.focus();
        }
        return;
    }

    const from = old_screen.?.geometry;
    const to = c.screen.?.geometry;

    var new_geometry = c.geometry;

    new_geometry.x = to.x + new_geometry.x - from.x;
    new_geometry.y = to.y + new_geometry.y - from.y;

    // resize the client if it doesn't fit the new screen */
    if (new_geometry.width > to.width)
        new_geometry.width = to.width;
    if (new_geometry.height > to.height)
        new_geometry.height = to.height;

    // make sure the client is still on the screen */
    if (new_geometry.x + @as(i32, @intCast(new_geometry.width)) > to.x + @as(i32, @intCast(to.width)))
        new_geometry.x = to.x + @as(i32, @intCast(to.width - new_geometry.width));
    if (new_geometry.y + @as(i32, @intCast(new_geometry.height)) > to.y + @as(i32, @intCast(to.height)))
        new_geometry.y = to.y + @as(i32, @intCast(to.height - new_geometry.height));
    if (!screen.includesArea(new_geometry)) {
        // If all else fails, force the client to end up on screen. */
        new_geometry.x = to.x;
        new_geometry.y = to.y;
    }

    // move / resize the client */
    _ = c.resize(new_geometry, false);

    // emit signal */
    _ = Object.push(state, c);
    if (old_screen != null) {
        _ = Object.push(state, old_screen.?);
    } else {
        state.pushNil();
    }
    Object.emitSignal(state, -2, "property::screen", 1);
    state.pop(1);

    if (had_focus)
        c.focus();
}

/// Is there any overlap between the given geometry and a given screen?
/// \param screen The logical screen number.
/// \param geom The geometry
/// \return True if there is any overlap between the geometry and a given screen.
///
/// From: screen_area_in_screen
pub fn includesArea(s: *Screen, geom: Area) bool {
    // zig fmt: off
    return (geom.x < s.geometry.x + @as(i32, @intCast(s.geometry.width)))
           and (geom.x + @as(i32, @intCast(geom.width)) > s.geometry.x )
           and (geom.y < s.geometry.y + @as(i32, @intCast(s.geometry.height)))
           and (geom.y + @as(i32, @intCast(geom.height)) > s.geometry.y);
    // zig fmt: on
}
