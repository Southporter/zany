const std = @import("std");
const lua = @import("lua");
const wayland = @import("wayland");
const log = std.log.scoped(.zanywm);
const Lua = lua.Lua;
const Screen = @import("object/Screen.zig");

const WM = @This();

const wl = wayland.client.wl;
const river = wayland.client.river;

const RegistryResults = struct {
    compositor: ?*wl.Compositor = null,
    rwm: ?*river.WindowManagerV1 = null,
    rbind: ?*river.XkbBindingsV1 = null,
    shm: ?*wl.Shm = null,
};
globals: struct {
    compositor: *wl.Compositor,
    rwm: *river.WindowManagerV1,
    rbind: *river.XkbBindingsV1,
    display: *wl.Display,
    registry: *wl.Registry,
},
state: enum {
    init,
    manage,
    render,
    finished,
    crash,
} = .init,
seats: wl.list.Head(Seat, .link) = undefined,
outputs: wl.list.Head(Viewport, .link) = undefined,
windows: wl.list.Head(Window, .link) = undefined,
gpa: std.mem.Allocator,

pub fn init(wm: *WM, gpa: std.mem.Allocator) !void {
    var registy_results: RegistryResults = .{};
    const display = try wl.Display.connect(null);
    const registry = try display.getRegistry();
    registry.setListener(*RegistryResults, registryListener, &registy_results);

    if (display.roundtrip() != .SUCCESS) {
        return error.WaylandConnectFailed;
    }

    const rwm = registy_results.rwm orelse return error.RiverWindowManagerNotFound;
    rwm.setListener(*WM, listener, wm);
    const compositor = registy_results.compositor orelse return error.WaylandCompositorNotFound;
    const rbind = registy_results.rbind orelse return error.RiverXkbBindingsNotFound;

    wm.* = .{
        .globals = .{
            .compositor = compositor,
            .rwm = rwm,
            .rbind = rbind,
            .display = display,
            .registry = registry,
        },
        .gpa = gpa,
    };
    wm.seats.init();
    wm.outputs.init();
    wm.windows.init();
}

pub fn deinit(wm: *WM) void {
    wm.globals.rbind.destroy();
    wm.globals.rwm.destroy();
    wm.globals.compositor.destroy();
    wm.globals.registry.destroy();
    wm.globals.display.disconnect();
}

pub fn poll(wm: *WM) !void {
    if (wm.globals.display.roundtrip() != .SUCCESS) {
        return error.WaylandDispatchFailed;
    }
}

fn listener(
    rwm: *river.WindowManagerV1,
    event: river.WindowManagerV1.Event,
    wm: *WM,
) void {
    log.debug("Got Window Manager Event: {any}", .{event});
    switch (event) {
        .unavailable => {
            log.warn("River Window Manager no longer available", .{});
        },
        .finished => {
            wm.state = .finished;
        },
        .manage_start => {
            wm.state = .manage;
            rwm.manageFinish();
        },
        .render_start => {
            wm.state = .render;
            rwm.renderFinish();
        },
        .session_locked => {},
        .session_unlocked => {},
        .window => |evt| {
            const node = evt.id.getNode() catch {
                return;
            };
            const win = wm.gpa.create(Window) catch {
                rwm.stop();
                wm.state = .crash;
                return;
            };
            win.* = .{
                .handle = evt.id,
                .node = node,
            };
            wm.windows.append(win);
            evt.id.setListener(*WM, Window.listener, wm);
        },
        .output => |evt| {
            const viewport = wm.gpa.create(Viewport) catch {
                rwm.stop();
                wm.state = .crash;
                return;
            };
            viewport.* = .{
                .handle = evt.id,
            };
            wm.outputs.append(viewport);
            evt.id.setListener(*WM, Viewport.listener, wm);
        },
        .seat => |evt| {
            const keybinder = wm.globals.rbind.getSeat(evt.id) catch {
                rwm.stop();
                wm.state = .crash;
                return;
            };
            const seat = wm.gpa.create(Seat) catch {
                rwm.stop();
                wm.state = .crash;
                return;
            };
            seat.* = .{
                .handle = evt.id,
                .keybinder = keybinder,
            };
            wm.seats.append(seat);
            evt.id.setListener(*WM, Seat.listener, wm);
            keybinder.setListener(*WM, Seat.keybindListener, wm);
        },
    }
}

fn registryListener(registry: *wl.Registry, event: wl.Registry.Event, res: *RegistryResults) void {
    switch (event) {
        .global => |global| {
            if (std.mem.orderZ(u8, global.interface, wl.Compositor.interface.name) == .eq) {
                res.compositor = registry.bind(global.name, wl.Compositor, 6) catch return;
            } else if (std.mem.orderZ(u8, global.interface, wl.Shm.interface.name) == .eq) {
                res.shm = registry.bind(global.name, wl.Shm, 2) catch return;
            } else if (std.mem.orderZ(u8, global.interface, river.WindowManagerV1.interface.name) == .eq) {
                res.rwm = registry.bind(global.name, river.WindowManagerV1, 3) catch return;
            } else if (std.mem.orderZ(u8, global.interface, river.XkbBindingsV1.interface.name) == .eq) {
                res.rbind = registry.bind(global.name, river.XkbBindingsV1, 2) catch return;
            }
        },
        .global_remove => {},
    }
}

const Seat = struct {
    handle: *river.SeatV1,
    link: wl.list.Link = .{
        .next = null,
        .prev = null,
    },
    raw: u32 = 0,
    keybinder: *river.XkbBindingsSeatV1,
    keybinds: std.ArrayList(Keybind) = .empty,

    const Keybind = struct {
        handle: *river.XkbBindingV1,
    };
    fn deinit(seat: Seat) void {
        for (seat.keybinds.items) |kb| {
            kb.handle.destroy();
        }
        seat.keybinder.destroy();
        seat.handle.destroy();
    }

    fn listener(handle: *river.SeatV1, event: river.SeatV1.Event, wm: *WM) void {
        const seat = wm.findSeat(handle) orelse unreachable;
        log.debug("Seat event for {*}: {any}", .{ seat, event });
        switch (event) {
            .shell_surface_interaction => {},
            .pointer_enter => {},
            .pointer_leave => {},
            .pointer_position => {},
            .op_delta => {},
            .op_release => {},
            .wl_seat => |evt| {
                seat.raw = evt.name;
            },
            .window_interaction => {},
            .removed => {
                seat.handle.destroy();
                remove(seat.link);
                wm.gpa.destroy(seat);
            },
        }
    }
    fn keybindListener(keybind: *river.XkbBindingsSeatV1, event: river.XkbBindingsSeatV1.Event, data: *WM) void {
        _ = keybind;
        _ = data;
        log.debug("Seat XkbBindings event for {any}", .{event});
        switch (event) {
            .ate_unbound_key => {},
        }
    }
};
fn findSeat(wm: *WM, handle: *river.SeatV1) ?*Seat {
    var iter = wm.seats.iterator(.forward);
    while (iter.next()) |seat| {
        if (seat.handle == handle) {
            return seat;
        }
    }
    return null;
}

/// Keep track of the screen viewport(s) independently from the screen objects.
///
/// A viewport is a collection of `outputs` objects and their associated
/// metadata. This structure is copied into Lua and then further extended from
/// there. The `id` field allows to differentiate between viewports that share
/// the same position and dimensions without having to rely on userdata pointer
/// comparison.
///
/// Screen objects are widely used by the public API and imply a very "visible"
/// concept. A viewport is a subset of what the concerns the "screen" class
/// previously handled. It is meant to be used by some low level Lua logic to
/// create screens from Lua rather than from C. This is required to increase the
/// flexibility of multi-screen setup or when screens are connected and
/// disconnected often.
///
/// Design rationals:
///
/// * The structure is not directly shared with Lua to avoid having to use the
///   slow "miss_handler" and unsafe "valid" systems used by other CAPI objects.
/// * The `viewport_t` implements a linked-list because its main purpose is to
///   offers a deduplication algorithm. Random access is never required.
/// * Everything that can be done in Lua is done in Lua.
/// * Since the legacy and "new" way to initialize screens share a lot of steps,
///   the C code is bent to share as much code as possible. This will reduce the
///   "dead code" and improve code coverage by the tests.
pub const Viewport = struct {
    handle: *river.OutputV1,
    raw: u32 = 0,
    x: i32 = 0,
    y: i32 = 0,
    height: isize = 0,
    width: isize = 0,
    screen: *Screen = undefined,
    link: wl.list.Link = .{
        .next = null,
        .prev = null,
    },

    fn listener(output: *river.OutputV1, event: river.OutputV1.Event, wm: *WM) void {
        log.debug("Got output event: {any}", .{event});
        const o = wm.findOutput(output) orelse {
            log.warn("Did not find output. Skipping event: {any}", .{event});
            return;
        };
        switch (event) {
            .position => |evt| {
                o.x = evt.x;
                o.y = evt.y;
            },
            .dimensions => |evt| {
                o.height = evt.height;
                o.width = evt.width;
            },
            .wl_output => |evt| {
                o.raw = evt.name;
            },
            .removed => {
                o.handle.destroy();
                remove(o.link);
                wm.gpa.destroy(o);
                // TODO: handle signal for removed outputs
            },
        }
    }
};
fn findOutput(wm: *WM, output: *river.OutputV1) ?*Viewport {
    var iter = wm.outputs.iterator(.forward);
    while (iter.next()) |out| {
        if (out.handle == output) {
            return out;
        }
    }
    return null;
}

fn remove(link: wl.list.Link) void {
    const prev = link.prev;
    const next = link.next;
    if (prev) |p| {
        p.next = next;
        if (next) |n| {
            n.prev = p;
        }
    }
    if (next) |n| {
        n.prev = prev;
        if (prev) |p| {
            p.next = next;
        }
    }
}

test "list remove" {
    var first = wl.list.Link{
        .prev = null,
        .next = null,
    };
    var middle = wl.list.Link{
        .prev = &first,
        .next = null,
    };
    first.next = &middle;

    var last = wl.list.Link{
        .prev = &middle,
        .next = null,
    };
    middle.next = &last;
    try std.testing.expectEqual(null, first.prev);
    try std.testing.expectEqual(&middle, first.next);
    try std.testing.expectEqual(&first, middle.prev);
    try std.testing.expectEqual(&last, middle.next);
    try std.testing.expectEqual(&middle, last.prev);
    try std.testing.expectEqual(null, last.next);

    remove(first);
    try std.testing.expectEqual(null, first.prev);
    try std.testing.expectEqual(&middle, first.next);
    try std.testing.expectEqual(null, middle.prev);
    try std.testing.expectEqual(&last, middle.next);
    try std.testing.expectEqual(&middle, last.prev);
    try std.testing.expectEqual(null, last.next);
    middle.prev = &first;

    remove(last);
    try std.testing.expectEqual(null, first.prev);
    try std.testing.expectEqual(&middle, first.next);
    try std.testing.expectEqual(&first, middle.prev);
    try std.testing.expectEqual(null, middle.next);
    try std.testing.expectEqual(&middle, last.prev);
    try std.testing.expectEqual(null, last.next);
    middle.next = &last;

    remove(middle);
    try std.testing.expectEqual(null, first.prev);
    try std.testing.expectEqual(&last, first.next);
    try std.testing.expectEqual(&first, middle.prev);
    try std.testing.expectEqual(&last, middle.next);
    try std.testing.expectEqual(&first, last.prev);
    try std.testing.expectEqual(null, last.next);
}

const Window = struct {
    handle: *river.WindowV1,
    title: ?[:0]const u8 = null,
    app_id: ?[:0]const u8 = null,
    parent: ?*river.WindowV1 = null,
    node: *river.NodeV1,
    link: wl.list.Link = .{
        .prev = null,
        .next = null,
    },

    fn listener(window: *river.WindowV1, event: river.WindowV1.Event, wm: *WM) void {
        log.debug("Got window event: {any}", .{event});
        const win = wm.findWindow(window) orelse {
            log.warn("Unable to find window for event: {any}", .{event});
            return;
        };
        switch (event) {
            .unreliable_pid => {},
            .minimize_requested => {},
            .maximize_requested => {},
            .unmaximize_requested => {},
            .fullscreen_requested => {},
            .exit_fullscreen_requested => {},
            .closed => {
                win.handle.destroy();
                remove(win.link);
                wm.gpa.destroy(win);
                // TODO: handle signaling for closed window
            },
            .dimensions => {},
            .dimensions_hint => {},
            .show_window_menu_requested => {},
            .pointer_resize_requested => {},
            .pointer_move_requested => {},
            .decoration_hint => {},
            .parent => |evt| {
                win.parent = evt.parent;
            },
            .title => |evt| {
                if (evt.title) |title| {
                    win.title = std.mem.span(title);
                } else {
                    win.title = null;
                }
            },
            .app_id => |evt| {
                if (evt.app_id) |app_id| {
                    win.app_id = std.mem.span(app_id);
                } else {
                    win.app_id = null;
                }
            },
        }
    }
};

fn findWindow(wm: *WM, window: *river.WindowV1) ?*Window {
    var iter = wm.windows.iterator(.forward);
    while (iter.next()) |win| {
        if (win.handle == window) {
            return win;
        }
    }
    return null;
}
