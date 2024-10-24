const std = @import("std");
const curl = @import("curl");

pub const Data = struct {
    const PreviousDay = struct {
        ticker: []const u8,
        err: ?[]const u8 = null,
        opening: ?f32 = null,
        closing: ?f32 = null,
    };

    allocator: std.mem.Allocator,
    tickers: []PreviousDay,

    pub fn deinit(self: *Data) void {
        self.allocator.free(self.tickers);
    }
};

const Response = struct {
    const Result = struct {
        T: []const u8,
        o: f32,
        c: f32,
    };

    results: ?[]Result,
};

pub fn getTickerData(easy: curl.Easy, api_key: []const u8, allocator: std.mem.Allocator, tickers: [][]const u8) !Data {
    var results = std.ArrayList(Data.PreviousDay).init(allocator);
    results.deinit();

    for (tickers) |ticker| {
        const url = try std.fmt.allocPrintZ(allocator, "https://api.polygon.io/v2/aggs/ticker/{s}/prev?adjusted=true&apiKey={s}", .{ ticker, api_key });
        const res = try easy.get(url);
        defer res.deinit();

        if (res.status_code != 200) {
            try results.append(Data.PreviousDay{
                .ticker = ticker,
                .err = "Error fetching data",
            });
            continue;
        }

        const parsed = try std.json.parseFromSlice(Response, allocator, res.body.?.items, .{ .ignore_unknown_fields = true, .allocate = .alloc_always });
        defer parsed.deinit();

        if (parsed.value.results == null) {
            try results.append(Data.PreviousDay{
                .ticker = ticker,
                .err = "No results found",
            });
            continue;
        }

        const data = parsed.value.results.?[0];

        try results.append(Data.PreviousDay{
            .ticker = ticker,
            .opening = data.o,
            .closing = data.c,
        });
    }

    return Data{
        .allocator = allocator,
        .tickers = try results.toOwnedSlice(),
    };
}
