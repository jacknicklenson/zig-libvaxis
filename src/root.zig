const std = @import("std");
const zigimg = @import("zigimg");
const vaxis = @import("vaxis");

pub const Rendered = union(enum) {
    single_frame: zigimg.Image,
    multi_frames: []zigimg.Image,
};

fn parse_anim() Rendered {
    @panic("Unimplemented!");
}

pub fn tuify(alloc: std.mem.Allocator, img: zigimg.Image) !Rendered {
    if (img.isAnimation()) {
        return parse_anim();
    } else {
        var grayscale_img = try zigimg.Image.create(alloc, img.width, img.height, .rgb24);
        for (img.pixels.rgb24, 0..) |p, idx| {
            grayscale_img.pixels.rgb24[idx] = zigimg.color.Rgb24.initRgb(p.g, p.g, p.g);
        }

        return Rendered{ .single_frame = grayscale_img };
    }
}

pub fn render(alloc: std.mem.Allocator, win: vaxis.Window, img: zigimg.Image, tuified: Rendered, tty: vaxis.Tty, vx: *vaxis.Vaxis) !void {
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
    for (tuified.single_frame.pixels.rgb24, 0..) |p, idx| {
        const y = idx / img.width;
        const cy = y / ch;
        const cx = (idx % img.width) / cw;
        g.items[cy % h].items[cx % w] += p.r;
    }
    win.clear();
    var segments = std.ArrayList(vaxis.Segment).init(alloc);
    defer segments.deinit();
    for (0..h) |y| {
        for (0..w) |x| {
            g.items[y].items[x] /= total_cell_pixel;
            const avg = g.items[y].items[x];
            const style: vaxis.Style = .{
                .fg = .{ .rgb = [3]u8{ @truncate(avg), @truncate(avg), @truncate(avg) } },
                .bg = .{ .rgb = [3]u8{ 0, 0, 0 } },
            };
            try segments.append(.{ .style = style, .text = "·" });
        }
    }
    _ = try win.print(segments.items, .{});
    try vx.render(tty.anyWriter());
}
