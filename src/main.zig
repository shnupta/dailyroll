const std = @import("std");
const thermal = @import("thermal");
const elio = @import("elio");
const curl = @import("curl");
const OpenMeteo = @import("modules/OpenMeteo.zig");
const Polygon = @import("modules/Polygon.zig");
const Guardian = @import("modules/Guardian.zig");
const ctime = @cImport(@cInclude("time.h"));

const tm20iii_page_width = 48;

const box_double_horizontal = &[_]u8{0xcd};
const box_double_vertical = &[_]u8{0xba};
const box_double_top_left = &[_]u8{0xc9};
const box_double_top_right = &[_]u8{0xbb};
const box_double_bottom_left = &[_]u8{0xc8};
const box_double_bottom_right = &[_]u8{0xbc};

const box_single_horizontal = &[_]u8{0xc4};
const box_single_vertical = &[_]u8{0xb3};
const box_single_top_left = &[_]u8{0xda};
const box_single_top_right = &[_]u8{0xbf};
const box_single_bottom_left = &[_]u8{0xc0};
const box_single_bottom_right = &[_]u8{0xd9};
const box_single_vertical_left = &[_]u8{0xb4};
const box_single_vertical_right = &[_]u8{0xc3};

const shading_low_density = &[_]u8{0xb0};

const BoxType = enum {
    single,
    double,
};

const Padding = enum {
    no,
    yes,
};

const HeaderOptions = struct {
    box_type: BoxType = .single,
    padding: Padding = .no,
};

fn printHeader(printer: *thermal.Printer, text: []const u8, text_len: comptime_int, options: HeaderOptions) void {
    const top_left = if (options.box_type == .single) box_single_top_left else box_double_top_left;
    const top_right = if (options.box_type == .single) box_single_top_right else box_double_top_right;
    const vertical_left = if (options.box_type == .double) box_double_vertical else blk: {
        if (options.padding == .no) break :blk box_single_vertical else break :blk box_single_vertical_left;
    };
    const vertical_right = if (options.box_type == .double) box_double_vertical else blk: {
        if (options.padding == .no) break :blk box_single_vertical else break :blk box_single_vertical_right;
    };
    const bottom_left = if (options.box_type == .single) box_single_bottom_left else box_double_bottom_left;
    const bottom_right = if (options.box_type == .single) box_single_bottom_right else box_double_bottom_right;
    const horizontal = if (options.box_type == .single) box_single_horizontal else box_double_horizontal;

    const pad_len = (tm20iii_page_width - (text_len + 2)) / 2;

    printer.text(top_left ++ horizontal ** text_len ++ top_right);
    printer.lineFeed();
    if (options.padding == .yes) {
        printer.text(horizontal ** pad_len);
    }
    printer.text(vertical_left);
    printer.text(text);
    printer.text(vertical_right);
    if (options.padding == .yes) {
        printer.text(horizontal ** pad_len);
    }
    printer.lineFeed();

    printer.text(bottom_left ++ horizontal ** text_len ++ bottom_right);
    printer.lineFeed();
}

fn connected(ctx: *anyopaque, conn: *elio.tcp.Connection) void {
    const data: *Data = @alignCast(@ptrCast(ctx));
    const weather: *const OpenMeteo.Data = data.meteo;
    const stocks: *const Polygon.Data = data.polygon;
    const articles: *const Guardian.Data = data.guardian;

    var printer = thermal.Printer.init(std.heap.page_allocator, ConnectionWriter.any(conn));
    defer printer.deinit();

    printer.initialise();
    printer.justify(.center);

    printer.text(box_double_top_left ++ box_double_horizontal ** 25 ++ box_double_top_right);
    printer.lineFeed();
    printer.text(shading_low_density ** 10);
    printer.text(box_double_vertical);
    printer.emphasise(true);
    printer.formattedText(" Daily Roll - {s} ", .{data.today});
    printer.emphasise(false);
    printer.text(box_double_vertical);
    printer.text(shading_low_density ** 10);
    printer.lineFeed();
    printer.text(box_double_bottom_left ++ box_double_horizontal ** 25 ++ box_double_bottom_right);
    printer.lineFeed();
    printer.resetStyles();
    printer.justify(.left);
    printer.lineFeed();

    printer.justify(.center);
    const weather_title = " Today's Weather ";
    printHeader(&printer, weather_title, weather_title.len, .{ .padding = .yes });

    printer.justify(.left);
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

    printer.justify(.center);
    const markets_title = " Markets ";
    printHeader(&printer, markets_title, markets_title.len, .{ .padding = .yes });

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
    printer.lineFeed();

    printer.justify(.center);
    const news_title = " News ";
    printHeader(&printer, news_title, news_title.len, .{ .padding = .yes });

    printer.justify(.left);
    for (articles.articles) |article| {
        if (article.title != null) {
            printer.text(article.title.?);
        } else {
            printer.text(article.err.?);
        }
        printer.printFeedLines(2);
    }
    printer.feedCut(4);
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
    today: []const u8,
    engine: *elio.Engine,
    meteo: *const OpenMeteo.Data,
    polygon: *const Polygon.Data,
    guardian: *const Guardian.Data,
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

    const guardian_key = try std.process.getEnvVarOwned(allocator, "GUARDIAN_API_KEY");
    defer allocator.free(guardian_key);
    var articles = try Guardian.getArticles(easy, guardian_key, allocator);
    defer articles.deinit();

    var engine = elio.Engine.init(allocator);
    defer engine.deinit();

    const time = ctime.time(null);
    const localtime = ctime.localtime(&time).*;
    const year: u32 = @intCast(localtime.tm_year + 1900);
    const month: u8 = @intCast(localtime.tm_mon + 1);
    const day: u8 = @intCast(localtime.tm_mday);
    const today = try std.fmt.allocPrint(allocator, "{d}-{d:0<2}-{d:0<2}", .{ year, month, day });
    defer allocator.free(today);

    var data = Data{
        .today = today,
        .engine = &engine,
        .meteo = &meteo,
        .polygon = &tickerData,
        .guardian = &articles,
    };

    var conn = try elio.tcp.Connection.init(allocator, &engine, elio.tcp.Connection.Handler{ .ptr = &data, .vtable = &vtable });
    defer conn.close();
    try conn.connect("192.168.68.196", 9100);

    try engine.start();
}
