const std = @import("std");
const lua = @import("lua");
const Signal = @import("../Signal.zig");
const zanylua = @import("../lua.zig");
const lib = @import("./lib.zig");
const util = @import("../util.zig");
const Class = @import("Class.zig");
const log = std.log.scoped(.object);

const Object = @This();

const LUAA_OBJECT_REGISTRY_KEY: [:0]const u8 = "awesome.object.registry";
signals: std.ArrayList(Signal) = .empty,

pub const meta = [_]lua.FnReg{
    .{ .name = "__tostring", .func = lua.wrap(toString) },
    .{ .name = "connect_signal", .func = lua.wrap(connectSignalSimple) },
    .{ .name = "disconnect_signal", .func = lua.wrap(disconnectSignalSimple) },
    .{ .name = "emit_signal", .func = lua.wrap(emitSignalSimple) },
};

// Setup the object system at startup.
// \param L The Lua VM state.
pub fn setup(state: *lua.Lua) void {

    // Push identification string
    _ = state.pushStringZ(LUAA_OBJECT_REGISTRY_KEY);
    // Create an empty table
    state.newTable();
    // Create an empty metatable
    state.newTable();
    // Set this empty table as the registry metatable.
    // It's used to store the number of reference on stored objects.
    state.setMetatable(-2);
    // Register table inside registry
    state.rawSetTable(lua.registry_index);
}

pub fn toString(state: *lua.Lua) i32 {
    var class = Class.get(state, 1);
    const obj = class.?.checkudata(state, 1) orelse return 0;
    var offset: i32 = 0;

    while (class) |c| : (class = class.?.parent) {
        if (offset > 0) {
            _ = state.pushString("/");
            offset += 1;
            state.insert(-offset);
        }
        _ = state.pushString(c.name);
        offset += 1;
        state.insert(-offset);

        if (c.tostring) |tostr| {
            _ = state.pushString("(");
            const n = 2 + tostr(state, obj);
            _ = state.pushString(")");
            for (0..@intCast(n)) |_| {
                state.insert(-offset);
            }
            offset += n;
        }
    }

    _ = state.pushFString(": {p}", .{obj});

    state.concat(offset + 1);

    return 1;
}

fn connectSignalSimple(state: *lua.Lua) i32 {
    connectSignalFromStack(state, 1, state.checkString(2), 3);
    return 0;
}

fn disconnectSignalSimple(state: *lua.Lua) i32 {
    disconnectSignalFromStack(state, 1, state.checkString(2), 3);
    return 0;
}

fn emitSignalSimple(state: *lua.Lua) i32 {
    emitSignal(state, 1, state.checkString(2), state.getTop() - 2);
    return 0;
}

// Add a signal to an object.
// \param L The Lua VM state.
// \param oud The object index on the stack.
// \param name The name of the signal.
// \param ud The index of function to call when signal is emitted.
fn connectSignalFromStack(state: *lua.Lua, oud: i32, name: [:0]const u8, ud: i32) void {
    lib.checkFunction(state, ud);
    const obj = state.toUserdata(Object, oud) catch {
        log.warn("Signal function from stack is not a userdata", .{});
        return;
    };
    const id = util.strhash(name);
    for (obj.signals.items) |*signal| {
        if (signal.id == id) {
            const reference = refItem(state, oud, ud) orelse return;
            signal.funcs.append(std.heap.c_allocator, reference) catch {
                log.err("Unable to add signal. Out of memory!", .{});
                return;
            };
            return;
        }
    }
}

// Remove a signal to an object.
// \param L The Lua VM state.
// \param oud The object index on the stack.
// \param name The name of the signal.
// \param ud The index of function to call when signal is emitted.
fn disconnectSignalFromStack(state: *lua.Lua, oud: i32, name: [:0]const u8, ud: i32) void {
    lib.checkFunction(state, ud);
    const obj = state.toUserdata(Object, oud) catch {
        log.warn("Object index does not point to userdata", .{});
        return;
    };
    const reference = state.toPointer(ud) catch {
        log.warn("Userdata is not a pointer", .{});
        return;
    };
    const id = util.strhash(name);
    for (obj.signals.items) |*signal| {
        if (signal.id == id) {
            signal.disconnect(reference);
            unrefItem(state, oud, reference);
        }
    }
    state.remove(ud);
}

// Emit a signal.
// @tparam string name A signal name.
// @param[opt] ... Various arguments.
// @function emit_signal
pub fn emitSignal(state: *lua.Lua, oud: i32, name: [:0]const u8, nargs: i32) void {
    const oud_abs = lib.absindex(state, oud);
    const class = Class.get(state, oud) orelse {
        log.warn("Could not find class at {d}", .{oud});
        return;
    };
    const obj = Class.toudata(state, oud, class) orelse {
        zanylua.warn(state, "Trying to emit signal '{s}' on non-object", .{name});
        return;
    };
    if (class.checker) |check| {
        if (check(obj)) {
            zanylua.warn(state, "Trying to emit signal '{s}' on invalid object", .{name});
            return;
        }
    }

    const id = util.strhash(name);
    for (obj.signals.items) |signal| {
        if (signal.id == id) {
            const nbfunc: i32 = @intCast(signal.funcs.items.len);
            state.checkStackErr(nbfunc + nargs + 2, "too much signal");
            for (signal.funcs.items) |func| {
                _ = Object.pushItem(state, oud_abs, func);
            }

            for (0..@intCast(nbfunc)) |i| {
                const offset: i32 = @intCast(i);
                // push object
                state.pushValue(oud_abs);
                //push all args
                for (0..@intCast(nargs)) |_| {
                    state.pushValue(-nargs - nbfunc - 1 + offset);
                }
                // push first function
                state.pushValue(-nargs - nbfunc - 1 + offset);
                // remove this first function
                state.remove(-nargs - nbfunc - 2 + offset);
                _ = lib.doFunction(state, nargs + 1, 0);
            }
        }
    }
    // Then emit signal on the class
    state.pushValue(oud);
    state.insert(-nargs - 1);
    if (Class.get(state, -nargs - 1)) |c| {
        c.emitSignal(state, name, nargs + 1);
    }
}

fn registryPush(state: *lua.Lua) void {
    _ = state.pushStringZ(LUAA_OBJECT_REGISTRY_KEY);
    _ = state.rawGetTable(lua.registry_index);
}
pub fn push(state: *lua.Lua, pointer: *anyopaque) i32 {
    registryPush(state);
    state.pushLightUserdata(pointer);
    _ = state.rawGetTable(-2);
    state.remove(-2);
    return 1;
}
// Push an object item on the stack.
// \param L The Lua VM state.
// \param ud The object index on the stack.
// \param pointer The item pointer.
// \return The number of element pushed on stack.
pub fn pushItem(state: *lua.Lua, ud: i32, pointer: *anyopaque) i32 {
    // Get env table of the object
    zanylua.getuservalue(state, ud);
    // Push key
    state.pushLightUserdata(pointer);
    // Get env.pointer
    const kind = state.rawGetTable(-2);
    // TODO: Check this somehow
    _ = kind;

    // Remove env table
    state.remove(-2);
    return 1;
}
// Reference an object and return a pointer to it.
// That only works with userdata, table, thread or function.
// \param L The Lua VM state.
// \param oud The object index on the stack.
// \return The object reference, or NULL if not referenceable.
pub fn ref(state: *lua.Lua, oud: i32) ?*anyopaque {
    registryPush(state);
    const pointer = incref(state, -1, if (oud < 0) oud - 1 else oud);
    state.pop(1);
    return pointer;
}

// Reference an object and return a pointer to it checking its type.
// That only works with userdata.
// \param L The Lua VM state.
// \param oud The object index on the stack.
// \param class The class of object expected
// \return The object reference, or NULL if not referenceable.
//
pub fn refClass(state: *lua.Lua, oud: i32, class: *Class) ?*anyopaque {
    _ = class.checkudata(state, oud);
    return ref(state, oud);
}

// Unreference an object and return a pointer to it.
// That only works with userdata, table, thread or function.
// \param L The Lua VM state.
// \param oud The object index on the stack.
//
pub fn unref(state: *lua.Lua, pointer: *anyopaque) void {
    registryPush(state);
    decref(state, -1, pointer);
    state.pop(1);
}
// Increment a object reference in its store table.
// \param L The Lua VM state.
// \param tud The table index on the stack.
// \param oud The object index on the stack.
// \return A pointer to the object.
//
fn incref(state: *lua.Lua, tud: i32, oud: i32) ?*anyopaque {
    // Get pointer value of the item
    const pointer = @constCast(state.toPointer(oud) catch {
        // Not reference able.
        state.remove(oud);
        return null;
    });

    // Push the pointer (key)
    state.pushLightUserdata(pointer); // constCast: C translation schenanigans
    // Push the data (value)
    state.pushValue(if (oud < 0) oud - 1 else oud);
    // table.lightudata = data
    state.rawSetTable(if (tud < 0) tud - 2 else tud);

    // refcount++

    // Get the metatable
    state.getMetatable(tud) catch unreachable;
    // Push the pointer (key)
    state.pushLightUserdata(pointer);
    // Get the number of references
    _ = state.rawGetTable(-2);
    // Get the number of references and increment it
    const count = switch (state.typeOf(-1)) {
        .number => (state.toInteger(-1) catch unreachable) + 1,
        .nil => 1,
        else => |kind| std.debug.panic("Unable to convert {t} to an integer for count", .{kind}),
    };
    state.pop(1);
    // Push the pointer (key)
    state.pushLightUserdata(pointer);
    // Push count (value)
    state.pushInteger(count);
    // Set metatable[pointer] = count
    state.rawSetTable(-3);
    // Pop metatable
    state.pop(1);

    // Remove referenced item
    state.remove(oud);

    return pointer;
}

// Decrement a object reference in its store table.
// \param L The Lua VM state.
// \param tud The table index on the stack.
// \param oud The object index on the stack.
// \return A pointer to the object.
fn decref(state: *lua.Lua, tud: i32, pointer: *const anyopaque) void {
    // First, refcount--
    // Get the metatable
    state.getMetatable(tud) catch unreachable;
    // Push the pointer (key)
    state.pushLightUserdata(@constCast(pointer));
    // Get the number of references
    _ = state.rawGetTable(-2);
    // Get the number of references and decrement it
    const count = (state.toInteger(-1) catch unreachable) - 1;
    // Did we find the item in our table? (tointeger(nil)-1) is -1
    if (count < 0) {
        std.log.warn("BUG: Reference not found: {d} {*}", .{ tud, pointer });
        std.debug.dumpCurrentStackTrace(null);

        // Pop reference count and metatable
        state.pop(2);
        return;
    }
    state.pop(1);
    // Push the pointer (key)
    state.pushLightUserdata(@constCast(pointer)); // constCast: Pointer from lua is *const, but this expects *anyopaque
    // Hasn't the ref reached 0?
    if (count == 0) {
        // Yup, delete it, set nil as value
        state.pushNil();
    } else {
        state.pushInteger(count);
    }
    // Set meta[pointer] = count/nil
    state.rawSetTable(-3);
    // Pop metatable
    state.pop(1);

    // Wait, no more ref?
    if (count <= 0) {
        // Yes? So remove it from table
        state.pushLightUserdata(@constCast(pointer));
        // Push nil as value
        state.pushNil();
        // table[pointer] = nil
        state.rawSetTable(if (tud < 0) tud - 2 else tud);
    }
}

// Store an item in the environment table of an object.
// \param L The Lua VM state.
// \param ud The index of the object on the stack.
// \param iud The index of the item on the stack.
// \return The item reference.
fn refItem(state: *lua.Lua, ud: i32, iud: i32) ?*anyopaque {
    // Get the env table from the object
    zanylua.getuservalue(state, ud);
    const pointer = incref(state, -1, if (iud < 0) iud - 1 else iud);
    // Remove env table
    state.pop(1);
    return pointer;
}

// Unref an item from the environment table of an object.
// \param L The Lua VM state.
// \param ud The index of the object on the stack.
// \param ref item.
fn unrefItem(state: *lua.Lua, ud: i32, pointer: *const anyopaque) void {
    // Get the env table from the object
    zanylua.getuservalue(state, ud);
    // Decrement
    decref(state, -1, pointer);
    // Remove env table
    state.pop(1);
}
