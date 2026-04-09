const lua = @import("lua");
const globals = @import("globals.zig");

pub fn index(state: *lua.Lua) i32 {
    globals.signals.emit(state, "debug::index::miss", 2);
    return 0;
}
pub fn newindex(state: *lua.Lua) i32 {
    globals.signals.emit(state, "debug::newindex::miss", 3);
    return 0;
}
