const std = @import("std");
const lua = @import("lua");
const Class = @import("lua/Class.zig");
const Object = @import("lua/Object.zig");
const Key = @import("object/Key.zig");
const globals = @import("globals.zig");
const wayland = @import("wayland");
const river = wayland.client.river;

const Button = @This();

obj: Object = .{},
modifiers: river.SeatV1.Modifiers = .{},
button: u32 = 0, //TODO: fix with river equivalent

var props = [_]Class.Property{
    .{
        .name = "button",
        .new = setButton,
        .index = getButton,
        .newindex = setButton,
    },
    .{
        .name = "modifiers",
        .new = setModifiers,
        .index = getModifiers,
        .newindex = setModifiers,
    },
};
var button_class: Class = .{
    .name = "button",
    .properties = props[0..],
    .allocator = new,
    .collector = wipe,
};

pub fn setup(state: *lua.Lua) !void {
    const methods = [_]lua.FnReg{
        .{ .name = "__call", .func = lua.wrap(call) },
    };
    const meta = [_]lua.FnReg{};
    return button_class.setup(state, &methods, &meta);
}

fn new(state: *lua.Lua) ?*Object {
    const button = button_class.create(Button, state) orelse return null;
    return &button.obj;
}

fn wipe(obj: *Object) void {
    const button: *Button = @fieldParentPtr("obj", obj);
    globals.gpa.destroy(button);
}

fn call(state: *lua.Lua) i32 {
    return button_class.new(state);
}

fn setButton(state: *lua.Lua, obj: *Object) i32 {
    _ = state;
    _ = obj;
    std.debug.panic("button.button `set` not implemented", .{});
    return 0;
}
fn getButton(state: *lua.Lua, obj: *Object) i32 {
    _ = state;
    _ = obj;
    std.debug.panic("button.button `get` not implemented", .{});
    return 0;
}
fn setModifiers(state: *lua.Lua, obj: *Object) i32 {
    const button: *Button = @fieldParentPtr("obj", obj);
    button.modifiers = Key.toModifiers(state, -1);
    Object.emitSignal(state, -3, "property::modifiers", 0);
    return 0;
}
fn getModifiers(state: *lua.Lua, obj: *Object) i32 {
    _ = state;
    _ = obj;
    std.debug.panic("button.modifiers `get` not implemented", .{});
    return 0;
}
