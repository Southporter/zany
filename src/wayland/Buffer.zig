const std = @import("std");
const cairo = @import("cairo");
const wayland = @import("wayland");
const wl = wayland.client.wl;
const WindowManager = @import("../WindowManager.zig");

const Buffer = @This();

mem_fd: std.posix.fd_t,
handle: ?*wl.Buffer,
shm_pool: *wl.ShmPool,
data: []u8,

pub fn create(id: usize, wm: *WindowManager) !Buffer {
    var name_buf: [32:0]u8 = undefined;
    const name = try std.fmt.bufPrintZ(name_buf[0..], "southgate-bg-{d}", .{id});
    const fd = try std.posix.memfd_createZ(name, 0);
    const shm_pool = try wm.globals.shm.createPool(fd, 4096);
    return .{
        .mem_fd = fd,
        .shm_pool = shm_pool,
        .handle = null,
        .data = &.{},
    };
}

pub fn destroy(self: *Buffer) void {
    if (self.handle) |h| h.destroy();
    self.shm_pool.destroy();
    std.posix.munmap(@alignCast(std.mem.sliceAsBytes(self.data)));
    std.posix.close(self.mem_fd);
}

pub fn resize(self: *Buffer, shm: *wl.Shm, width: i32, height: i32) !void {
    const size = width * height * 4;
    try std.posix.ftruncate(self.mem_fd, @intCast(size));
    self.data = try std.posix.mmap(null, @intCast(size), std.posix.PROT.READ | std.posix.PROT.WRITE, .{
        .TYPE = .SHARED,
    }, self.mem_fd, 0);
    if (self.handle) |h| h.destroy();
    self.shm_pool.destroy();
    self.shm_pool = try shm.createPool(self.mem_fd, size);

    self.handle = try self.shm_pool.createBuffer(0, width, height, width * 4, .argb8888);
}
