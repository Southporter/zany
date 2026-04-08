const std = @import("std");
const lua = @import("lua");
const globals = @import("./globals.zig");
const zanylua = @import("./lua.zig");
const lib = @import("./lua/lib.zig");
const utils = @import("./util.zig");
const Object = @import("./object/Object.zig");
const log = std.log.scoped(.signals);

const Signals = @This();

pub const Signal = struct {
    id: u64,
    funcs: std.ArrayList(*anyopaque) = .empty,

    // Maps to `signal_object_emit` in `luaobject.c`
    pub fn emit(signal: *Signal, state: *lua.Lua, nargs: i32) void {
        const nbfunc: i32 = @intCast(signal.funcs.items.len);

        state.checkStackErr(nbfunc + nargs + 1, "too much signal");
        // Push all functions and then execute, because this list can change
        // while executing funcs.
        for (signal.funcs.items) |func| {
            _ = Object.push(state, func);
        }

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
};

signals: std.ArrayList(Signal) = .empty,

pub fn emit(signals: *Signals, state: *lua.Lua, name: []const u8, nargs: i32) void {
    const id = utils.strhash(name);
    for (signals.signals.items) |*signal| {
        if (id == signal.id) {
            signal.emit(state, nargs);
        }
    }
    state.pop(nargs);
}

pub fn findByName(signals: *Signals, name: []const u8) ?*Signal {
    const id = utils.strhash(name);
    return signals.findById(id);
}
pub fn findById(signals: *Signals, id: u64) ?*Signal {
    for (signals.signals.items) |*signal| {
        if (id == signal.id) {
            return signal;
        }
    }
    return null;
}

pub fn connect(signals: *Signals, name: []const u8, func: *anyopaque) void {
    const id = utils.strhash(name);
    if (signals.findById(id)) |sigfound| {
        sigfound.funcs.append(globals.gpa, func) catch {
            log.err("OOM: connecting signal: {s}", .{name});
        };
    } else {
        var sig = Signal{ .id = id };
        sig.funcs.append(globals.gpa, func) catch {
            log.err("OOM: connecting signal: {s}", .{name});
        };
        signals.signals.append(globals.gpa, sig) catch {
            sig.funcs.deinit(globals.gpa);
        };
    }
}

pub fn disconnect(signals: *Signals, name: []const u8, func: *const anyopaque) bool {
    const id = utils.strhash(name);
    for (signals.signals.items) |*signal| {
        if (id == signal.id) {
            signal.disconnect(func);
            return true;
        }
    }
    return false;
}
