const Lua = @import("lua").Lua;
const Area = @This();
x: i32 = 0,
y: i32 = 0,
width: u32 = 0,
height: u32 = 0,

// Push a area type to a table on stack.
// \param L The Lua VM state.
// \param geometry The area geometry to push.
// \return The number of elements pushed on stack.
pub fn push(area: Area, state: *Lua) i32 {
    state.createTable(0, 4);
    state.pushInteger(area.x);
    state.setField(-2, "x");
    state.pushInteger(area.y);
    state.setField(-2, "y");
    state.pushInteger(area.width);
    state.setField(-2, "width");
    state.pushInteger(area.height);
    state.setField(-2, "height");
    return 1;
}
