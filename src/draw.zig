const std = @import("std");
const c = @import("deps");
const log = std.log.scoped(.draw);

/// Create a surface object from this pixbuf
/// \param buf The pixbuf
/// \return Number of items pushed on the lua stack.
pub fn surfaceFromPixbuf(buf: *c.GdkPixbuf) *c.cairo_surface_t {
    const width = c.gdk_pixbuf_get_width(buf);
    const height = c.gdk_pixbuf_get_height(buf);
    const pix_stride = c.gdk_pixbuf_get_rowstride(buf);
    var pixels = c.gdk_pixbuf_get_pixels(buf);
    const channels = c.gdk_pixbuf_get_n_channels(buf);
    var format = c.CAIRO_FORMAT_ARGB32;
    if (channels == 3)
        format = c.CAIRO_FORMAT_RGB24;

    const surface = c.cairo_image_surface_create(format, width, height);
    // const surface = cairo.cairo_image_surface_create(format, width, height) orelse {
    //     log.warn("unable to create cairo image surface", .{});
    //     std.process.cleanExit();
    // };
    c.cairo_surface_flush(surface);
    const cairo_stride = c.cairo_image_surface_get_stride(surface);
    var cairo_pixels = c.cairo_image_surface_get_data(surface);

    for (0..@intCast(height)) |_| {
        var row = pixels;
        var cairo_data: [*c]u32 = @ptrCast(@alignCast(cairo_pixels));
        for (0..@intCast(width)) |_| {
            if (channels == 3) {
                const r: u32 = row.*;
                row += 1;
                const g: u32 = row.*;
                row += 1;
                const b = row.*;
                row += 1;
                cairo_data.* = (r << 16) | (g << 8) | b;
                cairo_data += 1;
            } else {
                var r: u32 = row.*;
                row += 1;
                var g: u32 = row.*;
                row += 1;
                var b: u32 = row.*;
                row += 1;
                const a: u32 = row.*;
                row += 1;
                const a_f: f32 = @floatFromInt(a);
                const alpha = a_f / 255.0;
                r = @intFromFloat(@as(f32, @floatFromInt(r)) * alpha);
                g = @intFromFloat(@as(f32, @floatFromInt(g)) * alpha);
                b = @intFromFloat(@as(f32, @floatFromInt(b)) * alpha);
                cairo_data.* = (a << 24) | (r << 16) | (g << 8) | b;
                cairo_data += 1;
            }
        }
        pixels += @intCast(pix_stride);
        cairo_pixels += @intCast(cairo_stride);
    }

    c.cairo_surface_mark_dirty(surface);
    return surface orelse {
        unreachable;
    };
}
