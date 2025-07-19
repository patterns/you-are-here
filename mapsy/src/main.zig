const std = @import("std");
const vaxis = @import("vaxis");
const mapsy = @import("mapsy");
const Cell = vaxis.Cell;
const TextInput = vaxis.widgets.TextInput;
const border = vaxis.widgets.border;
const log = std.log.scoped(.main);

const Event = union(enum) {
    key_press: vaxis.Key,
    mouse: vaxis.Mouse,
    winsize: vaxis.Winsize,
    focus_in,
    focus_out,
    foo: u8,
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
    // calculations to prepare map attributes (extracted into steps from go-staticmaps)
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
    // We'll adjust the color index every keypress for the border
    var color_idx: u8 = 0;

    // init our text input widget. The text input widget needs an allocator to
    // store the contents of the input
    var text_input = TextInput.init(alloc, &vx.unicode);
    defer text_input.deinit();

    try vx.setMouseMode(writer, true);

    try buffered_writer.flush();
    // Sends queries to terminal to detect certain features. This should
    // _always_ be called, but is left to the application to decide when
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

    // The main event loop. Vaxis provides a thread safe, blocking, buffered
    // queue which can serve as the primary event queue for an application
    while (true) {
        // nextEvent blocks until an event is in the queue
        const event = loop.nextEvent();
        log.debug("event: {}", .{event});
        // exhaustive switching ftw. Vaxis will send events if your Event
        // enum has the fields for those events (ie "key_press", "winsize")
        switch (event) {
            .key_press => |key| {
                color_idx = switch (color_idx) {
                    255 => 0,
                    else => color_idx + 1,
                };
                if (key.matches('c', .{ .ctrl = true })) {
                    break;
                } else if (key.matches('l', .{ .ctrl = true })) {
                    vx.queueRefresh();
                } else if (key.matches('n', .{ .ctrl = true })) {
                    try vx.notify(tty.anyWriter(), "vaxis", "hello from vaxis");
                    loop.stop();
                    var child = std.process.Child.init(&.{"nvim"}, alloc);
                    _ = try child.spawnAndWait();
                    try loop.start();
                    try vx.enterAltScreen(tty.anyWriter());
                    vx.queueRefresh();
                } else if (key.matches(vaxis.Key.enter, .{})) {
                    text_input.clearAndFree();
                } else if (key.matches('j', .{})) {
                    clip_y += 1;
                } else if (key.matches('k', .{})) {
                    clip_y -|= 1;
                } else {
                    try text_input.update(.{ .key_press = key });
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

        n = (n + 1) % imgs.len;

        // vx.window() returns the root window. This window is the size of the
        // terminal and can spawn child windows as logical areas. Child windows
        // cannot draw outside of their bounds
        const win = vx.window();

        // Clear the entire space because we are drawing in immediate mode.
        // vaxis double buffers the screen. This new frame will be compared to
        // the old and only updated cells will be drawn
        win.clear();
        // draw the text_input using a bordered window
        const style: vaxis.Style = .{
            .fg = .{ .index = color_idx },
        };

        const child = win.child(.{
            .x_off = win.width / 2 - 20,
            .y_off = win.height / 2 - 3,
            .width = 40,
            .height = 3,
            .border = .{
                .where = .all,
                .style = style,
            },
        });
        text_input.draw(child);
        // draw the map image
        const img = imgs[n];
        const dims = try img.cellSize(win);
        const center = vaxis.widgets.alignment.center(win, dims.cols, dims.rows);
        try img.draw(center, .{ .scale = .contain, .clip_region = .{
            .y = clip_y,
        } });

        // Render the screen
        try vx.render(writer);
        try buffered_writer.flush();
    }
    
}
