const std = @import("std");
const Vapor = @import("vapor");
const mem = std.mem;
const json = std.json;
const http = std.http;
const auth = @import("auth.zig");
const CodexChatMessage = @import("../routes/Assembler.zig").CodexChatMessage;
const Assembler = @import("../routes/Assembler.zig");

// ─── Codex system prompt (required for OAuth-based access) ──────────
const codex_system_prompt = "You are Codex, a coding assistant made by OpenAI. You are running as a coding agent in a CLI on the user's machine. You help the user with coding tasks.";

// ─── Available models ───────────────────────────────────────────────
pub const Model = struct {
    alias: []const u8,
    id: []const u8,
};

pub const models = [_]Model{
    .{ .alias = "codex", .id = "gpt-5.2-codex" },
    .{ .alias = "5.2", .id = "gpt-5.2-codex" },
    .{ .alias = "5.3", .id = "gpt-5.3-codex" },
    .{ .alias = "mini", .id = "codex-mini-latest" },
};

const default_model = "gpt-5.2-codex";
const codex_api_url = "https://chatgpt.com/backend-api/codex/responses";

const ChatRole = enum {
    user,
    assistant,
};

const ChatMessage = CodexChatMessage;

fn roleToString(role: ChatRole) []const u8 {
    return switch (role) {
        .user => "user",
        .assistant => "assistant",
    };
}

fn contentTypeForRole(role: []const u8) []const u8 {
    if (mem.eql(u8, role, "user")) {
        return "input_text";
    } else if (mem.eql(u8, role, "assistant")) {
        return "output_text";
    }
    return "output_text";
}

fn resolveModel(name: []const u8) []const u8 {
    for (&models) |*m| {
        if (mem.eql(u8, m.alias, name)) return m.id;
    }
    return name; // allow raw model string
}

// ─── Parse SSE payload ──────────────────────────────────────────────
fn parseSSEPayload(allocator: mem.Allocator, raw: []const u8) ![]const u8 {
    var output_text = std.array_list.Managed(u8).init(allocator);
    defer output_text.deinit();

    // Split on double newlines (SSE event boundaries)
    var events = mem.splitSequence(u8, raw, "\n\n");
    while (events.next()) |event_chunk| {
        if (event_chunk.len == 0) continue;

        var data_buf = std.array_list.Managed(u8).init(allocator);
        defer data_buf.deinit();

        var lines = mem.splitScalar(u8, event_chunk, '\n');
        while (lines.next()) |line| {
            if (mem.startsWith(u8, line, "data:")) {
                const data_part = mem.trimStart(u8, line[5..], " ");
                if (data_buf.items.len > 0) try data_buf.append('\n');
                try data_buf.appendSlice(data_part);
            }
        }

        if (data_buf.items.len == 0) continue;
        if (mem.eql(u8, data_buf.items, "[DONE]")) continue;

        // Try to parse as JSON
        const parsed = json.parseFromSlice(json.Value, allocator, data_buf.items, .{}) catch continue;
        defer parsed.deinit();
        const payload = parsed.value;

        // Accumulate streaming deltas
        if (isPayloadType(payload, "response.output_text.delta")) {
            if (getDelta(payload)) |delta| {
                try output_text.appendSlice(delta);
            }
        }
    }

    if (output_text.items.len > 0) {
        return try allocator.dupe(u8, output_text.items);
    }

    return error.NoResponsePayload;
}

fn isPayloadType(val: json.Value, expected: []const u8) bool {
    if (val != .object) return false;
    const t = val.object.get("type") orelse return false;
    if (t != .string) return false;
    return mem.eql(u8, t.string, expected);
}

fn getDelta(val: json.Value) ?[]const u8 {
    if (val != .object) return null;
    const d = val.object.get("delta") orelse return null;
    if (d == .string) return d.string;
    return null;
}

// ─── Call the Codex / Responses API ─────────────────────────────────
pub fn callCodex(allocator: mem.Allocator, messages: []const ChatMessage, model_name: []const u8) !void {
    const access_token = try auth.getAccessToken(allocator);
    defer allocator.free(access_token);
    const model = resolveModel(model_name);

    // Build JSON body
    var out = std.Io.Writer.Allocating.init(allocator);
    defer out.deinit();

    var jw = std.json.Stringify{
        .writer = &out.writer,
        .options = .{},
    };

    try jw.beginObject();

    try jw.objectField("model");
    try jw.write(model);

    try jw.objectField("instructions");
    try jw.write(codex_system_prompt);

    try jw.objectField("input");
    try jw.beginArray();
    for (messages) |msg| {
        try jw.beginObject();
        try jw.objectField("type");
        try jw.write("message");
        try jw.objectField("role");
        try jw.write(msg.role);
        try jw.objectField("content");
        try jw.beginArray();
        try jw.beginObject();
        try jw.objectField("type");
        try jw.write(contentTypeForRole(msg.role));
        try jw.objectField("text");
        try jw.write(msg.text);
        try jw.endObject();
        try jw.endArray();
        try jw.endObject();
    }
    try jw.endArray();

    try jw.objectField("store");
    try jw.write(false);

    try jw.objectField("stream");
    try jw.write(true);

    try jw.endObject();

    const payload = try out.toOwnedSlice();
    defer allocator.free(payload);

    // Build Authorization header
    const auth_header = try std.fmt.allocPrint(allocator, "Bearer {s}", .{access_token});
    defer allocator.free(auth_header);

    var fc = Vapor.fetch(codex_api_url, .{
        .method = .POST,
        .body = payload,
        .extra_headers = &.{
            Vapor.Fetch.Header{
                .name = "Content-Type",
                .value = "application/json",
            },
            Vapor.Fetch.Header{
                .name = "Authorization",
                .value = auth_header,
            },
        },
    });
    fc.handle(handleCodexResponse, .{});
}

fn handleCodexResponse(resp: Vapor.Fetch.Result) void {
    switch (resp) {
        .ok => |ok| {
            const text = parseSSEPayload(Vapor.frame.arena(), ok.body) catch |err| {
                std.log.err("Error: {any}", .{err});
                return;
            };
            Assembler.applyAssistantContent(text);
        },
        .err => |er| {
            std.log.err("err {s}", .{er.body});
        },
    }
}

// ─── Extract text from a JSON response ──────────────────────────────
fn extractResponseText(allocator: mem.Allocator, raw: []const u8) ![]const u8 {
    const parsed = json.parseFromSlice(json.Value, allocator, raw, .{}) catch {
        return error.UnexpectedResponseFormat;
    };
    defer parsed.deinit();
    const data = parsed.value;

    if (data != .object) return error.UnexpectedResponseFormat;
    const output = data.object.get("output") orelse return error.UnexpectedResponseFormat;
    if (output != .array) return error.UnexpectedResponseFormat;

    var texts = std.array_list.Managed(u8).init(allocator);
    defer texts.deinit();

    for (output.array.items) |item| {
        if (item != .object) continue;

        // message items with content array
        const item_type = item.object.get("type") orelse continue;
        if (item_type == .string and mem.eql(u8, item_type.string, "message")) {
            const content = item.object.get("content") orelse continue;
            if (content != .array) continue;
            for (content.array.items) |block| {
                if (block != .object) continue;
                const block_type = block.object.get("type") orelse continue;
                if (block_type != .string) continue;
                if (mem.eql(u8, block_type.string, "output_text") or
                    mem.eql(u8, block_type.string, "text"))
                {
                    const text = block.object.get("text") orelse continue;
                    if (text == .string) {
                        if (texts.items.len > 0) try texts.append('\n');
                        try texts.appendSlice(text.string);
                    }
                }
            }
        }

        // direct text items
        if (item_type == .string and mem.eql(u8, item_type.string, "text")) {
            const text = item.object.get("text") orelse continue;
            if (text == .string) {
                if (texts.items.len > 0) try texts.append('\n');
                try texts.appendSlice(text.string);
            }
        }
    }

    if (texts.items.len > 0) {
        return try allocator.dupe(u8, texts.items);
    }

    // Fallback: dump the raw JSON
    return try allocator.dupe(u8, raw);
}

// ─── Parse chat CLI args and run ────────────────────────────────────
pub fn chatMain(allocator: mem.Allocator) !void {
    var args = try std.process.argsWithAllocator(allocator);
    defer args.deinit();

    _ = args.next(); // skip executable name

    var model_name: []const u8 = default_model;
    var prompt_parts = std.array_list.Managed([]const u8).init(allocator);
    defer prompt_parts.deinit();

    while (args.next()) |arg| {
        if (mem.eql(u8, arg, "--model") or mem.eql(u8, arg, "-m")) {
            model_name = args.next() orelse {
                std.log.info("  Error: --model requires a value\n", .{});
                return;
            };
        } else if (mem.eql(u8, arg, "chat")) {
            // skip the "chat" subcommand word itself
            continue;
        } else {
            try prompt_parts.append(arg);
        }
    }

    if (prompt_parts.items.len == 0) {
        try chatRepl(allocator, model_name);
        return;
    }

    // Join prompt parts with spaces
    var prompt_buf = std.array_list.Managed(u8).init(allocator);
    defer prompt_buf.deinit();
    for (prompt_parts.items, 0..) |part, i| {
        if (i > 0) try prompt_buf.append(' ');
        try prompt_buf.appendSlice(part);
    }

    var messages = std.array_list.Managed(ChatMessage).init(allocator);
    defer {
        for (messages.items) |msg| msg.deinit(allocator);
        messages.deinit();
    }

    const user_prompt = try allocator.dupe(u8, prompt_buf.items);
    try messages.append(.{ .role = .user, .text = user_prompt });

    const text = try callCodex(allocator, messages.items, model_name);
    defer allocator.free(text);

    // Print separator and response
    const sep = "─" ** 30;
    std.log.info("{s}\n", .{sep});
    std.log.info("{s}\n", .{text});
    std.log.info("{s}\n\n", .{sep});
}

fn chatRepl(allocator: mem.Allocator, model_name: []const u8) !void {
    const model = resolveModel(model_name);
    std.log.info("  Chat mode started (model: {s})\n", .{model});
    std.log.info("  Commands: /exit, /quit, /clear\n\n", .{});

    var messages = std.array_list.Managed(ChatMessage).init(allocator);
    defer {
        for (messages.items) |msg| msg.deinit(allocator);
        messages.deinit();
    }

    const stdin_buf = try allocator.alloc(u8, 1024 * 1024);
    defer allocator.free(stdin_buf);
    var stdin_reader = std.fs.File.stdin().reader(stdin_buf);
    const stdin = &stdin_reader.interface;
    const sep = "─" ** 30;

    while (true) {
        std.log.info("you> ", .{});
        const line_opt = try stdin.takeDelimiter('\n');
        if (line_opt == null) {
            std.log.info("\n", .{});
            break;
        }

        const line = mem.trim(u8, line_opt.?, " \r\t\n");
        if (line.len == 0) continue;

        if (mem.eql(u8, line, "/exit") or mem.eql(u8, line, "/quit")) {
            break;
        }
        if (mem.eql(u8, line, "/clear")) {
            for (messages.items) |msg| msg.deinit(allocator);
            messages.clearRetainingCapacity();
            std.log.info("  Conversation cleared.\n", .{});
            continue;
        }

        const user_text = try allocator.dupe(u8, line);
        errdefer allocator.free(user_text);
        try messages.append(.{ .role = .user, .text = user_text });

        const text = callCodex(allocator, messages.items, model_name) catch |err| {
            const last = messages.pop() orelse continue;
            allocator.free(last.text);
            std.log.info("  Error: {}\n\n", .{err});
            continue;
        };
        defer allocator.free(text);

        const assistant_text = try allocator.dupe(u8, text);
        errdefer allocator.free(assistant_text);
        try messages.append(.{ .role = .assistant, .text = assistant_text });

        std.log.info("{s}\n", .{sep});
        std.log.info("{s}\n", .{text});
        std.log.info("{s}\n\n", .{sep});
    }
}

fn printChatUsage() void {
    std.log.info(
        \\
        \\  codex-auth chat — Chat with Codex
        \\
        \\  Usage:
        \\    codex-auth chat                     Start interactive chat mode
        \\    codex-auth chat "your prompt here"
        \\    codex-auth chat --model mini "your prompt here"
        \\    codex-auth chat -m 5.3 "explain this code"
        \\
        \\  Interactive commands:
        \\    /exit, /quit    Exit chat mode
        \\    /clear          Clear conversation history
        \\
        \\  Models:
        \\    codex   → gpt-5.2-codex (default)
        \\    5.2     → gpt-5.2-codex
        \\    5.3     → gpt-5.3-codex
        \\    mini    → codex-mini-latest
        \\    (or pass any raw model string)
        \\
    , .{});
}
