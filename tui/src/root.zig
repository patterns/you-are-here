const std = @import("std");
const cairo = @import("cairo");
const s2 = @cImport({
    @cInclude("bindings.h");
});
const log = std.log.scoped(.libs2);
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
    xtilectr: f64,
    ytilectr: f64,
    xtilecount: i32,
    ytilecount: i32,
    ww: f64,
    hh: f64,
    xpixelctr: i32,
    ypixelctr: i32,
    savefile: []u8,
    savepath: []u8,
    appdatadir: []u8,
    pins: std.ArrayList([2]f64),
    allocator: std.mem.Allocator,

    pub fn init(args: anytype) Map {
        const alloc = args.allocator;

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
            .xtilectr = 0,
            .ytilectr = 0,
            .xtilecount = 0,
            .ytilecount = 0,
            .ww = 0,
            .hh = 0,
            .xpixelctr = 0,
            .ypixelctr = 0,
            .savefile = "",
            .savepath = "",
            .appdatadir = "",
            .pins = std.ArrayList([2]f64).init(alloc),
            .allocator = alloc,
        };
    }

    pub fn mercator(me: *Map) void {
        // using unit square projected is equivalent to the s2geometry mercator(0.5) shifted to (0,1]
        const ux, const uy = unitxyFromLatLng(me.lat, me.lng);
        me.xprojected = ux;
        me.yprojected = uy;
    }
    pub fn originTile(me: *Map) void {
        // scale mercator projection to obtain the center tile
        me.xtilectr = me.numtiles * me.xprojected;
        me.ytilectr = me.numtiles * me.yprojected;

        // potential tile count from frame resolution using map provider's tile size
        me.ww = @as(f64, @floatFromInt(me.xdimension)) / @as(f64, @floatFromInt(me.tilesize));
        me.hh = @as(f64, @floatFromInt(me.ydimension)) / @as(f64, @floatFromInt(me.tilesize));

        // determine upper left tile for origin tile coordinate
        me.xtileorigin = @as(i32, @intFromFloat(math.floor(me.xtilectr - 0.5 * me.ww)));
        me.ytileorigin = @as(i32, @intFromFloat(math.floor(me.ytilectr - 0.5 * me.hh)));

        log.debug("origin {d}, {d} ", .{ me.xtileorigin, me.ytileorigin });
    }
    pub fn tileCount(me: *Map) void {
        // distance (spanning) between upper left origin tile and right/bottom frame (in units of tiles)
        me.xtilecount = 1 + (@as(i32, @intFromFloat(math.floor(me.xtilectr + 0.5 * me.ww))) - me.xtileorigin);
        me.ytilecount = 1 + (@as(i32, @intFromFloat(math.floor(me.ytilectr + 0.5 * me.hh))) - me.ytileorigin);

        log.debug("tiles {d}, {d} ", .{ me.xtilecount, me.ytilecount });
    }
    pub fn centerPixel(me: *Map) void {
        const x_distance = @as(i32, @intFromFloat(me.xtilectr)) - me.xtileorigin;
        const y_distance = @as(i32, @intFromFloat(me.ytilectr)) - me.ytileorigin;

        // obtain center x,y using upper left tile as origin
        me.xpixelctr = x_distance * me.tilesize;
        me.ypixelctr = y_distance * me.tilesize;
        log.debug("centerpx {d}, {d} ", .{ me.xpixelctr, me.ypixelctr });
    }

    // format the tile URLs
    pub fn rasterSeries(me: *Map, cache: *std.ArrayList([]const u8)) !void {
        const total_world_tiles = math.powi(i32, 2, me.zoom) catch |err| {
            log.err("Failed to total world tiles at chosen zoom level.", .{});
            return err;
        };
        const allocator = me.allocator;

        var xx: i32 = 0;
        while (xx < me.xtilecount) : (xx += 1) {
            var x = me.xtileorigin + xx;
            if (x < 0) {
                x = x + total_world_tiles;
            } else if (x >= total_world_tiles) {
                x = x - total_world_tiles;
            }
            if (x < 0 or x >= total_world_tiles) {
                log.debug("Skipping out of bounds tile column {d} ", .{x});
                continue;
            }
            log.debug("tilecolumn {d} ", .{xx});

            var yy: i32 = 0;
            while (yy < me.ytilecount) : (yy += 1) {
                const y = me.ytileorigin + yy;
                if (y < 0 or y >= total_world_tiles) {
                    log.debug("Skipping out of bounds tile {d}/{d} ", .{ x, y });
                    continue;
                }

                const fpath, const found_status = try cachedExists(allocator, me.zoom, x, y, cache);
                ////defer allocator.free(fpath);

                if (found_status) {
                    log.debug("Using existing tile {d}/{d} ", .{ x, y });
                    continue;
                }

                const buffer = osmFetch(allocator, me.zoom, x, y) catch |err| {
                    log.err("Failed OSM fetch {d}/{d}/{d} ", .{ me.zoom, x, y });
                    return err;
                };
                defer allocator.free(buffer);

                rasterWrite(fpath, buffer) catch |err| {
                    log.err("Failed file creation {d}/{d}/{d} ", .{ me.zoom, x, y });
                    return err;
                };
            }
        }
    }

    // use Cairo to assemble the tiles into the whole image
    pub fn knit(me: *Map, cache: std.ArrayList([]const u8)) !void {
        // we're trying to contain Cairo calls within this function
        // because it should mean that refactors narrow down from here.

        const width: u16 = @intCast(me.tilesize * me.xtilecount);
        const height: u16 = @intCast(me.tilesize * me.ytilecount);

        const surf = try cairo.ImageSurface.create(.argb32, width, height);
        defer surf.destroy();
        const cr = try cairo.Context.create(surf.asSurface());
        defer cr.destroy();

        const t_lyr = try surf.createSimilar(cairo.Content.ColorAlpha, width, height);
        defer t_lyr.destroy();
        const t_sfc = t_lyr.asSurface();
        const t_cr = try cairo.Context.create(t_sfc);
        defer t_cr.destroy();

        const k = @as(usize, @intCast(me.xtilecount)); // figures per row
        const rw = @as(f64, @floatFromInt(me.tilesize)); // rectangle width
        const rh = @as(f64, @floatFromInt(me.tilesize)); // rectangle height

        for (cache.items, 0..) |fpath, i| {
            const col = @divTrunc(i, k);
            const row = @mod(i, k);
            const x = rw * @as(f64, @floatFromInt(col));
            const y = rh * @as(f64, @floatFromInt(row));
            try cachedTile(t_cr, x, y, fpath);
        }

        cr.setOperator(.Saturate);
        // semi transparent layer over map
        cr.selectFontFace("Sans", cairo.FontFace.FontSlant.Normal, cairo.FontFace.FontWeight.Normal);
        cr.setFontSize(24.0);

        const coords = try me.pinCoordinates();
        defer coords.deinit();
        try locationPins(cr, width, height, coords);

        // place OSM attribution in bottom corner
        const attribution = "OpenStreetMap";
        const te = cr.textExtents(attribution);
        const attr_x = @as(f64, @floatFromInt(width)) - te.width - te.x_bearing;
        const attr_y = @as(f64, @floatFromInt(height)) - te.height - te.y_bearing;
        cr.moveTo(attr_x, attr_y);
        cr.setSourceRgba(0.7, 0.0, 0.8, 0.5);
        cr.showText(attribution);

        // use the `tile layer` cairo.Surface to create a cairo.Pattern, then set that
        // pattern as the source for the cairo.Context.
        cr.setSourceSurface(t_sfc, 0, 0);
        cr.paint();

        const alloc = me.allocator;
        // output file to debug, but normally pass bytes to libvaxis draw
        me.appdatadir = try std.fs.getAppDataDir(alloc, "mapsy");
        me.savefile = try std.fmt.allocPrint(alloc, "knit-{d}{d}.png", .{ @trunc(me.lat), @trunc(@abs(me.lng)) });
        me.savepath = try std.fs.path.join(alloc, &[_][]const u8{ me.appdatadir, me.savefile });

        try surf.writeToPng(me.savepath);
    }

    pub fn pin(me: *Map, lat: f64, lng: f64) !void {
        // TODO guard for duplicates

        const loc = [2]f64{ lat, lng };
        try me.pins.append(loc);
    }
    fn pinCoordinates(me: *Map) !std.ArrayList([2]f64) {
        // produce a list of the xy coordinates in pixels
        // to be used to overlay location pins onto the image

        const alloc = me.allocator;
        var coords = std.ArrayList([2]f64).init(alloc);
        for (me.pins.items) |loc| {
            const x, const y = me.xyFromLatLng(loc[0], loc[1]);
            try coords.append([2]f64{ x, y });
        }

        return coords;
    }

    pub fn xyFromLatLng(me: Map, lat: f64, lng: f64) struct { f64, f64 } {
        // projection on unit square
        const ux, const uy = unitxyFromLatLng(lat, lng);

        const x_tile = ux * me.numtiles;
        const y_tile = uy * me.numtiles;
        const x_displace = x_tile - @as(f64, @floatFromInt(me.xtileorigin));
        const y_displace = y_tile - @as(f64, @floatFromInt(me.ytileorigin));

        const x = x_displace * @as(f64, @floatFromInt(me.tilesize));
        const y = y_displace * @as(f64, @floatFromInt(me.tilesize));

        log.debug("pin {d},{d} -> {d},{d} px", .{ lat, lng, x, y });
        return .{ x, y };
    }
    pub fn xyFromLatLng00(me: Map, lat: f64, lng: f64) struct { f64, f64 } {
        const ux, const uy = unitxyFromLatLng(lat, lng);
        const t_x = me.numtiles * ux;
        const t_y = me.numtiles * uy;

        const tile_sz = @as(f64, @floatFromInt(me.tilesize));
        const xctr_px = @as(f64, @floatFromInt(me.xpixelctr));
        const wd = @as(f64, @floatFromInt(me.xdimension));

        const x_px = xctr_px + (t_x - me.xtilectr) * tile_sz;
        const y_px = @as(f64, @floatFromInt(me.ypixelctr)) + (t_y - me.ytilectr) * tile_sz;

        const offset = me.numtiles * tile_sz;
        const min_x = xctr_px - (wd / 2);
        const max_x = min_x + wd;

        var x = x_px;
        if (x_px < min_x) {
            ////while (x < min_x): (x += offset) {}
            x += offset;
        } else if (x_px >= max_x) {
            ////while (x >= max_x): (x -= offset) {}
            x -= offset;
        }

        log.debug("pin {d},{d} -> {d},{d} px", .{ lat, lng, x, y_px });
        return .{ x, y_px };
    }

    pub fn deinit(me: *Map) void {
        const alloc = me.allocator;
        alloc.free(me.savepath);
        alloc.free(me.savefile);
        alloc.free(me.appdatadir);
    }
};

fn cachedTile(cr: *cairo.Context, x: f64, y: f64, fpath: []const u8) !void {
    const image = try cairo.ImageSurface.createFromPng(fpath);
    defer image.destroy();
    const surface = image.asSurface();

    cr.setSourceSurface(surface, x, y);
    cr.paint();
}
fn locationPins(cr: *cairo.Context, width: u16, height: u16, coords: std.ArrayList([2]f64)) !void {
    // TODO allow the pin to respond to click events

    for (coords.items) |xy| {
        try reddot(cr, xy[0], xy[1], width, height);
    }
}
fn reddot(cr: *cairo.Context, x: f64, y: f64, width: u16, height: u16) !void {
    const surface = try cr.getTarget();
    const red = try surface.createSimilar(cairo.Content.ColorAlpha, width, height);
    defer red.destroy();

    const red_cr = try cairo.Context.create(red);
    defer red_cr.destroy();

    red_cr.setSourceRgba(0.7, 0, 0, 0.9);
    red_cr.rectangle(cairo.Rectangle.init(.{ x, y, 10, 10 }));
    red_cr.fill();

    red_cr.setOperator(.Overlay);

    cr.setSourceSurface(red, 0, 0);
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
        .headers = .{ .user_agent = .{ .override = "Mozilla/5.0+(compatible; mapsy/0.1; https://github.com/patterns/you-are-here)" } },
    });
    log.debug("https://tile.openstreetmap.org/{d}/{d}/{d}.png ", .{ zoom, x, y });
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

/// Given latitude and longitude in degrees,
/// return x,y coordinates in the unit square
/// for a Web Mercator projection.
fn unitxyFromLatLng(lat: f64, lng: f64) struct { f64, f64 } {
    // convert coordinates to the Web Mercator projection
    // x = longitude
    // y = arsinh(tan(latitude))

    const x_m = lng;
    const y_m = math.asinh(math.tan(math.degreesToRadians(lat)));

    // transform the projected point onto the unit square
    // x = 0.5 + x / 360
    // y = 0.5 - y / 2pi

    const x_unit = 0.5 + x_m / 360;
    const y_unit = 0.5 - y_m / (2 * math.pi);

    log.debug("units {d},{d} -> {d},{d} px", .{ lat, lng, x_unit, y_unit });
    return .{ x_unit, y_unit };
}

test "verify Hachiko XY unit coordinates" {
    const x_unit, const y_unit = unitxyFromLatLng(35.6590699, 139.7006793);
    try testing.expect(x_unit == 0.8880574425);
    try testing.expect(y_unit == 0.39385379958274735);
}
test "verify center tile against s2geometry" {
    // TODO don't need s2geometry anymore if we save the expected values as pre-calculations

    // tile count at zoom level
    const zoom = 14;
    const total_tiles = std.math.exp2(@as(f64, zoom));

    // the expected values are from s2geometry mercator(0.5) shifted
    const projected_pt = s2.mercator(47.608013, -122.335167);
    const xtile_s2 = total_tiles * (projected_pt.x + 0.5);
    const ytile_s2 = total_tiles * (1 - (projected_pt.y + 0.5));

    // calculate unit x,y
    const x_unit, const y_unit = unitxyFromLatLng(47.608013, -122.335167);
    const xtile_usqr = total_tiles * x_unit;
    const ytile_usqr = total_tiles * y_unit;

    const xs = @trunc(xtile_s2);
    const ys = @trunc(ytile_s2);
    const xu = @trunc(xtile_usqr);
    const yu = @trunc(ytile_usqr);

    try testing.expect(xs == xu);
    try testing.expect(ys == yu);
}

const newline = "\x0A";
