const std = @import("std");
const lua = @import("lua");
const lib = @import("lua/lib.zig");
const Class = @import("lua/Class.zig");
const Object = @import("lua/Object.zig");
const Button = @import("button.zig");
const Color = @import("Color.zig");

const Window = @This();

pub const none = std.math.maxInt(u32);

obj: Object = .{},
//  The River window number
window: u32 = none,
//  The frame window, might be XCB_NONE
// xcb_window_t frame_window;
opacity: f32 = 1.0,
//  Strut
// strut_t strut;
//  Button bindings
buttons: std.ArrayList(Button) = .empty,
//  Do we have pending border changes?
border_need_update: bool = false,
//  Border color
border_color: Color = .default,
//  Border width
border_width: u16 = 2,
//  The window type
kind: Kind = .normal,
//  The border width callback
// void (*border_width_callback)(void *, uint16_t old, uint16_t new);
// Windows type
const Kind = enum(u8) {
    normal = 0,
    desktop,
    dock,
    splash,
    dialog,
    // The ones below may have TRANSIENT_FOR, but are not plain dialogs.
    // They were purposefully placed below DIALOG.
    menu,
    toolbar,
    utility,
    // This ones are usually set on override-redirect windows.
    dropdown_menu,
    popup_menu,
    tooltip,
    notification,
    combo,
    dnd,
};

var props = [_]Class.Property{
    .{ .name = "window", .index = getWindow },
    .{
        .name = "_opacity",
        .index = getOpacity,
        .newindex = setOpacity,
        .new = setOpacity,
    },
    .{
        .name = "_border_color",
        .index = getBorderColor,
        .newindex = setBorderColor,
        .new = setBorderColor,
    },
    .{
        .name = "_border_width",
        .index = getBorderWidth,
        .newindex = setBorderWidth,
        .new = setBorderWidth,
    },
};
pub var window_class: Class = .{
    .name = "window",
    .allocator = new,
    .collector = wipe,
    .properties = props[0..],
};

pub fn setup(state: *lua.Lua) !void {
    const methods = [_]lua.FnReg{};
    const meta = [_]lua.FnReg{
        .{ .name = "struts", .func = lua.wrap(struts) },
        .{ .name = "_buttons", .func = lua.wrap(handleButtons) },
        .{ .name = "set_xproperty", .func = lua.wrap(set_xproperty) },
        .{ .name = "get_xproperty", .func = lua.wrap(get_xproperty) },
    };

    return window_class.setup(state, &methods, &meta);
}

fn new(state: *lua.Lua) ?*Object {
    const window = window_class.create(Window, state) orelse return null;
    return &window.obj;
}

fn wipe(obj: *Object) void {
    const window: *Window = @fieldParentPtr("obj", obj);
    std.heap.c_allocator.destroy(window);
}

fn struts(state: *lua.Lua) i32 {
    _ = state;
    std.debug.panic("window.struts not implemented", .{});
    return 0;
}
fn handleButtons(state: *lua.Lua) i32 {
    _ = state;
    std.debug.panic("window.buttons not implemented", .{});
    return 0;
}
fn get_xproperty(state: *lua.Lua) i32 {
    _ = state;
    std.debug.panic("window.get_xproperty not implemented", .{});
    return 0;
}
fn set_xproperty(state: *lua.Lua) i32 {
    _ = state;
    std.debug.panic("window.set_xproperty not implemented", .{});
    return 0;
}

fn getWindow(state: *lua.Lua, obj: *Object) i32 {
    _ = state;
    _ = obj;
    std.debug.panic("window window property get not implemented", .{});
    return 0;
}
fn getOpacity(state: *lua.Lua, obj: *Object) i32 {
    _ = state;
    _ = obj;
    std.debug.panic("window opacity property get not implemented", .{});
    return 0;
}
fn setOpacity(state: *lua.Lua, obj: *Object) i32 {
    _ = state;
    _ = obj;
    std.debug.panic("window opacity property set not implemented", .{});
    return 0;
}
fn getBorderColor(state: *lua.Lua, obj: *Object) i32 {
    _ = state;
    _ = obj;
    std.debug.panic("window border color property get not implemented", .{});
    return 0;
}
fn setBorderColor(state: *lua.Lua, obj: *Object) i32 {
    _ = state;
    _ = obj;
    std.debug.panic("window border color property set not implemented", .{});
    return 0;
}
fn getBorderWidth(state: *lua.Lua, obj: *Object) i32 {
    _ = state;
    _ = obj;
    std.debug.panic("window border width property get not implemented", .{});
    return 0;
}
fn setBorderWidth(state: *lua.Lua, obj: *Object) i32 {
    _ = state;
    _ = obj;
    std.debug.panic("window border width property set not implemented", .{});
    return 0;
}
pub fn get_type(state: *lua.Lua, obj: *Object) i32 {
    const window: *Window = @fieldParentPtr("obj", obj);
    _ = state.pushString(@tagName(window.kind));
    return 1;
}
