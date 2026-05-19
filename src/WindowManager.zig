const std = @import("std");
const lua = @import("lua");
const wayland = @import("wayland");
const log = std.log.scoped(.zanywm);
const Lua = lua.Lua;
const Screen = @import("object/Screen.zig");
const Area = @import("common/Area.zig");
const Hints = @import("common/Hints.zig");
const Buffer = @import("wayland/Buffer.zig");

const WM = @This();

const wl = wayland.client.wl;
const wp = wayland.client.wp;
const river = wayland.client.river;

const RegistryResults = struct {
    compositor: ?*wl.Compositor = null,
    shm: ?*wl.Shm = null,
    cursor: ?*wp.CursorShapeManagerV1 = null,
    rwm: ?*river.WindowManagerV1 = null,
    rbind: ?*river.XkbBindingsV1 = null,
    xkb_config: ?*river.XkbConfigV1 = null,

    fn destroy(self: RegistryResults) void {
        if (self.compositor) |compositor| compositor.destroy();
        if (self.shm) |shm| shm.destroy();
        if (self.cursor) |cursor| cursor.destroy();
        if (self.rwm) |rwm| rwm.destroy();
        if (self.rbind) |rbind| rbind.destroy();
        if (self.xkb_config) |xkb_config| xkb_config.destroy();
    }
};
globals: struct {
    compositor: *wl.Compositor,
    shm: *wl.Shm,
    cursor: *wp.CursorShapeManagerV1,
    rwm: *river.WindowManagerV1,
    rbind: *river.XkbBindingsV1,
    xkb_config: *river.XkbConfigV1,
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
root_shell: struct {
    top: i32 = 0,
    bottom: i32 = 0,
    left: i32 = 0,
    right: i32 = 0,
    surface: *wl.Surface,
    shell_surface: *river.ShellSurfaceV1,
    buffer: Buffer,
    node: *river.NodeV1,

    fn include(self: *@This(), area: Area) void {
        const wm: *WM = @fieldParentPtr("root_shell", self);
        self.top = @min(self.top, area.y);
        self.bottom = @max(self.bottom, area.y + @as(i32, @intCast(area.height)));
        self.left = @min(self.left, area.x);
        self.right = @max(self.right, area.x + @as(i32, @intCast(area.width)));

        const s = self.size();
        self.buffer.resize(wm.globals.shm, s.width, s.height) catch unreachable;
    }
    pub fn size(self: @This()) struct { width: i32, height: i32 } {
        return .{
            .width = self.right - self.left,
            .height = self.bottom - self.top,
        };
    }
},
keyboard: Keyboard = .{
    .handle = undefined,
},
gpa: std.mem.Allocator,

pub fn init(wm: *WM, gpa: std.mem.Allocator) !void {
    var registy_results: RegistryResults = .{};
    errdefer registy_results.destroy();
    const display = try wl.Display.connect(null);
    errdefer display.disconnect();
    const registry = try display.getRegistry();
    errdefer registry.destroy();
    registry.setListener(*RegistryResults, registryListener, &registy_results);

    if (display.roundtrip() != .SUCCESS) {
        return error.WaylandConnectFailed;
    }

    const rwm = registy_results.rwm orelse return error.RiverWindowManagerNotFound;
    errdefer rwm.destroy();
    rwm.setListener(*WM, listener, wm);
    const xkb_config = registy_results.xkb_config orelse return error.RiverXkbConfigNotFound;
    errdefer xkb_config.destroy();
    const compositor = registy_results.compositor orelse return error.WaylandCompositorNotFound;
    errdefer compositor.destroy();
    const shm = registy_results.shm orelse return error.WaylandShmNotFound;
    errdefer shm.destroy();
    const rbind = registy_results.rbind orelse return error.RiverXkbBindingsNotFound;
    const cursor = registy_results.cursor orelse return error.WaylandCursorManagerNotFound;

    const root_surface = try compositor.createSurface();
    errdefer root_surface.destroy();
    const root_shell_surface = try rwm.getShellSurface(root_surface);
    errdefer root_shell_surface.destroy();
    const root_shell_node = try root_shell_surface.getNode();
    errdefer root_shell_node.destroy();
    wm.* = .{
        .globals = .{
            .compositor = compositor,
            .shm = shm,
            .rwm = rwm,
            .rbind = rbind,
            .display = display,
            .registry = registry,
            .cursor = cursor,
            .xkb_config = xkb_config,
        },
        .root_shell = .{
            .surface = root_surface,
            .buffer = try .create(0, wm),
            .shell_surface = root_shell_surface,
            .node = root_shell_node,
        },
        .gpa = gpa,
    };
    xkb_config.setListener(*WM, xkbConfigListener, wm);
    wm.seats.init();
    wm.outputs.init();
    wm.windows.init();
}

pub fn deinit(wm: *WM) void {
    wm.keyboard.deinit(wm.gpa);
    {
        var iter = wm.seats.safeIterator(.reverse);
        while (iter.next()) |seat| {
            seat.deinit();
        }
    }
    wm.root_shell.node.destroy();
    wm.root_shell.shell_surface.destroy();
    wm.root_shell.buffer.destroy();
    wm.root_shell.surface.destroy();
    wm.globals.rbind.destroy();
    wm.globals.rwm.destroy();
    wm.globals.cursor.destroy();
    wm.globals.shm.destroy();
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

fn xkbConfigListener(config: *river.XkbConfigV1, event: river.XkbConfigV1.Event, wm: *WM) void {
    log.debug("Xkb Config listener: {t}", .{event});
    switch (event) {
        .finished => {
            config.destroy();
        },
        .xkb_keyboard => |evt| {
            wm.keyboard.handle = evt.id;
            evt.id.setListener(*WM, Keyboard.listener, wm);
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
            } else if (std.mem.orderZ(u8, global.interface, wp.CursorShapeManagerV1.interface.name) == .eq) {
                res.cursor = registry.bind(global.name, wp.CursorShapeManagerV1, 1) catch return;
            } else if (std.mem.orderZ(u8, global.interface, river.XkbConfigV1.interface.name) == .eq) {
                res.xkb_config = registry.bind(global.name, river.XkbConfigV1, 1) catch return;
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
    seat: ?*wl.Seat = null,
    cursor: ?Cursor = null,
    keybinder: *river.XkbBindingsSeatV1,
    keybinds: std.ArrayList(Keybind) = .empty,
    const Cursor = struct {
        pointer: *wl.Pointer,
        shape_device: *wp.CursorShapeDeviceV1,
        button_state: std.StaticBitSet(32),
        position: struct {
            x: i24 = -1,
            y: i24 = -1,
        } = .{},

        fn listener(pointer: *wl.Pointer, event: wl.Pointer.Event, data: *?Cursor) void {
            _ = pointer;
            log.debug("Got pointer event: {t}", .{event});
            switch (event) {
                .enter => {},
                .leave => {},
                .motion => |evt| {
                    if (data.*) |*cursor| {
                        cursor.position.x = evt.surface_x.toInt();
                        cursor.position.y = evt.surface_y.toInt();
                    }
                },
                .button => |evt| switch (evt.state) {
                    .pressed => {
                        if (data.*) |*cursor| {
                            cursor.button_state.set(evt.button);
                        }
                    },
                    .released => {
                        if (data.*) |*cursor| {
                            cursor.button_state.unset(evt.button);
                        }
                    },
                    else => {},
                },
                .axis => {},
                .frame => {},
                .axis_source => {},
                .axis_stop => {},
                .axis_discrete => {},
                .axis_value120 => {},
                .axis_relative_direction => {},
            }
        }
    };

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
                seat.seat = wm.globals.registry.bind(evt.name, wl.Seat, 9) catch null;
                if (seat.seat) |s| {
                    const pointer = s.getPointer() catch {
                        log.warn("Unable to get pointer for seat {d}", .{evt.name});
                        return;
                    };
                    pointer.setListener(*?Cursor, Cursor.listener, &seat.cursor);
                    const device = wm.globals.cursor.getPointer(pointer) catch {
                        log.warn("Unable to get cursor shape device", .{});
                        return;
                    };
                    seat.cursor = .{
                        .pointer = pointer,
                        .shape_device = device,
                        .button_state = .initEmpty(),
                    };
                }
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
    const max_x = std.math.maxInt(i32);
    const max_y = std.math.maxInt(i32);
    handle: *river.OutputV1,
    wl_output: ?*wl.Output = null,
    geometry: Area = .{
        .x = max_x,
        .y = max_y,
    },
    size: struct {
        width_mm: i32 = 0,
        height_mm: i32 = 0,
    } = .{},
    orientation: wl.Output.Transform = .normal,
    details: struct {
        name: [:0]const u8 = "",
        description: [:0]const u8 = "",
    } = .{},
    scale: i32 = 1,
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
                if (evt.x < 0 or evt.y < 0) {
                    log.warn("Output x or y is less than 0: ({d}, {d})", .{ evt.x, evt.y });
                }
                o.geometry.x = evt.x;
                o.geometry.y = evt.y;
            },
            .dimensions => |evt| {
                o.geometry.height = @intCast(evt.height);
                o.geometry.width = @intCast(evt.width);
            },
            .wl_output => |evt| {
                o.wl_output = wm.globals.registry.bind(evt.name, wl.Output, 4) catch null;
                if (o.wl_output) |wl_output| {
                    wl_output.setListener(*Viewport, outputListener, o);
                }
            },
            .removed => {
                if (o.wl_output) |wl_output| {
                    wl_output.destroy();
                }
                o.handle.destroy();
                remove(o.link);
                wm.gpa.destroy(o);
                // TODO: handle signal for removed outputs
            },
        }
        if (o.geometry.x < max_x and o.geometry.y < max_y and o.geometry.width != 0 and o.geometry.height != 0) {
            wm.root_shell.include(o.geometry);
        }
    }

    fn outputListener(wl_output: *wl.Output, event: wl.Output.Event, viewport: *Viewport) void {
        _ = wl_output;
        switch (event) {
            .geometry => |evt| {
                viewport.geometry.x = evt.x;
                viewport.geometry.y = evt.y;
                viewport.size.height_mm = evt.physical_height;
                viewport.size.width_mm = evt.physical_width;
                viewport.orientation = evt.transform;
                log.debug("Found monitor: {s} {s}", .{ evt.make, evt.model });
                log.debug("Monitor has {t} subpixels", .{evt.subpixel});
            },
            .description => |evt| {
                viewport.details.description = std.mem.span(evt.description);
            },
            .name => |evt| {
                viewport.details.name = std.mem.span(evt.name);
            },
            .scale => |evt| {
                viewport.scale = evt.factor;
            },
            .done => {
                log.info("Output events complete", .{});
            },
            .mode => {
                log.info("Mode for output: {any}", .{event.mode});
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

pub const Window = struct {
    handle: *river.WindowV1,
    title: ?[:0]const u8 = null,
    app_id: ?[:0]const u8 = null,
    parent: ?*river.WindowV1 = null,
    area: Area = .{},
    hints: Hints = .{},
    pid: i32 = -1,
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
            .unreliable_pid => |evt| {
                win.pid = evt.unreliable_pid;
            },
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
            .dimensions => |evt| {
                win.area.width = @intCast(evt.width);
                win.area.height = @intCast(evt.height);
            },
            .dimensions_hint => |evt| {
                win.hints.min_width = evt.min_width;
                win.hints.max_width = evt.max_width;
                win.hints.min_height = evt.min_height;
                win.hints.max_height = evt.max_height;
            },
            .show_window_menu_requested => {},
            .pointer_resize_requested => {},
            .pointer_move_requested => {},
            .decoration_hint => |evt| {
                win.hints.decoration = evt.hint;
            },
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

const Keyboard = struct {
    handle: *river.XkbKeyboardV1,
    name: [:0]const u8 = "",
    idx: u32 = 0,
    input: ?*river.InputDeviceV1 = null,
    flags: struct {
        num_lock: Flag,
        caps_lock: Flag,
    } = .{
        .num_lock = .disabled,
        .caps_lock = .disabled,
    },
    const Flag = enum {
        enabled,
        disabled,
    };

    fn deinit(kb: *Keyboard, gpa: std.mem.Allocator) void {
        gpa.free(kb.name);
    }

    fn listener(handle: *river.XkbKeyboardV1, event: river.XkbKeyboardV1.Event, wm: *WM) void {
        const kb = &wm.keyboard;
        log.debug("Xkb Keyboard listener: {t}", .{event});
        switch (event) {
            .layout => |evt| {
                if (evt.name) |name| {
                    const new_name = std.mem.span(name);
                    wm.keyboard.name = wm.gpa.dupeZ(u8, new_name) catch return;
                    log.debug("New layout name: {s}", .{wm.keyboard.name});
                } else {
                    kb.name = "";
                }
                kb.idx = evt.index;
            },
            .removed => {
                handle.destroy();
            },
            .numlock_disabled => {
                kb.flags.num_lock = .disabled;
            },
            .numlock_enabled => {
                kb.flags.num_lock = .enabled;
            },
            .capslock_disabled => {
                kb.flags.caps_lock = .disabled;
            },
            .capslock_enabled => {
                kb.flags.caps_lock = .enabled;
            },
            .input_device => |evt| {
                kb.input = evt.device;
            },
        }
    }
};
