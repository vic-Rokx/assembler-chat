// =============================================================================
// VAPOR ASSEMBLER — AI Code Generator (Refactored)
// =============================================================================
// prompt → Zig/Vapor code. Tabs: Generate · Templates · Learn · History · Settings
// Collapsible sidebar nav. Glitch animation strip. Syntax highlighting panel.
// =============================================================================

const std = @import("std");
const Vapor = @import("vapor");
const Vaporize = @import("vaporize");
const Opaque = @import("opaque_ui");

const Text = Vapor.Text;
const TextFmt = Vapor.TextFmt;
const Row = Vapor.Row;
const Stack = Vapor.Stack;
const Center = Vapor.Center;
const Icon = Vapor.Icon;
const Button = Vapor.Button;
const Label = Vapor.Label;
const Animation = Vapor.Animation;
const SyntaxHighlighter = Vaporize.SyntaxHighlighter;
const Sheet = Opaque.Sheet;
const StringSelect = Opaque.StringSelect;
const loadFileFromChat = @import("Playground_state_switch.zig").loadFileFromChat;
const loadPlanner = @import("Planner.zig").loadPlanner;

// =============================================================================
// THEME — Color tokens for the Assembler UI
// =============================================================================

const Theme = struct {
    pub const text = Vapor.Types.Color.hex("#1A1917");
    pub const text_muted = Vapor.Types.Color.hex("#6B6760");
    pub const text_subtle = Vapor.Types.Color.hex("#A8A49E");
    pub const text_secondary = Vapor.Types.Color.hex("#a1a1aa");

    pub const border = Vapor.Types.Color.hex("#DDD9D2");
    pub const border_light = Vapor.Types.Color.hex("#EEEBE6");

    pub const accent = Vapor.Types.Color.hex("#1B3A6B");
    pub const accent_light = Vapor.Types.Color.hex("#E8EEF8");

    pub const success = Vapor.Types.Color.hex("#1A7A4A");
    pub const warning = Vapor.Types.Color.hex("#F5590B");
    pub const err = Vapor.Types.Color.hex("#C0392B");

    pub const code_bg = Vapor.Types.Color.hex("#111110");
    pub const code_surface = Vapor.Types.Color.hex("#1C1B19");
    pub const code_border = Vapor.Types.Color.hex("#383735");
};

// =============================================================================
// ANIMATIONS — All animation definitions for the Assembler UI
// =============================================================================

pub const glitch = Animation.init("glitch")
    .duration(200)
    .at(25).set(.translateX, -10).setColor(.backgroundColor, .red)
    .at(35).set(.translateX, 10).setColor(.backgroundColor, .green).set(.scaleX, 1.1)
    .at(59).set(.opacity, 0).setColor(.backgroundColor, .blue)
    .at(60).set(.opacity, 1).set(.translateX, -10).set(.blur, 5).set(.scaleX, 0.7)
    .at(100).set(.blur, 5).setColor(.backgroundColor, .yellow);

pub const spin = Animation.init("gen-spin")
    .prop(.rotate, 0, 360)
    .duration(900).easing(.linear).infinite();

pub const fade_in = Animation.init("gen-fade-in")
    .prop(.opacity, 0, 1).prop(.translateY, 8, 0)
    .duration(280).easing(.easeOut).fill(.forwards);

pub const pulse = Animation.init("gen-pulse")
    .prop(.opacity, 1, 0.4)
    .duration(700).dir(.alternate).infinite();

pub const slide_up = Animation.init("gen-slide-up")
    .prop(.translateY, 12, 0).prop(.opacity, 0, 1)
    .duration(240).easing(.easeOut).fill(.forwards);

pub const slide_in_from_right = Animation.init("from-right")
    .propUnit(.translateX, 100, 0, .percent)
    .duration(150)
    .easing(.easeInOut)
    .fill(.forwards);

pub const slide_out_from_right = Animation.init("to-right")
    .propUnit(.translateX, 0, 100, .percent)
    .duration(150)
    .easing(.easeInOut)
    .fill(.forwards);

pub const flip_down = Animation.init("flipDown")
    .at(0).setAll(.{ .translateY = -8, .opacity = 0.3 })
    .at(100).setAll(.{ .translateY = 0, .opacity = 1 })
    .duration(60)
    .easing(.easeOut)
    .fill(.both);

pub const letter_land = Animation.init("letterLand")
    .at(0).setAll(.{ .translateY = -4, .opacity = 0.8 })
    .at(50).setAll(.{ .translateY = 1 })
    .at(100).setAll(.{ .translateY = 0, .opacity = 1 })
    .duration(150)
    .easing(.easeOutBack)
    .fill(.both);

/// Register all animations with the Vapor runtime. Call once from init().
pub fn buildAll() void {
    glitch.build();
    spin.build();
    fade_in.build();
    pulse.build();
    slide_up.build();
    flip_down.build();
    letter_land.build();
    slide_in_from_right.build();
    slide_out_from_right.build();
}

// Extracted modules
const data = @import("data.zig");
const api = @import("api.zig");

// =============================================================================
// WORD FLIPPER STATE
// =============================================================================

const words = [_][]const u8{
    "ASSEMBLER",
    "ORCHESTRATOR",
    "CREATOR",
    "TEACHER",
    "MODEL",
};
const MAX_LEN = 12;
const alphabet = "ABCDEFGHIJKLMNOPQRSTUVWXYZ ";

const initial_word: usize = 0;
var current_word: usize = initial_word;
var is_spinning: [MAX_LEN]bool = [_]bool{false} ** MAX_LEN;
var spin_ticks: [MAX_LEN]u32 = [_]u32{0} ** MAX_LEN;
var target_ticks: [MAX_LEN]u32 = [_]u32{0} ** MAX_LEN;
var active_flip: bool = false;
var display_len: usize = words[initial_word].len;

var display: [MAX_LEN]u8 = blk: {
    var buf: [MAX_LEN]u8 = [_]u8{' '} ** MAX_LEN;
    const word = words[initial_word];
    const offset = (MAX_LEN - word.len) / 2;
    for (0..word.len) |i| {
        buf[offset + i] = word[i];
    }
    break :blk buf;
};

pub const ClaudeChatMessage = struct {
    role: []const u8, // "user" or "assistant"
    content: []const u8,
};

pub const CodexChatMessage = struct {
    role: []const u8, // "user" or "assistant"
    text: []const u8,
};

var claude_chat_history = Vapor.persist.array(ClaudeChatMessage);
var codex_chat_history = Vapor.persist.array(CodexChatMessage);
pub var chat_history: ChatHistory = .{ .default = null };

const ChatHistory = union(enum) {
    default: ?void,
    claude: *Vapor.ArrayArena(ClaudeChatMessage),
    codex: *Vapor.ArrayArena(CodexChatMessage),

    pub fn append(self: *ChatHistory, role: []const u8, value: []const u8) void {
        switch (self.*) {
            .claude => {
                claude_chat_history.append(.{
                    .role = role,
                    .content = value,
                });
            },
            .codex => {
                codex_chat_history.append(.{
                    .role = role,
                    .text = value,
                });
            },
            else => {
                Opaque.Toast.err(.{ .title = "Unsupported Model", .description = "Select a Claude or GPT model." });
            },
        }
    }
};

fn startFlip() void {
    if (active_flip) return;
    active_flip = true;

    const target = words[current_word];
    display_len = target.len;
    const offset = (MAX_LEN - display_len) / 2;

    for (0..MAX_LEN) |i| {
        if (i >= offset and i < offset + display_len) {
            is_spinning[i] = true;
            spin_ticks[i] = 0;
            const local = i - offset;
            target_ticks[i] = @intCast(8 + local * 3);
        } else {
            is_spinning[i] = false;
            spin_ticks[i] = 0;
            display[i] = ' ';
        }
    }
    tick();
}

fn tick() void {
    const target = words[current_word];
    const offset = (MAX_LEN - display_len) / 2;
    var any_active = false;

    for (0..MAX_LEN) |i| {
        if (!is_spinning[i]) continue;
        spin_ticks[i] += 1;

        if (spin_ticks[i] >= target_ticks[i]) {
            const local = i - offset;
            display[i] = if (local < target.len) target[local] else ' ';
            is_spinning[i] = false;
        } else {
            const tick_offset = spin_ticks[i] + @as(u32, @intCast(i)) * 7;
            display[i] = alphabet[tick_offset % alphabet.len];
            any_active = true;
        }
    }

    if (any_active) {
        Vapor.timeout("flipTick", 20, tick, .{});
    } else {
        active_flip = false;
    }
}

// =============================================================================
// ENUMS — TABS & NAV
// =============================================================================

const Tab = enum {
    generate,
    templates,
    learn,
    history,
    settings,

    pub fn label(self: Tab) []const u8 {
        return switch (self) {
            .generate => "Generate",
            .templates => "Templates",
            .learn => "Learn",
            .history => "History",
            .settings => "Settings",
        };
    }

    pub fn icon(self: Tab) Vapor.IconTokens {
        return switch (self) {
            .generate => .columns_gap,
            .templates => .grid_3x3,
            .learn => .hammer,
            .history => .clock_history,
            .settings => .gear,
        };
    }

    pub fn hint(self: Tab) []const u8 {
        return switch (self) {
            .generate => "Describe a UI component",
            .templates => "Start from a ready-made pattern",
            .learn => "Vapor concepts & examples",
            .history => "Your recent generations",
            .settings => "Model & output preferences",
        };
    }
};

const NavItem = enum {
    assembler,
    planner,
    playground,
    settings,

    pub fn label(self: NavItem) []const u8 {
        return switch (self) {
            .assembler => "Assembler",
            .planner => "Planner",
            .playground => "Playground",
            .settings => "Settings",
        };
    }

    pub fn icon(self: NavItem) Vapor.IconTokens {
        return switch (self) {
            .assembler => .cassette,
            .planner => .hammer,
            .playground => .braces,
            .settings => .gear,
        };
    }

    pub fn route(self: NavItem) []const u8 {
        return switch (self) {
            .assembler => "/",
            .planner => "/planner",
            .playground => "/playground",
            .settings => "/settings",
        };
    }

    pub fn setActive(path: []const u8) void {
        const item = std.meta.stringToEnum(NavItem, path[1..]) orelse .assembler;
        active_nav = item;
    }
};

// =============================================================================
// STATE
// =============================================================================

// Navigation
var active_tab: Tab = .generate;
var active_nav: NavItem = .assembler;
var sidebar_expanded: bool = false;
var is_nav_hovered: bool = false;

// Generate tab
var prompt_input: []const u8 = "";
var is_generating: bool = false;
var has_generated: bool = false;
pub var current_code: []const u8 = DEFAULT_CODE;
var markdown_source: []const u8 = "";

// Copy feedback
var copy_success: bool = false;

// History
const HistoryEntry = struct {
    prompt: []const u8,
    timestamp: []const u8,
    output: []const u8,
    mode: []const u8,
    model: []const u8,
    provider: []const u8,
};
var history = Vapor.persist.array(HistoryEntry);
const generation_history_key = "assembler_generation_history_v1";
var showing_history_diff: bool = false;

// Settings
var settings_model_idx: usize = 0;
var settings_comments: bool = true;
var settings_full_file: bool = true;

// Highlighter & markdown
var code_highlighter: SyntaxHighlighter = undefined;
const Root = @import("../main.zig");
var markdown: Root.vaporize.MarkDown(.{}) = .{};

// UI state
var show_code: bool = false;
var show_markdown: bool = false;
var is_hovered: bool = false;
var show_delete: ?usize = null;
var show_options: bool = false;
var active_pill: ?data.Pill = data.OPTION_PILLS[0];

const DEFAULT_CODE = "const Vapor = @import(\"vapor\");";

// File uploads
const FileInfo = struct {
    name: []const u8,
    type: []const u8,
    size: u32,
    url: []const u8,
};
var file_list = Vapor.persist.array(FileInfo);

// =============================================================================
// INIT
// =============================================================================

var sheet: Sheet = .{
    .content = renderCodePanel,
    .direction = .right,
    .size = 800,
};

var llm_select: Opaque.Select([]const u8) = undefined;
var vertex_selected: bool = false;

var io: std.Io = undefined;
pub fn init() void {
    Vapor.Page(.{ .src = @src() }, render, null);
    var threaded: std.Io.Threaded = .init_single_threaded;
    io = threaded.io();

    buildAll();

    Sheet.new();

    const model = Vapor.load([]const u8, "ai_model");
    llm_select = .fromItems(&.{
        .{ .label = "claude-opus-4-6", .value = "claude-opus-4-6" },
        .{ .label = "claude-sonnet-4-6", .value = "claude-sonnet-4-6" },
        .{ .label = "claude-sonnet-4-5", .value = "claude-sonnet-4-5" },
        .{ .label = "claude-haiku-4-5", .value = "claude-haiku-4-5" },
        .{ .label = "gpt-5.2-codex", .value = "gpt-5.2-codex" },
        .{ .label = "gpt-5.3-codex", .value = "gpt-5.3-codex" },
    });
    llm_select.height = .px(32);
    llm_select.border = .sharp(.all(1), .palette(.border_color_light));
    llm_select.selected_border = .sharp(.all(1), .palette(.tint));
    llm_select.on_select = onModelSelect;
    if (model) |m| {
        llm_select.default(.{ .label = m, .value = m });
        if (std.mem.startsWith(u8, m, "claude-")) {
            chat_history = .{ .claude = &claude_chat_history };
        } else if (std.mem.startsWith(u8, m, "gpt-")) {
            chat_history = .{ .codex = &codex_chat_history };
        } else {
            Opaque.Toast.err(.{
                .title = "Unsupported Model",
                .description = "Select a Claude or GPT model.",
            });
        }
    }

    if (Vapor.load([]const u8, "active_mode")) |active_mode| {
        for (data.OPTION_PILLS, 0..) |pill, i| {
            if (std.mem.eql(u8, pill.label, active_mode)) {
                active_pill = pill;
                current_word = i;
                startFlip();
                break;
            }
        }
    }

    code_highlighter = SyntaxHighlighter.init(Vapor.arena(.persist));
    code_highlighter.use_cpy_btn = false;
    code_highlighter.parse(DEFAULT_CODE) catch unreachable;

    markdown.compile(markdown_source) catch unreachable;
    loadGenerationHistory();

    const fix_prompt = Vapor.load([]const u8, "assembler-fix-prompt") orelse "";
    if (fix_prompt.len > 0) {
        prompt_input = Vapor.persist.dupe(fix_prompt);
        active_pill = data.OPTION_PILLS[4];
        current_word = 4;
        startFlip();

        Vapor.store("assembler-fix-prompt", "");
        Vapor.timeout("assembler-auto-fix", 60, submitPrompt, .{});
    }
}

fn saveGenerationHistory() void {
    const json = std.json.Stringify.valueAlloc(Vapor.frame.arena(), history.items, .{}) catch return;
    Vapor.store(generation_history_key, json);
}

fn loadGenerationHistory() void {
    const raw = Vapor.load([]const u8, generation_history_key) orelse return;
    const parsed = std.json.parseFromSlice(
        []HistoryEntry,
        Vapor.frame.arena(),
        raw,
        .{ .ignore_unknown_fields = true },
    ) catch return;

    history.clearRetainingCapacity();
    for (parsed.value) |entry| {
        history.append(.{
            .prompt = Vapor.persist.dupe(entry.prompt),
            .timestamp = Vapor.persist.dupe(entry.timestamp),
            .output = Vapor.persist.dupe(entry.output),
            .mode = Vapor.persist.dupe(entry.mode),
            .model = Vapor.persist.dupe(entry.model),
            .provider = Vapor.persist.dupe(entry.provider),
        });
    }
}

fn makeTimestamp() []const u8 {
    return Vapor.persist.fmt("{d}", .{Vapor.Kit.timestamp()});
}

fn makeLineDiff(current: []const u8, target: []const u8) []const u8 {
    var out = Vapor.frame.array(u8);
    var a_it = std.mem.splitScalar(u8, current, '\n');
    var b_it = std.mem.splitScalar(u8, target, '\n');

    while (true) {
        const a = a_it.next();
        const b = b_it.next();
        if (a == null and b == null) break;

        if (a != null and b != null and std.mem.eql(u8, a.?, b.?)) {
            out.appendSlice("  ");
            out.appendSlice(a.?);
            out.appendSlice("\n");
            continue;
        }
        if (a) |line| {
            out.appendSlice("- ");
            out.appendSlice(line);
            out.appendSlice("\n");
        }
        if (b) |line| {
            out.appendSlice("+ ");
            out.appendSlice(line);
            out.appendSlice("\n");
        }
    }

    return Vapor.persist.dupe(out.slice());
}

fn addGenerationHistory(prompt: []const u8, output: []const u8, mode: []const u8, model: []const u8, provider: []const u8) void {
    history.insert(0, .{
        .prompt = Vapor.persist.dupe(prompt),
        .timestamp = makeTimestamp(),
        .output = Vapor.persist.dupe(output),
        .mode = Vapor.persist.dupe(mode),
        .model = Vapor.persist.dupe(model),
        .provider = Vapor.persist.dupe(provider),
    });
    if (history.items.len > 30) {
        _ = history.orderedRemove(0);
    }
    saveGenerationHistory();
}

fn restoreHistoryItem(i: usize) void {
    if (i >= history.items.len) return;
    const item = history.items[i];
    prompt_input = item.prompt;
    showing_history_diff = false;
    has_generated = true;

    if (std.mem.eql(u8, item.mode, "markdown")) {
        markdown_source = item.output;
        markdown.compile(markdown_source) catch {};
        show_markdown = true;
        show_code = false;
    } else {
        current_code = item.output;
        code_highlighter.recompile(current_code) catch {};
        show_code = true;
        show_markdown = false;
    }
}

fn diffHistoryItem(i: usize) void {
    if (i >= history.items.len) return;
    const item = history.items[i];
    const current = if (std.mem.eql(u8, item.mode, "markdown")) markdown_source else current_code;
    const diff_text = makeLineDiff(current, item.output);
    code_highlighter.recompile(diff_text) catch {};
    showing_history_diff = true;
    show_code = true;
    show_markdown = false;
}

fn clearHistoryDiff() void {
    showing_history_diff = false;
    if (has_generated) {
        code_highlighter.recompile(current_code) catch {};
    }
}

// =============================================================================
// API HANDLERS
// =============================================================================

fn submitPromptStr(p: []const u8) void {
    if (p.len == 0 or is_generating) return;
    is_generating = true;

    const saved = Vapor.arena(.persist).dupe(u8, p) catch return;

    // Append user message to history
    chat_history.append("user", saved);

    const model = llm_select.selectedValue() orelse return;

    if (std.mem.startsWith(u8, model, "claude-")) {
        api.submitToClaude(chat_history.claude.items, handleClaudeResponse, model) catch {
            is_generating = false;
        };
    } else if (std.mem.startsWith(u8, model, "gpt-")) {
        api.submitToCodex(chat_history.codex.items, model) catch {
            is_generating = false;
        };
    } else {
        is_generating = false;
        Opaque.Toast.err(.{
            .title = "Unsupported Model",
            .description = "Select a Claude or GPT model.",
        });
    }
}

fn submitPromptStrVertex(p: []const u8) void {
    if (p.len == 0) return;
    if (is_generating) return;

    is_generating = true;
    copy_success = false;

    const model = llm_select.selectedValue() orelse {
        Opaque.Toast.err(.{ .title = "Model Not Found", .description = "Please select a model from the dropdown." });
        return;
    };
    _ = model;

    api.submitToBackendVertex(prompt_input, handleGenerateResponse);
}

fn submitViaBackend(p: []const u8) void {
    if (p.len == 0) return;
    if (is_generating) return;

    is_generating = true;
    copy_success = false;

    const model = llm_select.selectedValue() orelse {
        Opaque.Toast.err(.{ .title = "Model Not Found", .description = "Please select a model from the dropdown." });
        return;
    };
    _ = model;

    api.submitToBackend(prompt_input, handleGenerateResponse);
}

fn submitPrompt() void {
    if (llm_select.selectedValue() == null) {
        Opaque.Toast.err(.{ .title = "Model Not Found", .description = "Please select a model from the dropdown." });
        return;
    }
    if (active_pill) |ap| {
        if (std.mem.eql(u8, ap.label, "model")) {
            if (vertex_selected) {
                submitPromptStrVertex(prompt_input);
            } else {
                submitPromptStr(prompt_input);
            }
            return;
        }
        Opaque.Toast.err(.{ .title = "API Keys Missing", .description = "Select Model option and Model that corresponds to your API keys." });
        // submitViaBackend(prompt_input);
    }
}

fn parseChatHistory(messages: ChatHistory) []const u8 {
    var content = Vapor.frame.array(u8);
    switch (messages) {
        .claude => {
            for (messages.claude.items) |message| {
                const is_user = std.mem.eql(u8, message.role, "user");
                if (is_user) {
                    content.appendSlice(">>> ");
                    content.appendSlice(message.content);
                } else {
                    content.appendSlice("::: assistant\n");
                    content.appendSlice(message.content);
                    content.appendSlice("\n\n:::");
                }
                content.appendSlice("\n\n");
            }
            return content.slice();
        },
        .codex => {
            for (messages.codex.items) |message| {
                const is_user = std.mem.eql(u8, message.role, "user");
                if (is_user) {
                    content.appendSlice(">>> ");
                    content.appendSlice(message.text);
                } else {
                    content.appendSlice("::: assistant\n");
                    content.appendSlice(message.text);
                    content.appendSlice("\n\n:::");
                }
                content.appendSlice("\n\n");
            }
            return content.slice();
        },
        else => {},
    }

    return content.slice();
}

var message_response: ?api.MessageResponse = null;
pub fn applyAssistantContent(content_raw: []const u8) void {
    const content = Vapor.persist.dupe(content_raw);
    chat_history.append("assistant", content);

    const parsed_history = parseChatHistory(chat_history);

    markdown_source = parsed_history;
    has_generated = true;
    markdown.compile(markdown_source) catch unreachable;

    active_tab = .generate;
    show_markdown = true;
    show_code = false;
    showing_history_diff = false;

    const model = llm_select.selectedValue() orelse "unknown";
    const provider: []const u8 = if (std.mem.startsWith(u8, model, "gpt-")) "openai" else "claude";
    addGenerationHistory(prompt_input, content_raw, "markdown", model, provider);
    prompt_input = "";
    is_generating = false;
}

fn handleClaudeResponse(resp: Vapor.Fetch.Result) void {
    switch (resp) {
        .ok => |ok| {
            const parsed = api.parseResp(api.MessageResponse, ok.body, Vapor.frame.arena()) catch |err| {
                Opaque.Toast.err(.{ .title = "Parsing Error", .description = Vapor.frame.fmt("{any}", .{err}) });
                return;
            };
            var content: []const u8 = "";
            for (parsed.content) |block| {
                if (std.mem.eql(u8, block.type, "text")) {
                    content = block.text orelse "";
                }
            }
            applyAssistantContent(content);
        },
        .err => |er| {
            current_code = Vapor.fmtln("// Error: {s}", .{er.message});
            active_tab = .generate;
        },
    }
}

fn handleOpenAIResponse(resp: Vapor.Fetch.Result) void {
    switch (resp) {
        .ok => |ok| {
            const parsed = api.parseResp(api.OpenAIResponse, ok.body, Vapor.frame.arena()) catch |err| {
                Opaque.Toast.err(.{ .title = "Parsing Error", .description = Vapor.frame.fmt("{any}", .{err}) });
                return;
            };
            if (parsed.choices.len == 0) {
                Opaque.Toast.err(.{
                    .title = "Empty Response",
                    .description = "OpenAI returned no choices.",
                });
                return;
            }
            applyAssistantContent(parsed.choices[0].message.content);
        },
        .err => |er| {
            current_code = Vapor.fmtln("// Error: {s}", .{er.message});
            active_tab = .generate;
        },
    }
}

fn handleGenerateResponse(resp: Vapor.Fetch.Result) void {
    is_generating = false;
    switch (resp) {
        .ok => |ok| {
            current_code = api.unescapeJson(ok.body);
            has_generated = true;
            code_highlighter.recompile(current_code) catch {};
            show_markdown = false;
            show_code = true;
            showing_history_diff = false;

            const model = llm_select.selectedValue() orelse "backend";
            const provider: []const u8 = if (vertex_selected) "vertex" else "backend";
            addGenerationHistory(prompt_input, current_code, "code", model, provider);
            active_tab = .generate;
        },
        .err => |er| {
            current_code = Vapor.fmtln("// Error: {s}", .{er.message});
            active_tab = .generate;
        },
    }
}

// =============================================================================
// EVENT HANDLERS
// =============================================================================

fn onPromptKeyDown(evt: *Vapor.Event) void {
    if (std.mem.eql(u8, evt.key(), "Enter") and evt.metaKey()) {
        evt.preventDefault();
        submitPrompt();
    }
}

fn toggleVertexMode() void {
    vertex_selected = !vertex_selected;
}

fn selectTab(tab: Tab) void {
    active_tab = tab;
}
fn selectNav(nav: NavItem, _: *Vapor.Event) void {
    active_nav = nav;
    // Vapor.Kit.navigate(nav.route());
}

fn onSidebarHover(_: *Vapor.Event) void {
    sidebar_expanded = true;
}
fn onSidebarLeave(_: *Vapor.Event) void {
    sidebar_expanded = false;
}

fn onHoverNav(is_active: bool, _: *Vapor.Event) void {
    is_hovered = is_active;
}
fn onLeaveNav(_: *Vapor.Event) void {
    is_hovered = false;
}

fn copyToClipboard() void {
    Vapor.Clipboard.copy(current_code);
    copy_success = true;
    Vapor.timeout("copy", 1000, toggleIcon, .{});
}

fn toggleIcon() void {
    copy_success = !copy_success;
}

fn saveToFile() void {
    Vapor.FileReader.downloadFile("vapor_component.zig", current_code, .@"text/plain");
}

fn openPlanner() void {
    // Store the generated markdown so the Planner page can load it
    loadPlanner(markdown_source);
    Vapor.store("assembler-plan", markdown_source);
    Vapor.navigate("/planner");
}

fn openPlayground() void {
    loadFileFromChat();
    Vapor.navigate("/playground");
}

fn selectModel(i: usize) void {
    settings_model_idx = i;
}
fn toggleComments() void {
    settings_comments = !settings_comments;
}
fn toggleFullFile() void {
    settings_full_file = !settings_full_file;
}

fn upload(evt: *Vapor.Event) void {
    var reader: Vapor.FileReader = .init(evt);

    const info = reader.fileInfo(0) catch |err| {
        Vapor.print(.err, "Failed to get file info: {any}", .{err});
        return;
    };

    std.log.info("file {s} of type {s} with size {d}", .{ info.name, info.type, info.size });

    const file = Vapor.persist.dupe(reader.createURLfromFile(0) catch |err| {
        Vapor.print(.err, "Failed to create object URL: {any}", .{err});
        unreachable;
    });

    file_list.append(.{
        .name = Vapor.persist.dupe(info.name),
        .type = Vapor.persist.dupe(info.type),
        .size = info.size,
        .url = file,
    });
}

fn removeFile(file: FileInfo, i: usize) void {
    _ = file;
    _ = file_list.orderedRemove(i);
}

fn showDelete(i: usize, evt: *Vapor.Event) void {
    _ = evt;
    show_delete = i;
}

fn hideDelete(evt: *Vapor.Event) void {
    _ = evt;
    show_delete = null;
}

fn selectPill(pill: data.Pill, index: usize) void {
    current_word = index;
    active_pill = pill;
    Vapor.store("active_mode", pill.label);
    startFlip();
}

fn toggleCodePanel() void {
    show_code = !show_code;
    show_markdown = false;
}

fn toggleMarkdownPanel() void {
    show_markdown = !show_markdown;
    show_code = false;
}

fn toggleWithTransitionMarkdown() void {
    Vapor.lib.startViewTransition(toggleMarkdownPanel, .{});
}

fn toggleWithTransition() void {
    Vapor.lib.startViewTransition(toggleCodePanel, .{});
}

fn onModelSelect(_: *Opaque.Select([]const u8), item: *Opaque.Select([]const u8).Item) void {
    Vapor.store("ai_model", item.value);

    if (std.mem.startsWith(u8, item.value, "claude-")) {
        chat_history = .{ .claude = &claude_chat_history };
    } else if (std.mem.startsWith(u8, item.value, "gpt-")) {
        chat_history = .{ .codex = &codex_chat_history };
    } else {
        Opaque.Toast.err(.{
            .title = "Unsupported Model",
            .description = "Select a Claude or GPT model.",
        });
    }
}

// =============================================================================
// RENDER — SIDEBAR
// =============================================================================

const ICON_AREA_WIDTH = 40;
const SIDEBAR_COLLAPSED = 40 + 10 + 10;
const SIDEBAR_EXPANDED = 240;

pub fn renderSidebar() void {
    const route = Vapor.currentPath();
    NavItem.setActive(route);
    const w: Vapor.Types.Sizing = if (sidebar_expanded) .px(SIDEBAR_EXPANDED) else .px(SIDEBAR_COLLAPSED);

    Stack()
        .width(w)
        .height(.percent(100))
        .background(.palette(.background))
        .border(.right(1, Theme.border))
        .padding(.all(8))
        .spacing(4)
        .transition(.{ .properties = &.{.width}, .duration = 150, .timing = .easeInOut })
        .onHover(onSidebarHover, .{})
        .onLeave(onSidebarLeave, .{})
        .children({

        // Logo
        Row()
            .layout(.left_center)
            .spacing(12)
            .children({
            Row()
                .height(.px(40))
                .width(.px(ICON_AREA_WIDTH))
                .layout(.center)
                .children({
                Vapor.Svg(.{ .svg = @embedFile("assembler_logo.svg"), .override = true })
                    .fill(.palette(.text))
                    .layout(.center)
                    .size(.squarePx(40))
                    .end();
            });

            if (sidebar_expanded) {
                Text("Assembler")
                    .font(13, 600, Theme.text)
                    .fontFamily("'DM Sans', sans-serif")
                    .animationEnter("gen-fade-in")
                    .end();
            }
        });

        // Nav items
        Stack()
            .width(.percent(100))
            .layout(.left_center)
            .children({
            for (std.enums.values(NavItem)) |nav| {
                const active = active_nav == nav;
                Vapor.Link(.{ .url = nav.route() })
                    .onEvent(.click, selectNav, .{nav})
                    .ariaLabel(nav.label())
                    .pos(.relative)
                    .layout(.left_center)
                    .spacing(12)
                    .width(if (sidebar_expanded) .percent(100) else .px(ICON_AREA_WIDTH))
                    .height(.px(40))
                    .pointer()
                    .duration(150)
                    .background(if (active) .transparentize(.palette(.tint), 1) else .transparent)
                    .hover(.{
                        .background = if (active) .hex("#222160") else .palette(.highlight_color),
                    })
                    .onHoverCtx(onHoverNav, .{active})
                    .onLeave(onLeaveNav, .{})
                    .children({
                    if (active) {
                        renderNavCorners();
                    } else {
                        Vapor.Null();
                    }

                    Row()
                        .height(.px(40))
                        .width(.px(40))
                        .layout(.center)
                        .children({
                        Icon(nav.icon())
                            .font(14, 100, if (nav == active_nav) .white else Theme.text_secondary)
                            .end();
                    });

                    if (sidebar_expanded) {
                        Stack()
                            .width(.percent(100))
                            .layout(.left_center)
                            .children({
                            Text(nav.label())
                                .layout(.left_center)
                                .animationEnter("opaque-fade-in")
                                .animationExit("opaque-fade-out")
                                .font(14, 100, if (active) .white else Theme.text_secondary)
                                .end();
                        });
                    }
                });
            }
        });
    });
}

/// Render the 4 decorative corner borders on the active nav item
fn renderNavCorners() void {
    const border_tl: Vapor.Types.Border = if (!is_hovered) .sharp(.{ .bottom = 1, .right = 1 }, .palette(.tint)) else .sharp(.{ .top = 1, .left = 1 }, .hex("#222160"));
    const border_tl_pos: Vapor.Types.Position = if (!is_hovered) .tl(.px(-6), .px(-6), .absolute) else .tl(.px(-1), .px(-1), .absolute);
    Row().id("nav-button-top-left").pos(border_tl_pos).width(.px(6)).height(.px(6)).border(border_tl).children({});

    const border_tr: Vapor.Types.Border = if (!is_hovered) .sharp(.{ .bottom = 1, .left = 1 }, .palette(.tint)) else .sharp(.{ .top = 1, .right = 1 }, .hex("#222160"));
    const border_tr_pos: Vapor.Types.Position = if (!is_hovered) .tr(.px(-6), .px(-6), .absolute) else .tr(.px(-1), .px(-1), .absolute);
    Row().id("nav-button-top-right").pos(border_tr_pos).width(.px(6)).height(.px(6)).border(border_tr).children({});

    const border_bl: Vapor.Types.Border = if (!is_hovered) .sharp(.{ .top = 1, .right = 1 }, .palette(.tint)) else .sharp(.{ .bottom = 1, .left = 1 }, .hex("#222160"));
    const border_bl_pos: Vapor.Types.Position = if (!is_hovered) .bl(.px(-6), .px(-6), .absolute) else .bl(.px(-1), .px(-1), .absolute);
    Row().id("nav-button-bottom-left").pos(border_bl_pos).width(.px(6)).height(.px(6)).border(border_bl).children({});

    const border_br: Vapor.Types.Border = if (!is_hovered) .sharp(.{ .top = 1, .left = 1 }, .palette(.tint)) else .sharp(.{ .bottom = 1, .right = 1 }, .hex("#222160"));
    const border_br_pos: Vapor.Types.Position = if (!is_hovered) .br(.px(-6), .px(-6), .absolute) else .br(.px(-1), .px(-1), .absolute);
    Row().id("nav-button-bottom-right").pos(border_br_pos).width(.px(6)).height(.px(6)).border(border_br).children({});
}

// =============================================================================
// RENDER — TAB BAR
// =============================================================================

fn renderTabBar() void {
    Row()
        .width(.percent(100)).height(.px(44))
        .padding(.horizontal(24))
        .layout(.left_center)
        .background(.palette(.background))
        .border(.bottom(1, Theme.border))
        .children({
        for (std.enums.values(Tab)) |tab| {
            const active = active_tab == tab;
            Button(selectTab, .{tab})
                .ariaLabel(tab.label())
                .height(.px(44)).padding(.horizontal(16))
                .layout(.center).spacing(7)
                .background(.transparent)
                .border(.bottom(if (active) 1 else 1, if (active) Theme.accent else .transparent))
                .pointer().duration(100)
                .children({
                Icon(tab.icon())
                    .font(11, 400, if (active) Theme.accent else Theme.text_subtle)
                    .end();
                Text(tab.label())
                    .font(12, if (active) 600 else 400, if (active) Theme.accent else Theme.text_muted)
                    .fontFamily("'DM Sans', sans-serif")
                    .end();
            });
        }
    });
}

// =============================================================================
// RENDER — FILE ATTACHMENT ROW (shared between prompt views)
// =============================================================================

fn renderFileAttachments() void {
    if (file_list.items.len > 0) {
        Row().width(.expand)
            .spacing(16)
            .children({
            for (file_list.items, 0..) |file, i| {
                const image = std.ascii.startsWithIgnoreCase(file.type, "image");
                Stack()
                    .height(.clamp(0, 64, 64, .px))
                    .pos(.relative)
                    .onHover(showDelete, .{i})
                    .onLeave(hideDelete, .{})
                    .children({
                    if (show_delete != null and show_delete.? == i) {
                        Button(removeFile, .{ file, i })
                            .ariaLabel("Remove File")
                            .pos(.tl(.px(-12), .px(-12), .absolute))
                            .background(.palette(.background))
                            .pointer()
                            .size(.squarePx(24))
                            .border(.thin(.palette(.border_color_light)))
                            .radius(.all(99))
                            .layout(.center)
                            .hover(.{ .transform = .scaleDecimal(1.05) })
                            .children({
                            Icon(.trash3)
                                .font(12, 100, .palette(.text_muted)).end();
                        });
                    } else {
                        Vapor.Null();
                    }
                    if (image) {
                        Vapor.Image(.{ .src = file.url })
                            .border(.thin(.palette(.border_color_light)))
                            .radius(.all(4))
                            .duration(100)
                            .hover(.{
                                .shadow = .glow(1, .transparentize(.palette(.text), 0.5)),
                            })
                            .size(.full)
                            .end();
                    } else {
                        Stack()
                            .height(.clamp(0, 64, 64, .px))
                            .border(.thin(.palette(.border_color_light)))
                            .padding(.xy(4, 4))
                            .radius(.all(4))
                            .children({
                            Text(file.name).font(12, 400, .palette(.text_muted)).end();
                        });
                    }
                });
            }
        });
    } else {
        Vapor.Null();
    }
}

// =============================================================================
// RENDER — PROMPT INPUT CONTROLS (shared bottom bar)
// =============================================================================

fn renderPromptControls() void {
    Row().width(.percent(100))
        .height(.fit)
        .layout(.bottom_center).children({
        Row().width(.percent(100)).layout(.x_between_center)
            .pos(.relative)
            .children({
            Row()
                .layout(.left_center)
                .spacing(8).items(.{
                Row()
                    .hover(.{
                        .transform = .{ .deg = 10, .size_type = .deg, .scale_size = 1.05, .type = &.{ .scale, .rotate } },
                        .text_color = .palette(.text),
                    })
                    .duration(120)
                    .textColor(.palette(.text_muted))
                    .width(.px(32)).height(.px(32)).layout(.center).items(.{
                    Vapor.TextField(.file)
                        .a11y(.{ .label = "File Upload" })
                        .pos(.absolute)
                        .pointer()
                        .layout(.center)
                        .width(.px(32))
                        .onEvent(.change, upload, .{})
                        .end(),
                    Icon(.plus_lg)
                        .fontSize(20),
                }),

                Text(if (prompt_input.len > 0)
                    Vapor.frame.fmt("{d} chars · ⌘↵", .{prompt_input.len})
                else
                    "⌘↵ to generate")
                    .font(12, 400, Theme.text_subtle)
                    .fontFamily("'DM Mono', monospace"),
            });

            Row()
                .width(.expand)
                .layout(.right_center)
                .spacing(16).items(.{
                Row().width(.percent(if (show_code or show_markdown) 50 else 40)).child(llm_select.render()),

                Button(submitPrompt, .{})
                    .ariaLabel("Submit Prompt")
                    .width(.px(30)).height(.px(30))
                    .pointer().duration(120)
                    .hover(.{ .transform = .scaleDecimal(1.05) })
                    .background(if (prompt_input.len > 0) .palette(.tint) else .black)
                    .border(.round(if (prompt_input.len > 0) .palette(.tint) else .transparent, .all(0)))
                    .layout(.center)
                    .children({
                    if (is_generating) {
                        Icon(.arrow_clockwise)
                            .font(14, 400, .white)
                            .animation("gen-spin").end();
                    } else {
                        Icon(.send).font(14, 400, .white).end();
                    }
                }),

                Button(submitPrompt, .{})
                    .ariaLabel("Submit Prompt")
                    .width(.px(32)).height(.px(32))
                    .pointer().duration(120)
                    .hover(.{ .transform = .scaleDecimal(1.05) })
                    .opacity(if (prompt_input.len > 0) 0.1 else 1)
                    .layout(.center)
                    .children({
                    Vapor.Graphic(.{ .src = "/assets/speak.svg" })
                        .fill(.palette(.text))
                        .hover(.{ .fill = .palette(.tint) })
                        .layout(.center)
                        .size(.squarePx(24))
                        .end();
                }),
            });
        });
    });
}

// =============================================================================
// RENDER — WORD DISPLAY (shared between full and split views)
// =============================================================================

fn renderWordDisplay(font_size: u8, cell_width: f32) void {
    Row().spacing(2).whiteSpace(.pre_wrap).children({
        const offset = (MAX_LEN - display_len) / 2;
        for (0..MAX_LEN) |i| {
            const active = i >= offset and i < offset + display_len;
            const last_in_word = active and (i == offset + display_len - 1);

            Stack()
                .width(if (active) .px(cell_width) else .px(0))
                .opacity(if (active) 1.0 else 0.0)
                .transition(.{ .duration = 300, .timing = .ease, .properties = &.{ .opacity, .width } })
                .layout(.center)
                .pos(.relative)
                .children({
                Text(&[1]u8{display[i]})
                    .font(font_size, 100, Theme.text)
                    .transform(if (last_in_word) Vapor.Types.Transform.rotateXYZ(0, 180, 0) else .{})
                    .fontStyle(if (last_in_word) .italic else .normal)
                    .animation(
                        if (is_spinning[i])
                            "flipDown"
                        else if (spin_ticks[i] > 0)
                            "letterLand"
                        else
                            null,
                    )
                    .end();
            });
        }
    });
}

// =============================================================================
// RENDER — PROMPT CARD (shared textarea + controls)
// =============================================================================

fn renderPromptCard(model_width: Vapor.Types.Sizing) void {
    _ = model_width;
    Stack()
        .inlineStyle("view-transition-name: myWidget", .{})
        .width(.percent(55))
        .spacing(24)
        .layout(.center)
        .mt(12)
        .padding(.all(16))
        .border(.round(.palette(.border_color_light), .all(0)))
        .shadow(Vapor.Types.NewShadow.init().dropSpread(0, 1, 8, 4, .transparentize(.black, 0.03)))
        .spacing(8)
        .children({
        renderFileAttachments();

        Vapor.TextArea()
            .height(.elastic(72, 256))
            .resize(.none)
            .outline(.none, null)
            .bind(&prompt_input)
            .border(.none)
            .placeholder("Describe the Vapor component you want to build…")
            .width(.expand)
            .onEvent(.keydown, onPromptKeyDown, .{})
            .fontSize(14)
            .fontFamily("'DM Mono', monospace")
            .inlineStyle("field-sizing: content;", .{})
            .end();

        renderPromptControls();
    });
}

// =============================================================================
// RENDER — PROMPT BAR (full-width, initial state)
// =============================================================================

fn renderPromptBar() void {
    Stack()
        .minWidth(.percent(30))
        .width(.expand)
        .padding(.xy(32, 20))
        .spacing(12)
        .layout(.top_center)
        .mt(256)
        .border(.bottom(1, Theme.border))
        .children({
        renderWordDisplay(42, 26);
        // Row()
        //     .spacing(12)
        //     .width(.percent(55))
        //     .layout(.right_center)
        //     .children({
        //     Label("Vertex Mode").font(18, 100, .palette(.text)).end();
        //     Opaque.Switch.render("vertex_switch", toggleVertexMode, .{});
        // });
        renderPromptCard(.percent(30));

        Row().spacing(12).children({
            for (data.OPTION_PILLS, 0..) |option, i| {
                renderOptionPill(option, i);
            }
        });
        Stack()
            .width(.percent(55))
            .children({
            renderRunHistory();
        });
    });
}

// =============================================================================
// RENDER — GENERATE TAB
// =============================================================================

fn renderGenerateTab() void {
    Row().width(.percent(100)).height(.grow).children({
        if (!show_code and !show_markdown) {
            renderPromptBar();
        } else {
            // ── LEFT: prompt column ───────────────────────────────────
            Stack()
                .width(.percent(40)).height(.percent(100))
                .background(.palette(.background))
                .border(.right(1, Theme.border))
                .padding(.all(24)).spacing(20)
                .children({
                renderWordDisplay(30, 18);

                // Textarea card (split view uses full width)
                Stack()
                    .inlineStyle("view-transition-name: myWidget", .{})
                    .width(.percent(100))
                    .spacing(24)
                    .layout(.center)
                    .mt(12)
                    .padding(.all(16))
                    .border(.round(.palette(.border_color_light), .all(0)))
                    .shadow(Vapor.Types.NewShadow.init().dropSpread(0, 1, 8, 4, .transparentize(.black, 0.03)))
                    .spacing(8)
                    .children({
                    renderFileAttachments();

                    Vapor.TextArea()
                        .height(.elastic(72, 256))
                        .resize(.none)
                        .outline(.none, null)
                        .bind(&prompt_input)
                        .border(.none)
                        .placeholder("Describe the Vapor component you want to build…")
                        .width(.expand)
                        .onEvent(.keydown, onPromptKeyDown, .{})
                        .fontSize(14)
                        .fontFamily("'DM Mono', monospace")
                        .inlineStyle("field-sizing: content;", .{})
                        .end();

                    renderPromptControls();
                });

                // Quick-action pills
                Stack().spacing(6).children({
                    Row().spacing(8).wrap(.wrap).children({
                        for (data.OPTION_PILLS, 0..) |pill, i| {
                            renderOptionPill(pill, i);
                        }
                    });
                    renderRunHistory();
                });
            });
        }

        // ── RIGHT: code/markdown panel ────────────────────────────────
        if (show_code or show_markdown) {
            renderCodePanel(&sheet);
        }
    });
}

fn renderOptionPill(pill: data.Pill, i: usize) void {
    const background: Vapor.Types.Color = if (active_pill) |ap| if (std.mem.eql(u8, ap.label, pill.label)) .yellow else .transparent else .transparent;
    const border_color: Vapor.Types.Color = if (active_pill) |ap| if (std.mem.eql(u8, ap.label, pill.label)) .yellow else .transparent else .transparent;
    Opaque.Button(selectPill, .{ pill, i })
        .ariaLabel(Vapor.frame.fmt("{s}-btn", .{pill.label}))
        .hover(.{ .background = .yellow, .animation = "glitch" })
        .radius(.all(0))
        // .border(.round(.yellow, .all(0)))
        .colorMix(.darken(.border_color, border_color, 0.05))
        .radius(.all(0))
        .background(background)
        .padding(.xy(14, 7)).spacing(8).pointer()
        .height(.px(36))
        .children({
        if (std.mem.eql(u8, pill.label, "learn")) {
            Vapor.Svg(.{ .svg = @embedFile("toolbox.svg") })
                .size(.squarePx(16))
                .fill(.palette(.text))
                .end();
        } else if (std.mem.eql(u8, pill.label, "assembler")) {
            Vapor.Svg(.{ .svg = @embedFile("assemble.svg") })
                .size(.squarePx(20))
                .stroke(.palette(.text))
                .fill(.transparent)
                .end();
        } else {
            Icon(pill.icon)
                .font(14, 100, .palette(.text))
                .fontFamily("IBM Plex Mono, monospace")
                .end();
        }
        Text(pill.label)
            .font(12, 100, Theme.text)
            .fontFamily("IBM Plex Mono, monospace")
            .end();
        Text("_ ⇒")
            .font(12, 100, Theme.text_muted)
            .fontFamily("IBM Plex Mono, monospace")
            .end();
    });
}

fn renderRunHistory() void {
    Stack()
        .width(.percent(100))
        .spacing(8)
        .mt(8)
        .children({
        Text("Run History")
            .font(12, 600, Theme.text_muted)
            .fontFamily("'DM Mono', monospace")
            .end();

        if (history.items.len == 0) {
            Text("No runs yet")
                .font(11, 400, Theme.text_subtle)
                .fontFamily("'DM Mono', monospace")
                .end();
        } else {
            Stack()
                .width(.percent(100))
                .scroll(.scrollY())
                .height(.percent(100))
                .spacing(8)
                .children({
                const start: usize = if (history.items.len > 8) history.items.len - 8 else 0;
                for (history.items[start..], start..) |item, i| {
                    Stack()
                        .width(.percent(100))
                        .background(.palette(.background))
                        .padding(.all(8))
                        .border(.round(Theme.border, .all(0)))
                        .spacing(6)
                        .children({
                        Row()
                            .layout(.x_between_center)
                            .children({
                            const dt = Vapor.DateTime.fromTimestamp(std.fmt.parseInt(i64, item.timestamp, 10) catch 0) catch unreachable;
                            Text(Vapor.frame.fmt("#{d} · {s} · {s}", .{ i + 1, item.provider, dt.format(Vapor.frame.arena()) catch "" }))
                                .font(10, 500, Theme.text_subtle)
                                .fontFamily("'DM Mono', monospace")
                                .end();
                            Row()
                                .spacing(6)
                                .children({
                                Button(restoreHistoryItem, .{i})
                                    .ariaLabel("Restore History Item")
                                    .padding(.xy(8, 4))
                                    .border(.round(Theme.border, .all(0)))
                                    .hover(.{ .background = .yellow, .text_color = .black })
                                    .pointer()
                                    .children({
                                    Text("Restore").fontSize(10).fontFamily("'DM Mono', monospace").end();
                                });
                                Button(diffHistoryItem, .{i})
                                    .ariaLabel("Diff History Item")
                                    .padding(.xy(8, 4))
                                    .border(.round(Theme.border, .all(0)))
                                    .hover(.{ .background = .yellow, .text_color = .black })
                                    .pointer()
                                    .children({
                                    Text("Diff").fontSize(10).fontFamily("'DM Mono', monospace").end();
                                });
                            });
                        });
                        Text(item.prompt)
                            .font(11, 400, Theme.text_muted)
                            .fontFamily("'DM Mono', monospace")
                            .whiteSpace(.pre_wrap)
                            .end();
                    });
                }
            });
        }
    });
}

// =============================================================================
// RENDER — CODE PANEL
// =============================================================================

fn renderCodePanel(_: *Sheet) void {
    Stack()
        .width(.expand)
        .height(.percent(100))
        .background(if (show_markdown) .transparent else Theme.code_bg)
        .animationEnter("from-right")
        .children({

        // Toolbar
        Row()
            .width(.percent(100))
            .height(.px(44))
            .padding(.horizontal(20)).layout(.x_between_center)
            .background(if (show_markdown) .transparent else Theme.code_surface)
            .border(.bottom(1, if (show_markdown) Theme.border else Theme.code_border))
            .children({
            Row().layout(.left_center).spacing(0).children({
                Row()
                    .padding(.horizontal(16)).height(.px(44))
                    .layout(.center).spacing(8)
                    .border(.bottom(1, if (show_markdown) Theme.accent else .hex("#8B8A86")))
                    .children({
                    Icon(.filetype_md).font(11, 400, if (show_markdown) Theme.text_muted else .hex("#8B8A86")).end();
                    Text(if (showing_history_diff)
                        "history.diff"
                    else if (has_generated)
                        if (show_markdown) "response.md" else "vapor_component.zig"
                    else
                        "unknown")
                        .font(11, 400, if (show_markdown) Theme.text else .hex("#C8C5BF"))
                        .fontFamily("'DM Mono', monospace").end();
                    if (is_generating) {
                        Row()
                            .width(.px(5)).height(.px(5))
                            .background(.hex("#F5A623"))
                            .border(.round(.hex("#F5A623"), .all(3)))
                            .animation("gen-pulse").children({});
                    }
                });
            });

            Row().layout(.right_center).spacing(6).children({
                if (show_code) {
                    if (showing_history_diff) {
                        codeAction(.x_lg, "Close Diff", .hex("#8B8A86"), clearHistoryDiff);
                    }
                    codeAction(
                        if (copy_success) .check2 else .clipboard,
                        if (copy_success) "Copied!" else "Copy",
                        if (copy_success) Theme.success else .hex("#8B8A86"),
                        copyToClipboard,
                    );
                    codeAction(.download, "Save .zig", .hex("#8B8A86"), saveToFile);
                }
                // Changed: "Open in Planner" instead of "Open in Playground"
                if (show_markdown) {
                    codeAction(.codepen, "Open in Planner", if (show_markdown) Theme.text_muted else .hex("#8B8A86"), openPlanner);
                } else {
                    codeAction(.codepen, "Open in Playground", if (show_code) Theme.text_muted else .hex("#8B8A86"), openPlayground);
                }
            });
        });

        // Body
        Stack()
            .width(.percent(100)).height(.grow)
            .scroll(.scrollY()).padding(.all(20))
            .children({
            if (is_generating) {
                renderGeneratingState();
            } else {
                if (show_code) {
                    code_highlighter.render() catch unreachable;
                } else if (show_markdown) {
                    markdown.render() catch unreachable;
                }
            }
        });
    });
}

fn codeAction(
    ico: Vapor.IconTokens,
    label_text: []const u8,
    ico_color: Vapor.Types.Color,
    action: anytype,
) void {
    Button(action, .{})
        .ariaLabel(label_text)
        .layout(.center).spacing(5).padding(.xy(10, 5))
        .background(.transparent)
        .border(.round(if (show_markdown) Theme.border else Theme.code_border, .all(0)))
        .pointer().duration(100)
        .textColor(ico_color)
        .fill(ico_color)
        .hover(.{ .background = .yellow, .text_color = .black, .fill = .black })
        .children({
        if (std.mem.eql(u8, ico.web orelse "", Vapor.IconTokens.codepen.web.?)) {
            Vapor.Svg(.{ .svg = ico.svg.? })
                .size(.squarePx(16))
                .end();
        } else {
            Icon(ico).font(11, 400, null).end();
        }
        Text(label_text)
            .font(10, 500, null)
            .fontFamily("'DM Mono', monospace").end();
    });
}

fn renderGeneratingState() void {
    Stack().width(.percent(100)).spacing(10).padding(.all(6)).children({
        skeletonLine(72);
        skeletonLine(52);
        skeletonLine(88);
        skeletonLine(38);
        skeletonLine(65);
        skeletonLine(50);
        Vapor.Spacer(6).end();
        skeletonLine(58);
        skeletonLine(78);
        skeletonLine(33);
        Vapor.Spacer(6).end();
        skeletonLine(62);
        skeletonLine(48);
        skeletonLine(75);
    });
}

fn skeletonLine(w: f32) void {
    Row()
        .height(.px(13)).width(.percent(w))
        .background(.hex("#242320"))
        .border(.round(.hex("#242320"), .all(3)))
        .animation("gen-pulse").children({});
}

// =============================================================================
// MAIN RENDER
// =============================================================================

fn render() void {
    Row()
        .width(.expand).height(.percent(100))
        .background(.palette(.background))
        .children({
        Stack().width(.expand).height(.percent(100)).children({
            Row()
                .width(.percent(100))
                .padding(.horizontal(12))
                .height(.px(44))
                .layout(.right_center)
                .spacing(4)
                .children({
                Button(toggleWithTransitionMarkdown, .{})
                    .ariaLabel("Toggle Markdown")
                    .width(.px(40))
                    .height(.px(40))
                    .layout(.center)
                    .background(if (show_markdown) .palette(.tint) else .palette(.background))
                    .textColor(if (show_markdown) .white else .palette(.text))
                    .duration(100)
                    .hover(.{ .background = .palette(.tint), .text_color = .white })
                    .pointer()
                    .children({
                    Icon(.filetype_md)
                        .fontSize(18)
                        .end();
                });
                Button(toggleWithTransition, .{})
                    .ariaLabel("Toggle Code")
                    .width(.px(40))
                    .height(.px(40))
                    .layout(.center)
                    .background(if (show_code) .palette(.tint) else .palette(.background))
                    .textColor(if (show_code) .white else .palette(.text))
                    .duration(100)
                    .hover(.{ .background = .palette(.tint), .text_color = .white })
                    .pointer()
                    .children({
                    Icon(.code_slash)
                        .fontSize(18)
                        .end();
                });
            });

            renderGenerateTab();
        });
    });
}
