// =============================================================================
// API — Fetch logic, response parsing, system prompt
// =============================================================================

const std = @import("std");
const Vapor = @import("vapor");
const Opaque = @import("opaque_ui");
const ClaudeChatMessage = @import("Assembler.zig").ClaudeChatMessage;
const CodexChatMessage = @import("Assembler.zig").CodexChatMessage;
const TokenResponse = @import("Settings.zig").TokenResponse;
const Chat = @import("../auth/chat.zig");
const backend = @import("backend.zig");

pub const SYSTEM_PROMPT =
    "You are an expert Vapor framework (Zig to WASM) UI developer. " ++
    "Generate clean, idiomatic Vapor/Zig code for the described UI component. " ++
    "Output ONLY the complete Zig source file — no markdown fences, no prose, no backticks. " ++
    "Rules: state at module level (never inside render), use Stack() for vertical layouts, " ++
    "Button() when passing arguments to handlers, .end() on every leaf element, " ++
    "include pub fn init() registering the page, and fn render(). Minimal and correct.";

// =============================================================================
// RESPONSE TYPES
// =============================================================================

pub const ContentBlock = struct {
    type: []const u8,
    text: ?[]const u8 = null,
};

pub const Usage = struct {
    input_tokens: i64,
    output_tokens: i64,
};

pub const MessageResponse = struct {
    id: []const u8,
    type: []const u8,
    role: []const u8,
    content: []ContentBlock,
    model: []const u8,
    stop_reason: ?[]const u8 = null,
    usage: ?Usage = null,
};

pub const OpenAIChoiceMessage = struct {
    role: []const u8,
    content: []const u8,
};

pub const OpenAIChoice = struct {
    message: OpenAIChoiceMessage,
};

pub const OpenAIResponse = struct {
    id: []const u8,
    model: []const u8,
    choices: []OpenAIChoice,
};

// =============================================================================
// PARSING
// =============================================================================

pub fn parseResp(comptime T: type, body: []const u8, allocator: std.mem.Allocator) !T {
    const parsed = std.json.parseFromSlice(
        T,
        allocator,
        body,
        .{ .ignore_unknown_fields = true },
    ) catch return error.MalformedJson;

    // NOTE: Do NOT deinit parsed — the returned value's slices ([]const u8, []ContentBlock, etc.)
    // point into memory owned by the parsed result. The caller's arena will free everything.
    return parsed.value;
}

// =============================================================================
// FETCH HELPERS
// =============================================================================

const fetch = Vapor.fetch;

/// Submit prompt to the local backend
pub fn submitToBackend(
    prompt: []const u8,
    handler: fn (Vapor.Fetch.Result) void,
) void {
    // Escaped: a prompt with quotes or newlines is still valid JSON.
    const payload = std.json.Stringify.valueAlloc(Vapor.arena(.frame), .{ .query = prompt }, .{}) catch return;

    fetch(backend.url("/chat"), .{
        .method = .POST,
        .body = payload,
        .credentials = "include",
        .body_type = .json,
    }).handle(handler, .{});
}

/// Submit prompt to the local backend
pub fn submitToBackendVertex(
    prompt: []const u8,
    handler: fn (Vapor.Fetch.Result) void,
) void {
    // Escaped: a prompt with quotes or newlines is still valid JSON.
    const payload = std.json.Stringify.valueAlloc(Vapor.arena(.frame), .{ .query = prompt }, .{}) catch return;

    fetch(backend.url("/api/vertex"), .{
        .method = .POST,
        .body = payload,
        .credentials = "include",
        .body_type = .json,
    }).handle(handler, .{});
}

/// Submit prompt directly to the Claude API via browser
pub fn submitToClaude(
    messages: []const ClaudeChatMessage,
    handler: fn (Vapor.Fetch.Result) void,
    model: []const u8,
) !void {
    const key = Vapor.load([]const u8, "claude_api_token") orelse {
        Opaque.Toast.err(.{
            .title = "Claude API Key Not Found",
            .description = "Please set your Claude API key in the settings page.",
        });
        return error.ClaudeApiKeyNotFound;
    };

    const body: struct {
        model: []const u8 = "",
        max_tokens: u32 = 1024,
        messages: []const ClaudeChatMessage = &.{},
    } = .{
        .model = model,
        .messages = messages,
    };

    const json = std.json.Stringify.valueAlloc(Vapor.frame.arena(), body, .{}) catch unreachable;

    fetch("https://api.anthropic.com/v1/messages", .{
        .method = .POST,
        .body = json,
        .body_type = .json,
        .extra_headers = &.{
            Vapor.Fetch.Header{ .name = "x-api-key", .value = key },
            Vapor.Fetch.Header{ .name = "anthropic-version", .value = "2023-06-01" },
            Vapor.Fetch.Header{ .name = "anthropic-dangerous-direct-browser-access", .value = "true" },
        },
    }).handle(handler, .{});
}

/// Submit prompt directly to the OpenAI API via browser
pub fn submitToCodex(
    messages: []const CodexChatMessage,
    model: []const u8,
) !void {
    Chat.callCodex(Vapor.persist.arena(), messages, model) catch |err| {
        Opaque.Toast.err(.{
            .title = "OpenAI API Error",
            .description = "Please check your OpenAI API key in the settings page.",
        });
        return err;
    };
}

/// Submit prompt to Claude via Google Cloud Vertex AI
pub fn submitToClaudeVertex(
    messages: []const ClaudeChatMessage,
    handler: fn (Vapor.Fetch.Result) void,
    model: []const u8,
) void {
    const project_id = Vapor.load([]const u8, "gcp_project_id") orelse {
        Opaque.Toast.err(.{
            .title = "GCP Project ID Not Found",
            .description = "Please set your Google Cloud Project ID in the settings page.",
        });
        return;
    };
    // gcloud auth print-access-token
    const access_token = Vapor.load([]const u8, "vertex_access_token") orelse {
        Opaque.Toast.err(.{
            .title = "Vertex Access Token Not Found",
            .description = "Please set your Google Cloud Vertex Access Token in the settings page.",
        });
        return;
    };
    // const region = "us-east5";
    const region = "us-central1";
    // const region = "global";

    const body: struct {
        anthropic_version: []const u8 = "vertex-2023-10-16",
        max_tokens: u32 = 1024,
        messages: []const ClaudeChatMessage = &.{},
        stream: bool = false,
    } = .{
        .messages = messages,
    };

    const json = std.json.Stringify.valueAlloc(Vapor.frame.arena(), body, .{}) catch unreachable;

    const url = std.fmt.allocPrint(
        Vapor.frame.arena(),
        "https://{s}-aiplatform.googleapis.com/v1/projects/{s}/locations/{s}/publishers/anthropic/models/{s}:rawPredict",
        .{ region, project_id, region, model },
    ) catch unreachable;

    fetch(url, .{
        .method = .POST,
        .body = json,
        .body_type = .json,
        .credentials = "include",
        .extra_headers = &.{
            Vapor.Fetch.Header{ .name = "Authorization", .value = std.fmt.allocPrint(
                Vapor.frame.arena(),
                "Bearer {s}",
                .{access_token},
            ) catch unreachable },
        },
    }).handle(handler, .{});
}
