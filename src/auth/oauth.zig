const std = @import("std");
const crypto = std.crypto;
const http = std.http;
const json = std.json;
const mem = std.mem;
const base64url = std.base64.url_safe_no_pad;

// ─── OpenAI Codex public OAuth config ───────────────────────────────
pub const OAuthConfig = struct {
    client_id: []const u8 = "app_EMoamEEZ73f0CkXaXp7hrann",
    auth_url: []const u8 = "https://auth.openai.com/oauth/authorize",
    token_url: []const u8 = "https://auth.openai.com/oauth/token",
    redirect_port: u16 = 1455,
    scopes: []const u8 = "openid profile email offline_access",

    pub fn redirectUri(self: OAuthConfig, allocator: mem.Allocator) ![]const u8 {
        return try std.fmt.allocPrint(allocator, "http://localhost:{d}/auth/callback", .{self.redirect_port});
    }
};

pub const oauth_config = OAuthConfig{};

// ─── PKCE ───────────────────────────────────────────────────────────
pub const PKCE = struct {
    verifier: [43]u8, // base64url of 32 random bytes
    challenge: [43]u8, // base64url of SHA-256(verifier)
    // verifier_slice: []const u8,
    // challenge_slice: []const u8,
};

pub fn generatePKCE() PKCE {
    var random_bytes: [32]u8 = undefined;
    crypto.random.bytes(&random_bytes);

    var verifier: [43]u8 = undefined;
    _ = base64url.Encoder.encode(&verifier, &random_bytes);

    var hash: [32]u8 = undefined;
    crypto.hash.sha2.Sha256.hash(&verifier, &hash, .{});

    var challenge: [43]u8 = undefined;
    _ = base64url.Encoder.encode(&challenge, &hash);
    std.debug.print("challenge: {s}\n", .{challenge});

    const result = PKCE{
        .verifier = verifier,
        .challenge = challenge,
        // .verifier_slice = undefined,
        // .challenge_slice = undefined,
    };
    // result.verifier_slice = &result.verifier;
    // result.challenge_slice = &result.challenge;
    return result;
}

// ─── State parameter for CSRF protection ────────────────────────────
pub const State = struct {
    bytes: [22]u8, // base64url of 16 random bytes
    // slice: []const u8,
};

pub fn generateState() State {
    var random_bytes: [16]u8 = undefined;
    crypto.random.bytes(&random_bytes);

    var encoded: [22]u8 = undefined;
    _ = base64url.Encoder.encode(&encoded, &random_bytes);

    const result = State{
        .bytes = encoded,
        // .slice = undefined,
    };
    // result.slice = &result.bytes;
    return result;
}

// ─── Build the browser auth URL ─────────────────────────────────────
pub fn buildAuthUrl(allocator: mem.Allocator, pkce: *const PKCE, state: *const State) ![]const u8 {
    const redirect_uri = try oauth_config.redirectUri(allocator);
    defer allocator.free(redirect_uri);

    return try std.fmt.allocPrint(
        allocator,
        "{s}?response_type=code&client_id={s}&redirect_uri={s}&scope={s}&code_challenge={s}&code_challenge_method=S256&state={s}",
        .{
            oauth_config.auth_url,
            oauth_config.client_id,
            redirect_uri,
            oauth_config.scopes,
            &pkce.challenge,
            &state.bytes,
        },
    );
}

// ─── Token response from OpenAI ─────────────────────────────────────
pub const TokenResponse = struct {
    access_token: []const u8,
    refresh_token: ?[]const u8 = null,
    id_token: ?[]const u8 = null,
    expires_in: i64,
    token_type: []const u8,

    pub fn deinit(self: TokenResponse, allocator: mem.Allocator) void {
        allocator.free(self.access_token);
        if (self.refresh_token) |refresh_token| allocator.free(refresh_token);
        if (self.id_token) |id_token| allocator.free(id_token);
        allocator.free(self.token_type);
    }
};

// ─── Exchange auth code for tokens ──────────────────────────────────
pub fn exchangeCodeForTokens(allocator: mem.Allocator, code: []const u8, code_verifier: []const u8) !TokenResponse {
    const redirect_uri = try oauth_config.redirectUri(allocator);
    defer allocator.free(redirect_uri);

    const body = try std.fmt.allocPrint(
        allocator,
        "grant_type=authorization_code&code={s}&redirect_uri={s}&client_id={s}&code_verifier={s}",
        .{ code, redirect_uri, oauth_config.client_id, code_verifier },
    );
    defer allocator.free(body);

    return try postTokenRequest(allocator, body);
}

// ─── Refresh an access token ────────────────────────────────────────
pub fn refreshAccessToken(allocator: mem.Allocator, refresh_token: []const u8) !TokenResponse {
    const body = try std.fmt.allocPrint(
        allocator,
        "grant_type=refresh_token&client_id={s}&refresh_token={s}",
        .{ oauth_config.client_id, refresh_token },
    );
    defer allocator.free(body);

    return try postTokenRequest(allocator, body);
}

// ─── Shared POST to token endpoint ──────────────────────────────────
fn postTokenRequest(allocator: mem.Allocator, body: []const u8) !TokenResponse {
    const uri = std.Uri.parse(oauth_config.token_url) catch return error.InvalidUri;

    var client = http.Client{ .allocator = allocator };
    defer client.deinit();

    var response_body = std.io.Writer.Allocating.init(allocator);
    defer response_body.deinit();

    const resp = try client.fetch(.{
        .method = .POST,
        .headers = .{
            .content_type = .{ .override = "application/x-www-form-urlencoded" },
        },
        .location = .{ .uri = uri },
        .payload = body,
        .response_writer = &response_body.writer,
    });

    if (resp.status != .ok) {
        std.debug.print("Token request failed ({d}): {s}\n", .{
            @intFromEnum(resp.status),
            response_body.written(),
        });
        return error.TokenRequestFailed;
    }

    const parsed = json.parseFromSlice(
        TokenResponse,
        allocator,
        response_body.written(),
        .{ .ignore_unknown_fields = true },
    ) catch return error.MalformedJson;
    defer parsed.deinit();

    const v = parsed.value;

    // Dupe all strings so they survive after response_body is freed
    var owned: TokenResponse = undefined;
    owned.access_token = try allocator.dupe(u8, v.access_token);
    errdefer allocator.free(owned.access_token);
    owned.refresh_token = if (v.refresh_token) |rt| try allocator.dupe(u8, rt) else null;
    errdefer if (owned.refresh_token) |refresh_token| allocator.free(refresh_token);
    owned.id_token = if (v.id_token) |id_token| try allocator.dupe(u8, id_token) else null;
    errdefer if (owned.id_token) |id_token| allocator.free(id_token);
    owned.expires_in = v.expires_in;
    owned.token_type = try allocator.dupe(u8, v.token_type);
    errdefer allocator.free(owned.token_type);
    return owned;
}

// ─── Decode JWT payload (no verification — just reading claims) ─────
pub fn decodeJwtPayload(allocator: mem.Allocator, token: []const u8) ![]u8 {
    // Find the payload segment (between first and second '.')
    const first_dot = mem.indexOfScalar(u8, token, '.') orelse return error.InvalidJwt;
    const rest = token[first_dot + 1 ..];
    const second_dot = mem.indexOfScalar(u8, rest, '.') orelse return error.InvalidJwt;
    const payload_b64 = rest[0..second_dot];

    // Pad to multiple of 4 for standard base64url decoding
    const pad_len = (4 - (payload_b64.len % 4)) % 4;
    const padded = try allocator.alloc(u8, payload_b64.len + pad_len);
    defer allocator.free(padded);
    @memcpy(padded[0..payload_b64.len], payload_b64);
    for (padded[payload_b64.len..]) |*b| b.* = '=';

    // base64url decode
    const decoded_len = base64url.Decoder.calcSizeForSlice(padded) catch return error.InvalidJwt;
    const decoded = try allocator.alloc(u8, decoded_len);
    errdefer allocator.free(decoded);

    base64url.Decoder.decode(decoded, padded) catch return error.InvalidJwt;
    return decoded;
}

// ─── Extract ChatGPT account info from id_token ─────────────────────
pub const AccountInfo = struct {
    chatgpt_account_id: []const u8,
    organization_id: []const u8,
    project_id: []const u8,
    email: []const u8,
    name: []const u8,

    pub fn deinit(self: AccountInfo, allocator: mem.Allocator) void {
        allocator.free(self.chatgpt_account_id);
        allocator.free(self.organization_id);
        allocator.free(self.project_id);
        allocator.free(self.email);
        allocator.free(self.name);
    }
};

pub fn extractAccountInfo(allocator: mem.Allocator, id_token: []const u8) !AccountInfo {
    const Claims = struct {
        const AuthClaims = struct {
            chatgpt_account_id: ?[]const u8 = null,
            organization_id: ?[]const u8 = null,
            project_id: ?[]const u8 = null,
        };

        @"https://api.openai.com/auth": ?AuthClaims = null,
        email: ?[]const u8 = null,
        name: ?[]const u8 = null,
    };

    const decoded = try decodeJwtPayload(allocator, id_token);
    defer allocator.free(decoded);

    const parsed = try json.parseFromSlice(
        Claims,
        allocator,
        decoded,
        .{ .ignore_unknown_fields = true },
    );
    defer parsed.deinit();

    const auth_claims = parsed.value.@"https://api.openai.com/auth";

    var info: AccountInfo = undefined;
    info.chatgpt_account_id = try allocator.dupe(u8, if (auth_claims) |v| (v.chatgpt_account_id orelse "") else "");
    errdefer allocator.free(info.chatgpt_account_id);
    info.organization_id = try allocator.dupe(u8, if (auth_claims) |v| (v.organization_id orelse "") else "");
    errdefer allocator.free(info.organization_id);
    info.project_id = try allocator.dupe(u8, if (auth_claims) |v| (v.project_id orelse "") else "");
    errdefer allocator.free(info.project_id);
    info.email = try allocator.dupe(u8, parsed.value.email orelse "");
    errdefer allocator.free(info.email);
    info.name = try allocator.dupe(u8, parsed.value.name orelse "");
    errdefer allocator.free(info.name);
    return info;
}
