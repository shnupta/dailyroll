const std = @import("std");
const thermal = @import("thermal");
const elio = @import("elio");
const curl = @import("curl");
const OpenMeteo = @import("modules/OpenMeteo.zig");
const Polygon = @import("modules/Polygon.zig");

fn connected(ctx: *anyopaque, conn: *elio.tcp.Connection) void {
    const data: *Data = @alignCast(@ptrCast(ctx));
    const weather: *const OpenMeteo.Data = data.meteo;
    const stocks: *const Polygon.Data = data.polygon;

    var printer = thermal.Printer.init(std.heap.page_allocator, ConnectionWriter.any(conn));
    defer printer.deinit();

    printer.initialise();
    printer.setUnderline(.two_dot);
    printer.justify(.center);
    printer.formattedText("Daily Roll - {s}", .{weather.sunrise[0..10]});
    printer.lineFeed();
    printer.resetStyles();
    printer.justify(.left);
    printer.printFeedLines(2);

    printer.setUnderline(.two_dot);
    printer.text("Today's Weather");
    printer.resetStyles();
    printer.lineFeed();

    printer.formattedText("{s}", .{weather.description});
    printer.lineFeed();
    printer.text("Min: ");
    printer.formattedText("{d}", .{weather.temp_min_c});
    printer.setCharacterCode(.wpc1252);
    printer.text(&.{ 0xB0, 'C' });
    printer.setCharacterCode(.pc437);
    printer.text(" Max: ");
    printer.formattedText("{d}", .{weather.temp_max_c});
    printer.setCharacterCode(.wpc1252);
    printer.text(&.{ 0xB0, 'C' });
    printer.setCharacterCode(.pc437);
    printer.lineFeed();
    printer.formattedText("Precipitation: {d}% ({d}mm)", .{ weather.precipitation_probability, weather.precipitation_sum_mm });
    printer.lineFeed();
    printer.formattedText("Sunrise: {s} Sunset: {s}", .{ weather.sunrise[11..], weather.sunset[11..] });
    printer.printFeedLines(2);

    printer.setUnderline(.two_dot);
    printer.text("Markets");
    printer.resetStyles();
    printer.lineFeed();

    for (stocks.tickers) |ticker| {
        printer.emphasise(true);
        printer.formattedText("{s: <5}: ", .{ticker.ticker});
        printer.emphasise(false);

        if (ticker.err != null) {
            printer.formattedText("err: {s}", .{ticker.err.?});
        } else {
            printer.formattedText("O: {d: >6} C: {d: >6} ({d: >5.2}%)", .{ ticker.opening.?, ticker.closing.?, ((ticker.closing.? - ticker.opening.?) / ticker.opening.?) * 100.0 });
        }
        printer.lineFeed();
    }

    printer.feedCut(6);
    printer.flush() catch |err| {
        std.debug.print("Uh oh: {s}\n", .{@errorName(err)});
        return;
    };

    data.engine.stop();
}

fn disconnected(_: *anyopaque, _: *elio.tcp.Connection) void {}

const vtable: elio.tcp.Connection.Handler.VTable = .{ .connected = connected, .disconnected = disconnected };

const ConnectionWriter = struct {
    fn any(conn: *elio.tcp.Connection) std.io.AnyWriter {
        return .{
            .context = conn,
            .writeFn = write,
        };
    }

    fn write(context: *const anyopaque, bytes: []const u8) anyerror!usize {
        const conn: *elio.tcp.Connection = @constCast(@alignCast(@ptrCast(context)));
        try conn.writeSlice(bytes);
        return bytes.len;
    }
};

const Data = struct {
    engine: *elio.Engine,
    meteo: *const OpenMeteo.Data,
    polygon: *const Polygon.Data,
};

pub fn main() !void {
    const allocator = std.heap.page_allocator;

    const polygon_key = try std.process.getEnvVarOwned(allocator, "POLYGON_API_KEY");
    defer allocator.free(polygon_key);

    const ca_bundle = try curl.allocCABundle(allocator);
    defer ca_bundle.deinit();
    const easy = try curl.Easy.init(allocator, .{ .ca_bundle = ca_bundle });
    defer easy.deinit();

    var meteo = try OpenMeteo.getDaily(easy, allocator);
    defer meteo.deinit();

    var tickers = [_][]const u8{ "SPY", "QQQ", "VGK", "BRK.B", "FXI" };
    var tickerData = try Polygon.getTickerData(easy, polygon_key, allocator, tickers[0..]);
    defer tickerData.deinit();

    var engine = elio.Engine.init(allocator);
    defer engine.deinit();

    var data = Data{
        .engine = &engine,
        .meteo = &meteo,
        .polygon = &tickerData,
    };

    var conn = try elio.tcp.Connection.init(allocator, &engine, elio.tcp.Connection.Handler{ .ptr = &data, .vtable = &vtable });
    defer conn.close();
    try conn.connect("192.168.68.196", 9100);

    try engine.start();
}
