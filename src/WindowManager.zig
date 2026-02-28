const std = @import("std");
const lua = @import("lua");
const wayland = @import("wayland");
const Lua = lua.Lua;

const WM = @This();

const wl = wayland.client.wl;
const river = wayland.client.river;

const RegistryResults = struct {
    compositor: ?*wl.Compositor = null,
    rwm: ?*river.WindowManagerV1 = null,
    rbind: ?*river.XkbBindingsV1,
    shm: ?*wl.Shm = null,
};
globals: struct {
    compositor: *wl.Compositor,
    rwm: *river.WindowManagerV1,
    rbind: *river.XkbBindingsV1,
},
pub fn init(wm: *WM) !void {
    var registy_results: RegistryResults = .{};
    const display = try wl.Display.connect(null);
    const registry = try display.getRegistry();
    registry.setListener(*RegistryResults, registryListener, &registy_results);

    wm.globals = .{
        .compositor = registy_results.compositor orelse return error.WaylandCompositorNotFound,
        .rwm = registy_results.rwm orelse return error.RiverWindowManagerNotFound,
        .rbind = registy_results.rbind orelse return error.RiverXkbBindingsNotFound,
    };
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
