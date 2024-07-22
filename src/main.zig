const std = @import("std");
const zigimg = @import("zigimg");
const yazap = @import("yazap");
const vaxis = @import("vaxis");
const root = @import("root.zig");

const Event = union(enum) {
    key_press: vaxis.Key,
    winsize: vaxis.Winsize,
};

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer if (gpa.detectLeaks()) std.log.err("Memory Leak Detected!", .{});
    const alloc = gpa.allocator();

    var app = yazap.App.init(alloc, "libvaxis", "Experimenting");
    defer app.deinit();

    var libvaxis = app.rootCommand();

    try libvaxis.addArg(yazap.Arg.booleanOption("version", 'v', "Print version number"));
    try libvaxis.addArg(yazap.Arg.singleValueOption("file", 'f', "File to asciify"));
    const matches = try app.parseProcess();
    if (!matches.containsArgs()) {
        try app.displayHelp();
        return;
    }
    if (matches.containsArg("version")) {
        std.log.info("v0.1.0", .{});
        return;
    }
    const file = matches.getSingleValue("file") orelse @panic("Usage: zig-libvaxis <file>\n");
    var img = try zigimg.Image.fromFilePath(alloc, file);
    defer img.deinit();

    try img.convert(.rgb24);
    var render = try root.tuify(alloc, img);
    defer switch (render) {
        .single_frame => |*s| s.deinit(),
        .multi_frames => |m| for (m) |*me| me.deinit(),
    };

    var tty = try vaxis.Tty.init();
    defer tty.deinit();

    var vx = try vaxis.init(alloc, .{});
    defer vx.deinit(alloc, tty.anyWriter());

    var loop: vaxis.Loop(Event) = .{
        .tty = &tty,
        .vaxis = &vx,
    };
    try loop.init();

    try loop.start();
    defer loop.stop();

    try vx.enterAltScreen(tty.anyWriter());
    try vx.queryTerminal(tty.anyWriter(), 1 * std.time.ns_per_s);

    while (true) {
        const event = loop.nextEvent();
        switch (event) {
            .key_press => |key| {
                if (key.matches('c', .{ .ctrl = true })) {
                    break;
                } else if (key.matches('l', .{ .ctrl = true })) {
                    vx.queueRefresh();
                }
            },
            .winsize => |ws| try vx.resize(alloc, tty.anyWriter(), ws),
        }
        const win = vx.window();
        try root.render(alloc, win, img, render, tty, &vx);
    }
}
