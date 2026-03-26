const Color = @This();

pixel: u32,
red: u16,
green: u16,
blue: u16,
alpha: u16,
initialized: bool = false,

pub const default: Color = .{
    .pixel = 0,
    .alpha = 255,
    .red = undefined,
    .blue = undefined,
    .green = undefined,
    .initialized = false,
};
