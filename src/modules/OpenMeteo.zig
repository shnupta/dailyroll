const std = @import("std");
const curl = @import("curl");

pub const Data = struct {
    temp_max_c: f32,
    temp_min_c: f32,
    precipitation_probability: u8,
    precipitation_sum_mm: f32,
    description: []const u8,
    sunrise: []const u8,
    sunset: []const u8,

    allocator: std.mem.Allocator,

    pub fn deinit(self: *Data) void {
        self.allocator.free(self.sunrise);
        self.allocator.free(self.sunset);
    }
};

const Response = struct {
    const Daily = struct {
        weather_code: [1]u8,
        temperature_2m_max: [1]f32,
        temperature_2m_min: [1]f32,
        sunrise: [1][]const u8,
        sunset: [1][]const u8,
        precipitation_probability_max: [1]u8,
        precipitation_sum: [1]f32,
    };

    daily: Daily,
};

pub fn getDaily(easy: curl.Easy, allocator: std.mem.Allocator) !Data {
    const meteo_resp = try easy.get("https://api.open-meteo.com/v1/forecast?latitude=52.374&longitude=4.8897&daily=weather_code,temperature_2m_max,temperature_2m_min,sunrise,sunset,precipitation_sum,precipitation_hours,precipitation_probability_max&timezone=auto&forecast_days=1");
    defer meteo_resp.deinit();

    var meteo = try std.json.parseFromSlice(Response, allocator, meteo_resp.body.?.items, .{ .ignore_unknown_fields = true, .allocate = .alloc_always });
    defer meteo.deinit();

    const daily = meteo.value.daily;

    return Data{
        .allocator = allocator,
        .temp_max_c = daily.temperature_2m_max[0],
        .temp_min_c = daily.temperature_2m_min[0],
        .precipitation_probability = daily.precipitation_probability_max[0],
        .precipitation_sum_mm = daily.precipitation_sum[0],
        .sunrise = try allocator.dupeZ(u8, daily.sunrise[0]),
        .sunset = try allocator.dupeZ(u8, daily.sunset[0]),
        .description = getWeatherDescription(daily.weather_code[0]),
    };
}

fn getWeatherDescription(code: u8) []const u8 {
    switch (code) {
        0 => return "Clear sky",
        1, 2, 3 => return "Mainly clear, partly cloudy, and overcast",
        45, 48 => return "Fog and depositing rime fog",
        51, 53, 55 => return "Drizzle: Light, moderate, and dense intensity",
        56, 57 => return "Freezing Drizzle: Light and dense intensity",
        61, 63, 65 => return "Rain: Slight, moderate and heavy intensity",
        66, 67 => return "Freezing Rain: Light and heavy intensity",
        71, 73, 75 => return "Snow fall: Slight, moderate, and heavy intensity",
        77 => return "Snow grains",
        80, 81, 82 => return "Rain showers: Slight, moderate, and violent",
        85, 86 => return "Snow showers slight and heavy",
        95 => return "Thunderstorm: Slight or moderate",
        96, 99 => return "Thunderstorm with slight and heavy hail",
        else => return "Unknown weather code",
    }
}
