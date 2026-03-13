const std = @import("std");
const lua = @import("lua");
const zanylua = @import("../lua.zig");
const lib = @import("./lib.zig");
const Signal = @import("../Signal.zig");
const Object = @import("./Object.zig");

const Class = @This();

name: []const u8,
signals: []Signal,
parent: ?*Class = null,
// /** Allocator for creating new objects of that class */
// lua_class_allocator_t allocator;
// /** Garbage collection function */
// lua_class_collector_t collector;
properties: []Property,
indexMissProperty: PropFn,
newindexMissProperty: PropFn,
checker: ?Checker = null,
instances: u32,
tostring: PropFn,
indexMissHandler: i32,
newindexMissHandler: i32,

const PropFn = *const fn (state: *lua.Lua, obj: *Object) i32;

const Checker = *const fn (obj: *Object) bool;

const Property = struct {
    name: [:0]const u8,
    new: PropFn,
    index: PropFn,
    newindex: PropFn,
};

pub fn get(state: *lua.Lua, offset: i32) ?*Class {
    const t = state.typeOf(offset);
    state.getMetatable(offset) catch return null;
    if (t == .userdata) {
        const table_type = state.rawGetTable(lua.registry_index);
        std.debug.assert(table_type == .userdata);
        const class = state.toUserdata(Class, -1) catch return null;
        state.pop(1);
        return class;
    }
    return null;
}

pub fn getPropertyByName(self: *Class, name: [:0]const u8) ?*Property {
    for (self.properties) |*prop| {
        if (std.mem.eql(u8, prop.name, name)) {
            return prop;
        }
    }
    return null;
}

// Get a property of a object.
// \param L The Lua VM state.
// \param lua_class The Lua class.
// \param fieldidx The index of the field name.
// \return The object property if found, NULL otherwise.
//
pub fn getProperty(self: *Class, state: *lua.Lua, offset: i32) ?*Property {
    // Lookup the property using token
    const attr = state.checkString(offset);

    // Look for the property in the class; if not found, go in the parent class.
    var lua_class = self;
    while (lua_class) |c| : (lua_class = lua_class.parent) {
        const prop = c.getPropByName(attr);
        if (prop) |p| return p;
    }

    return null;
}

// Try to use the metatable of an object.
// \param L The Lua VM state.
// \param idxobj The index of the object.
// \param idxfield The index of the field (attribute) to get.
// \return The number of element pushed on stack.
fn useMetatable(state: *lua.Lua, idxobj: i32, idxfield: i32) bool {
    var class = get(state, idxobj);
    while (class) |c| : (class = class.?.parent) {
        state.pushLightUserdata(c);
        // Get its metatable from registry
        state.rawGetTable(lua.registry_index);

        state.pushValue(idxfield);
        state.rawGetTable(-2);

        // Do we have a field like that?
        if (state.isNil(-1)) {
            // Nope, pop everything off and continue next loop
            state.pop(2);
        } else {
            state.remove(-2);
            return true;
        }
    }

    return false;
}
// Convert a object to a udata if possible.
// \param L The Lua VM state.
// \param ud The index.
// \param class The wanted class.
// \return A pointer to the object, NULL otherwise.
fn toudata(state: *lua.Lua, ud: i32, class: *Class) ?*Class {
    const userdata = state.toUserdata(Class, ud);
    state.getMetatable(ud) catch return null;
    if (userdata) |_| {
        state.rawGetTable(lua.registry_index);
        var metatable_class = state.toUserdata(Class, -1);

        // remove lightuserdata (lua_class pointer) */
        state.pop(1);

        // Now, check that the class given in argument is the same as the
        // metatable's object, or one of its parent (inheritance) */
        while (metatable_class) |c| : (metatable_class = metatable_class.?.parent) {
            if (c == class) return userdata;
        }
    }
    return null;
}
// Check for a udata class.
// \param L The Lua VM state.
// \param ud The object index on the stack.
// \param class The wanted class.
fn checkudata(state: *lua.Lua, ud: i32, class: *Class) ?*Class {
    const p = toudata(state, ud, class);
    if (p == null) {
        zanylua.typeError(state, ud, class.name);
    } else if (class.checker and !class.checker(p.?)) {
        state.raiseErrorStr("invalid object", .{});
    }
    return p;
}

pub fn index(state: *lua.Lua) i32 {
    if (useMetatable(state, 1, 2)) {
        return 1;
    }

    const class = get(state, 1) orelse return 0;

    // Is this the special 'valid' property? This is the only property
    // accessible for invalid objects and thus needs special handling.
    const attr = state.checkString(2);
    const valid: [:0]const u8 = "valid";
    if (std.mem.eql(u8, attr, valid)) {
        const p = toudata(state, 1, class);
        if (class.checker) {
            state.pushBoolean(p != null and class.checker(p));
        } else {
            state.pushboolean(p != null);
        }
        return 1;
    }

    const property = class.getProperty(state, 2);

    // This is the table storing the object private variables.
    const private: [:0]const u8 = "_private";
    const data: [:0]const u8 = "data";
    if (std.mem.eql(u8, attr, private)) {
        checkudata(state, 1, class);
        zanylua.getuservalue(state, 1);
        state.getField(-1, "data");
        return 1;
    } else if (std.mem.eql(u8, attr, data)) {
        zanylua.deprecate(@src(), state, "Use `._private` instead of `.data`");
        checkudata(state, 1, class);
        zanylua.getuservalue(state, 1);
        state.getField(-1, "data");
        return 1;
    }

    // Property does exist and has an index callback */
    if (property) |prop| {
        if (prop.index)
            return prop.index(state, checkudata(state, 1, class));
    } else {
        if (class.indexMissHandler != lua.ref_nil) {
            return lib.callHandler(state, class.indexMissHandler);
        }
        if (class.indexMissProperty) {
            return class.indexMissProperty(state, checkudata(state, 1, class));
        }
    }

    return 0;
}
pub fn newIndex(state: *lua.Lua) i32 {
    _ = state;
    return 0;
}
