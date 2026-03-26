const std = @import("std");
const lua = @import("lua");
const wayland = @import("wayland");
const log = std.log.scoped(.zanywm);
const Lua = lua.Lua;

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
seats: std.ArrayList(Seat) = .empty,
outputs: std.ArrayList(Output) = .empty,
windows: std.ArrayList(Window) = .empty,
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

    wm.* = .{
        .globals = .{
            .compositor = compositor,
            .rwm = rwm,
            .rbind = registy_results.rbind orelse return error.RiverXkbBindingsNotFound,
            .display = display,
            .registry = registry,
        },
        .gpa = gpa,
    };
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
            // This pointer is not stable
            const window = wm.windows.addOne(wm.gpa) catch {
                rwm.stop();
                wm.state = .crash;
                return;
            };
            window.* = .{
                .handle = evt.id,
                .node = node,
            };
            evt.id.setListener(*WM, Window.listener, wm);
        },
        .output => |evt| {
            // This pointer is not stable
            const output = wm.outputs.addOne(wm.gpa) catch {
                rwm.stop();
                wm.state = .crash;
                return;
            };
            output.handle = evt.id;
            evt.id.setListener(*WM, Output.listener, wm);
        },
        .seat => |evt| {
            const keybinder = wm.globals.rbind.getSeat(evt.id) catch {
                rwm.stop();
                wm.state = .crash;
                return;
            };
            // This pointer is not stable
            const seat = wm.seats.addOne(wm.gpa) catch {
                rwm.stop();
                wm.state = .crash;
                return;
            };
            seat.* = .{
                .handle = evt.id,
                .keybinder = keybinder,
            };
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

    fn listener(seat: *river.SeatV1, event: river.SeatV1.Event, wm: *WM) void {
        const seat_index = wm.findSeat(seat) orelse unreachable;
        const data = &wm.seats.items[seat_index];
        log.debug("Seat event for {d}: {any}", .{ seat_index, event });
        switch (event) {
            .shell_surface_interaction => {},
            .pointer_enter => {},
            .pointer_leave => {},
            .pointer_position => {},
            .op_delta => {},
            .op_release => {},
            .wl_seat => |evt| {
                data.raw = evt.name;
            },
            .window_interaction => {},
            .removed => {
                const s = wm.seats.swapRemove(seat_index);
                s.deinit();
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
fn findSeat(wm: *WM, handle: *river.SeatV1) ?usize {
    for (wm.seats.items, 0..) |s, index| {
        if (s.handle == handle) return index;
    }
    return null;
}

const Output = struct {
    handle: *river.OutputV1,
    raw: u32 = 0,
    x: i32,
    y: i32,
    height: isize,
    width: isize,

    fn listener(output: *river.OutputV1, event: river.OutputV1.Event, wm: *WM) void {
        log.debug("Got output event: {any}", .{event});
        const index = wm.findOutput(output) orelse {
            log.warn("Did not find output. Skipping event: {any}", .{event});
            return;
        };
        const data = &wm.outputs.items[index];
        switch (event) {
            .position => |evt| {
                data.x = evt.x;
                data.y = evt.y;
            },
            .dimensions => |evt| {
                data.height = evt.height;
                data.width = evt.width;
            },
            .wl_output => |evt| {
                data.raw = evt.name;
            },
            .removed => {
                const o = wm.outputs.swapRemove(index);
                o.handle.destroy();
            },
        }
    }
};
fn findOutput(wm: *WM, handle: *river.OutputV1) ?usize {
    for (wm.outputs.items, 0..) |*o, index| {
        if (o.handle == handle) return index;
    }
    return null;
}

const Window = struct {
    handle: *river.WindowV1,
    title: ?[:0]const u8 = null,
    app_id: ?[:0]const u8 = null,
    parent: ?*river.WindowV1 = null,
    node: *river.NodeV1,

    fn listener(window: *river.WindowV1, event: river.WindowV1.Event, wm: *WM) void {
        log.debug("Got window event: {any}", .{event});
        const win_index = wm.findWindow(window) orelse {
            log.warn("Unable to find window for event: {any}", .{event});
            return;
        };
        const data = &wm.windows.items[win_index];
        switch (event) {
            .unreliable_pid => {},
            .minimize_requested => {},
            .maximize_requested => {},
            .unmaximize_requested => {},
            .fullscreen_requested => {},
            .exit_fullscreen_requested => {},
            .closed => {
                const win = wm.windows.swapRemove(win_index);
                win.handle.destroy();
            },
            .dimensions => {},
            .dimensions_hint => {},
            .show_window_menu_requested => {},
            .pointer_resize_requested => {},
            .pointer_move_requested => {},
            .decoration_hint => {},
            .parent => |evt| {
                data.parent = evt.parent;
            },
            .title => |evt| {
                if (evt.title) |title| {
                    data.title = std.mem.span(title);
                } else {
                    data.title = null;
                }
            },
            .app_id => |evt| {
                if (evt.app_id) |app_id| {
                    data.app_id = std.mem.span(app_id);
                } else {
                    data.app_id = null;
                }
            },
        }
    }
};
fn findWindow(wm: *WM, handle: *river.WindowV1) ?usize {
    for (wm.windows.items, 0..) |*w, index| {
        if (w.handle == handle) return index;
    }
    return null;
}
