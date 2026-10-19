const std = @import("std");
const mem = std.mem;
const oauth = @import("oauth.zig");
const store = @import("store.zig");
// const callback_server = @import("callback_server.zig");
const Vapor = @import("vapor");

// ─── Get a valid access token (login, refresh, or cached) ──────────
pub fn getAccessToken(allocator: mem.Allocator) ![]const u8 {
    const stored = store.loadTokens(allocator);

    // 1. If we have a valid cached token, use it
    if (stored) |tokens| {
        defer tokens.deinit(allocator);
        // if (!store.isExpired(tokens)) {
        return try allocator.dupe(u8, tokens.access_token);
        // }

        // 2. If expired but we have a refresh token, try refreshing
        // if (tokens.refresh_token) |refresh_token| {
        //     std.debug.print("  Access token expired — refreshing...\n", .{});
        //     const refreshed = oauth.refreshAccessToken(allocator, refresh_token) catch |err| {
        //         std.debug.print("  Refresh failed, need to re-login: {}\n", .{err});
        //         return login(allocator);
        //     };
        //     defer refreshed.deinit(allocator);
        //
        //     const saved = try store.saveTokens(allocator, .{
        //         .access_token = refreshed.access_token,
        //         .refresh_token = refreshed.refresh_token,
        //         .id_token = refreshed.id_token,
        //         .expires_in = refreshed.expires_in,
        //     });
        //     defer saved.deinit(allocator);
        //     return try allocator.dupe(u8, saved.access_token);
        // }
    }

    return error.NoToken;
    // 3. No token or refresh failed — do full login
    // return login();
}

// ─── Full browser-based OAuth login ─────────────────────────────────
pub fn login() void {
    var pkce = oauth.generatePKCE();
    var state = oauth.generateState();

    const auth_url = oauth.buildAuthUrl(Vapor.frame.arena(), &pkce, &state) catch unreachable;

    // std.log.debug("\n  Opening browser for ChatGPT sign-in...\n\n", .{});
    // std.log.debug("  If it doesn't open, visit:\n  {s}\n\n", .{auth_url});
    const cli = "https://auth.openai.com/oauth/authorize?response_type=code&client_id=app_EMoamEEZ73f0CkXaXp7hrann&redirect_uri=http://localhost:1455/auth/callback&scope=openid profile email offline_access&code_challenge=f3sYDWhiLUVJ2ikciV7IknQt4ELE9L1eLV8lIqz1j14&code_challenge_method=S256&state=THmYsGdU27e9b4hBMTtdSQ";
    std.log.debug("{s}", .{cli});
    std.log.debug("{s}", .{auth_url});
    Vapor.redirect(auth_url);

    // Try to open browser
    // openBrowser(allocator, auth_url);

    // // Wait for the redirect (validates state)
    // const code = try callback_server.waitForAuthCallback(allocator, &state.bytes);
    // defer allocator.free(code);
    // std.debug.print("  Received authorization code — exchanging for tokens...\n\n", .{});
    //
    // const tokens = try oauth.exchangeCodeForTokens(allocator, code, &pkce.verifier);
    // defer tokens.deinit(allocator);
    // const saved = try store.saveTokens(allocator, .{
    //     .access_token = tokens.access_token,
    //     .refresh_token = tokens.refresh_token,
    //     .id_token = tokens.id_token,
    //     .expires_in = tokens.expires_in,
    // });
    // defer saved.deinit(allocator);
    //
    // // Show account info if we got an id_token
    // if (tokens.id_token) |id_token| {
    //     if (oauth.extractAccountInfo(allocator, id_token)) |info| {
    //         defer info.deinit(allocator);
    //         std.debug.print("  Account info:\n", .{});
    //         std.debug.print("    Name:    {s}\n", .{info.name});
    //         std.debug.print("    Email:   {s}\n", .{info.email});
    //         std.debug.print("    Account: {s}\n", .{info.chatgpt_account_id});
    //         std.debug.print("    Org:     {s}\n", .{info.organization_id});
    //     } else |_| {
    //         // id_token parsing is best-effort
    //     }
    // }
    //
    // // Print expiry
    // const expires_sec = @divFloor(saved.expires_at, 1000);
    // std.debug.print("\n  Token expires at: epoch {d}\n\n", .{expires_sec});
    //
    // return try allocator.dupe(u8, saved.access_token);
}

// ─── Open a URL in the system browser ───────────────────────────────
fn openBrowser(allocator: mem.Allocator, url: []const u8) void {
    const open_cmds = switch (@import("builtin").os.tag) {
        .macos => &[_][]const u8{ "open", url },
        .windows => &[_][]const u8{ "rundll32", "url.dll,FileProtocolHandler", url },
        else => &[_][]const u8{ "xdg-open", url }, // Linux
    };

    var child = std.process.Child.init(open_cmds, allocator);
    child.spawn() catch return;
    // Don't wait — fire and forget
}

// ─── CLI command: status ────────────────────────────────────────────
pub fn statusCommand(allocator: mem.Allocator) void {
    const stored = store.loadTokens(allocator);
    if (stored == null) {
        std.debug.print("  Not logged in. Run: codex-auth login\n\n", .{});
        return;
    }

    const tokens = stored.?;
    defer tokens.deinit(allocator);
    if (store.isExpired(tokens)) {
        std.debug.print("  Token expired. Run: codex-auth login\n\n", .{});
        return;
    }

    const now_ms = std.time.milliTimestamp();
    const remaining_ms = tokens.expires_at - now_ms;
    const mins = @divFloor(remaining_ms, 60_000);
    std.debug.print("  ✓ Logged in. Token valid for ~{d} minutes.\n\n", .{mins});

    if (tokens.id_token) |id_token| {
        if (oauth.extractAccountInfo(allocator, id_token)) |info| {
            defer info.deinit(allocator);
            std.debug.print("    Name:  {s}\n", .{info.name});
            std.debug.print("    Email: {s}\n\n", .{info.email});
        } else |_| {}
    }
}

// ─── CLI command: logout ────────────────────────────────────────────
pub fn logoutCommand(allocator: mem.Allocator) void {
    store.clearTokens(allocator);
    std.debug.print("  ✓ Tokens cleared.\n\n", .{});
}
