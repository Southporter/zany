const std = @import("std");
const lua = @import("lua");
const lib = @import("lua/lib.zig");
const Class = @import("lua/Class.zig");
const Object = @import("lua/Object.zig");
const Client = @import("client.zig");
const globals = @import("globals.zig");

const Tag = @This();
obj: Object = .{},

name: ?[:0]const u8 = null,
activated: bool = false,
selected: bool = false,
clients: std.ArrayList(*Client) = .empty,

var tag_class: Class = .{
    .name = "tag",
    .properties = props[0..],
    .allocator = new,
    .collector = wipe,
};

var props = [_]Class.Property{
    .{ .name = "name", .new = setName, .index = getName, .newindex = setName },
};

pub fn setup(state: *lua.Lua) !void {
    const methods = [_]lua.FnReg{
        .{ .name = "__call", .func = lua.wrap(newTag) },
    };
    const meta = [_]lua.FnReg{
        .{ .name = "clients", .func = lua.wrap(getClients) },
    };

    return tag_class.setup(state, &methods, &meta);
}

fn new(state: *lua.Lua) ?*Object {
    const tag = tag_class.create(Tag, state) orelse return null;
    return &tag.obj;
}

fn wipe(obj: *Object) void {
    const tag: *Tag = @fieldParentPtr("obj", obj);
    globals.gpa.destroy(tag);
}

// Create a new tag.
// \param L The Lua VM state.
// \luastack
// \lparam A name.
// \lreturn A new tag object.
fn newTag(state: *lua.Lua) i32 {
    return tag_class.new(state);
}

// Get or set the clients attached to this tag.
//
// @tparam[opt=nil] table clients_table None or a table of clients to set as being tagged with
//  this tag.
// @treturn table A table with the clients attached to this tags.
// @method clients
fn getClients(state: *lua.Lua) i32 {
    //     tag_t *tag = luaA_checkudata(L, 1, &tag_class);
    const obj = tag_class.checkudata(state, 1) orelse return 0;
    const tag: *Tag = @fieldParentPtr("obj", obj);
    if (state.getTop() == 2) {
        lib.checkTable(state, 2);
        for (tag.clients.items) |c| {

            // Only untag if we aren't going to add this tag again
            var found = false;
            state.pushNil();
            while (state.next(2)) {
                const tc = Client.client_class.checkudata(state, -1);
                state.pop(1);
                if (&c.window.obj != tc) continue;
                state.pop(1);
                found = true;
                break;
            }
            if (!found) {
                tag.untagClient(c);
            }
        }

        state.pushNil();
        while (state.next(1)) {
            const o = Client.client_class.checkudata(state, -1);
            const client = Client.from(o.?);
            state.pushValue(1);
            tagClient(state, client);
            state.pop(1);
        }
    }
    state.createTable(@intCast(tag.clients.items.len), 0);

    for (tag.clients.items, 0..) |client, i| {
        _ = Object.push(state, client);
        state.rawSetIndex(-2, @intCast(i + 1));
    }
    return 1;
}
// Tag a client with the tag on top of the stack.
// \param L The Lua VM state.
// \param c the client to tag
fn tagClient(state: *lua.Lua, client: *Client) void {
    const pointer = Object.refClass(state, -1, &tag_class) orelse return;
    const obj: *Object = @ptrCast(@alignCast(pointer));
    const tag: *Tag = @fieldParentPtr("obj", obj);
    // don't tag twice
    if (tag.isTagged(client)) {
        Object.unref(state, tag);
        return;
    }
    tag.clients.append(std.heap.c_allocator, client) catch return;
    // ewmh_client_update_desktop(c);
    // banning_need_update();
    // client.screen.updateWorkarea();
    // tag.emitClientSignal(client, "tagged");
}

// Check if a client is tagged with the specified tag.
// \param c the client
// \param t the tag
// \return true if the client is tagged with the tag, false otherwise.
fn isTagged(tag: *Tag, client: *Client) bool {
    for (tag.clients.items) |c| {
        if (client == c) return true;
    }
    return false;
}

// Set the tag name.
// \param L The Lua VM state.
// \param tag The tag to name.
// \return The number of elements pushed on stack.
//
fn setName(state: *lua.Lua, obj: *Object) i32 {
    const tag: *Tag = @fieldParentPtr("obj", obj);

    const buf = state.checkString(-1);
    if (tag.name) |name| std.heap.c_allocator.free(name);

    tag.name = std.heap.c_allocator.dupeZ(u8, buf) catch return 0;
    Object.emitSignal(state, -3, "property::name", 0);
    // ewmh_update_net_desktop_names();
    return 0;
}

fn getName(state: *lua.Lua, obj: *Object) i32 {
    const tag: *Tag = @fieldParentPtr("obj", obj);

    if (tag.name) |name| {
        _ = state.pushStringZ(name);
    } else {
        state.pushNil();
    }
    return 1;
}

fn untagClient(tag: *Tag, client: *Client) void {
    for (tag.clients.items) |c| {
        if (c == client) {
            std.debug.panic("Need to finish untagClient", .{});
            // lua_State *L = globalconf_get_lua_State();
            // client_array_take(&t->clients, i);
            // banning_need_update();
            // ewmh_client_update_desktop(c);
            // client.screen.?.updateWorkarea();
            // tag_client_emit_signal(t, c, "untagged");
            // luaA_object_unref(L, t);
            return;
        }
    }
}
