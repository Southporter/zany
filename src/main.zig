const std = @import("std");
const log = std.log.scoped(.zany);
const zanywm = @import("zanywm");

const ConfigOptions = packed struct {
    none: bool = true,
    argb: bool = true,
    run_test: bool = false,
    force: bool = false,
};

const Path: type = [:0]const u8;

pub fn main() !void {
    const gpa: std.heap.DebugAllocator(.{}) = .init;
    defer if (gpa.deinit() == .leak) {
        log.warn("Memory leak detected", {});
    };

    var args = std.process.args();
    var search_path: std.ArrayList(Path) = .empty;
    var options = ConfigOptions{};

    const conf_path = checkArgs(args, &options, &search_path);

    var zany = zanywm.init();
    defer zany.deinit();

    try zany.run();
}

const help =
    \\"Usage: zany [OPTION]
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
;
fn checkArgs(args: std.process.ArgIterator, options: *ConfigOptions, search_paths: *std.ArrayList(Path)) Path {}
