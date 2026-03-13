const lua = @import("lua");
const Class = @import("lua/Class.zig");

class: Class,

pub fn setup(state: *lua.Lua) void {
    const methods = [_]lua.FnReg{
    .{ .name = "add_signal", .func = addSignal },
    .{ .name = "connect_signal", .func = connectSignal },
    .{ .name = "disconnect_signal", .func = disconnectSignal },
    .{ .name = "emit_signal", .func = emitSignal },
    .{ .name = "instances", .func = instances },
    .{ .name = "set_index_miss_handler", .func = setIndexMissHandler },
    .{ .name = "set_newindex_miss_handler", .func = setNewIndexMissHandler },
    .{ .name = "count", .func = count },
    .{ .name = "_viewports", .func = viewports },
    .{ .name = "_scan_quiet", .func = quietScan },
    .{ .name = "__index", .func = moduleIndex },
    .{ .name = "__newindex", .func = moduleNewIndex },
    .{ .name = "__call", .func = call },
    .{ .name = "fake_add", .func = fakeAdd },
    };
    const meta = [_]lua.FnReg{
};

    const struct luaL_Reg screen_meta[] =
    {
        LUA_OBJECT_META(screen)
        LUA_CLASS_META
        { "fake_remove", luaA_screen_fake_remove },
        { "fake_resize", luaA_screen_fake_resize },
        { "swap", luaA_screen_swap },
        { NULL, NULL },
    };

    luaA_class_setup(L, &screen_class, "screen", NULL,
                     (lua_class_allocator_t) screen_new,
                     (lua_class_collector_t) screen_wipe,
                     (lua_class_checker_t) screen_checker,
                     luaA_class_index_miss_property, luaA_class_newindex_miss_property,
                     screen_methods, screen_meta);
    luaA_class_add_property(&screen_class, "geometry",
                            NULL,
                            (lua_class_propfunc_t) luaA_screen_get_geometry,
                            NULL);
    luaA_class_add_property(&screen_class, "index",
                            NULL,
                            (lua_class_propfunc_t) luaA_screen_get_index,
                            NULL);
    luaA_class_add_property(&screen_class, "_outputs",
                            NULL,
                            (lua_class_propfunc_t) luaA_screen_get_outputs,
                            NULL);
    luaA_class_add_property(&screen_class, "_managed",
                            NULL,
                            (lua_class_propfunc_t) luaA_screen_get_managed,
                            NULL);
    luaA_class_add_property(&screen_class, "workarea",
                            NULL,
                            (lua_class_propfunc_t) luaA_screen_get_workarea,
                            NULL);
    luaA_class_add_property(&screen_class, "name",
                            (lua_class_propfunc_t) luaA_screen_set_name,
                            (lua_class_propfunc_t) luaA_screen_get_name,
                            (lua_class_propfunc_t) luaA_screen_set_name);
}

