const std = @import("std");
const lua = @import("lua");
const zanylua = @import("../lua.zig");
const lib = @import("../lua/lib.zig");
const util = @import("../util.zig");
const Signals = @import("../Signals.zig");
const Object = @import("./Object.zig");
const globals = @import("../globals.zig");

const log = std.log.scoped(.luaclass);

const Class = @This();

name: [:0]const u8,
signals: Signals = .{},
parent: ?*Class = null,
// /** Allocator for creating new objects of that class */
allocator: *const fn (state: *lua.Lua) ?*Object,
// /** Garbage collection function */
collector: *const fn (obj: *Object) void,
properties: []Property,
indexMissProperty: ?PropFn = null,
newindexMissProperty: ?PropFn = null,
checker: ?Checker = null,
instances: u32 = 0,
tostring: ?PropFn = null,
indexMissHandler: i32 = lua.ref_nil,
newindexMissHandler: i32 = lua.ref_nil,

const Handler = *const fn (state: *lua.Lua) c_int;
const PropFn = *const fn (state: *lua.Lua, obj: *Object) i32;

const Checker = *const fn (obj: *Object) bool;

pub const Property = struct {
    name: [:0]const u8,
    new: ?PropFn = null,
    index: ?PropFn = null,
    newindex: ?PropFn = null,
};

/// prefix##_new
pub fn create(class: *Class, comptime T: type, state: *lua.Lua) ?*T {
    const item = state.newUserdata(T);
    item.* = .{};
    class.instances += 1;

    _ = class.setType(state);
    state.newTable();
    state.newTable();
    state.setMetatable(-2);
    state.newTable();
    state.setField(-2, "data");
    lib.setUserValue(state, -2) catch |err| {
        std.debug.panic("Unexpected error in setUserValue: {t}", .{err});
        return null;
    };
    state.pushValue(-1);
    class.signals.emit(state, "new", 1);

    return item;
}

pub fn format(
    self: Class,
    writer: *std.Io.Writer,
) std.Io.Writer.Error!void {
    return writer.print("Class(name={s}, parent={s})", .{ self.name, if (self.parent) |p| p.name else "none" });
}

fn add_signal(state: *lua.Lua) i32 {
    _ = state;
    log.warn("add_signal is deprecated", .{});
    return 0;
}
// luaA_##prefix##_class_connect_signal
fn connect_signal(state: *lua.Lua) i32 {
    const class = state.toUserdata(Class, lua.Lua.upvalueIndex(1)) catch {
        @breakpoint();
        log.warn("No class upvalue ({d})!!!!!!!", .{lua.Lua.upvalueIndex(1)});
        return 0;
    };
    const name = state.checkString(1);
    log.debug("Connecting signal `{s}` for class {s}", .{ name, class.name });
    connectSignalFromStack(state, class, name, 2);
    return 0;
}

// luaA_##prefix##_class_disconnect_signal
fn disconnect_signal(state: *lua.Lua) i32 {
    const class = state.toUserdata(Class, lua.Lua.upvalueIndex(1)) catch {
        @breakpoint();
        log.warn("No class upvalue ({d})!!!!!!!", .{lua.Lua.upvalueIndex(1)});
        return 0;
    };
    const name = state.checkString(1);
    disconnectSignalFromStack(state, class, name, 2);
    return 0;
}

// luaA_##prefix##_class_emit_signal
fn emit_signal(state: *lua.Lua) i32 {
    const class = state.toUserdata(Class, lua.Lua.upvalueIndex(1)) catch {
        @breakpoint();
        log.warn("No class upvalue ({d})!!!!!!!", .{lua.Lua.upvalueIndex(1)});
        return 0;
    };
    const name = state.checkString(1);
    log.debug("Emitting signal `{s}` for class {s}", .{ name, class.name });
    class.signals.emit(state, name, state.getTop() - 1);
    return 0;
}
fn getInstances(state: *lua.Lua) i32 {
    const class = state.toUserdata(Class, lua.Lua.upvalueIndex(1)) catch {
        return 0;
    };
    state.pushInteger(class.instances);
    return 1;
}
// luaA_##prefix##_set_newindex_miss_handler
fn set_index_miss_handler(state: *lua.Lua) i32 {
    const class = state.toUserdata(Class, lua.Lua.upvalueIndex(1)) catch {
        @breakpoint();
        log.warn("No class upvalue ({d})!!!!!!!", .{lua.Lua.upvalueIndex(1)});
        return 0;
    };
    return lib.registerFct(state, 1, &class.indexMissHandler);
}
fn set_newindex_miss_handler(state: *lua.Lua) i32 {
    const class = state.toUserdata(Class, lua.Lua.upvalueIndex(1)) catch {
        @breakpoint();
        log.warn("No class upvalue ({d})!!!!!!!", .{lua.Lua.upvalueIndex(1)});
        return 0;
    };
    return lib.registerFct(state, 1, &class.newindexMissHandler);
}

// Convert a object to a udata if possible.
// \param L The Lua VM state.
// \param ud The index.
// \param class The wanted class.
// \return A pointer to the object, NULL otherwise.
pub fn toudata(state: *lua.Lua, ud: i32, class: *Class) ?*Object {
    const userdata = state.toUserdata(Object, ud) catch return null;
    state.getMetatable(ud) catch return null;

    // Get the lua_class_t that matches this metatable
    _ = state.rawGetTable(lua.registry_index);
    var metatable_class = state.toUserdata(Class, -1) catch null;

    // remove lightuserdata (lua_class pointer) */
    state.pop(1);

    // Now, check that the class given in argument is the same as the
    // metatable's object, or one of its parent (inheritance) */
    while (metatable_class) |c| : (metatable_class = metatable_class.?.parent) {
        if (c == class) return userdata;
    }
    return null;
}

// Check for a udata class.
// \param L The Lua VM state.
// \param ud The object index on the stack.
// \param class The wanted class.
pub fn checkudata(class: *Class, state: *lua.Lua, ud: i32) ?*Object {
    const p = toudata(state, ud, class);
    if (p == null) {
        _ = zanylua.typeError(state, ud, class.name);
    } else if (class.checker != null and !class.checker.?(p.?)) {
        state.raiseErrorStr("invalid object", .{});
    }
    return p;
}

// Get an object lua_class.
// \param L The Lua VM state.
// \param idx The index of the object on the stack.
pub fn get(state: *lua.Lua, offset: i32) ?*Class {
    const stack_depth_start = state.getTop();
    defer lib.assertStackEffect(0, stack_depth_start, state.getTop());
    const t = state.typeOf(offset);
    state.getMetatable(offset) catch return null;
    if (t == .userdata) {
        _ = state.rawGetTable(lua.registry_index);
        const class = state.toUserdata(Class, -1) catch return null;
        state.pop(1);
        return class;
    }
    return null;
}

// Newindex meta function for objects after they were GC'd.
// \param L The Lua VM state.
// \return The number of elements pushed on stack.
fn newindexInvalid(state: *lua.Lua) i32 {
    state.raiseErrorStr("attempt to index an object that was already garbage collected", .{});
}

// Index meta function for objects after they were GC'd.
// \param L The Lua VM state.
// \return The number of elements pushed on stack.
fn indexInvalid(state: *lua.Lua) i32 {
    const attr = state.checkString(2);
    if (std.mem.eql(u8, attr, "valid")) {
        state.pushBoolean(false);
        return 1;
    }
    return newindexInvalid(state);
}

// From `common/luaobject.c`
pub fn setType(class: *Class, state: *lua.Lua) i32 {
    state.pushLightUserdata(class);
    _ = state.rawGetTable(lua.registry_index);
    state.setMetatable(-2);
    return 1;
}

// Garbage collect a Lua object.
// \param L The Lua VM state.
// \return The number of elements pushed on stack.
fn gc(state: *lua.Lua) i32 {
    const item = state.toUserdata(Object, 1) catch unreachable;
    item.signals.signals.deinit(globals.gpa);
    // Get the object class
    var class: ?*Class = get(state, 1) orelse unreachable;
    class.?.instances -= 1;
    // Call the collector function of the class, and all its parent classes */
    while (class) |c| : (class = class.?.parent) {
        c.collector(item);
    }
    // Unset its metatable so that e.g. luaA_toudata() will no longer accept
    // this object. This is needed since other __gc methods can still use this.
    // We also make sure that `item.valid == false`.
    state.newTable();
    state.pushFunction(lua.wrap(indexInvalid));
    state.setField(-2, "__index");
    state.pushFunction(lua.wrap(newindexInvalid));
    state.setField(-2, "__newindex");
    state.setMetatable(1);
    return 0;
}

// Setup a new Lua class.
// \param L The Lua VM state.
// \param name The class name.
// \param parent The parent class (inheritance).
// \param allocator The allocator function used when creating a new object.
// \param Collector The collector function used when garbage collecting an
// object.
// \param checker The check function to call when using luaA_checkudata().
// \param index_miss_property Function to call when an object of this class
// receive a __index request on an unknown property.
// \param newindex_miss_property Function to call when an object of this class
// receive a __newindex request on an unknown property.
// \param methods The methods to set on the class table.
// \param meta The meta-methods to set on the class objects.
pub fn setup(class: *Class, state: *lua.Lua, methods: []const lua.FnReg, meta: []const lua.FnReg) !void {

    // Create the object metatable
    state.newTable();
    // Register it with class pointer as key in the registry
    // class-pointer -> metatable
    state.pushLightUserdata(class);
    // Duplicate the object metatable
    state.pushValue(-2);
    state.rawSetTable(lua.registry_index);
    // Now register class pointer with metatable as key in the registry
    // metatable -> class-pointer
    state.pushValue(-1);
    state.pushLightUserdata(class);
    state.rawSetTable(lua.registry_index);

    // Duplicate objects metatable
    state.pushValue(-1);
    // Set garbage collector in the metatable
    state.pushFunction(lua.wrap(gc));
    state.setField(-2, "__gc");

    state.setField(-2, "__index"); // metatable.__index = metatable      1

    {
        state.setFuncs(&Object.meta, 0);
        state.setFuncs(&.{
            .{ .name = "__index", .func = lua.wrap(index) },
            .{ .name = "__newindex", .func = lua.wrap(newIndex) },
        }, 0);
        state.setFuncs(meta, 0);
    } // 1

    {
        state.newTable(); // 2
        state.pushLightUserdata(class); // 3
        state.setFuncs(&.{
            .{ .name = "add_signal", .func = lua.wrap(add_signal) },
            .{ .name = "connect_signal", .func = lua.wrap(connect_signal) },
            .{ .name = "disconnect_signal", .func = lua.wrap(disconnect_signal) },
            .{ .name = "emit_signal", .func = lua.wrap(emit_signal) },
            .{ .name = "instances", .func = lua.wrap(getInstances) },
            .{ .name = "set_index_miss_handler", .func = lua.wrap(set_index_miss_handler) },
            .{ .name = "set_newindex_miss_handler", .func = lua.wrap(set_newindex_miss_handler) },
        }, 1); // 2
        state.setFuncs(methods, 0); //2
        state.pushValue(-1); //3
        state.setGlobal(class.name); //2
    } // 2
    state.pushValue(-1); // dup self as metatable              3
    state.setMetatable(-2); // set self as metatable              2 */
    state.pop(2);

    // lua_class_array_append(&luaA_classes, class);
}

// luaA_class_connect_signal
pub fn class_connect_signal(state: *lua.Lua, class: *Class, func: lua.FnReg) void {
    log.debug("class_connect_signal: {s} => {s}", .{ class.name, func.name });
    state.pushFunction(func.func.?);
    connectSignalFromStack(state, class, func.name, -1);
}

fn connectSignalFromStack(state: *lua.Lua, class: *Class, name: []const u8, ud: i32) void {
    lib.checkFunction(state, ud);
    const ref = Object.ref(state, ud) orelse unreachable;

    class.signals.connect(name, ref);
}

// const CONNECTED_SUFFIX = "::connected";
// fn connectSignalFromStack(state: *lua.Lua, class: *Class, name: []const u8, ud: i32) void {
//     lib.checkFunction(state, ud);
//
//     // Duplicate the function in the stack
//     state.pushValue(ud);
//
//     var buf: [1024]u8 = undefined;
//
//     const sig_name = std.fmt.bufPrintZ(&buf, "{s}{s}", .{ name, CONNECTED_SUFFIX }) catch unreachable;
//     // Emit a signal to notify Lua of the global connection.
//     //
//     //  This can useful during initialization where the signal needs to be
//     //  artificially emitted for existing objects as soon as something connects
//     //  to it
//     //
//     const ref = Object.ref(state, ud) orelse unreachable;
//     const id = util.strhash(sig_name);
//     for (class.signals.signals.items) |*signal| {
//         if (signal.id == id) {
//             signal.emit(state, 1);
//             // /* Register the signal to the CAPI list */
//             signal.funcs.append(globals.gpa, ref) catch {
//                 log.err("Failed to append signal to list", .{});
//                 return;
//             };
//             return;
//         }
//     }
//     // Signal not found, create it
//     var sig: Signals.Signal = .{
//         .id = id,
//     };
//     sig.funcs.append(globals.gpa, ref) catch {
//         log.err("Failed to add signal handler to list", .{});
//     };
//     class.signals.signals.append(globals.gpa, sig) catch {
//         log.err("Failde to add signal to the list", .{});
//         // Drop handler since we won't be able to reference this signal in the future
//         sig.funcs.deinit(globals.gpa);
//     };
// }

fn disconnectSignalFromStack(state: *lua.Lua, class: *Class, name: []const u8, ud: i32) void {
    lib.checkFunction(state, ud);
    const ref = state.toPointer(ud) catch unreachable;
    if (class.signals.disconnect(name, @constCast(ref))) {
        Object.unref(state, ref);
    }
    state.remove(ud);
}

fn class_emit_signal(state: *lua.Lua, class: *Class, name: []const u8, nargs: i32) void {
    log.debug("Class emit signal: {s} => {s}", .{ class.name, name });
    class.signals.emit(state, name, nargs);
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
        _ = state.rawGetTable(lua.registry_index);

        state.pushValue(idxfield);
        _ = state.rawGetTable(-2);

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
    var lua_class: ?*Class = self;
    while (lua_class) |c| : (lua_class = lua_class.?.parent) {
        const prop = c.getPropertyByName(attr);
        if (prop) |p| return p;
    }

    return null;
}

// Generic index meta function for objects.
// \param L The Lua VM state.
// \return The number of elements pushed on stack.
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
        if (class.checker) |checker| {
            state.pushBoolean(p != null and checker(p.?));
        } else {
            state.pushBoolean(p != null);
        }
        return 1;
    }

    const property = class.getProperty(state, 2);

    // This is the table storing the object private variables.
    const private: [:0]const u8 = "_private";
    const data: [:0]const u8 = "data";
    if (std.mem.eql(u8, attr, private)) {
        _ = class.checkudata(state, 1);
        zanylua.getuservalue(state, 1);
        _ = state.getField(-1, "data");
        return 1;
    } else if (std.mem.eql(u8, attr, data)) {
        // TODO: uncomment this after updating to awseome base branch
        // zanylua.deprecate(@src(), state, "Use `._private` instead of `.data`");
        _ = class.checkudata(state, 1);
        zanylua.getuservalue(state, 1);
        _ = state.getField(-1, "data");
        return 1;
    }

    // Property does exist and has an index callback */
    if (property) |prop| {
        if (prop.index) |indexFn|
            return indexFn(state, class.checkudata(state, 1).?);
    } else {
        if (class.indexMissHandler != lua.ref_nil) {
            return lib.callHandler(state, class.indexMissHandler);
        }
        if (class.indexMissProperty) |prop| {
            return prop(state, class.checkudata(state, 1).?);
        }
    }

    return 0;
}

// Generic newindex meta function for objects.
// \param L The Lua VM state.
// \return The number of elements pushed on stack.
//
pub fn newIndex(state: *lua.Lua) i32 {
    // Try to use metatable first.
    if (useMetatable(state, 1, 2))
        return 1;

    const class = get(state, 1) orelse return 0;

    const property = class.getProperty(state, 2);

    // Property does exist and has a newindex callback
    if (property) |prop| {
        if (prop.newindex) |func| {
            const obj = class.checkudata(state, 1);
            return func(state, obj.?);
        }
    } else {
        if (class.newindexMissHandler != lua.ref_nil) return lib.callHandler(state, class.newindexMissHandler);
        if (class.newindexMissProperty) |prop| {
            const obj = class.checkudata(state, 1);
            return prop(state, obj.?);
        }
    }

    return 0;
}

/// Generic constructor function for objects.
/// \param L The Lua VM state.
/// \return The number of elements pushed on stack.
///
/// luaA_class_new
pub fn new(class: *Class, state: *lua.Lua) i32 {
    // Check we have a table that should contains some properties
    lib.checkTable(state, 2);

    // Create a new object
    const obj = class.allocator(state) orelse return 0;
    // Push the first key before iterating
    state.pushNil();
    // Iterate over the property keys
    while (state.next(2)) {
        // Check that the key is a string.
        // We cannot call tostring blindly or Lua will convert a key that is a
        // number TO A STRING, confusing lua_next() */
        if (state.isString(-2)) {
            const prop = class.getProperty(state, -2);

            if (prop) |p| {
                if (p.new) |alloc| {
                    _ = alloc(state, obj);
                }
            }
        }
        // Remove value
        state.pop(1);
    }

    return 1;
}
