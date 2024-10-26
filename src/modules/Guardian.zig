const std = @import("std");
const curl = @import("curl");

pub const Data = struct {
    const Article = struct {
        title: ?[]const u8 = null,
        err: ?[]const u8 = null,
    };

    allocator: std.mem.Allocator,
    articles: []Article,

    pub fn deinit(self: *Data) void {
        self.allocator.free(self.articles);
    }
};

const Response = struct {
    const InnerResponse = struct {
        const Result = struct {
            webTitle: []const u8,
        };

        results: []Result,
    };
    response: InnerResponse,
};

pub fn getArticles(easy: curl.Easy, api_key: []const u8, allocator: std.mem.Allocator) !Data {
    var articles = std.ArrayList(Data.Article).init(allocator);
    defer articles.deinit();

    const url = try std.fmt.allocPrintZ(allocator, "https://content.guardianapis.com/search?section=world&api-key={s}", .{api_key});
    const res = try easy.get(url);
    defer res.deinit();

    if (res.status_code != 200) {
        try articles.append(.{
            .err = "Failed to retrieve articles",
        });
    } else {
        const parsed = try std.json.parseFromSlice(Response, allocator, res.body.?.items, .{ .ignore_unknown_fields = true, .allocate = .alloc_always });
        defer parsed.deinit();

        const response = parsed.value.response;

        for (response.results, 0..) |result, idx| {
            var buf = [_]u8{0} ** 1024;
            std.mem.copyForwards(u8, buf[0..], result.webTitle);

            const replaced_forwardtick = std.mem.replace(u8, result.webTitle, &[3]u8{ 0xe2, 0x80, 0x98 }, &[1]u8{'\''}, buf[0..]);
            const replaced_backtick = std.mem.replace(u8, buf[0..], &[3]u8{ 0xe2, 0x80, 0x99 }, &[1]u8{'\''}, buf[0..]);
            const replaced_longdash = std.mem.replace(u8, buf[0..], &[3]u8{ 0xe2, 0x80, 0x93 }, &[1]u8{'-'}, buf[0..]);
            const newlen = result.webTitle.len - 2 * (replaced_backtick + replaced_forwardtick + replaced_longdash);

            try articles.append(.{ .title = try allocator.dupeZ(u8, buf[0..newlen]) });

            if (idx >= 4) break;
        }
    }

    return Data{
        .allocator = allocator,
        .articles = try articles.toOwnedSlice(),
    };
}
