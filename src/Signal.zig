const std = @import("std");
const lua = @import("lua");
const zanylua = @import("./lua.zig");
const lib = @import("./lua/lib.zig");
const Object = @import("./lua/Object.zig");

const Signal = @This();

id: u64,
funcs: std.ArrayList(*anyopaque) = .empty,

pub fn emit(signal: *Signal, state: *lua.Lua, nargs: i32) void {
    const nbfunc: i32 = @intCast(signal.funcs.items.len);

    state.checkStackErr(nbfunc + nargs + 1, "too much signal");
    // Push all functions and then execute, because this list can change
    // while executing funcs.
    for (signal.funcs.items) |func| {
        _ = Object.push(state, func);

        for (0..@intCast(nbfunc)) |i| {
            const offset: i32 = @intCast(i);
            // push args
            for (0..@intCast(nargs)) |_| {
                state.pushValue(-nargs - nbfunc + offset);
            }
            // push first function
            state.pushValue(-nargs - nbfunc + offset);
            state.remove(-nargs - nbfunc - 1 + offset);
            _ = lib.doFunction(state, nargs, 0);
        }
    }
}

// Disconnect a signal inside a signal array.
// You are in charge of reference counting.
// \param arr The signal array.
// \param name The signal name.
// \param ref The reference to remove.
pub fn disconnect(signal: *Signal, ref: *const anyopaque) void {
    for (signal.funcs.items, 0..) |func, i| {
        if (func == ref) {
            _ = signal.funcs.swapRemove(i);
            return;
        }
    }
}
