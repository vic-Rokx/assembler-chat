// ============================================================================
// PLAYGROUND AUTOCOMPLETE INTEGRATION
// ============================================================================
//
// This file shows the changes needed to integrate ZigAutoComplete into
// the existing playground editor (playground.zig / document 1).
//
// Below is the full updated playground.zig with autocomplete wired in.
// Changes are marked with "// NEW" comments.
// ============================================================================

const std = @import("std");
const Vapor = @import("vapor");
const Vaporize = @import("vaporize");
const Opaque = @import("opaque_ui");
const Assembler = @import("Assembler.zig");

const Text = Vapor.Text;
const TextFmt = Vapor.TextFmt;
const Row = Vapor.Row;
const Stack = Vapor.Stack;
const Center = Vapor.Center;
const Icon = Vapor.Icon;
const Button = Vapor.Button;
const Animation = Vapor.Animation;
const SyntaxHighlighter = Vaporize.SyntaxHighlighter;
const SideBar = Opaque.SideBar;
const Sheet = Opaque.Sheet;
const StringSelect = Opaque.StringSelect;
const TextArea = Vapor.TextArea;

const ZigAutoComplete = @import("zig_autocomplete.zig").ZigAutoComplete; // NEW

var content_buffer: *Vapor.ArrayArena(u8) = undefined;
var content: []const u8 = @embedFile("main_sample.zig");

var code_editor: SyntaxHighlighter = undefined;
var autocomplete: ZigAutoComplete = undefined; // NEW
const File = struct {
    name: []const u8,
    content: []const u8,
    file_name: []const u8,
    buffer: Vapor.ArrayArena(u8),
    editing: bool = false,
};
var selected_file: usize = 0;
var files = Vapor.persist.array(File);

// ============================================================================
// Auto-close pairs (unchanged)
// ============================================================================

const AutoClosePair = struct { open: u8, close: u8 };

const auto_close_pairs = [_]AutoClosePair{
    .{ .open = '{', .close = '}' },
    .{ .open = '(', .close = ')' },
    .{ .open = '[', .close = ']' },
    .{ .open = '"', .close = '"' },
};

fn getClosingChar(c: u8) ?u8 {
    for (auto_close_pairs) |pair| {
        if (pair.open == c) return pair.close;
    }
    return null;
}

fn isClosingChar(c: u8) bool {
    for (auto_close_pairs) |pair| {
        if (pair.close == c) return true;
    }
    return false;
}

// ============================================================================
// State
// ============================================================================

var text_area: Vapor.Element = .{};
var highlighter_layer: Vapor.Element = .{};
var editor_container: Vapor.Element = .{};

var holding_meta: bool = false;
var holding_ctrl: bool = false;
var holding_shift: bool = false;

var indent_buffer: [8192]u8 = undefined;
var new_cursor_pos: usize = 0;

const line_height: f32 = 22.5;
const char_width: f32 = 8.7; // NEW — monospace char width for position calc

const PlaygroundRunEntry = struct {
    timestamp: []const u8,
    state: []const u8,
    source: []const u8,
    error_text: []const u8,
};
var playground_run_history = Vapor.persist.array(PlaygroundRunEntry);
const playground_history_key = "playground_run_history_v1";
var playground_diff_text: []const u8 = "";

fn fixWithModel() void {
    const err_text = if (err_response) |err| err.body else "Unknown compile error";
    const prompt = Vapor.persist.fmt(
        \\The following Vapor/Zig code failed to compile in the WASM playground.
        \\Return only a corrected complete Zig source file (no markdown, no prose).
        \\
        \\Compiler error:
        \\{s}
        \\
        \\Current code:
        \\{s}
    , .{ err_text, content });

    Vapor.store("assembler-fix-prompt", prompt);
    Vapor.store("active_mode", "model");
    Vapor.navigate("/");
}

// ============================================================================
// Init
// ============================================================================

pub fn init() void {
    files.append(.{
        .name = "main.zig",
        .content = @embedFile("main_sample.zig"),
        .file_name = "main_sample.zig",
        .buffer = Vapor.persist.array(u8),
    });
    files.append(.{
        .name = "Editor.zig",
        .content = @embedFile("editor_sample.zig"),
        .file_name = "editor_sample.zig",
        .buffer = Vapor.persist.array(u8),
    });

    loadFiles();
    loadPlaygroundRunHistory();
    // files.items[selected_file].buffer.appendSlice(content);
    // files.items[selected_file + 1].buffer.appendSlice(files.items[selected_file + 1].content);

    code_editor = SyntaxHighlighter.init(Vapor.persist.arena());
    // code_editor.scrolling_enabled = true;

    code_editor.parse(content) catch unreachable;

    content_buffer = &files.items[selected_file].buffer;
    // content_buffer.appendSlice(content);
    content = content_buffer.items;

    autocomplete = ZigAutoComplete.init(Vapor.persist.arena()); // NEW
    size = Vapor.lib.browser_width * 0.4;

    Vapor.Page(.{ .route = "/playground" }, render, null);
}

fn loadFiles() void {
    for (files.items, 0..) |file, i| {
        const loaded_content = Vapor.load([]const u8, file.file_name) orelse file.content;
        files.items[i].buffer.clearRetainingCapacity();
        files.items[i].buffer.appendSlice(loaded_content);
    }
    content = files.items[selected_file].buffer.items;
}

// ============================================================================
// Buffer management (unchanged)
// ============================================================================

fn setText(new_text: []const u8) void {
    content_buffer.clearRetainingCapacity();
    content_buffer.appendSlice(new_text);
    content = content_buffer.items;
}

fn reparse() void {
    code_editor.recompile(content) catch |err| {
        std.log.err("playground: failed to recompile {any}", .{err});
        return;
    };
    files.items[selected_file].content = content;
}

fn makeTimestamp() []const u8 {
    return Vapor.persist.fmt("{d}", .{Vapor.Kit.timestamp()});
}

fn savePlaygroundRunHistory() void {
    const json = std.json.Stringify.valueAlloc(Vapor.frame.arena(), playground_run_history.items, .{}) catch return;
    Vapor.store(playground_history_key, json);
}

fn loadPlaygroundRunHistory() void {
    const raw = Vapor.load([]const u8, playground_history_key) orelse return;
    const parsed = std.json.parseFromSlice(
        []PlaygroundRunEntry,
        Vapor.frame.arena(),
        raw,
        .{ .ignore_unknown_fields = true },
    ) catch return;

    playground_run_history.clearRetainingCapacity();
    for (parsed.value) |entry| {
        playground_run_history.append(.{
            .timestamp = Vapor.persist.dupe(entry.timestamp),
            .state = Vapor.persist.dupe(entry.state),
            .source = Vapor.persist.dupe(entry.source),
            .error_text = Vapor.persist.dupe(entry.error_text),
        });
    }
}

fn addPlaygroundRunHistory(state: []const u8, error_text: []const u8) void {
    playground_run_history.append(.{
        .timestamp = makeTimestamp(),
        .state = Vapor.persist.dupe(state),
        .source = Vapor.persist.dupe(content),
        .error_text = Vapor.persist.dupe(error_text),
    });
    if (playground_run_history.items.len > 30) {
        _ = playground_run_history.orderedRemove(0);
    }
    savePlaygroundRunHistory();
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

fn restorePlaygroundHistory(i: usize) void {
    if (i >= playground_run_history.items.len) return;
    setText(playground_run_history.items[i].source);
    reparse();
    new_cursor_pos = @min(new_cursor_pos, content.len);
    Vapor.onLayout(updateCursorPosition, .{});
}

fn diffPlaygroundHistory(i: usize) void {
    if (i >= playground_run_history.items.len) return;
    playground_diff_text = makeLineDiff(content, playground_run_history.items[i].source);
}

fn clearPlaygroundDiff() void {
    playground_diff_text = "";
}

// ============================================================================
// Helpers (unchanged)
// ============================================================================

const LineBounds = struct { start: usize, end: usize };

fn getLineBounds(cursor_pos: usize) LineBounds {
    const start = if (std.mem.lastIndexOf(u8, content[0..cursor_pos], "\n")) |p| p + 1 else 0;
    const end = std.mem.indexOfPos(u8, content, cursor_pos, "\n") orelse content.len;
    return .{ .start = start, .end = end };
}

fn gotoLine(line_number: usize) ?usize {
    if (line_number == 0) return null;

    var current_line: usize = 1;
    var i: usize = 0;

    if (line_number == 1) return 0;

    while (i < content.len) : (i += 1) {
        if (content[i] == '\n') {
            current_line += 1;
            if (current_line == line_number) return i + 1;
        }
    }

    return null;
}

fn getFirstContentColumn(line_number: usize) ?usize {
    const line_start = gotoLine(line_number) orelse return null;
    const bounds = getLineBounds(line_start);
    const line = content[bounds.start..bounds.end];

    var col: usize = 0;
    for (line) |c| {
        if (c != ' ' and c != '\t') break;
        col += 1;
    }

    return col + 1; // 1-based
}

fn updateCursorPosition() void {
    text_area.setCursorPosition(new_cursor_pos);
}

// ============================================================================
// Autocomplete helpers (NEW)
// ============================================================================

fn updateAutocompletePosition(cursor_pos: usize) void {
    const text_before = content[0..@min(cursor_pos, content.len)];

    var line_count: usize = 1;
    var last_newline: usize = 0;
    for (text_before, 0..) |c, i| {
        if (c == '\n') {
            line_count += 1;
            last_newline = i + 1;
        }
    }

    const column = cursor_pos - last_newline;
    const cx: f32 = @as(f32, @floatFromInt(column)) * char_width + 48;
    const cy: f32 = @as(f32, @floatFromInt(line_count - 1)) * line_height + 12 - text_area.scrollTop();

    autocomplete.update(content, cursor_pos, cx, cy);
}

fn triggerAutocomplete() void {
    const cursor_pos = text_area.cursorPosition();
    updateAutocompletePosition(cursor_pos);
    autocomplete.show(content, cursor_pos, autocomplete.cursor_x, autocomplete.cursor_y);
}

fn triggerAutocompleteLazy() void {
    const cursor_pos = text_area.cursorPosition();
    updateAutocompletePosition(cursor_pos);
    if (autocomplete.partial_word.len < 1) {
        autocomplete.hide();
    }
}

fn acceptAutocompleteSuggestion() void {
    const insert_text = autocomplete.getInsertText() orelse return;
    const partial_start = autocomplete.getPartialStart();
    const cursor_pos = text_area.cursorPosition();

    const before = content[0..partial_start];
    const after = content[cursor_pos..];

    const total = std.fmt.allocPrint(Vapor.arena(.frame), "{s}{s}{s}", .{ before, insert_text, after }) catch unreachable;
    setText(total);
    new_cursor_pos = partial_start + insert_text.len;

    autocomplete.hide();
    reparse();
    Vapor.onLayout(updateCursorPosition, .{});
}

// ============================================================================
// Event handlers (UPDATED with autocomplete integration)
// ============================================================================

fn onChange(evt: *Vapor.Event) void {
    const new_text = evt.text();
    content_buffer.clearRetainingCapacity();
    content_buffer.appendSlice(new_text);
    content = content_buffer.items;
    autocomplete.markDirty(); // ADD THIS
    reparse();
}

fn onScroll(code: *SyntaxHighlighter, _: *Vapor.Event) void {
    if (Vapor.Kit.throttle(8)) return;
    const scroll_top = text_area.scrollTop();
    code.scrollToTop(scroll_top);
    autocomplete.hide(); // NEW — hide on scroll
}

fn onBlur(_: *Vapor.Event) void {
    holding_meta = false;
    holding_ctrl = false;
    holding_shift = false;
    autocomplete.hide(); // NEW
    Vapor.store(files.items[selected_file].file_name, content);
}

fn onKeyUp(evt: *Vapor.Event) void {
    const key = evt.key();
    if (std.mem.eql(u8, key, "Meta")) holding_meta = false;
    if (std.mem.eql(u8, key, "Control")) holding_ctrl = false;
    if (std.mem.eql(u8, key, "Shift")) holding_shift = false;
}

fn onKeyDown(evt: *Vapor.Event) void {
    const key = evt.key();

    // ---- Track modifier keys ----
    if (std.mem.eql(u8, key, "Meta")) {
        holding_meta = true;
        return;
    } else if (std.mem.eql(u8, key, "Control")) {
        holding_ctrl = true;
        return;
    } else if (std.mem.eql(u8, key, "Shift")) {
        holding_shift = true;
        return;
    }

    // ---- NEW: Autocomplete navigation when dropdown is visible ----
    if (autocomplete.visible) {
        if (std.mem.eql(u8, key, "ArrowUp")) {
            evt.preventDefault();
            autocomplete.moveUp();
            return;
        } else if (std.mem.eql(u8, key, "ArrowDown")) {
            evt.preventDefault();
            autocomplete.moveDown();
            return;
        } else if (std.mem.eql(u8, key, "Tab") or std.mem.eql(u8, key, "Enter")) {
            if (autocomplete.getSelected()) |_| {
                evt.preventDefault();
                acceptAutocompleteSuggestion();
                return;
            }
        } else if (std.mem.eql(u8, key, "Escape")) {
            evt.preventDefault();
            autocomplete.hide();
            return;
        }
    }

    // ---- Keyboard shortcuts (Meta/Cmd + key) ----
    if (holding_meta) {
        if (std.mem.eql(u8, key, "/") or std.mem.eql(u8, key, "?")) {
            evt.preventDefault();
            toggleComment(evt);
            return;
        }
        if (std.mem.eql(u8, key, "d")) {
            evt.preventDefault();
            duplicateLine();
            return;
        }
        if (std.mem.eql(u8, key, "k")) {
            evt.preventDefault();
            deleteLine();
            return;
        }
        if (evt.altKey()) {
            if (std.mem.eql(u8, key, "ArrowUp")) {
                evt.preventDefault();
                moveLineUp();
                return;
            } else if (std.mem.eql(u8, key, "ArrowDown")) {
                evt.preventDefault();
                moveLineDown();
                return;
            }
        }
        return;
    }

    // ---- NEW: Ctrl+Space to manually trigger autocomplete ----
    if (std.mem.eql(u8, key, " ") and holding_ctrl) {
        evt.preventDefault();
        triggerAutocomplete();
        return;
    }

    // ---- Enter ----
    if (std.mem.eql(u8, key, "Enter")) {
        evt.preventDefault();
        autocomplete.hide(); // NEW
        handleEnter();
        return;
    }

    // ---- Tab / Shift+Tab ----
    if (std.mem.eql(u8, key, "Tab")) {
        evt.preventDefault();
        handleTab(evt.shiftKey());
        return;
    }

    // ---- Auto-close pairs ----
    if (key.len == 1 and getClosingChar(key[0]) != null) {
        const open = key[0];
        const close = getClosingChar(open).?;
        if (open == '"' and isCursorInsideString('"')) return;
        evt.preventDefault();
        insertAutoClosePair(open, close);
        autocomplete.hide(); // NEW — hide after bracket insertion
        return;
    }

    // ---- Skip over existing closing char ----
    if (key.len == 1 and isClosingChar(key[0]) and key[0] != '"') {
        if (trySkipClosingChar(key[0])) {
            evt.preventDefault();
            return;
        }
    }

    // ---- Backspace ----
    if (std.mem.eql(u8, key, "Backspace")) {
        if (tryDeletePair()) {
            evt.preventDefault();
            autocomplete.hide(); // NEW
            return;
        }
        autocomplete.hide(); // NEW
    }

    // ---- NEW: Trigger autocomplete lazily on alphanumeric / underscore / @ / . ----
    if (key.len == 1 and (std.ascii.isAlphanumeric(key[0]) or key[0] == '_' or key[0] == '@' or key[0] == '.')) {
        Vapor.onLayout(triggerAutocompleteLazy, .{});
    } else if (std.mem.eql(u8, key, " ") or std.mem.eql(u8, key, "Delete") or std.mem.eql(u8, key, "Escape")) {
        autocomplete.hide(); // NEW — hide on space/delete/escape
    }
}

// ============================================================================
// Smart Enter (unchanged)
// ============================================================================

fn handleEnter() void {
    const cursor_pos = text_area.cursorPosition();
    const ls = if (std.mem.lastIndexOf(u8, content[0..cursor_pos], "\n")) |p| p + 1 else 0;
    const line = content[ls..cursor_pos];

    var indent: usize = 0;
    for (line) |ch| {
        if (ch == ' ' or ch == '\t') indent += 1 else break;
    }

    var extra: usize = 0;
    const trimmed = std.mem.trimEnd(u8, std.mem.trim(u8, line, " \t"), " \t");
    if (trimmed.len > 0) {
        const last = trimmed[trimmed.len - 1];
        if (last == '{' or last == '(' or last == '[' or last == '=' or last == '|') {
            extra = 4;
        }
        if (std.mem.endsWith(u8, trimmed, "=>")) {
            extra = 4;
        }
    }

    const total_indent = @min(indent + extra, indent_buffer.len);
    @memset(indent_buffer[0..total_indent], ' ');

    const char_before = if (cursor_pos > 0) content[cursor_pos - 1] else @as(u8, 0);
    const char_after = if (cursor_pos < content.len) content[cursor_pos] else @as(u8, 0);
    const between = (char_before == '{' and char_after == '}') or
        (char_before == '(' and char_after == ')') or
        (char_before == '[' and char_after == ']');

    if (between) {
        const ins = std.fmt.allocPrint(Vapor.arena(.frame), "\n{s}\n{s}", .{
            indent_buffer[0..total_indent],
            indent_buffer[0..indent],
        }) catch unreachable;
        new_cursor_pos = cursor_pos + 1 + total_indent;
        const total = std.fmt.allocPrint(Vapor.arena(.frame), "{s}{s}{s}", .{ content[0..cursor_pos], ins, content[cursor_pos..] }) catch unreachable;
        setText(total);
    } else {
        const ins = std.fmt.allocPrint(Vapor.arena(.frame), "\n{s}", .{indent_buffer[0..total_indent]}) catch unreachable;
        new_cursor_pos = cursor_pos + ins.len;
        const total = std.fmt.allocPrint(Vapor.arena(.frame), "{s}{s}{s}", .{ content[0..cursor_pos], ins, content[cursor_pos..] }) catch unreachable;
        setText(total);
    }

    reparse();
    Vapor.onLayout(updateCursorPosition, .{});
}

// ============================================================================
// Tab / Indent / Outdent (unchanged)
// ============================================================================

fn handleTab(shift: bool) void {
    const cursor_pos = text_area.cursorPosition();
    const selection = text_area.selection() orelse return;

    if (selection.start != selection.end) {
        if (shift) {
            handleBlockOutdent(selection.start, selection.end);
        } else {
            handleBlockIndent(selection.start, selection.end);
        }
        return;
    }

    if (shift) {
        outdentCurrentLine(cursor_pos);
    } else {
        const indent = "    ";
        const total = std.fmt.allocPrint(Vapor.arena(.frame), "{s}{s}{s}", .{ content[0..cursor_pos], indent, content[cursor_pos..] }) catch unreachable;
        setText(total);
        new_cursor_pos = cursor_pos + indent.len;
        reparse();
        Vapor.onLayout(updateCursorPosition, .{});
    }
}

fn handleBlockIndent(start: usize, end: usize) void {
    const line_start = if (std.mem.lastIndexOf(u8, content[0..start], "\n")) |p| p + 1 else 0;
    const line_end = if (std.mem.indexOfPos(u8, content, end, "\n")) |p| p else content.len;

    var result = std.array_list.Managed(u8).init(Vapor.arena(.frame));
    var iter = std.mem.splitSequence(u8, content[line_start..line_end], "\n");
    var first = true;

    while (iter.next()) |line| {
        if (!first) result.append('\n') catch unreachable;
        first = false;
        if (line.len > 0) {
            result.appendSlice("    ") catch unreachable;
        }
        result.appendSlice(line) catch unreachable;
    }

    const total = std.fmt.allocPrint(Vapor.arena(.frame), "{s}{s}{s}", .{ content[0..line_start], result.items, content[line_end..] }) catch unreachable;
    setText(total);
    new_cursor_pos = start + 4;
    reparse();
    Vapor.onLayout(updateCursorPosition, .{});
}

fn handleBlockOutdent(start: usize, end: usize) void {
    const line_start = if (std.mem.lastIndexOf(u8, content[0..start], "\n")) |p| p + 1 else 0;
    const line_end = if (std.mem.indexOfPos(u8, content, end, "\n")) |p| p else content.len;

    var result = std.array_list.Managed(u8).init(Vapor.arena(.frame));
    var iter = std.mem.splitSequence(u8, content[line_start..line_end], "\n");
    var first = true;

    while (iter.next()) |line| {
        if (!first) result.append('\n') catch unreachable;
        first = false;

        var skip: usize = 0;
        for (line) |c| {
            if (c == ' ' and skip < 4) {
                skip += 1;
            } else break;
        }
        result.appendSlice(line[skip..]) catch unreachable;
    }

    const total = std.fmt.allocPrint(Vapor.arena(.frame), "{s}{s}{s}", .{ content[0..line_start], result.items, content[line_end..] }) catch unreachable;
    setText(total);
    new_cursor_pos = if (start >= 4) start - 4 else start;
    reparse();
    Vapor.onLayout(updateCursorPosition, .{});
}

fn outdentCurrentLine(cursor_pos: usize) void {
    const bounds = getLineBounds(cursor_pos);
    const line = content[bounds.start..bounds.end];

    var skip: usize = 0;
    for (line) |c| {
        if (c == ' ' and skip < 4) {
            skip += 1;
        } else break;
    }

    const total = std.fmt.allocPrint(Vapor.arena(.frame), "{s}{s}{s}", .{ content[0..bounds.start], line[skip..], content[bounds.end..] }) catch unreachable;
    setText(total);
    new_cursor_pos = if (cursor_pos >= skip) cursor_pos - skip else cursor_pos;
    reparse();
    Vapor.onLayout(updateCursorPosition, .{});
}

// ============================================================================
// Auto-close pairs (unchanged)
// ============================================================================

fn isCursorInsideString(quote_char: u8) bool {
    const cursor_pos = text_area.cursorPosition();
    var count: usize = 0;
    var i: usize = 0;
    while (i < cursor_pos and i < content.len) : (i += 1) {
        if (content[i] == '\\' and i + 1 < content.len) {
            i += 1;
            continue;
        }
        if (content[i] == quote_char) count += 1;
    }
    return count % 2 == 1;
}

fn insertAutoClosePair(open: u8, close: u8) void {
    const cursor_pos = text_area.cursorPosition();
    const selection = text_area.selection() orelse return;

    if (selection.start != selection.end) {
        const selected = content[selection.start..selection.end];
        const wrapped = std.fmt.allocPrint(Vapor.arena(.frame), "{c}{s}{c}", .{ open, selected, close }) catch unreachable;
        const total = std.fmt.allocPrint(Vapor.arena(.frame), "{s}{s}{s}", .{ content[0..selection.start], wrapped, content[selection.end..] }) catch unreachable;
        setText(total);
        new_cursor_pos = selection.start + wrapped.len;
    } else {
        if (open == close and cursor_pos < content.len and content[cursor_pos] == close) {
            new_cursor_pos = cursor_pos + 1;
            Vapor.onLayout(updateCursorPosition, .{});
            return;
        }
        const pair = std.fmt.allocPrint(Vapor.arena(.frame), "{c}{c}", .{ open, close }) catch unreachable;
        const total = std.fmt.allocPrint(Vapor.arena(.frame), "{s}{s}{s}", .{ content[0..cursor_pos], pair, content[cursor_pos..] }) catch unreachable;
        setText(total);
        new_cursor_pos = cursor_pos + 1;
    }

    reparse();
    Vapor.onLayout(updateCursorPosition, .{});
}

fn trySkipClosingChar(close: u8) bool {
    const cursor_pos = text_area.cursorPosition();
    if (cursor_pos < content.len and content[cursor_pos] == close) {
        new_cursor_pos = cursor_pos + 1;
        Vapor.onLayout(updateCursorPosition, .{});
        return true;
    }
    return false;
}

fn tryDeletePair() bool {
    const cursor_pos = text_area.cursorPosition();
    if (cursor_pos == 0 or cursor_pos >= content.len) return false;

    const before = content[cursor_pos - 1];
    const after = content[cursor_pos];

    for (auto_close_pairs) |pair| {
        if (before == pair.open and after == pair.close) {
            const total = std.fmt.allocPrint(Vapor.arena(.frame), "{s}{s}", .{ content[0 .. cursor_pos - 1], content[cursor_pos + 1 ..] }) catch unreachable;
            setText(total);
            new_cursor_pos = cursor_pos - 1;
            reparse();
            Vapor.onLayout(updateCursorPosition, .{});
            return true;
        }
    }
    return false;
}

// ============================================================================
// Comment toggling (unchanged)
// ============================================================================

fn toggleComment(_: *Vapor.Event) void {
    const selection = text_area.selection() orelse return;

    if (selection.start != selection.end) {
        toggleBlockComment(selection.start, selection.end);
        return;
    }

    const cursor_pos = text_area.cursorPosition();
    const bounds = getLineBounds(cursor_pos);
    const line = content[bounds.start..bounds.end];

    var content_start: usize = 0;
    for (line) |c| {
        if (c == ' ' or c == '\t') content_start += 1 else break;
    }

    const line_content = line[content_start..];
    var result: []const u8 = undefined;

    if (std.mem.startsWith(u8, line_content, "// ")) {
        result = std.fmt.allocPrint(Vapor.arena(.frame), "{s}{s}", .{ line[0..content_start], line_content[3..] }) catch unreachable;
        new_cursor_pos = if (cursor_pos >= 3) cursor_pos - 3 else cursor_pos;
    } else if (std.mem.startsWith(u8, line_content, "//")) {
        result = std.fmt.allocPrint(Vapor.arena(.frame), "{s}{s}", .{ line[0..content_start], line_content[2..] }) catch unreachable;
        new_cursor_pos = if (cursor_pos >= 2) cursor_pos - 2 else cursor_pos;
    } else {
        result = std.fmt.allocPrint(Vapor.arena(.frame), "{s}// {s}", .{ line[0..content_start], line_content }) catch unreachable;
        new_cursor_pos = cursor_pos + 3;
    }

    const total = std.fmt.allocPrint(Vapor.arena(.frame), "{s}{s}{s}", .{ content[0..bounds.start], result, content[bounds.end..] }) catch unreachable;
    setText(total);
    reparse();
    Vapor.onLayout(updateCursorPosition, .{});
}

fn toggleBlockComment(sel_start: usize, sel_end: usize) void {
    const line_start = if (std.mem.lastIndexOf(u8, content[0..sel_start], "\n")) |p| p + 1 else 0;
    const line_end = if (std.mem.indexOfPos(u8, content, sel_end, "\n")) |p| p else content.len;

    const selected_block = content[line_start..line_end];

    var all_commented = true;
    var check_iter = std.mem.splitSequence(u8, selected_block, "\n");
    while (check_iter.next()) |line| {
        const trimmed = std.mem.trimStart(u8, line, " \t");
        if (trimmed.len > 0 and !std.mem.startsWith(u8, trimmed, "//")) {
            all_commented = false;
            break;
        }
    }

    var result = std.array_list.Managed(u8).init(Vapor.arena(.frame));
    var iter = std.mem.splitSequence(u8, selected_block, "\n");
    var first = true;

    while (iter.next()) |line| {
        if (!first) result.append('\n') catch unreachable;
        first = false;

        if (all_commented) {
            var cs: usize = 0;
            for (line) |c| {
                if (c == ' ' or c == '\t') cs += 1 else break;
            }
            const lc = line[cs..];
            if (std.mem.startsWith(u8, lc, "// ")) {
                result.appendSlice(line[0..cs]) catch unreachable;
                result.appendSlice(lc[3..]) catch unreachable;
            } else if (std.mem.startsWith(u8, lc, "//")) {
                result.appendSlice(line[0..cs]) catch unreachable;
                result.appendSlice(lc[2..]) catch unreachable;
            } else {
                result.appendSlice(line) catch unreachable;
            }
        } else {
            if (line.len == 0) continue;
            var cs: usize = 0;
            for (line) |c| {
                if (c == ' ' or c == '\t') cs += 1 else break;
            }
            result.appendSlice(line[0..cs]) catch unreachable;
            result.appendSlice("// ") catch unreachable;
            result.appendSlice(line[cs..]) catch unreachable;
        }
    }

    const total = std.fmt.allocPrint(Vapor.arena(.frame), "{s}{s}{s}", .{ content[0..line_start], result.items, content[line_end..] }) catch unreachable;
    setText(total);
    new_cursor_pos = line_start + result.items.len;
    reparse();
    Vapor.onLayout(updateCursorPosition, .{});
}

// ============================================================================
// Line operations (unchanged)
// ============================================================================

fn duplicateLine() void {
    const cursor_pos = text_area.cursorPosition();
    const bounds = getLineBounds(cursor_pos);
    const line = content[bounds.start..bounds.end];

    const duplicated = std.fmt.allocPrint(Vapor.arena(.frame), "{s}\n{s}", .{ line, line }) catch unreachable;
    const total = std.fmt.allocPrint(Vapor.arena(.frame), "{s}{s}{s}", .{ content[0..bounds.start], duplicated, content[bounds.end..] }) catch unreachable;
    setText(total);
    new_cursor_pos = bounds.end + 1 + (cursor_pos - bounds.start);
    reparse();
    Vapor.onLayout(updateCursorPosition, .{});
}

fn deleteLine() void {
    const cursor_pos = text_area.cursorPosition();
    const bounds = getLineBounds(cursor_pos);

    const delete_end = if (bounds.end < content.len) bounds.end + 1 else bounds.end;
    const total = std.fmt.allocPrint(Vapor.arena(.frame), "{s}{s}", .{ content[0..bounds.start], content[delete_end..] }) catch unreachable;
    setText(total);
    new_cursor_pos = bounds.start;
    reparse();
    Vapor.onLayout(updateCursorPosition, .{});
}

fn moveLineUp() void {
    const cursor_pos = text_area.cursorPosition();
    const bounds = getLineBounds(cursor_pos);

    if (bounds.start == 0) return;

    const prev_line_end = bounds.start - 1;
    const prev_line_start = if (std.mem.lastIndexOf(u8, content[0..prev_line_end], "\n")) |p| p + 1 else 0;

    const current_line = content[bounds.start..bounds.end];
    const prev_line = content[prev_line_start..prev_line_end];

    const swapped = std.fmt.allocPrint(Vapor.arena(.frame), "{s}\n{s}", .{ current_line, prev_line }) catch unreachable;
    const total = std.fmt.allocPrint(Vapor.arena(.frame), "{s}{s}{s}", .{ content[0..prev_line_start], swapped, content[bounds.end..] }) catch unreachable;
    setText(total);
    new_cursor_pos = prev_line_start + (cursor_pos - bounds.start);
    reparse();
    Vapor.onLayout(updateCursorPosition, .{});
}

fn moveLineDown() void {
    const cursor_pos = text_area.cursorPosition();
    const bounds = getLineBounds(cursor_pos);

    if (bounds.end >= content.len) return;

    const next_line_start = bounds.end + 1;
    const next_line_end = std.mem.indexOfPos(u8, content, next_line_start, "\n") orelse content.len;

    const current_line = content[bounds.start..bounds.end];
    const next_line = content[next_line_start..next_line_end];

    const swapped = std.fmt.allocPrint(Vapor.arena(.frame), "{s}\n{s}", .{ next_line, current_line }) catch unreachable;
    const total = std.fmt.allocPrint(Vapor.arena(.frame), "{s}{s}{s}", .{ content[0..bounds.start], swapped, content[next_line_end..] }) catch unreachable;
    setText(total);
    const raw_pos = next_line_start + next_line.len + 1 + (cursor_pos - bounds.start);
    new_cursor_pos = @min(raw_pos, content.len);
    reparse();
    Vapor.onLayout(updateCursorPosition, .{});
}

// ============================================================================
// Wasm / Fetch (unchanged)
// ============================================================================

const fetch = Vapor.fetch;
const backend = @import("backend.zig");
const diagnostics = @import("diagnostics.zig");
const build_options = @import("build_options");

const BuildState = enum {
    empty,
    loading,
    result,
    err,
};
var build_state: BuildState = .empty;
var err_response: ?Vapor.Fetch.ErrorResponse = null;

fn getWasm() void {
    build_state = .loading;
    err_response = null;
    var fetchstate = fetch(backend.url("/api/wasm/build"), .{
        .method = .POST,
        .body = content,
        .body_type = .string,
        .credentials = "include",
    });
    // fetchstate.force_error = true;
    fetchstate.handle(handleWasmResponse, .{});
}

fn handleWasmResponse(resp: Vapor.Fetch.Result) void {
    code_editor.clearExternalErrors();
    switch (resp) {
        .ok => |ok| {
            // Drop the last build's marks.
            reparse();
            std.log.info("ok {d}", .{ok.body.len});
            build_state = .result;
            err_response = null;
            addPlaygroundRunHistory("result", "");
            if (Vapor.lib.isWasi) {
                // The body is the build's id; its wasm is served under it.
                const wasm_url = backend.url(Vapor.frame.fmt("/api/wasm/build/{s}.wasm", .{ok.body}));
                Vapor.Wasm.runPlaygroundWasm(wasm_url.ptr, wasm_url.len);
            }
        },
        .err => |err| {
            build_state = .err;
            err_response = .{
                .code = err.code,
                .message = Vapor.dupe(err.message, .persist),
                .body = Vapor.dupe(err.body, .persist),
                .url = Vapor.dupe(err.url, .persist),
                .elapsed_ms = err.elapsed_ms,
                .kind = err.kind,
            };
            addPlaygroundRunHistory("error", err.body);
            // Underline the token each diagnostic points at, until the next
            // build. The messages point into the persisted body.
            var it = diagnostics.iterate(err_response.?.body);
            while (it.next()) |diagnostic| {
                const column = findClosestTokenColumn(diagnostic.line, diagnostic.column);
                code_editor.addExternalError(diagnostic.line, column, diagnostic.message) catch break;
            }
            reparse();
        },
    }
}

fn findClosestTokenColumn(line_number: usize, target_col: usize) usize {
    const line_start = gotoLine(line_number) orelse return 1;
    const bounds = getLineBounds(line_start);
    const line = content[bounds.start..bounds.end];

    // If target column is within line length, use it
    if (target_col > 0 and target_col <= line.len) {
        return target_col;
    }

    // Column is past end of line — walk backwards to find last non-whitespace
    var last_col: usize = 1;
    for (line, 0..) |c, i| {
        if (c != ' ' and c != '\t') {
            last_col = i + 1; // 1-based
        }
    }

    return last_col;
}

// ============================================================================
// Render functions (UPDATED — autocomplete overlay added)
// ============================================================================

fn gotoTab(file: *File, i: usize) void {
    _ = file;
    // Save current content into the file's content field
    files.items[selected_file].content = content;

    selected_file = i;
    content_buffer = &files.items[selected_file].buffer;

    // Buffer already has the right data from last time,
    // only reload if content was set externally
    content = content_buffer.items;
    code_editor.recompile(content) catch return;
    Vapor.onLayout(updateCursorPosition, .{});
}

fn addTab() void {
    files.append(.{
        .name = "New File",
        .content = "",
        .file_name = "new_file.zig",
        .buffer = Vapor.persist.array(u8),
    });
    selected_file = files.items.len - 1;
    content_buffer = &files.items[selected_file].buffer;
    content = content_buffer.items;
    code_editor.recompile(content) catch return;
}

fn loadFileWithContent() void {
    files.append(.{
        .name = "New File",
        .content = Assembler.current_code,
        .file_name = "new_file.zig",
        .buffer = Vapor.persist.array(u8),
    });
    selected_file = files.items.len - 1;
    files.items[selected_file].buffer.appendSlice(Assembler.current_code);
    content_buffer = &files.items[selected_file].buffer;
    content = content_buffer.items;
    code_editor.recompile(content) catch |err| {
        std.log.err("playground: failed to recompile {any}", .{err});
        return;
    };
    Vapor.onLayout(Vapor.cycle, .{});
}

fn editFile(file: *File, i: usize, evt: *Vapor.Event) void {
    _ = evt;
    _ = i;
    file.editing = true;
}

fn blurFile(file: *File, i: usize, evt: *Vapor.Event) void {
    _ = evt;
    _ = i;
    file.editing = false;
}

fn CodeRow(code: *SyntaxHighlighter) void {
    Stack().width(.expand)
        .height(.percent(100))
        .children({
        Stack().width(.percent(100))
            .height(.percent(100))
            .background(.hex("#111110"))
            .children({
            if (Vapor.isDesktop()) {
                Row()
                    .width(.percent(100))
                    .height(.percent(6))
                    .padding(.horizontal(24))
                    .children({
                    Row()
                        .width(.expand)
                        .spacing(8)
                        .children({
                        for (files.items, 0..) |*file, i| {
                            if (file.editing) {
                                Vapor.TextField(.string)
                                    .bind(&file.name)
                                    .onEvent(.blur, blurFile, .{ file, i })
                                    .focus()
                                    .width(.clamp(114, 114, 256, .px))
                                    .outline(.none, null)
                                    .layout(.center)
                                    .height(.percent(100))
                                    .border(.bottom(1, .white))
                                    .background(.transparent)
                                    .fontFamily("Geist Mono, monospace")
                                    .font(14, 300, .white).end();
                            } else {
                                Button(gotoTab, .{ file, i })
                                    .onEvent(.dblclick, editFile, .{ file, i })
                                    .opacity(if (i == selected_file) 1 else 0.5)
                                    .hover(.{ .opacity = 1 })
                                    .padding(.all(8))
                                    .width(.clamp(114, 114, 256, .px))
                                    .layout(.center)
                                    .height(.percent(100))
                                    .border(.bottom(1, .white))
                                    .pointer()
                                    .children({
                                    Text(file.name)
                                        .fontStyle(.italic)
                                        .fontFamily("Geist Mono, monospace")
                                        .font(14, 300, .white).end();
                                });
                            }
                        }

                        Button(addTab, .{})
                            .padding(.all(8))
                            .layout(.center)
                            .hover(.{ .transform = .scaleDecimal(1.2) })
                            .width(.fit)
                            .pointer()
                            .child(Icon(.plus).font(14, 300, .white));
                    });

                    // NEW: Autocomplete hint in header
                    Row()
                        .layout(.right_center)
                        .width(.expand)
                        .height(.percent(100))
                        .children({
                        Text("EMOJIS NOT SUPPORTED")
                            .font(11, 400, .palette(.danger))
                            .end();
                    });
                });
            }
            Center().width(.percent(100))
                .height(.expand)
                .scroll(.scrollY())
                .background(.hex("#282828"))
                .pos(.relative)
                .children({
                Row()
                    // .ref(&highlighter_layer)
                    .height(.percent(100))
                    .width(.percent(100))
                    .padding(.horizontal(12))
                    // .scroll(.scroll_y())
                    .pos(.tl(.percent(0), .percent(0), .absolute))
                    .background(.hex("#282828"))
                    .children({
                    code.render() catch unreachable;
                });

                // Transparent textarea layer
                Row()
                    .background(.transparent)
                    .width(.percent(100))
                    .height(.percent(100))
                    .padding(.horizontal(12))
                    .pos(.tl(.percent(0), .percent(0), .absolute))
                    .children({
                    TextArea()
                        .ref(&text_area)
                        .background(.transparent)
                        .bind(&content)
                        .width(.percent(100))
                        .outline(.none, null)
                        .border(.none)
                        .resize(.none)
                        .border(.thin(.transparent))
                        .height(.percent(100))
                        .textDecoration(.none)
                        .whiteSpace(.pre)
                        .padding(.{ .top = 11, .left = 47 })
                        .fontFamily("DM Mono, monospace")
                        .caret(.{ .type = .line, .color = .hex("#00AAFF") })
                        .textDecoration(.none)
                        .fontSize(15)
                        .fontWeight(400)
                        .textColor(.transparent)
                        .onEvent(.scroll, onScroll, .{code})
                        .onChange(onChange, .{})
                        .onEvent(.keydown, onKeyDown, .{})
                        .onEvent(.keyup, onKeyUp, .{})
                        .onEvent(.blur, onBlur, .{})
                        .end();
                });

                // NEW: Autocomplete overlay (render last so it's on top)
                autocomplete.render();
            });
        });
    });
}

fn clearPlaygroundHistory() void {
    playground_run_history.clearRetainingCapacity();
    playground_diff_text = "";
    Vapor.store(playground_history_key, "");
}

fn Output() void {
    Row()
        .pos(.relative)
        .ref(&container)
        .width(.px(size))
        .height(.percent(100))
        .border(.top(1, .palette(.border_color_light)))
        .children({
        Row()
            .height(.percent(100))
            .layout(.center)
            .pos(.tl(.px(0), .px(-4), .absolute))
            .createDraggable(&draggable)
            .children({
            Row()
                .width(.px(8))
                .height(.percent(100))
                .layout(.center)
                .border(.thin(.palette(.border_color_light)))
                .cursor(Vapor.Types.Cursor.ew_resize)
                .children({
                Vapor.Divider(8)
                    .layer(Vapor.Types.BackgroundLayer.grid(4, 1, .palette(.border_color_light)))
                    .height(.percent(100))
                    .end();
            });
        });

        // On its own origin (see build.zig), so the code it runs cannot
        // read the API keys this app keeps in its storage.
        Vapor.Iframe(build_options.playground_url)
            .border(.none)
            .outline(.none, null)
            .width(.expand)
            .height(.percent(100))
            .id("playground-frame")
            .end();

        Row().children({
            switch (build_state) {
                .loading => {
                    Center()
                        .width(.percent(100))
                        .height(.percent(100))
                        .pos(.tl(.percent(0), .percent(0), .absolute))
                        .blur(50)
                        .children({
                        Vapor.Svg(.{ .svg = @embedFile("loader.svg"), .override = true })
                            .width(.percent(50))
                            .end();
                    });
                },
                .err => {
                    const err_text = if (err_response) |err| err.body else "Unknown err";
                    Row()
                        .padding(.all(16))
                        .width(.percent(100))
                        .height(.percent(100))
                        .children({
                        Stack()
                            .width(.percent(100))
                            .height(.fit)
                            .inlineStyle("border-top: 8px solid rgba(var(--tint))", .{})
                            .radius(Vapor.Types.BorderRadius.all(8))
                            .padding(.all(8))
                            .background(.hex("#111110"))
                            .spacing(8)
                            .children({
                            Text("Error Compiling Vapor App").font(24, 100, .white).end();
                            Stack()
                                .width(.percent(100))
                                .height(.fit)
                                .radius(Vapor.Types.BorderRadius.all(8))
                                .padding(.all(8))
                                .background(.hex("#282828"))
                                .children({
                                Text(err_text)
                                    .whiteSpace(.pre_wrap)
                                    .font(16, 100, .white)
                                    .end();
                            });

                            Row()
                                .mt(8)
                                .layout(.right_center)
                                .children({
                                Opaque.Button(fixWithModel, .{})
                                    .background(.transparentize(.palette(.tint), 1))
                                    .height(.px(34))
                                    .padding(.xy(12, 6))
                                    .border(.thin(.palette(.border_color_light)))
                                    .pointer()
                                    .children({
                                    Text("Fix With Model")
                                        .font(12, 400, .palette(.background))
                                        .end();
                                });
                            });
                        });
                    });
                },
                .empty, .result => {
                    Vapor.Null();
                },
            }
        });

        Stack()
            .pos(.tr(.px(0), .px(0), .absolute))
            .width(if (show_playground_history) .px(360) else .px(0))
            .height(.percent(100))
            .background(.hex("#111110"))
            .border(.left(if (show_playground_history) 1 else 0, .palette(.border_color_light)))
            .transition(.{ .duration = 100, .timing = .easeInOut, .properties = &.{.width} })
            .children({
            if (show_playground_history) {
                Stack()
                    .width(.percent(100))
                    .height(.percent(100))
                    .padding(.all(10))
                    .spacing(8)
                    .children({
                    Row()
                        .width(.expand)
                        .layout(.x_between_center)
                        .items(.{
                        Text("Playground Run History")
                            .font(18, 100, .white),
                        Button(clearPlaygroundHistory, .{})
                            .padding(.xy(8, 4))
                            .hover(.{ .background = .yellow, .text_color = .black })
                            .textColor(.white)
                            .pointer()
                            .children({
                            Text("Clear").fontSize(12).fontWeight(500).end();
                        }),
                    });

                    Stack()
                        .width(.percent(100))
                        .height(.grow)
                        .scroll(.scrollY())
                        .spacing(8)
                        .children({
                        if (playground_run_history.items.len == 0) {
                            Text("No runs yet")
                                .font(11, 400, .hex("#c8c8c8"))
                                .end();
                        } else {
                            const start: usize = if (playground_run_history.items.len > 8) playground_run_history.items.len - 8 else 0;
                            for (playground_run_history.items[start..], start..) |item, i| {
                                Stack()
                                    .padding(.all(8))
                                    .border(.thin(.hex("#3a3a3a")))
                                    .spacing(6)
                                    .children({
                                    Row()
                                        .layout(.x_between_center)
                                        .children({
                                        Text(Vapor.frame.fmt("#{d} · {s} · {s}", .{ i + 1, item.state, item.timestamp }))
                                            .font(12, 400, .hex("#c8c8c8"))
                                            .end();
                                        Row()
                                            .spacing(6)
                                            .children({
                                            Button(restorePlaygroundHistory, .{i})
                                                .padding(.xy(8, 4))
                                                .hover(.{ .background = .yellow, .text_color = .black })
                                                .textColor(.white)
                                                .pointer()
                                                .children({
                                                Text("Restore").fontSize(12).fontWeight(500).end();
                                            });
                                            Button(diffPlaygroundHistory, .{i})
                                                .padding(.xy(8, 4))
                                                .hover(.{ .background = .yellow, .text_color = .black })
                                                .textColor(.white)
                                                .pointer()
                                                .children({
                                                Text("Diff").fontSize(12).fontWeight(500).end();
                                            });
                                        });
                                    });
                                    if (item.error_text.len > 0) {
                                        Text(item.error_text)
                                            .font(10, 300, .hex("#ff9b9b"))
                                            .whiteSpace(.pre_wrap)
                                            .end();
                                    } else {
                                        Vapor.Null();
                                    }
                                });
                            }
                        }
                    });

                    if (playground_diff_text.len > 0) {
                        Stack()
                            .width(.percent(100))
                            .height(.grow)
                            .padding(.all(10))
                            .background(.hex("#151515"))
                            .border(.thin(.hex("#3a3a3a")))
                            .radius(.all(8))
                            .spacing(8)
                            .children({
                            Row()
                                .layout(.x_between_center)
                                .children({
                                Text("Playground Diff")
                                    .font(12, 600, .white)
                                    .end();
                                Button(clearPlaygroundDiff, .{})
                                    .padding(.xy(8, 4))
                                    .border(.thin(.hex("#3a3a3a")))
                                    .pointer()
                                    .children({
                                    Text("Close").font(10, 500, .white).end();
                                });
                            });
                            Stack()
                                .width(.percent(100))
                                .height(.grow)
                                .scroll(.scrollY())
                                .children({
                                Text(playground_diff_text)
                                    .font(12, 300, .hex("#d6d6d6"))
                                    .whiteSpace(.pre_wrap)
                                    .fontFamily("'DM Mono', monospace")
                                    .end();
                            });
                        });
                    } else {
                        Vapor.Null();
                    }
                });
            } else {
                Vapor.Null();
            }
        });
    });
}

fn mount() void {
    text_area.setAttribute("spellcheck", "false");
    if (!versions_requested) {
        versions_requested = true;
        fetch(backend.url("/api/wasm/versions"), .{ .method = .GET }).handle(handleVersions, .{});
    }
}

/// What the backend builds playground code with, for the header. Null
/// until the backend answers.
const Versions = struct { zig: []const u8, vapor: []const u8 };
var versions: ?Versions = null;
var versions_requested = false;

fn handleVersions(resp: Vapor.Fetch.Result) void {
    switch (resp) {
        .ok => |ok| versions = std.json.parseFromSliceLeaky(Versions, Vapor.persist.arena(), ok.body, .{}) catch null,
        // The header keeps saying it does not know.
        .err => {},
    }
}

fn renderNav() void {
    Row()
        .width(.percent(100))
        .height(.px(60))
        .padding(.horizontal(20)).layout(.x_between_center)
        .background(.palette(.background))
        .children({
        Row().children({
            for (&[_][]const u8{ "P", "L", "A", "Y", "G", "R", "O", "U", "N", "D" }, 0..) |c, i| {
                Stack()
                    .width(.px(18))
                    .transition(.{ .duration = 300, .timing = .ease, .properties = &.{ .opacity, .width } })
                    .layout(.center)
                    .pos(.relative)
                    .children({
                    Text(c)
                        .font(24, 100, .palette(.text))
                        .transform(if (i == 9) Vapor.Types.Transform.rotateXYZ(0, 180, 0) else .{})
                        .fontStyle(if (i == 9) .italic else .normal)
                        .end();
                });
            }
        });

        Row()
            .spacing(8)
            .children({
            Opaque.Button(togglePlaygroundHistory, .{})
                .background(if (show_playground_history) .palette(.tint) else .transparentize(.palette(.tint), 1))
                .height(.px(36))
                .padding(.xy(12, 6))
                .radius(.all(0))
                .pointer()
                .children({
                Text("History")
                    .font(14, 300, if (show_playground_history) .white else .palette(.background))
                    .end();
            });

            Opaque.Button(getWasm, .{})
                .background(.transparentize(.palette(.tint), 1))
                .height(.px(36))
                .padding(.xy(12, 6))
                .radius(.all(0))
                .pointer()
                .children({
                Text("Submit ⌘ + Enter")
                    .font(14, 300, .palette(.background))
                    .end();
            });
        });
    });
}

var draggable: Vapor.Draggable = .{
    .on_drag = onDrag,
};

var size: f32 = 0;
var container: Vapor.Element = .{};
var show_playground_history: bool = false;
fn onDrag(_: *Vapor.Draggable, _: *Vapor.Event) void {
    size -= draggable.movement_x;
    container.mutateAttribute(.{ .width = .{ .value = size, .unit = .px } });
}

fn togglePlaygroundHistory() void {
    show_playground_history = !show_playground_history;
}

pub fn loadFileFromChat() void {
    loadFileWithContent();
}

pub fn render() void {
    Stack()
        .width(.expand)
        .height(.percent(100))
        .children({
        renderNav();

        Stack().width(.percent(100)).height(.expand).children({
            Row()
                .spacing(8)
                .padding(.all(8))
                .items(.{
                Text(Vapor.frame.fmt("Zig Version: {s}", .{if (versions) |v| v.zig else "…"})).font(14, 200, .palette(.text)),
                Text(Vapor.frame.fmt("Vapor Version: {s}", .{if (versions) |v| v.vapor else "…"})).font(14, 200, .palette(.text)),
            });
            Row().width(.percent(100))
                .pos(.relative)
                .height(.expand).children({
                CodeRow(&code_editor);
                Output();
            });
        });
    });
    Vapor.Hooks(.{ .mounted = mount })({});
}
