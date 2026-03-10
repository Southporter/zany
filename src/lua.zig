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

pub fn openLib(state: *Lua, name: [:0]const u8, methods: []const lua.FnReg, meta: []const lua.FnReg) !void {
    try state.newMetatable(name);
    state.pushValue(-1); // Dup metatable
    state.setField(-2, "__index"); // metatable.__index = metatable

    state.setFuncs(meta, 0); // Pops of userdata at the end
    try registerFns(state, name, methods); //
    state.pushValue(-1); // dup self as metatable
    state.setMetatable(-2); // set self as metatable
    state.pop(2);
}

fn registerFns(state: *Lua, name: [:0]const u8, methods: []const lua.FnReg) !void {
    state.newTable();

    state.setFuncs(methods, 0);
    state.pushValue(-1); // Dupe table for glbal
    state.setGlobal(name);
}

pub fn setupSignals(state: *Lua, global: [:0]const u8) !void {
    try state.getGlobal(global);
    try state.pushString("unix_signal");
    try state.newTable();
    if (@hasField(std.posix.SIG, "IOT")) try setupSignal(state, .IOT);
    if (@hasField(std.posix.SIG, "EMT")) try setupSignal(state, .EMT);
    if (@hasField(std.posix.SIG, "STKFLT")) try setupSignal(state, .STKFLT);
    if (@hasField(std.posix.SIG, "IO")) try setupSignal(state, .IO);
    if (@hasField(std.posix.SIG, "CLD")) try setupSignal(state, .CLD);
    if (@hasField(std.posix.SIG, "PWR")) try setupSignal(state, .PWR);
    if (@hasField(std.posix.SIG, "INFO")) try setupSignal(state, .INFO);
    if (@hasField(std.posix.SIG, "LOST")) try setupSignal(state, .LOST);
    if (@hasField(std.posix.SIG, "WINCH")) try setupSignal(state, .WINCH);
    if (@hasField(std.posix.SIG, "UNUSED")) try setupSignal(state, .UNUSED);

    // POSIX.1-1990, according to man 7 signal
    try setupSignal(.HUP);
    try setupSignal(.INT);
    try setupSignal(.QUIT);
    try setupSignal(.ILL);
    try setupSignal(.ABRT);
    try setupSignal(.FPE);
    try setupSignal(.KILL);
    try setupSignal(.SEGV);
    try setupSignal(.PIPE);
    try setupSignal(.ALRM);
    try setupSignal(.TERM);
    try setupSignal(.USR1);
    try setupSignal(.USR2);
    try setupSignal(.CHLD);
    try setupSignal(.CONT);
    try setupSignal(.STOP);
    try setupSignal(.TSTP);
    try setupSignal(.TTIN);
    try setupSignal(.TTOU);

    // POSIX.1-2001, according to man 7 signal */
    try setupSignal(.BUS);
    // Some Operating Systems doesn't have SIGPOLL (e.g. FreeBSD) */
    if (@hasField(std.posix.SIG, "POLL")) try setupSignal(state, .POLL);

    try setupSignal(.PROF);
    try setupSignal(.SYS);
    try setupSignal(.TRAP);
    try setupSignal(.URG);
    try setupSignal(.VTALRM);
    try setupSignal(.XCPU);
    try setupSignal(.XFSZ);

    // Set awesome.signal to the table we just created, key was already pushed
    try state.rawSetTable(-3);
    // pop `awesome`;
    state.pop(1);
}
fn setupSignal(state: *Lua, sig: std.posix.SIG) !void {
    // Set awesome.unix_signal["SIGSTOP"] = 42
    try state.pushInteger(sig);
    state.setField(-2, @tagName(sig));

    // Set awesome.unix_signal[42] = "SIGSTOP"
    state.pushInteger(sig);
    state.pushString(@tagName(sig));
    state.setTable(-3);
}

const stdlib = @cImport({
    @cInclude("stdlib.h");
});
pub fn initRng(state: *Lua) !void {
    const math_type = try state.getGlobal("math");
    std.debug.assert(math_type == .table);
    const randomseed_type = state.getField(-1, "randomseed");
    std.debug.assert(randomseed_type == .function);

    const randomseed = undefined; // Random enough. Whatever data was left. NOT secure
    var prng = std.Random.DefaultPrng.init(randomseed);
    const rand = prng.random();
    state.pushInteger(rand.int(u32));
    // Call `math.randomseed`
    state.protectedCall(.{
        .args = 1,
        .results = 0,
        .msg_handler = 0,
    }) catch |err| {
        log.warn("Random number generator initialization failed: {t}-{s}", .{ err, state.toString(-1) catch |err2| return err2 });
        state.pop(2);
        return;
    };

    // Remove `math`
    state.pop(1);

    // Seed random for the C stdlib which Lua calls
    stdlib.srand(rand.int(u32));
    stdlib.srandom(rand.int(u32));
}

pub fn loadRc(state: *Lua, config_path: ?[:0]const u8) !void {
    const path = config_path orelse std.process.fatal("Config path fallback not implemented!!!!!!!!!", .{});
    state.doFile(path) catch |err| {
        const msg = state.toString(-1) catch |err2| return err2;
        log.err("Failed to load from file: {t} - {s}", .{ err, msg });
        return err;
    };

    state.pushFunction(lua.wrap(onError));
    state.insert(-2);
    state.protectedCall(.{
        .args = 0,
        .results = 0,
        .msg_handler = -2,
    }) catch |err| {
        const msg = state.toString(-1) catch |err2| return err2;
        log.err("Failed to run config file: {t} - {s}", .{ err, msg });
        state.pop(2);
    };

    state.pop(1);
}

fn onError(state: *Lua) i32 {
    _ = state;
    log.err("Hit onError", .{});
    // TODO: Convert this over
    // // Convert error to string, to prevent a follow-up error with lua_concat.
    // luaA_tolstring(L, -1, NULL);
    //
    // /* duplicate string error */
    // lua_pushvalue(L, -1);
    // /* emit error signal */
    // signal_object_emit(L, &global_signals, "debug::error", 1);
    //
    // if(!luaL_dostring(L, "return debug.traceback(\"error while running function!\", 3)"))
    // {
    //     /* Move traceback before error */
    //     lua_insert(L, -2);
    //     /* Insert sentence */
    //     lua_pushliteral(L, "\nerror: ");
    //     /* Move it before error */
    //     lua_insert(L, -2);
    //     lua_concat(L, 3);
    // }
    return 0;
}
