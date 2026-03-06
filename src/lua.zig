const std = @import("std");
const lua = @import("lua");
const log = std.log.scoped(.zanyLua);

const Lua = lua.Lua;

const Vm = @This();

// Patch lua globals for compatibility
pub fn fixup(state: *Lua) !void {
    const str_type = try state.getGlobal("string");
    std.debug.assert(str_type == .table);
    state.pushFunction(lua.wrap(mbstrlen));
    state.setField(-2, "wlen");
    state.pop(1);

    state.pushFunction(lua.wrap(customType));
    state.setGlobal("type");
}

// UTF-8 aware string length computing.
// returns: The number of elements pushed on stack.
fn mbstrlen(state: *Lua) i32 {
    const str = state.checkString(1);
    const view = std.unicode.Utf8View.init(str) catch |err| {
        log.err("String passed to mbstrlen is not UTF-8: {t}", .{err});
        state.pushInteger(-1);
        return 1;
    };
    var count: isize = 0;
    var iter = view.iterator();
    while (iter.nextCodepoint()) |_| : (count += 1) {}

    state.pushInteger(count);
    return 1;
}

const Class = struct {
    name: []const u8,

    fn from(state: *Lua, index: i32) ?*Class {
        const t = state.typeOf(index);
        state.getMetatable(index) catch return null;
        if (t == .userdata) {
            const table_type = state.rawGetTable(lua.registry_index);
            std.debug.assert(table_type == .userdata);
            const class = state.toUserdata(Class, -1) catch return null;
            state.pop(1);
            return class;
        }
        return null;
    }
};

fn customType(state: *Lua) i32 {
    state.checkAny(1);
    const t = state.typeOf(1);
    if (t == .userdata) {
        const class = Class.from(state, 1);
        if (class) |c| {
            _ = state.pushString(c.name);
            return 1;
        }
    }
    _ = state.pushString(state.typeNameIndex(1));
    return 1;
}
