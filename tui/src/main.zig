const std = @import("std");
const vaxis = @import("vaxis");
const mapsy = @import("mapsy");
const Cell = vaxis.Cell;
const TextInput = vaxis.widgets.TextInput;
const border = vaxis.widgets.border;
const log = std.log.scoped(.main);

pub const std_options: std.Options = .{
    ////.log_level = .warn,
    .log_level = .info,
};

pub fn main() !void {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    const alloc = arena.allocator();

    var lat: f64 = 47.608013;
    var lng: f64 = -122.335167;
    var map = try mapFromLatLng(alloc, lat, lng);

    // TUI begins
    // we should check the media resolution and pick values (currently fixed at 1024x1024)
    //  xs: 0,
    //  sm: 576px,
    //  md: 768px,
    //  lg: 992px,
    //  xl: 1200px,
    //  xxl: 1400px
    // or
    //  small: 0,
    //  medium: 640px,
    //  large: 1024px,
    //  xlarge: 1200px,
    //  xxlarge: 1440px,

    // Initalize a tty
    var tty = try vaxis.Tty.init();
    defer tty.deinit();

    // Use a buffered writer for better performance. There are a lot of writes
    // in the render loop and this can have a significant savings
    var buffered_writer = tty.bufferedWriter();
    const writer = buffered_writer.writer().any();

    // Initialize Vaxis
    var vx = try vaxis.init(alloc, .{
        .kitty_keyboard_flags = .{ .report_events = true },
    });
    defer vx.deinit(alloc, tty.anyWriter());

    var loop: vaxis.Loop(Event) = .{ .tty = &tty, .vaxis = &vx };
    try loop.init();

    // Start the read loop. This puts the terminal in raw mode and begins
    // reading user input
    try loop.start();
    defer loop.stop();

    // Optionally enter the alternate screen
    try vx.enterAltScreen(tty.anyWriter());

    // init our text input widget. The text input widget needs an allocator to
    // store the contents of the input
    var lat_input = TextInput.init(alloc, &vx.unicode);
    defer lat_input.deinit();
    var lng_input = TextInput.init(alloc, &vx.unicode);
    defer lng_input.deinit();
    const lat_plchold = try std.fmt.allocPrint(alloc, "{d}", .{lat});
    defer alloc.free(lat_plchold);
    const lng_plchold = try std.fmt.allocPrint(alloc, "{d}", .{lng});
    defer alloc.free(lng_plchold);
    try lat_input.insertSliceAtCursor(lat_plchold);
    try lng_input.insertSliceAtCursor(lng_plchold);

    try vx.setMouseMode(writer, true);

    try buffered_writer.flush();
    // Sends queries to terminal to detect certain features. This should
    // _always_ be called, but is left to the application to decide when
    try vx.queryTerminal(tty.anyWriter(), 1 * std.time.ns_per_s);

    var img1 = try vaxis.zigimg.Image.fromFilePath(alloc, map.savepath);
    defer img1.deinit();

    var imgs = [_]vaxis.Image{
        try vx.transmitImage(alloc, tty.anyWriter(), &img1, .rgba),
        ////try vx.loadImage(alloc, tty.anyWriter(), .{ .path = "zig.png" }),
    };
    defer vx.freeImage(tty.anyWriter(), imgs[0].id);
    ////defer vx.freeImage(tty.anyWriter(), imgs[1].id);

    var focus: Focus = .latitude;
    var subframe: vaxis.Window = undefined;

    // The main event loop. Vaxis provides a thread safe, blocking, buffered
    // queue which can serve as the primary event queue for an application
    while (true) {
        // nextEvent blocks until an event is in the queue
        const event = loop.nextEvent();

        // exhaustive switching ftw. Vaxis will send events if your Event
        // enum has the fields for those events (ie "key_press", "winsize")
        switch (event) {
            .key_press => |key| {
                if (key.matches('c', .{ .ctrl = true })) {
                    break;
                } else if (key.matches('l', .{ .ctrl = true })) {
                    vx.queueRefresh();
                } else if (key.matches('n', .{ .ctrl = true })) {
                    try vx.notify(tty.anyWriter(), "vaxis", "hello from vaxis");
                } else if (key.matches(vaxis.Key.enter, .{})) {
                    // use lat/lng input fields to load map
                    var lat_buf: [48]u8 = undefined;
                    var lng_buf: [48]u8 = undefined;
                    lat = try std.fmt.parseFloat(f64, lat_input.sliceToCursor(&lat_buf));
                    lng = try std.fmt.parseFloat(f64, lng_input.sliceToCursor(&lng_buf));
                    map.deinit();
                    map = try mapFromLatLng(alloc, lat, lng);
                    img1.deinit();
                    img1 = try vaxis.zigimg.Image.fromFilePath(alloc, map.savepath);
                    vx.freeImage(tty.anyWriter(), imgs[0].id);
                    imgs[0] = try vx.transmitImage(alloc, tty.anyWriter(), &img1, .rgba);
                } else if (key.matches(vaxis.Key.tab, .{})) {
                    // change focus to the next text box
                    if (focus == .latitude) {
                        focus = .longitude;
                    } else {
                        focus = .latitude;
                    }
                } else {
                    // keypress goes to the text box in-focus
                    if (focus == .latitude) {
                        try lat_input.update(.{ .key_press = key });
                    } else {
                        try lng_input.update(.{ .key_press = key });
                    }
                }
            },
            .mouse => {
                if (subframe.hasMouse(event.mouse)) |mo| {
                    // calculate the ptr position within the image frame
                    const img_col = mo.col - subframe.x_off;
                    const img_row = mo.row - subframe.y_off;
                    log.info("m({d},{d}):{s}", .{
                        img_col,           img_row,
                        @tagName(mo.type),
                    });
                }
            },

            // winsize events are sent to the application to ensure that all
            // resizes occur in the main thread. This lets us avoid expensive
            // locks on the screen. All applications must handle this event
            // unless they aren't using a screen (IE only detecting features)
            //
            // This is the only call that the core of Vaxis needs an allocator
            // for. The allocations are because we keep a copy of each cell to
            // optimize renders. When resize is called, we allocated two slices:
            // one for the screen, and one for our buffered screen. Each cell in
            // the buffered screen contains an ArrayList(u8) to be able to store
            // the grapheme for that cell Each cell is initialized with a size
            // of 1, which is sufficient for all of ASCII. Anything requiring
            // more than one byte will incur an allocation on the first render
            // after it is drawn. Thereafter, it will not allocate unless the
            // screen is resized
            .winsize => |ws| try vx.resize(alloc, tty.anyWriter(), ws),
            else => {},
        }

        // vx.window() returns the root window. This window is the size of the
        // terminal and can spawn child windows as logical areas. Child windows
        // cannot draw outside of their bounds
        const win = vx.window();

        // Clear the entire space because we are drawing in immediate mode.
        // vaxis double buffers the screen. This new frame will be compared to
        // the old and only updated cells will be drawn
        win.clear();

        // draw the map image
        const img = imgs[0];
        const dims = try img.cellSize(win);
        subframe = vaxis.widgets.alignment.bottomRight(win, dims.cols, dims.rows);
        try img.draw(subframe, .{ .scale = .contain });

        inputFields(win, focus, &lat_input, &lng_input);

        // Render the screen
        try vx.render(writer);
        try buffered_writer.flush();
    }
}

fn mapFromLatLng(alloc: std.mem.Allocator, lat: f64, lng: f64) !mapsy.Map {
    const zoom = 12;
    const total = std.math.exp2(@as(f64, zoom));
    var map = mapsy.Map.init(.{
        .tilesize = 256,
        .zoom = zoom,
        .xdimension = 1024,
        .ydimension = 1024,
        .numtiles = total,
        .lat = lat,
        .lng = lng,
        .allocator = alloc,
    });

    // calculations to prepare map attributes (extracted into steps from go-staticmaps)
    map.mercator();
    map.originTile();
    map.tileCount();
    map.centerPixel();

    // TODO we want each marker to have property for the image xy coord in order
    //      to create child-windows that will respond to events
    try map.pin(47.23854, -122.44094);
    try map.pin(47.5501, -122.2872);
    try map.pin(47.52391, -122.27636);
    try map.pin(47.576, -122.29307);
    try map.pin(47.60533, -122.3018);
    try map.pin(47.49049, -122.23853);

    var cache = std.ArrayList([]const u8).init(alloc);
    defer cache.deinit(); //TODO do we need to free each item?
    map.rasterSeries(&cache) catch |err| {
        log.err("Raster tile url list failed", .{});
        return err;
    };
    map.knit(cache) catch |err| {
        log.err("Tile knitting failed", .{});
        return err;
    };
    return map;
}

// show or hide the input fields along the left hand side
fn inputFields(win: vaxis.Window, focus: Focus, lat_input: *TextInput, lng_input: *TextInput) void {

    // draw order determines the cursor position
    if (focus == .latitude) {
        lng_input.draw(win.child(.{
            .x_off = 1,
            .y_off = 4,
            .width = 40,
            .height = 3,
            .border = .{
                .where = .all,
                .style = style_blue,
            },
        }));
        lat_input.draw(win.child(.{
            .x_off = 1,
            .y_off = 1,
            .width = 40,
            .height = 3,
            .border = .{
                .where = .all,
                .style = style_lime,
            },
        }));
    } else {
        lat_input.draw(win.child(.{
            .x_off = 1,
            .y_off = 1,
            .width = 40,
            .height = 3,
            .border = .{
                .where = .all,
                .style = style_blue,
            },
        }));
        lng_input.draw(win.child(.{
            .x_off = 1,
            .y_off = 4,
            .width = 40,
            .height = 3,
            .border = .{
                .where = .all,
                .style = style_lime,
            },
        }));
    }
}

// The index that pressing the tab key will cycle through (input boxes).
const Focus = enum(u8) {
    none,
    latitude,
    longitude,
    sitename,
    address,
    _,
};

const Event = union(enum) {
    key_press: vaxis.Key,
    mouse: vaxis.Mouse,
    winsize: vaxis.Winsize,
    focus_in,
    focus_out,
    foo: u8,
};

// yellow:3
const style_lime: vaxis.Style = .{
    .fg = .{ .index = 2 },
};
const style_blue: vaxis.Style = .{
    .fg = .{ .index = 4 },
};
const style_pink: vaxis.Style = .{
    .fg = .{ .index = 1 },
};
