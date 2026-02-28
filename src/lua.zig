const std = @import("std");
const lua = @import("lua");

const Lua = lua.Lua;

const Vm = @This();

instance: *Lua,

pub fn init(gpa: std.mem.Allocator, onPanic: ) !Vm {
    const instance = try Lua.init(gpa);
    instance.atPanic(lua.wrap(zanyPanic));
    return .{
        .instance = instance,
    };
}

fn zanyPanic(instance: *Lua) i32 {
    return 0;
}

pub fn deinit(vm: *Vm) void {
    vm.instance.deinit();
}
