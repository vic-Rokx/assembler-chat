const std = @import("std");
const Vapor = @import("vapor");
const build_options = @import("build_options");

pub fn baseUrl() []const u8 {
    return build_options.backend_base_url;
}

pub fn url(path: []const u8) []const u8 {
    const base = baseUrl();
    if (base.len == 0) return path;
    return std.fmt.allocPrint(Vapor.arena(.frame), "{s}{s}", .{ base, path }) catch unreachable;
}
