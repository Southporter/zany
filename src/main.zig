const std = @import("std");
const builtin = @import("builtin");
const log = std.log.scoped(.zany);
const Zany = @import("zanywm");
const Config = Zany.Config;

pub fn main() !void {
    var gpa: std.heap.DebugAllocator(.{}) = .init;
    defer if (gpa.deinit() == .leak) {
        log.warn("Memory leak detected", .{});
    };
    var stdout_file = std.fs.File.stdout();
    var stdout_buf: [1024]u8 = undefined;
    var stdout_writer = stdout_file.writer(stdout_buf[0..]);

    var options_arena = std.heap.ArenaAllocator.init(gpa.allocator());
    defer options_arena.deinit();
    var args = std.process.args();
    var config = checkOptions(&args, options_arena.allocator()) catch |err| {
        log.info("Options check failed. Printing help: {t}", .{err});
        try help(&stdout_writer.interface);
        try stdout_writer.interface.flush();
        return;
    };
    const config_paths = std.process.getEnvVarOwned(options_arena.allocator(), "XDG_CONFIG_DIRS") catch "/etc/xdg";
    // const config_home = std.process.getEnvVarOwned(options_arena.allocator(), "XDG_CONFIG_HOME") catch "";

    var config_path_iter = std.mem.splitSequence(u8, config_paths, ":");
    while (config_path_iter.next()) |path| {
        try config.search.append(options_arena.allocator(), try options_arena.allocator().dupeZ(u8, path));
    }
    var zany: Zany = undefined;
    try zany.init(gpa.allocator(), config);
    defer zany.deinit(gpa.allocator());

    {
        var sa: std.posix.Sigaction = .{
            .handler = .{
                .handler = fatal,
            },
            .flags = std.posix.SA.RESETHAND,
            .mask = std.posix.sigemptyset(),
        };
        std.posix.sigaction(std.posix.SIG.ABRT, &sa, null);
        std.posix.sigaction(std.posix.SIG.BUS, &sa, null);
        std.posix.sigaction(std.posix.SIG.FPE, &sa, null);
        std.posix.sigaction(std.posix.SIG.ILL, &sa, null);
        std.posix.sigaction(std.posix.SIG.SEGV, &sa, null);

        sa.handler.handler = child;
        sa.flags = std.posix.SA.NOCLDSTOP | std.posix.SA.RESTART;
        std.posix.sigaction(std.posix.SIG.CHLD, &sa, null);
    }

    try zany.run();
}

fn help(writer: *std.Io.Writer) std.Io.Writer.Error!void {
    return writer.writeAll(
        \\Usage: zany [OPTION]
        \\  -h, --help             show help
        \\  -v, --version          show version
        \\  -c, --config FILE      configuration file to use
        \\  -f, --force            ignore modelines and apply the command line arguments
        \\  -s, --search DIR       add a directory to the library search path
        \\  -k, --check            check configuration file syntax
        \\  -a, --no-argb          disable client transparency support
        \\  -l  --api-level LEVEL  select a different API support level than the current version 
        \\  -m, --screen on|off    enable or disable automatic screen creation (default: on)
        \\  -r, --replace          replace an existing window manager
        \\
    );
}

const Flag = enum {
    help,
    version,
    config,
    force,
    search,
    check,
    no_argb,
    api_level,
    screen,
    replace,

    invalid,
    fn from(src: [:0]const u8) Flag {
        if (src[0] != '-') {
            return .invalid;
        }
        if (src.len == 2) {
            return switch (src[1]) {
                'h' => .help,
                'v' => .version,
                'c' => .config,
                'f' => .force,
                's' => .search,
                'k' => .check,
                'a' => .no_argb,
                'l' => .api_level,
                'm' => .screen,
                'r' => .replace,
                else => .invalid,
            };
        } else {
            if (src[0] != '-' or src[1] != '-') {
                return .invalid;
            }
            return switch (src[2]) {
                'h' => if (std.mem.eql(u8, src[2..], "help")) .help else .invalid,
                'v' => if (std.mem.eql(u8, src[2..], "version")) .version else .invalid,
                'c' => switch (src[3]) {
                    'h' => if (std.mem.eql(u8, src[2..], "check")) .check else .invalid,
                    'o' => if (std.mem.eql(u8, src[2..], "config")) .config else .invalid,
                    else => .invalid,
                },
                'f' => if (std.mem.eql(u8, src[2..], "force")) .force else .invalid,
                'n' => if (std.mem.eql(u8, src[2..], "no-argb")) .no_argb else .invalid,
                'a' => if (std.mem.eql(u8, src[2..], "api-level")) .api_level else .invalid,
                'r' => if (std.mem.eql(u8, src[2..], "replace")) .replace else .invalid,
                's' => switch (src[3]) {
                    'c' => if (std.mem.eql(u8, src[2..], "screen")) .screen else .invalid,
                    'e' => if (std.mem.eql(u8, src[2..], "search")) .search else .invalid,
                    else => .invalid,
                },
                else => .invalid,
            };
        }
    }
};

fn checkOptions(args: *std.process.ArgIterator, arena: std.mem.Allocator) !Config {
    var config = Config{};

    const cmd = args.next();
    log.debug("Cmd is {?s}", .{cmd});

    while (args.next()) |arg| {
        log.debug("Processing arg: {s}", .{arg});
        switch (Flag.from(arg)) {
            .help => return error.HelpCalled,
            .version => config.version = true,
            .config => {
                const file = args.next() orelse return error.InvalidConfigSwitch;
                config.config = file;
            },
            .force => config.force = true,
            .search => {
                const path = args.next() orelse return error.InvalidSearchSwitch;
                try config.search.append(arena, try arena.dupeZ(u8, path));
            },
            .check => config.check = true,
            .no_argb => config.no_argb = true,
            .api_level => {
                const level = args.next() orelse return error.InvalidApiLevelSwitch;
                config.api_level = try std.SemanticVersion.parse(level);
            },
            .screen => {
                const raw = args.next() orelse return error.InvalidScreenSwitch;
                config.screen = std.meta.stringToEnum(Config.ScreenCreation, raw) orelse return error.InvalidScreenValue;
            },
            .replace => config.replace = true,
            .invalid => return error.UnknownFlag,
        }
    }

    return config;
}

fn fatal(sig: i32) callconv(.c) void {
    log.err("signal {d}, dumping stack trace", .{sig});
    std.debug.dumpCurrentStackTrace(null);
    std.process.exit(1);
}

fn child(sig: i32) callconv(.c) void {
    std.debug.assert(sig == std.posix.SIG.CHLD);
    std.process.fatal("Recieved SIG.CHLD", .{});
}
