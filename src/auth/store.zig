const std = @import("std");
const json = std.json;
const fs = std.fs;
const mem = std.mem;
const Vapor = @import("vapor");

const store_dir_name = ".codex-auth";
const store_file_name = "tokens.json";

// ─── Stored token structure ─────────────────────────────────────────
pub const StoredTokens = struct {
    access_token: []const u8,
    refresh_token: ?[]const u8 = null,
    id_token: ?[]const u8 = null,
    expires_in: i64, // epoch ms

    pub fn deinit(self: StoredTokens, allocator: mem.Allocator) void {
        allocator.free(self.access_token);
        if (self.refresh_token) |refresh_token| allocator.free(refresh_token);
        if (self.id_token) |id_token| allocator.free(id_token);
    }
};

// ─── Token input (from OAuth response) ──────────────────────────────
pub const TokenInput = struct {
    access_token: []const u8,
    refresh_token: ?[]const u8 = null,
    id_token: ?[]const u8 = null,
    expires_in: i64,
};

// ─── Resolve the store directory and file paths ─────────────────────
fn getStoreDir(allocator: mem.Allocator) ![]const u8 {
    const home = std.posix.getenv("HOME") orelse return error.NoHomeDir;
    return try std.fs.path.join(allocator, &.{ home, store_dir_name });
}

fn getStoreFile(allocator: mem.Allocator) ![]const u8 {
    const home = std.posix.getenv("HOME") orelse return error.NoHomeDir;
    return try std.fs.path.join(allocator, &.{ home, store_dir_name, store_file_name });
}

// ─── Save tokens to disk ────────────────────────────────────────────
pub fn saveTokens(allocator: mem.Allocator, tokens: TokenInput) !StoredTokens {
    const now_ms = std.time.milliTimestamp();
    var data: StoredTokens = undefined;
    data.access_token = try allocator.dupe(u8, tokens.access_token);
    errdefer allocator.free(data.access_token);
    data.refresh_token = if (tokens.refresh_token) |refresh_token| try allocator.dupe(u8, refresh_token) else null;
    errdefer if (data.refresh_token) |refresh_token| allocator.free(refresh_token);
    data.id_token = if (tokens.id_token) |id_token| try allocator.dupe(u8, id_token) else null;
    errdefer if (data.id_token) |id_token| allocator.free(id_token);
    data.expires_in = now_ms + tokens.expires_in * 1000;

    const dir_path = try getStoreDir(allocator);
    defer allocator.free(dir_path);

    // Create directory if it doesn't exist
    fs.cwd().makePath(dir_path) catch {};

    const file_path = try getStoreFile(allocator);
    defer allocator.free(file_path);

    // Serialize to JSON
    var buf = std.io.Writer.Allocating.init(allocator);
    defer buf.deinit();

    try json.Stringify.value(data, .{ .whitespace = .indent_2 }, &buf.writer);

    // Write with owner-only permissions (0o600)
    const file = try fs.cwd().createFile(file_path, .{ .mode = 0o600 });
    defer file.close();
    try file.writeAll(buf.written());

    std.debug.print("  Tokens saved to {s}\n", .{file_path});
    return data;
}

// ─── Load tokens from disk ──────────────────────────────────────────
pub fn loadTokens(allocator: mem.Allocator) ?StoredTokens {
    const tokens_json = Vapor.load([]const u8, "codex-tokens") orelse return null;

    const parsed = json.parseFromSlice(
        StoredTokens,
        allocator,
        tokens_json,
        .{ .ignore_unknown_fields = true },
    ) catch |err| {
        std.log.err("Failed to parse tokens: {any}", .{err});
        return null;
    };
    defer parsed.deinit();

    var owned: StoredTokens = undefined;
    owned.access_token = allocator.dupe(u8, parsed.value.access_token) catch return null;
    errdefer allocator.free(owned.access_token);
    owned.refresh_token = if (parsed.value.refresh_token) |refresh_token| allocator.dupe(u8, refresh_token) catch return null else null;
    errdefer if (owned.refresh_token) |refresh_token| allocator.free(refresh_token);
    owned.id_token = if (parsed.value.id_token) |id_token| allocator.dupe(u8, id_token) catch return null else null;
    errdefer if (owned.id_token) |id_token| allocator.free(id_token);
    owned.expires_in = parsed.value.expires_in;
    return owned;
}

// ─── Clear stored tokens ────────────────────────────────────────────
pub fn clearTokens(allocator: mem.Allocator) void {
    const file_path = getStoreFile(allocator) catch return;
    defer allocator.free(file_path);

    fs.cwd().deleteFile(file_path) catch {};
}

// ─── Check if tokens are expired ────────────────────────────────────
pub fn isExpired(tokens: StoredTokens) bool {
    return isExpiredWithBuffer(tokens, 60_000);
}

pub fn isExpiredWithBuffer(tokens: StoredTokens, buffer_ms: i64) bool {
    const now_ms = std.time.milliTimestamp();
    return now_ms >= tokens.expires_in - buffer_ms;
}
