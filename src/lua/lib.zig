const std = @import("std");
const lua = @import("lua");
const zanylua = @import("../lua.zig");
const Class = @import("../object/Class.zig");
const Zany = @import("../zany.zig");
const log = std.log.scoped(.lualib);

pub var dofunction_on_error: ?*const fn (state: *lua.Lua) i32 = null;

// Call a registered function. Its arguments are the complete stack contents.
// \param L The Lua VM state.
// \param handler The function to call.
// \return The number of elements pushed on stack.
pub inline fn callHandler(state: *lua.Lua, handler: c_int) i32 {
    // This is based on luaA_dofunction, but allows multiple return values */
    std.debug.assert(handler != lua.ref_nil);
    const nargs = state.getTop();

    // Push error handling function and move it before args */
    state.pushFunction(lua.wrap(doFunctionOnError));
    state.insert(-nargs - 1);
    const error_func_pos: i32 = 1;

    // push function and move it before args
    _ = state.rawGetIndex(lua.registry_index, handler);
    state.insert(-nargs - 1);

    state.protectedCall(.{
        .args = nargs,
        .results = lua.mult_return,
        .msg_handler = error_func_pos,
    }) catch {
        log.warn("{!s}", .{state.toString(-1)});
        state.pop(2);
        return 0;
    };

    // Remove error function */
    state.remove(error_func_pos);
    return state.getTop();
}

fn doFunctionOnError(state: *lua.Lua) i32 {
    if (dofunction_on_error) |on_error|
        return on_error(state);
    return 0;
}
// Execute an Lua function on top of the stack.
// \param L The Lua stack.
// \param nargs The number of arguments for the Lua function.
// \param nret The number of returned value from the Lua function.
// \return True on no error, false otherwise.
pub fn doFunction(state: *lua.Lua, nargs: i32, nret: i32) bool {
    // Move function before arguments
    state.insert(-nargs - 1);
    // Push error handling function
    state.pushFunction(lua.wrap(doFunctionOnError));
    // Move error handling function before args and function
    state.insert(-nargs - 2);
    const error_func_pos = state.getTop() - nargs - 1;
    state.protectedCall(.{
        .args = nargs,
        .results = nret,
        .msg_handler = -nargs - 2,
    }) catch |err| {
        log.warn("{t}: {s}", .{ err, state.toString(-1) catch @tagName(state.typeOf(-1)) });
        //remove error func and error string
        state.pop(2);
        return false;
    };
    // Remove error function
    state.remove(error_func_pos);
    return true;
}

pub fn checkFunction(state: *lua.Lua, idx: i32) void {
    if (!state.isFunction(idx)) {
        _ = zanylua.typeError(state, idx, "function");
    }
}
pub fn checkTable(state: *lua.Lua, idx: i32) void {
    if (!state.isTable(idx)) {
        _ = zanylua.typeError(state, idx, "table");
    }
}
pub fn checkBoolean(state: *lua.Lua, idx: i32) bool {
    if (!state.isBoolean(idx)) {
        _ = zanylua.typeError(state, idx, "boolean");
    }
    return state.toBoolean(idx);
}

// Convert a stack index to positive.
// \param L The Lua VM state.
// \param ud The index.
// \return A positive index.
pub inline fn absindex(state: *lua.Lua, ud: i32) i32 {
    return if (ud > 0 or ud <= lua.registry_index) ud else state.getTop() + ud + 1;
}

pub fn setUserValue(state: *lua.Lua, index: i32) !void {
    return switch (lua.lang) {
        .lua51, .luajit => state.setFnEnvironment(index),
        .lua52, .lua53 => state.setUserValue(index),
        else => @compileError("setUserValue not implemented for >= 5.4"),
    };
}

// Try to use the metatable of an object.
// \param L The Lua VM state.
// \param idxobj The index of the object.
// \param idxfield The index of the field (attribute) to get.
// \return The number of element pushed on stack.
pub fn useMetatable(state: *lua.Lua, idxobj: i32, idxfield: i32) i32 {
    var class: ?*Class = Class.get(state, idxobj);
    while (class) |c| : (class = class.?.parent) {
        // Push the class
        state.pushLightUserdata(c);
        // Get its metatable from registry
        _ = state.rawGetTable(lua.registry_index);

        state.pushValue(idxfield);
        // Get the field in the metatable
        _ = state.rawGetTable(-2);
        // Do we have a field like that?
        if (!state.isNil(-1)) {
            // Yes, so remove the metatable and return it!
            state.remove(-2);
            return 1;
        }
        //No, so remove the metatable and its value
        state.pop(2);
    }

    return 0;
}

//* Register a function.
// \param L The Lua stack.
// \param idx Index of the function in the stack.
// \param fct A int address: it will be filled with the int
// registered. If the address points to an already registered function, it will
// be unregistered.
// \return luaA_register value.
//
// from luaa.c luaA_registerfct
pub fn registerFct(state: *lua.Lua, idx: i32, fct: *i32) i32 {
    checkFunction(state, idx);

    return register(state, idx, fct);
}
//* Register an Lua object.
// \param L The Lua stack.
// \param idx Index of the object in the stack.
// \param ref A int address: it will be filled with the int
// registered. If the address points to an already registered object, it will
// be unregistered.
// \return Always 0.
// from luaa.c luaA_register
fn register(state: *lua.Lua, idx: i32, ref: *i32) i32 {
    state.pushValue(idx);
    if (ref.* != lua.ref_nil)
        state.unref(lua.registry_index, ref.*);
    ref.* = state.ref(lua.registry_index) catch {
        std.debug.panic("Failed to ref in `register`", .{});
        return lua.ref_nil;
    };
    return 0;
}

pub fn getZany(state: *lua.Lua) *Zany {
    const zany_type = state.getGlobal("__zany") catch unreachable;
    std.debug.assert(zany_type == .light_userdata);
    const zany: *Zany = state.toUserdata(Zany, -1) catch unreachable;
    state.pop(1);
    return zany;
}

test "getZany stack effect" {
    const state = try lua.Lua.init(std.testing.allocator);
    defer state.deinit();

    var global: Zany = undefined;
    state.pushLightUserdata(&global);
    state.setGlobal("__zany");

    const after = getZany(state);
    try std.testing.expectEqual(&global, after);
    // Stack effect should be 0
    try std.testing.expectEqual(0, state.getTop());
}

fn rangeError(state: *lua.Lua, narg: c_int, min: lua.Number, max: lua.Number) i32 {
    const msg = state.pushFString("value in [%f, %f] expected, got %f", .{
        min, max, state.toNumber(narg) catch std.math.inf(f64),
    });

    switch (lua.lang) {
        .lua52, .lua53, .lua54 => {
            state.traceback(state, null, 2);
            state.concat(2);
        },
        else => {},
    }
    return state.argError(narg, msg);
}

fn numberError(state: *lua.Lua, n: c_int) noreturn {
    const msg = state.pushFString("value at %d is not a Lua Number", .{n});
    switch (lua.lang) {
        .lua52, .lua53, .lua54 => {
            state.traceback(state, null, 2);
            state.concat(2);
        },
        else => {},
    }
    return state.argError(n, msg);
}

fn checkNumberRange(state: *lua.Lua, n: c_int, min: lua.Number, max: lua.Number) lua.Number {
    const res = state.toNumber(n) catch numberError(state, n);
    if (res < min or res > max) {
        _ = rangeError(state, n, min, max);
    }
    return res;
}

fn optNumberRange(state: *lua.Lua, narg: c_int, def: lua.Number, min: lua.Number, max: lua.Number) lua.Number {
    if (state.isNoneOrNil(narg)) {
        return def;
    }
    return checkNumberRange(state, narg, min, max);
}

pub fn getOptNumberRange(state: *lua.Lua, idx: c_int, name: [:0]const u8, def: lua.Number, min: lua.Number, max: lua.Number) lua.Number {
    const kind = state.getField(idx, name);
    defer state.pop(1);

    if (kind == .nil or kind == .number) {
        return optNumberRange(state, -1, def, min, max);
    }
    return def;
}
