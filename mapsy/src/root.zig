const std = @import("std");
const cairo = @import("cairo");
const s2 = @cImport({
    @cInclude("bindings.h");
});

const testing = std.testing;
const math = std.math;

pub const Map = struct {
    tilesize: i32,
    zoom: i32,
    xdimension: i32,
    ydimension: i32,
    numtiles: f64,
    lat: f64,
    lng: f64,
    xprojected: f64,
    yprojected: f64,
    xtileorigin: i32,
    ytileorigin: i32,
    xtilemark: f64,
    ytilemark: f64,
    xtilecount: i32,
    ytilecount: i32,
    ww: f64,
    hh: f64,
    xpixelmark: i32,
    ypixelmark: i32,
    savefile: []u8,
    savepath: []u8,
    appdatadir: []u8,
    arena: std.heap.ArenaAllocator,

    pub fn init(args: anytype) Map {
        return .{
            .tilesize = args.tilesize,
            .zoom = args.zoom,
            .xdimension = args.xdimension,
            .ydimension = args.ydimension,
            .numtiles = args.numtiles,
            .lat = args.lat,
            .lng = args.lng,
            .xprojected = 0,
            .yprojected = 0,
            .xtileorigin = 0,
            .ytileorigin = 0,
            .xtilemark = 0,
            .ytilemark = 0,
            .xtilecount = 0,
            .ytilecount = 0,
            .ww = 0,
            .hh = 0,
            .xpixelmark = 0,
            .ypixelmark = 0,
            .savefile = "",
            .savepath = "",
            .appdatadir = "",
            .arena = args.arena,
        };
    }

    pub fn mercator(me: *Map) void {
        // invoke s2 library to make projection from lat/lng to coords
        const pointe = s2.mercator(me.lat, me.lng);
        me.xprojected = pointe.x;
        me.yprojected = pointe.y;
        std.debug.print("projection {d}, {d} {s}", .{ me.xprojected, me.yprojected, newline });
    }
    pub fn originTile(me: *Map) void {
        // calc origin tile's index
        me.xtilemark = me.numtiles * (me.xprojected + 0.5);
        me.ytilemark = me.numtiles * (1 - (me.yprojected + 0.5));

        me.ww = @as(f64, @floatFromInt(me.xdimension)) / @as(f64, @floatFromInt(me.tilesize));
        me.hh = @as(f64, @floatFromInt(me.ydimension)) / @as(f64, @floatFromInt(me.tilesize));

        me.xtileorigin = @as(i32, @intFromFloat(math.floor(me.xtilemark - 0.5 * me.ww)));
        me.ytileorigin = @as(i32, @intFromFloat(math.floor(me.ytilemark - 0.5 * me.hh)));

        std.debug.print("origin {d}, {d} {s}", .{ me.xtileorigin, me.ytileorigin, newline });
    }
    pub fn tileCount(me: *Map) void {
        // number of tiles along x/y axis
        me.xtilecount = 1 + (@as(i32, @intFromFloat(math.floor(me.xtilemark + 0.5 * me.ww))) - me.xtileorigin);
        me.ytilecount = 1 + (@as(i32, @intFromFloat(math.floor(me.ytilemark + 0.5 * me.hh))) - me.ytileorigin);

        std.debug.print("tiles {d}, {d} {s}", .{ me.xtilecount, me.ytilecount, newline });
    }
    pub fn markerPixel(me: *Map) void {
        const width_total = me.tilesize * me.xtilecount;
        const height_total = me.tilesize * me.ytilecount;
        std.debug.print("size {d}, {d} {s}", .{ width_total, height_total, newline });

        me.xpixelmark = @as(i32, @intFromFloat((me.xtilemark - @as(f64, @floatFromInt(me.xtileorigin))) * @as(f64, @floatFromInt(me.tilesize))));
        me.ypixelmark = @as(i32, @intFromFloat((me.ytilemark - @as(f64, @floatFromInt(me.ytileorigin))) * @as(f64, @floatFromInt(me.tilesize))));
        std.debug.print("centerpx {d}, {d} {s}", .{ me.xpixelmark, me.ypixelmark, newline });
    }

    // format the tile URLs
    pub fn rasterSeries(me: *Map, cache: *std.ArrayList([]const u8)) !void {
        const tiles = math.powi(i32, 2, me.zoom) catch |err| {
            std.debug.print("Shifting (power-2) overflowed {s}", .{newline});
            return err;
        };
        const allocator = me.arena.allocator();

        var xx: i32 = 0;
        while (xx < me.xtilecount) : (xx += 1) {
            var x = me.xtileorigin + xx;
            if (x < 0) {
                x = x + tiles;
            } else if (x >= tiles) {
                x = x - tiles;
            }
            if (x < 0 or x >= tiles) {
                std.debug.print("Skipping out of bounds tile column {d} {s}", .{ x, newline });
                continue;
            }
            std.debug.print("tilecolumn {d} {s}", .{ xx, newline });

            var yy: i32 = 0;
            while (yy < me.ytilecount) : (yy += 1) {
                const y = me.ytileorigin + yy;
                if (y < 0 or y >= tiles) {
                    std.debug.print("Skipping out of bounds tile {d}/{d} {s}", .{ x, y, newline });
                    continue;
                }

                const fpath, const found_status = try cachedExists(allocator, me.zoom, x, y, cache);
                ////defer allocator.free(fpath);

                if (found_status) {
                    std.debug.print("Using existing tile {d}/{d} {s}", .{ x, y, newline });
                    continue;
                }

                const buffer = osmFetch(allocator, me.zoom, x, y) catch |err| {
                    std.debug.print("Failed OSM fetch {d}/{d}/{d} {s}", .{ me.zoom, x, y, newline });
                    return err;
                };
                defer allocator.free(buffer);

                rasterWrite(fpath, buffer) catch |err| {
                    std.debug.print("Failed file creation {d}/{d}/{d} {s}", .{ me.zoom, x, y, newline });
                    return err;
                };
            }
        }
    }

    // use Cairo to assemble the tiles into the whole image
    pub fn knit(me: *Map, cache: std.ArrayList([]const u8)) !void {
        const width: u16 = @intCast(me.tilesize * me.xtilecount);
        const height: u16 = @intCast(me.tilesize * me.ytilecount);

        const surface = try cairo.ImageSurface.create(.argb32, width, height);
        defer surface.destroy();
        const cr = try cairo.Context.create(surface.asSurface());
        defer cr.destroy();

        cr.selectFontFace("Sans", cairo.FontFace.FontSlant.Normal, cairo.FontFace.FontWeight.Normal);
        cr.setFontSize(18.0);

        const k = @as(usize, @intCast(me.xtilecount)); // figures per row
        const rw = @as(f64, @floatFromInt(me.tilesize)); // rectangle width
        const rh = @as(f64, @floatFromInt(me.tilesize)); // rectangle height

        for (cache.items, 0..) |fpath, i| {
            const col = @divTrunc(i, k);
            const row = @mod(i, k);
            const x = rw * @as(f64, @floatFromInt(col));
            const y = rh * @as(f64, @floatFromInt(row));
            try draw(cr, x, y, fpath);
        }
        const alloc = me.arena.allocator();
        // output file to debug, but normally pass bytes to libvaxis draw
        me.appdatadir = try std.fs.getAppDataDir(alloc, "mapsy");
        me.savefile = try std.fmt.allocPrint(alloc, "knit-{d}{d}.png", .{ @trunc(me.lat), @trunc(@abs(me.lng)) });
        me.savepath = try std.fs.path.join(alloc, &[_][]const u8{ me.appdatadir, me.savefile });

        try surface.writeToPng(me.savepath);
    }

    pub fn deinit(me: *Map) void {
        const alloc = me.arena.allocator();
        alloc.free(me.savepath);
        alloc.free(me.savefile);
        alloc.free(me.appdatadir);
        me.arena.deinit();
    }
};

fn draw(cr: *cairo.Context, x: f64, y: f64, fpath: []const u8) !void {
    const image = try cairo.ImageSurface.createFromPng(fpath);
    defer image.destroy();
    const surface = image.asSurface();

    cr.setSourceSurface(surface, x, y);
    cr.paint();
}

fn osmFetch(allocator: std.mem.Allocator, zoom: i32, x: i32, y: i32) ![]const u8 {
    var url: std.BoundedArray(u8, 256) = .{};
    try url.writer().print("https://tile.openstreetmap.org/{d}/{d}/{d}.png", .{ zoom, x, y });
    var body = std.ArrayList(u8).init(allocator);
    errdefer body.deinit();
    var client: std.http.Client = .{ .allocator = allocator };
    defer client.deinit();
    //TODO user-agent as config setting
    _ = try client.fetch(.{
        .location = .{ .url = url.constSlice() },
        .response_storage = .{ .dynamic = &body },
        .headers = .{ .user_agent = .{ .override = "Mozilla/5.0+(compatible; mapsy/0.1; https://github.com/patterns/mapsy)" } },
    });
    std.debug.print("https://tile.openstreetmap.org/{d}/{d}/{d}.png {s}", .{ zoom, x, y, newline });
    return body.toOwnedSlice();
}

fn rasterWrite(fpath: []const u8, png: []const u8) !void {
    const file = try std.fs.createFileAbsolute(fpath, .{ .read = true });
    defer file.close();
    try file.writeAll(png);
}
fn cachedExists(allocator: std.mem.Allocator, zoom: i32, x: i32, y: i32, cache: *std.ArrayList([]const u8)) !struct { []u8, bool } {
    // prefer local file, and save a network trip
    var buf: [48]u8 = undefined;
    const fname = try std.fmt.bufPrint(&buf, "tile-{d}-{d}-{d}.png", .{ zoom, x, y });
    const ad = try std.fs.getAppDataDir(allocator, "mapsy");
    defer allocator.free(ad);
    const fpath = try std.fs.path.join(allocator, &[_][]const u8{ ad, fname });
    ////defer allocator.free(fpath);

    std.fs.accessAbsolute(fpath, .{ .mode = .read_write }) catch |err| {
        if (err == std.fs.Dir.AccessError.FileNotFound) {
            try cache.append(fpath);
            return .{ fpath, false };
        }
    };

    try cache.append(fpath);
    return .{ fpath, true };
}

const newline = "\x0A";

export fn add(a: i32, b: i32) i32 {
    return a + b;
}
test "basic add functionality" {
    try testing.expect(add(3, 7) == 10);
}
