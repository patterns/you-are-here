const std = @import("std");
const vaxis = @import("vaxis");
const mapsy = @import("mapsy");

const Event = union(enum) {
    key_press: vaxis.Key,
    winsize: vaxis.Winsize,
};

pub fn main() !void {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    const alloc = arena.allocator();

    // TODO accept lat/lng args from libvaxis
    const lat = 47.608013;
    const lng = -122.335167;
    ////const lat = 40.7128;
    ////const lng = -74.006;

    const zoom = 14;
    const total = std.math.exp2(@as(f64, zoom));
    var map = mapsy.Map.init(.{
        .tilesize = 256,
        .zoom = zoom,
        .xdimension = 800,
        .ydimension = 600,
        .numtiles = total,
        .lat = lat,
        .lng = lng,
        .arena = arena,
    });
    defer map.deinit();

    map.mercator();
    map.originTile();
    map.tileCount();
    map.markerPixel();

    var cache = std.ArrayList([]const u8).init(alloc);
    defer cache.deinit(); //TODO do we need to free each item?
    map.rasterSeries(&cache) catch |err| {
        std.debug.print("Raster tile url list failed", .{});
        return err;
    };
    map.knit(cache) catch |err| {
        std.debug.print("Tile knitting failed", .{});
        return err;
    };

    // TUI begins
    var tty = try vaxis.Tty.init();
    defer tty.deinit();

    var vx = try vaxis.init(alloc, .{});
    defer vx.deinit(alloc, tty.anyWriter());

    var loop: vaxis.Loop(Event) = .{ .tty = &tty, .vaxis = &vx };
    try loop.init();

    try loop.start();
    defer loop.stop();

    try vx.enterAltScreen(tty.anyWriter());
    try vx.queryTerminal(tty.anyWriter(), 1 * std.time.ns_per_s);

    var img1 = try vaxis.zigimg.Image.fromFilePath(alloc, map.savepath);
    defer img1.deinit();

    const imgs = [_]vaxis.Image{
        try vx.transmitImage(alloc, tty.anyWriter(), &img1, .rgba),
        try vx.loadImage(alloc, tty.anyWriter(), .{ .path = "zig.png" }),
    };
    defer vx.freeImage(tty.anyWriter(), imgs[0].id);
    defer vx.freeImage(tty.anyWriter(), imgs[1].id);

    var n: usize = 0;

    var clip_y: u16 = 0;

    while (true) {
        const event = loop.nextEvent();
        switch (event) {
            .key_press => |key| {
                if (key.matches('c', .{ .ctrl = true })) {
                    return;
                } else if (key.matches('l', .{ .ctrl = true })) {
                    vx.queueRefresh();
                } else if (key.matches('j', .{}))
                    clip_y += 1
                else if (key.matches('k', .{}))
                    clip_y -|= 1;
            },
            .winsize => |ws| try vx.resize(alloc, tty.anyWriter(), ws),
        }

        n = (n + 1) % imgs.len;
        const win = vx.window();
        win.clear();

        const img = imgs[n];
        const dims = try img.cellSize(win);
        const center = vaxis.widgets.alignment.center(win, dims.cols, dims.rows);
        try img.draw(center, .{ .scale = .contain, .clip_region = .{
            .y = clip_y,
        } });

        try vx.render(tty.anyWriter());
    }
}
