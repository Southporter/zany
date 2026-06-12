const std = @import("std");
const c = @import("deps");
const lua = @import("lua");
const zany = @import("../lua.zig");
const zanylib = @import("../lua/lib.zig");
const log = std.log.scoped(.key);
const wayland = @import("wayland");
const Modifiers = wayland.client.river.SeatV1.Modifiers;
const Object = @import("Object.zig");
const Class = @import("Class.zig");
const globals = @import("../globals.zig");

const Key = @This();

obj: Object = .{},
modifiers: Modifiers = .{},
keysym: Keysym = .empty,
keycode: Keycode = .none,

const Keycode = enum(u16) {
    empty = 0,
    none = std.math.maxInt(u16),
    _,

    fn name(code: Keycode, buf: []u8) []u8 {
        std.debug.assert(buf.len >= 12);
        return std.fmt.bufPrint(buf, "#{d}", .{@intFromEnum(code)}) catch unreachable;
    }
};

const Keysym = enum(u32) {
    empty = 0,
    @"0" = hash("0"),
    @"1" = hash("1"),
    @"2" = hash("2"),
    @"3" = hash("3"),
    @"4" = hash("4"),
    @"5" = hash("5"),
    @"6" = hash("6"),
    @"7" = hash("7"),
    @"8" = hash("8"),
    @"9" = hash("9"),
    a = hash("a"),
    b = hash("b"),
    c = hash("c"),
    d = hash("d"),
    e = hash("e"),
    f = hash("f"),
    g = hash("g"),
    h = hash("h"),
    i = hash("i"),
    j = hash("j"),
    k = hash("k"),
    l = hash("l"),
    m = hash("m"),
    n = hash("n"),
    o = hash("o"),
    p = hash("p"),
    q = hash("q"),
    r = hash("r"),
    s = hash("s"),
    t = hash("t"),
    u = hash("u"),
    v = hash("v"),
    w = hash("w"),
    x = hash("x"),
    y = hash("y"),
    z = hash("z"),

    space = hash("space"),
    @"return" = hash("return"),
    tab = hash("tab"),
    escape = hash("escape"),

    left = hash("left"),
    right = hash("right"),
    up = hash("up"),
    down = hash("down"),

    // TODO: Figure out how to handle lock modifiers. For now, stick it here.
    lock,

    unknown = std.math.maxInt(u32),

    fn name(keysym: Keysym, buf: []u8) ?[]u8 {
        std.debug.assert(buf.len >= 64);
        switch (keysym) {
            else => {
                const len = c.xkb_keysym_get_name(@intFromEnum(keysym), buf.ptr, buf.len);
                if (len == -1) {
                    return null;
                }
                return buf[0..@intCast(len)];
            },
        }
    }

    fn hash(input: []const u8) u32 {
        var hasher = std.hash.Fnv1a_32.init();
        hasher.update(input);
        return hasher.final();
    }
    fn parse(input: []const u8) Keysym {
        std.debug.assert(input.len <= 32);
        var buf: [32]u8 = undefined;
        const lowered = std.ascii.lowerString(&buf, input);
        const h = hash(lowered);
        return std.meta.intToEnum(Keysym, h) catch {
            log.err("Unknown key symbol {s}", .{input});
            return .unknown;
        };
    }
};

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

pub var key_class: Class = .{
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
    // globals.gpa.destroy(key);
    _ = key;
}

fn create(state: *lua.Lua) i32 {
    return key_class.new(state);
}

fn keystore(state: *lua.Lua, ud: i32, str: []const u8) void {
    if (str.len <= 0) return;

    const obj = key_class.checkudata(state, ud) orelse return;
    const key: *Key = @fieldParentPtr("obj", obj);

    if (str.len == 1) {
        key.keysym = .parse(str);
        key.keycode = .empty;
    } else if (str[0] == '#') {
        key.keysym = .empty;
        key.keycode = @enumFromInt(str[1]);
    } else {
        key.keycode = .empty;

        if (std.mem.eql(u8, str, "Lock")) {
            key.keysym = .lock;
        } else {
            key.keysym = .parse(str);
        }
    }
    Object.emitSignal(state, ud, "property::key", 0);
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
        defer state.pop(1);
        if (kind == .nil) {
            continue;
        }
        std.debug.assert(kind == .string);
        const key = state.checkString(-1);
        log.debug("Key: {s}", .{key});
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
        } else if (std.mem.eql(u8, key, "Lock")) {
            // Not sure what to do with Lock
            log.info("Lock not handled", .{});
        } else {
            log.warn("Key in `toModifiers` not handled: {s}", .{key});
        }
    }
    return mods;
}
// Push a modifier set to a Lua table.
// \param L The Lua VM state.
// \param modifiers The modifier.
// \return The number of elements pushed on stack.
pub fn pushModifiers(state: *lua.Lua, modifiers: Modifiers) i32 {
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
    _ = obj;
    const key = state.checkString(-1);
    keystore(state, -3, key);
    return 0;
}
fn getKey(state: *lua.Lua, obj: *Object) i32 {
    const k: *Key = @fieldParentPtr("obj", obj);
    if (k.keycode != .empty) {
        var buf: [12]u8 = undefined;
        const name = k.keycode.name(&buf);
        _ = state.pushString(name);
    } else {
        var buf: [64]u8 = undefined;
        const name = k.keysym.name(&buf);
        if (name) |n| {
            _ = state.pushString(n);
        } else {
            return 0;
        }
    }
    return 1;
}
fn getKeysym(state: *lua.Lua, obj: *Object) i32 {
    const key: *Key = @fieldParentPtr("obj", obj);
    var buf: [64]u8 = undefined;
    const name = key.keysym.name(&buf);
    if (name) |n| {
        _ = state.pushString(n);
        return 1;
    }
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
