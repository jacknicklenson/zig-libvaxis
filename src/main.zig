const std = @import("std");
const zigimg = @import("zigimg");
const yazap = @import("yazap");
const vaxis = @import("vaxis");
const Cell = vaxis.Cell;
const TextInput = vaxis.widgets.TextInput;
const border = vaxis.widgets.border;

const chars_brightness = " `.-':_,^=;><+!rc*/z?sLTv)J7(|Fi{C}fI31tlu[neoZ5Yxjya]2ESwqkP6h9d4VpOGbUAKXHm8RD#$Bg0MNWQ%&@";

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

    var grayscale_img = try zigimg.Image.create(alloc, 400, 300, zigimg.PixelFormat.rgb24);
    defer grayscale_img.deinit();
    for (img.pixels.rgb24, 0..) |p, idx| {
        grayscale_img.pixels.rgb24[idx] = zigimg.color.Rgb24.initRgb(p.g, p.g, p.g);
    }

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
        const w = win.width;
        const h = win.height;
        const cw = img.width / w;
        const ch = img.height / h;
        const total_cell_pixel = cw * ch;
        var g = std.ArrayList(std.ArrayList(usize)).init(alloc);
        defer {
            for (0..h) |j| g.items[j].deinit();
            g.deinit();
        }
        for (0..h) |j| {
            try g.append(std.ArrayList(usize).init(alloc));
            for (0..w) |_| {
                try g.items[j].append(0);
            }
        }
        for (grayscale_img.pixels.rgb24, 0..) |p, idx| {
            const y = idx / img.width;
            const cy = y / ch;
            const cx = idx / cw;
            g.items[cy % h].items[cx % w] += p.r;
        }
        win.clear();
        for (0..h) |y| {
            for (0..w) |x| {
                g.items[y].items[x] /= total_cell_pixel;
                const avg = g.items[y].items[x];
                const style: vaxis.Style = .{
                    .fg = .{ .rgb = [3]u8{ @truncate(avg), @truncate(avg), @truncate(avg) } },
                    .bg = .{ .rgb = [3]u8{ 0, 0, 0 } },
                };
                _ = try win.printSegment(.{ .style = style, .text = "·" }, .{});
            }
        }
        try vx.render(tty.anyWriter());
    }
}
