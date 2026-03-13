const std = @import("std");
const lua = @import("lua");
const zanylua = @import("../lua.zig");
const log = std.log.scoped(.lualib);

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
    state.rawGetIndex(lua.registry_index, handler);
    state.insert(-nargs - 1);

    state.protectedCall(.{
        .args = nargs,
        .results = lua.mult_return,
        .msg_handler = error_func_pos,
    }) catch {
        log.warn("{s}", .{state.toString(-1)});
        state.pop(2);
        return 0;
    };

    // Remove error function */
    state.remove(error_func_pos);
    return state.getTop();
}

inline fn doFunctionOnError(state: *lua.Lua) i32 {
    _ = state;
    // if (zanylua.dofunction_on_error)
    //     return zanylua.dofunction_on_error(L);
    return 0;
}
