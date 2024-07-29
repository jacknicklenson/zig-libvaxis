const std = @import("std");
const zigimg = @import("zigimg");
const vaxis = @import("vaxis");

pub const Rendered = union(enum) {
    single_frame: zigimg.Image,
    multi_frames: []zigimg.Image,
};

fn parse_anim(alloc: std.mem.Allocator, img: zigimg.Image) !Rendered {
    var frame = std.ArrayList(zigimg.Image).init(alloc);
    for (img.animation.frames.items) |f| {
        var grayscale_img = try zigimg.Image.create(alloc, img.width, img.height, .rgb24);
        defer grayscale_img.deinit();
        for (f.pixels.indexed8.palette, 0..) |p, idx| {
            grayscale_img.pixels.rgb24[idx] = zigimg.color.Rgb24.initRgb(p.g, p.g, p.g);
        }
        try frame.append(grayscale_img);
    }
    return .{ .multi_frames = try frame.toOwnedSlice() };
}

pub fn tuify(alloc: std.mem.Allocator, img: zigimg.Image) !Rendered {
    if (img.isAnimation()) {
        return parse_anim(alloc, img);
    } else {
        var grayscale_img = try zigimg.Image.create(alloc, img.width, img.height, .rgb24);
        for (img.pixels.rgb24, 0..) |p, idx| {
            grayscale_img.pixels.rgb24[idx] = zigimg.color.Rgb24.initRgb(p.g, p.g, p.g);
        }

        return Rendered{ .single_frame = grayscale_img };
    }
}

pub fn render(alloc: std.mem.Allocator, win: vaxis.Window, img: zigimg.Image, tuified: Rendered, tty: vaxis.Tty, vx: *vaxis.Vaxis) !void {
    switch (tuified) {
        .multi_frames => |mf| {
            if (mf[0].width < win.width)
                std.debug.panic("image width ({d}) is smaller than terminal cell width ({d}). It should be bigger or equal!", .{ mf[0].width, win.width });
            if (mf[0].height < win.height)
                std.debug.panic("image height ({d}) is smaller than terminal cell height ({d}). It should be bigger or equal!", .{ mf[0].height, win.height });
            const w = win.width;
            const h = win.height;
            const cw = mf[0].width / w;
            const ch = mf[0].height / h;
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
            for (mf) |simg| {
                for (simg.pixels.rgb24, 0..) |p, idx| {
                    const y = idx / simg.width;
                    const cy = y / ch;
                    const cx = (idx % simg.width) / cw;
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
                        try segments.append(.{ .style = style, .text = "." });
                    }
                }
                _ = try win.print(segments.items, .{});
                try vx.render(tty.anyWriter());
                std.time.sleep(100_000_000);
            }
        },
        .single_frame => |simg| {
            if (simg.width < win.width)
                std.debug.panic("image width ({d}) is smaller than terminal cell width ({d}). It should be bigger or equal!", .{ simg.width, win.width });
            if (simg.height < win.height)
                std.debug.panic("image height ({d}) is smaller than terminal cell height ({d}). It should be bigger or equal!", .{ simg.height, win.height });
            const w = win.width;
            const h = win.height;
            const cw = simg.width / w;
            const ch = simg.height / h;
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
            for (simg.pixels.rgb24, 0..) |p, idx| {
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
                    try segments.append(.{ .style = style, .text = "." });
                }
            }
            _ = try win.print(segments.items, .{});
            try vx.render(tty.anyWriter());
        },
    }
}
