const std = @import("std");
const lua = @import("lua");
const zany = @import("../lua.zig");
const zanylib = @import("../lua/lib.zig");
const log = std.log.scoped(.key);
const wayland = @import("wayland");
const Modifiers = wayland.client.river.SeatV1.Modifiers;
const Object = @import("../lua/Object.zig");
const Class = @import("../lua/Class.zig");
const globals = @import("../globals.zig");

const Key = @This();

obj: Object = .{},
// Key modifier
modifiers: Modifiers = .{},
// /** Keysym */
// keysym;
// /** Keycode */
// xcb_keycode_t keycode;
//
var props = [_]Class.Property{
    .{
        .name = "key",
        .new = setKey,
        .index = getKey,
        .newindex = setKey,
    },
    .{
        .name = "keysym",
        .index = getKeysym,
    },
    .{
        .name = "modifiers",
        .new = setModifiers,
        .index = getModifiers,
        .newindex = setModifiers,
    },
};

var key_class: Class = .{
    .name = "key",
    .allocator = new,
    .collector = wipe,
    .properties = props[0..],
};
pub fn setup(state: *lua.Lua) !void {
    const methods = [_]lua.FnReg{
        .{ .name = "__call", .func = lua.wrap(create) },
    };
    const meta = [_]lua.FnReg{};

    return key_class.setup(state, &methods, &meta);
}

fn new(state: *lua.Lua) ?*Object {
    const key = key_class.create(Key, state);
    return if (key) |k| &k.obj else null;
}

fn wipe(obj: *Object) void {
    const key: *Key = @fieldParentPtr("obj", obj);
    globals.gpa.destroy(key);
}

fn create(state: *lua.Lua) i32 {
    return key_class.new(state);
}

// Take a modifier table from the stack and return modifiers mask.
// \param L The Lua VM state.
// \param ud The index of the table.
// \return The mask value.
pub fn toModifiers(state: *lua.Lua, ud: i32) Modifiers {
    zanylib.checkTable(state, ud);
    const len = state.rawLen(ud);
    var mods: Modifiers = .{};

    for (0..len) |i| {
        const kind = state.rawGetIndex(ud, @intCast(i));
        std.debug.assert(kind == .string);
        const key = state.checkString(-1);
        if (std.mem.eql(u8, key, "Mod1")) {
            mods.mod1 = true;
        } else if (std.mem.eql(u8, key, "Mod3")) {
            mods.mod3 = true;
        } else if (std.mem.eql(u8, key, "Mod4")) {
            mods.mod4 = true;
        } else if (std.mem.eql(u8, key, "Mod5")) {
            mods.mod5 = true;
        } else if (std.mem.eql(u8, key, "Shift")) {
            mods.shift = true;
        } else if (std.mem.eql(u8, key, "Ctrl")) {
            mods.ctrl = true;
        } else {
            log.warn("Key in `toModifiers` not handled: {s}", .{key});
        }
        state.pop(1);
    }
    return mods;
}
// Push a modifier set to a Lua table.
// \param L The Lua VM state.
// \param modifiers The modifier.
// \return The number of elements pushed on stack.
fn pushModifiers(state: *lua.Lua, modifiers: Modifiers) i32 {
    state.newTable();
    {
        var i: i32 = 1;
        if (modifiers.shift) {
            _ = state.pushStringZ("Shift");
            state.rawSetIndex(-2, i);
            i += 1;
        }
        if (modifiers.ctrl) {
            _ = state.pushStringZ("Ctrl");
            state.rawSetIndex(-2, i);
            i += 1;
        }
        if (modifiers.mod1) {
            _ = state.pushStringZ("Mod1");
            state.rawSetIndex(-2, i);
            i += 1;
        }
        if (modifiers.mod3) {
            _ = state.pushStringZ("Mod3");
            state.rawSetIndex(-2, i);
            i += 1;
        }
        if (modifiers.mod4) {
            _ = state.pushStringZ("Mod4");
            state.rawSetIndex(-2, i);
            i += 1;
        }
        if (modifiers.mod5) {
            _ = state.pushStringZ("Mod5");
            state.rawSetIndex(-2, i);
            i += 1;
        }
    }
    return 1;
}

fn setKey(state: *lua.Lua, obj: *Object) i32 {
    const key: *Key = @fieldParentPtr("obj", obj);
    _ = key;
    _ = state;
    std.debug.panic("key.set_key not implemented", .{});
    return 0;
}
fn getKey(state: *lua.Lua, obj: *Object) i32 {
    const key: *Key = @fieldParentPtr("obj", obj);
    _ = key;
    _ = state;
    std.debug.panic("key.get_key not implemented", .{});
    return 0;
}
fn getKeysym(state: *lua.Lua, obj: *Object) i32 {
    const key: *Key = @fieldParentPtr("obj", obj);
    _ = key;
    _ = state;
    std.debug.panic("key.get_keysym not implemented", .{});
    return 0;
}
fn setModifiers(state: *lua.Lua, obj: *Object) i32 {
    const key: *Key = @fieldParentPtr("obj", obj);
    key.modifiers = toModifiers(state, -1);
    Object.emitSignal(state, -3, "property::modifiers", 0);
    return 0;
}
fn getModifiers(state: *lua.Lua, obj: *Object) i32 {
    const key: *Key = @fieldParentPtr("obj", obj);
    return pushModifiers(state, key.modifiers);
}
