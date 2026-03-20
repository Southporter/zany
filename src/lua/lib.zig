const std = @import("std");
const lua = @import("lua");
const zanylua = @import("../lua.zig");
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
        log.warn("{t}: {s}", .{ err, state.toString(-1) catch unreachable });
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

// Convert a stack index to positive.
// \param L The Lua VM state.
// \param ud The index.
// \return A positive index.
pub inline fn absindex(state: *lua.Lua, ud: i32) i32 {
    return if (ud > 0 or ud <= lua.registry_index) ud else state.getTop() + ud + 1;
}
