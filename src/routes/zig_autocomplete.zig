// ============================================================================
// ZIG AUTOCOMPLETE — Updated with semantic analysis integration
// ============================================================================
//
// Changes from the original:
//   - Added `ZigSemanticAnalyzer` as a dependency
//   - `generateSuggestions` now calls the analyzer for:
//       • Dot completions on user-defined types (struct fields, enum values, methods)
//       • User-defined symbols (variables, functions, types) in general completion
//   - Added `reanalyze()` method — call after content changes (debounce recommended)
//   - After-dot context now tries semantic resolution FIRST, falls back to static list
//   - Top-level / function-body contexts now include user-defined symbols
//
// The static Vapor/Zig keyword lists remain as fallbacks.
// ============================================================================

const std = @import("std");
const Allocator = std.mem.Allocator;
const Vapor = @import("vapor");
const Box = Vapor.Box;
const Text = Vapor.Text;
const Row = Vapor.Row;
const Stack = Vapor.Stack;
const Icon = Vapor.Icon;
const IconTokens = Vapor.IconTokens;

const ZigSemanticAnalyzer = @import("zig_semantic.zig").ZigSemanticAnalyzer;
const CompletionItem = @import("zig_semantic.zig").CompletionItem;
const CompletionKind = @import("zig_semantic.zig").CompletionKind;

// ============================================================================
// Suggestion Types (unchanged, with additions)
// ============================================================================

pub const SuggestionKind = enum {
    keyword,
    builtin,
    vapor_component,
    vapor_method,
    vapor_layout,
    snippet,
    type_name,
    // NEW kinds for semantic completions
    field,
    user_function,
    user_variable,
    enum_value,
    module,

    pub fn icon(self: SuggestionKind) *const IconTokens {
        return switch (self) {
            .keyword => .body_text,
            .builtin => .at_sign,
            .vapor_component => .braces,
            .vapor_method => .list_columns,
            .vapor_layout => .box,
            .snippet => .code_square,
            .type_name => .diamond,
            .field => .list_columns,
            .user_function => .code_square,
            .user_variable => .body_text,
            .enum_value => .diamond,
            .module => .braces,
        };
    }

    pub fn color(self: SuggestionKind) Vapor.Types.Color {
        return switch (self) {
            .keyword => .hex("#C792EA"),
            .builtin => .hex("#82AAFF"),
            .vapor_component => .hex("#FFCB6B"),
            .vapor_method => .hex("#89DDFF"),
            .vapor_layout => .hex("#C3E88D"),
            .snippet => .hex("#F78C6C"),
            .type_name => .hex("#FFCB6B"),
            .field => .hex("#F07178"),
            .user_function => .hex("#82AAFF"),
            .user_variable => .hex("#EEFFFF"),
            .enum_value => .hex("#C3E88D"),
            .module => .hex("#89DDFF"),
        };
    }

    pub fn label(self: SuggestionKind) []const u8 {
        return switch (self) {
            .keyword => "keyword",
            .builtin => "builtin",
            .vapor_component => "component",
            .vapor_method => "method",
            .vapor_layout => "layout",
            .snippet => "snippet",
            .type_name => "type",
            .field => "field",
            .user_function => "fn",
            .user_variable => "var",
            .enum_value => "enum",
            .module => "module",
        };
    }
};

pub const Suggestion = struct {
    text: []const u8,
    kind: SuggestionKind,
    detail: ?[]const u8 = null,
    insert_text: ?[]const u8 = null,
    score: u32 = 0,
};

// ============================================================================
// Context Detection (unchanged)
// ============================================================================

pub const ZigContext = enum {
    top_level,
    after_dot,
    after_at,
    after_vapor_dot,
    in_function_body,
    after_open_paren,
    in_children,
    after_sizing_method,
    after_background,
    after_font,
    after_layout,
    after_padding,
    after_border,
    after_import,
    after_enum_dot, // NEW: after `.` in enum literal context (e.g. `.admin`)
    unknown,
};

// ============================================================================
// Zig Autocomplete Engine
// ============================================================================

pub const ZigAutoComplete = struct {
    allocator: Allocator,
    suggestions: std.array_list.Managed(Suggestion),
    filtered: std.array_list.Managed(Suggestion),
    selected_index: usize = 0,
    visible: bool = false,
    partial_word: []const u8 = "",
    partial_start: usize = 0,
    cursor_x: f32 = 0,
    cursor_y: f32 = 0,
    context: ZigContext = .top_level,
    max_suggestions: usize = 12, // bumped from 10 for richer results

    // NEW: semantic analyzer
    analyzer: ZigSemanticAnalyzer,
    /// Track whether we need to re-analyze (set true on content change)
    analysis_dirty: bool = true,
    /// Cache the source we last analyzed to avoid redundant work
    last_analyzed_len: usize = 0,

    const Self = @This();

    pub fn init(allocator: Allocator) Self {
        return .{
            .allocator = allocator,
            .suggestions = std.array_list.Managed(Suggestion).init(allocator),
            .filtered = std.array_list.Managed(Suggestion).init(allocator),
            .analyzer = ZigSemanticAnalyzer.init(allocator),
        };
    }

    pub fn deinit(self: *Self) void {
        self.suggestions.deinit();
        self.filtered.deinit();
        self.analyzer.deinit();
    }

    // ========================================================================
    // NEW: Re-analyze source code (call after content changes, ideally debounced)
    // ========================================================================

    pub fn reanalyze(self: *Self, source: []const u8) void {
        self.analyzer.analyze(source);
        self.analysis_dirty = false;
        self.last_analyzed_len = source.len;
    }

    /// Mark analysis as needing refresh (call on every keystroke)
    pub fn markDirty(self: *Self) void {
        self.analysis_dirty = true;
    }

    /// Ensure analysis is up to date before generating suggestions
    fn ensureAnalyzed(self: *Self, source: []const u8) void {
        // Re-analyze if dirty or if source length changed significantly
        if (self.analysis_dirty or
            (if (source.len > self.last_analyzed_len)
            source.len - self.last_analyzed_len
        else
            self.last_analyzed_len - source.len) > 0)
        {
            self.reanalyze(source);
        }
    }

    // ========================================================================
    // Context Detection (same as before, with enum dot addition)
    // ========================================================================

    pub fn detectContext(self: *Self, text: []const u8, cursor_pos: usize) ZigContext {
        _ = self;
        if (cursor_pos == 0 or text.len == 0) return .top_level;
        const safe_pos = @min(cursor_pos, text.len);
        const char_before = text[safe_pos - 1];

        if (char_before == '@') return .after_at;

        // Check method context BEFORE generic dot
        const method_ctx = detectMethodContext(text, safe_pos);
        if (method_ctx != .unknown) return method_ctx;

        if (char_before != '.' and std.ascii.isAlphanumeric(char_before) or char_before == '_') {
            var scan = safe_pos - 1;
            while (scan > 0 and (std.ascii.isAlphanumeric(text[scan - 1]) or text[scan - 1] == '_')) {
                scan -= 1;
            }
            if (scan > 0 and text[scan - 1] == '.') {
                // Check what's before the dot
                const before_dot = findTokenBeforePos(text, scan - 1);
                if (before_dot) |token| {
                    if (std.mem.eql(u8, token, "Vapor")) return .after_vapor_dot;
                }
                return .after_dot;
            }
        }

        if (char_before == '.') {
            // Check if this is an enum literal dot (preceded by space, `=`, `(`, `,`, `{`)
            if (safe_pos >= 2) {
                const two_before = text[safe_pos - 2];
                if (two_before == ' ' or two_before == '=' or two_before == '(' or
                    two_before == ',' or two_before == '{' or two_before == '\n')
                {
                    return .after_enum_dot;
                }
            }

            const before_dot = findTokenBeforePos(text, safe_pos - 1);
            if (before_dot) |token| {
                if (std.mem.eql(u8, token, "Vapor")) return .after_vapor_dot;
            }
            return .after_dot;
        }

        if (isInsideImportParens(text, safe_pos)) return .after_import;
        if (isInsideChildren(text, safe_pos)) return .in_children;
        if (isInsideFunctionBody(text, safe_pos)) return .in_function_body;

        return .top_level;
    }

    fn findTokenBeforePos(text: []const u8, dot_pos: usize) ?[]const u8 {
        if (dot_pos == 0) return null;
        const end = dot_pos;
        var start = end;
        while (start > 0) {
            const c = text[start - 1];
            if (std.ascii.isAlphanumeric(c) or c == '_') {
                start -= 1;
            } else break;
        }
        if (start == end) return null;
        return text[start..end];
    }

    fn detectMethodContext(text: []const u8, pos: usize) ZigContext {
        var depth: i32 = 0;
        var i: usize = pos;
        while (i > 0) {
            i -= 1;
            const c = text[i];
            if (c == ')') {
                depth += 1;
            } else if (c == '(') {
                if (depth == 0) {
                    const method = findTokenBeforePos(text, i);
                    if (method) |m| {
                        if (std.mem.eql(u8, m, "width") or std.mem.eql(u8, m, "height") or
                            std.mem.eql(u8, m, "minWidth") or std.mem.eql(u8, m, "maxWidth") or
                            std.mem.eql(u8, m, "minHeight") or std.mem.eql(u8, m, "maxHeight"))
                            return .after_sizing_method;

                        if (std.mem.eql(u8, m, "background")) return .after_background;
                        if (std.mem.eql(u8, m, "font")) return .after_font;
                        if (std.mem.eql(u8, m, "layout")) return .after_layout;
                        if (std.mem.eql(u8, m, "padding") or std.mem.eql(u8, m, "margin")) return .after_padding;
                        if (std.mem.eql(u8, m, "border")) return .after_border;
                    }
                    return .after_open_paren;
                }
                depth -= 1;
            } else if (c == '\n') {
                break;
            }
        }
        return .unknown;
    }

    fn isInsideImportParens(text: []const u8, pos: usize) bool {
        if (pos < 9) return false;
        var i: usize = pos;
        var depth: i32 = 0;
        while (i > 0) {
            i -= 1;
            if (text[i] == ')') depth += 1;
            if (text[i] == '(') {
                if (depth == 0) {
                    if (i >= 7 and std.mem.eql(u8, text[i - 7 .. i], "@import")) return true;
                    return false;
                }
                depth -= 1;
            }
            if (text[i] == '\n') break;
        }
        return false;
    }

    fn isInsideChildren(text: []const u8, pos: usize) bool {
        var brace_depth: i32 = 0;
        var i: usize = pos;
        while (i > 0) {
            i -= 1;
            if (text[i] == '}') brace_depth += 1;
            if (text[i] == '{') {
                if (brace_depth == 0) {
                    if (i >= 11) {
                        var j = i - 1;
                        while (j > 0 and (text[j] == ' ' or text[j] == '\n')) j -= 1;
                        if (j > 0 and text[j] == '(') {
                            if (j >= 9 and std.mem.eql(u8, text[j - 9 .. j], ".children")) return true;
                        }
                    }
                    return false;
                }
                brace_depth -= 1;
            }
        }
        return false;
    }

    fn isInsideFunctionBody(text: []const u8, pos: usize) bool {
        var brace_depth: i32 = 0;
        var i: usize = pos;
        while (i > 0) {
            i -= 1;
            if (text[i] == '}') brace_depth += 1;
            if (text[i] == '{') {
                if (brace_depth == 0) {
                    const before = std.mem.trimEnd(u8, text[0..i], " \t\n");
                    if (before.len > 0 and before[before.len - 1] == ')') return true;
                    if (std.mem.endsWith(u8, before, "void")) return true;
                    return false;
                }
                brace_depth -= 1;
            }
        }
        return false;
    }

    // ========================================================================
    // Suggestion Generation — UPDATED with semantic integration
    // ========================================================================

    pub fn generateSuggestions(self: *Self, text: []const u8, cursor_pos: usize) void {
        self.suggestions.clearRetainingCapacity();
        self.context = self.detectContext(text, cursor_pos);
        self.extractPartialWord(text, cursor_pos);

        // Ensure semantic analysis is current
        self.ensureAnalyzed(text);

        switch (self.context) {
            .after_at => {
                self.addZigBuiltins();
            },
            .after_dot => {
                // NEW: Try semantic dot-completion first
                const semantic_items = self.analyzer.completionsForDot(text, cursor_pos);
                if (semantic_items.len > 0) {
                    self.addSemanticCompletions(semantic_items);
                } else {
                    // Fallback to static dot completions
                    self.addDotCompletions();
                }
            },
            .after_vapor_dot => {
                self.addVaporNamespace();
            },
            .after_enum_dot => {
                // Try struct literal completion first (e.g. `T{ .field`)
                const struct_items = self.analyzer.completionsForDot(text, cursor_pos);
                if (struct_items.len > 0) {
                    self.addSemanticCompletions(struct_items);
                } else {
                    // Fallback: offer all known enum values
                    const enum_items = self.analyzer.completionsForEnumLiteral();
                    if (enum_items.len > 0) {
                        self.addSemanticCompletions(enum_items);
                    }
                    // Also add static dot completions as fallback
                    self.addDotCompletions();
                }
            },
            .after_sizing_method => {
                self.addSizingValues();
            },
            .after_background => {
                self.addColorValues();
            },
            .after_font => {},
            .after_layout => {
                self.addLayoutValues();
            },
            .after_padding => {
                self.addPaddingValues();
            },
            .after_border => {
                self.addBorderValues();
            },
            .after_import => {
                self.addImportTargets();
            },
            .in_children => {
                self.addVaporComponents();
                self.addZigKeywords();
                self.addZigControlFlow();
                self.addUserSymbols(); // NEW
            },
            .in_function_body => {
                self.addUserSymbols(); // NEW — user types/vars/fns first (higher relevance)
                self.addZigKeywords();
                self.addZigControlFlow();
                self.addVaporComponents();
                self.addZigTypes();
                self.addZigBuiltins();
            },
            .top_level => {
                self.addTopLevelKeywords();
                self.addUserSymbols(); // NEW
                self.addZigTypes();
                self.addZigBuiltins();
            },
            .after_open_paren => {
                self.addUserSymbols(); // NEW
                self.addZigTypes();
                self.addZigKeywords();
            },
            .unknown => {
                self.addUserSymbols(); // NEW
                self.addZigKeywords();
                self.addVaporComponents();
                self.addZigTypes();
            },
        }

        self.filterSuggestions();
    }

    // ========================================================================
    // NEW: Add completions from semantic analyzer
    // ========================================================================

    fn addSemanticCompletions(self: *Self, items: []const CompletionItem) void {
        for (items) |item| {
            const kind: SuggestionKind = switch (item.kind) {
                .field => .field,
                .method => .user_function,
                .enum_value => .enum_value,
                .variable => .user_variable,
                .constant => .user_variable,
                .function => .user_function,
                .type_name => .type_name,
                .module => .module,
                .keyword => .keyword,
                .snippet => .snippet,
            };
            self.addSuggestion(item.label, kind, item.detail);
        }
    }

    fn addUserSymbols(self: *Self) void {
        const items = self.analyzer.allUserSymbols();
        self.addSemanticCompletions(items);
    }

    // ========================================================================
    // Static suggestion helpers (unchanged from original)
    // ========================================================================

    fn addSuggestion(self: *Self, text: []const u8, kind: SuggestionKind, detail: ?[]const u8) void {
        self.suggestions.append(.{
            .text = text,
            .kind = kind,
            .detail = detail,
            .score = 0,
        }) catch {};
    }

    fn addSuggestionWithInsert(self: *Self, text: []const u8, kind: SuggestionKind, detail: ?[]const u8, insert: []const u8) void {
        self.suggestions.append(.{
            .text = text,
            .kind = kind,
            .detail = detail,
            .insert_text = insert,
            .score = 0,
        }) catch {};
    }

    fn addTopLevelKeywords(self: *Self) void {
        const kws = [_][]const u8{
            "const", "var",            "pub",    "fn",     "struct",
            "enum",  "union",          "export", "extern", "comptime",
            "test",  "usingnamespace",
        };
        for (kws) |kw| self.addSuggestion(kw, .keyword, null);

        self.addSuggestionWithInsert("pub fn", .snippet, "Public function", "pub fn ");
        self.addSuggestionWithInsert("pub fn init()", .snippet, "Init function", "pub fn init() void {\n    \n}");
        self.addSuggestionWithInsert("pub fn render()", .snippet, "Render function", "pub fn render() void {\n    \n}");
        self.addSuggestionWithInsert("export fn init()", .snippet, "Export init", "export fn init() void {\n    \n}");
    }

    fn addZigKeywords(self: *Self) void {
        const kws = [_][]const u8{
            "const",       "var",    "fn",       "return", "if",
            "else",        "for",    "while",    "switch", "break",
            "continue",    "defer",  "errdefer", "try",    "catch",
            "orelse",      "and",    "or",       "pub",    "comptime",
            "inline",      "struct", "enum",     "union",  "error",
            "undefined",   "null",   "true",     "false",  "unreachable",
            "threadlocal",
        };
        for (kws) |kw| self.addSuggestion(kw, .keyword, null);
    }

    fn addZigControlFlow(self: *Self) void {
        self.addSuggestionWithInsert("if () {}", .snippet, "If block", "if () {\n    \n}");
        self.addSuggestionWithInsert("for () |item|", .snippet, "For loop", "for () |item| {\n    \n}");
        self.addSuggestionWithInsert("while () {}", .snippet, "While loop", "while () {\n    \n}");
        self.addSuggestionWithInsert("switch () {}", .snippet, "Switch", "switch () {\n    \n}");
    }

    fn addZigBuiltins(self: *Self) void {
        const builtins = [_]struct { name: []const u8, detail: []const u8 }{
            .{ .name = "@import", .detail = "Import module" },
            .{ .name = "@intCast", .detail = "Integer cast" },
            .{ .name = "@floatFromInt", .detail = "Int to float" },
            .{ .name = "@intFromFloat", .detail = "Float to int" },
            .{ .name = "@intFromEnum", .detail = "Enum to int" },
            .{ .name = "@enumFromInt", .detail = "Int to enum" },
            .{ .name = "@as", .detail = "Type coercion" },
            .{ .name = "@min", .detail = "Minimum" },
            .{ .name = "@max", .detail = "Maximum" },
            .{ .name = "@memset", .detail = "Set memory" },
            .{ .name = "@memcpy", .detail = "Copy memory" },
            .{ .name = "@truncate", .detail = "Truncate integer" },
            .{ .name = "@ptrCast", .detail = "Pointer cast" },
            .{ .name = "@alignCast", .detail = "Alignment cast" },
            .{ .name = "@sizeOf", .detail = "Size of type" },
            .{ .name = "@alignOf", .detail = "Alignment of type" },
            .{ .name = "@tagName", .detail = "Enum/union tag name" },
            .{ .name = "@typeName", .detail = "Type name string" },
            .{ .name = "@typeInfo", .detail = "Type info" },
            .{ .name = "@embedFile", .detail = "Embed file contents" },
            .{ .name = "@field", .detail = "Access field by name" },
            .{ .name = "@hasField", .detail = "Check field exists" },
            .{ .name = "@panic", .detail = "Panic with message" },
            .{ .name = "@This", .detail = "Current type" },
            .{ .name = "@src", .detail = "Source location" },
            .{ .name = "@errorName", .detail = "Error tag name" },
            .{ .name = "@splat", .detail = "Vector splat" },
            .{ .name = "@bitCast", .detail = "Reinterpret bits" },
            .{ .name = "@constCast", .detail = "Remove const" },
            .{ .name = "@volatileCast", .detail = "Remove volatile" },
        };
        for (builtins) |b| {
            if (self.context == .after_at) {
                self.addSuggestionWithInsert(b.name, .builtin, b.detail, b.name[1..]);
            } else {
                self.addSuggestion(b.name, .builtin, b.detail);
            }
        }
    }

    fn addZigTypes(self: *Self) void {
        const types = [_][]const u8{
            "u8",       "u16",  "u32",     "u64",       "u128",     "usize",
            "i8",       "i16",  "i32",     "i64",       "i128",     "isize",
            "f16",      "f32",  "f64",     "f128",      "bool",     "void",
            "noreturn", "type", "anytype", "anyopaque", "anyerror",
        };
        for (types) |t| self.addSuggestion(t, .type_name, "Type");

        self.addSuggestion("[]const u8", .type_name, "String slice");
        self.addSuggestion("[]u8", .type_name, "Mutable string");
        self.addSuggestion("Allocator", .type_name, "std.mem.Allocator");
    }

    fn addVaporComponents(self: *Self) void {
        const components = [_]struct { name: []const u8, detail: []const u8 }{
            .{ .name = "Stack()", .detail = "Vertical layout" },
            .{ .name = "Row()", .detail = "Horizontal layout" },
            .{ .name = "Center()", .detail = "Centered container" },
            .{ .name = "Box()", .detail = "Generic container" },
            .{ .name = "Text", .detail = "Text element" },
            .{ .name = "TextFmt", .detail = "Formatted text" },
            .{ .name = "Button", .detail = "Button(handler, .{})" },
            .{ .name = "TextField", .detail = "Text input" },
            .{ .name = "TextArea()", .detail = "Multiline input" },
            .{ .name = "Icon", .detail = "Icon element" },
            .{ .name = "Image", .detail = "Image element" },
            .{ .name = "Link", .detail = "Navigation link" },
            .{ .name = "Spacer", .detail = "Vertical spacer" },
            .{ .name = "Label", .detail = "Label element" },
            .{ .name = "Heading", .detail = "Heading element" },
            .{ .name = "Form", .detail = "Form container" },
        };
        for (components) |c| self.addSuggestion(c.name, .vapor_component, c.detail);
    }

    fn addVaporNamespace(self: *Self) void {
        const items = [_]struct { name: []const u8, detail: []const u8 }{
            .{ .name = "Stack", .detail = "Vertical layout" },
            .{ .name = "Row", .detail = "Horizontal layout" },
            .{ .name = "Center", .detail = "Centered container" },
            .{ .name = "Box", .detail = "Generic container" },
            .{ .name = "Text", .detail = "Text element" },
            .{ .name = "TextFmt", .detail = "Formatted text" },
            .{ .name = "Button", .detail = "Button component" },
            .{ .name = "TextField", .detail = "Text input" },
            .{ .name = "TextArea", .detail = "Multiline input" },
            .{ .name = "Icon", .detail = "Icon element" },
            .{ .name = "Image", .detail = "Image element" },
            .{ .name = "Page", .detail = "Register page route" },
            .{ .name = "Kit", .detail = "Utilities namespace" },
            .{ .name = "Types", .detail = "Type definitions" },
            .{ .name = "Animation", .detail = "Animation builder" },
            .{ .name = "Event", .detail = "Event type" },
            .{ .name = "Clipboard", .detail = "Clipboard API" },
            .{ .name = "Static", .detail = "Static utilities" },
            .{ .name = "persist", .detail = "Persistent arena" },
            .{ .name = "frame", .detail = "Frame arena" },
            .{ .name = "view", .detail = "View arena" },
            .{ .name = "arena", .detail = "Get arena by scope" },
            .{ .name = "onEnd", .detail = "Run after frame" },
            .{ .name = "cycle", .detail = "Trigger re-render" },
            .{ .name = "init", .detail = "Initialize Vapor" },
            .{ .name = "isDesktop", .detail = "Desktop check" },
            .{ .name = "Binded", .detail = "Bound element ref" },
            .{ .name = "Draggable", .detail = "Draggable handler" },
            .{ .name = "Array", .detail = "Managed array type" },
            .{ .name = "Divider", .detail = "Divider line" },
            .{ .name = "Iframe", .detail = "Iframe embed" },
            .{ .name = "Wasm", .detail = "Wasm utilities" },
        };
        for (items) |item| self.addSuggestion(item.name, .vapor_component, item.detail);
    }

    fn addDotCompletions(self: *Self) void {
        const methods = [_]struct { name: []const u8, detail: []const u8 }{
            .{ .name = "width", .detail = "Set width" },
            .{ .name = "height", .detail = "Set height" },
            .{ .name = "size", .detail = "Set size" },
            .{ .name = "background", .detail = "Set background" },
            .{ .name = "padding", .detail = "Set padding" },
            .{ .name = "margin", .detail = "Set margin" },
            .{ .name = "spacing", .detail = "Gap between children" },
            .{ .name = "layout", .detail = "Set layout alignment" },
            .{ .name = "border", .detail = "Set border" },
            .{ .name = "radius", .detail = "Border radius" },
            .{ .name = "font", .detail = "(size, weight, color)" },
            .{ .name = "fontSize", .detail = "Font size" },
            .{ .name = "fontWeight", .detail = "Font weight" },
            .{ .name = "fontFamily", .detail = "Font family" },
            .{ .name = "bold", .detail = "Bold text" },
            .{ .name = "pointer", .detail = "Cursor pointer" },
            .{ .name = "shadow", .detail = "Box shadow" },
            .{ .name = "scroll", .detail = "Scroll behavior" },
            .{ .name = "pos", .detail = "Position" },
            .{ .name = "zIndex", .detail = "Z-index" },
            .{ .name = "hidden", .detail = "Hide element" },
            .{ .name = "children", .detail = "Add children" },
            .{ .name = "end", .detail = "Commit to tree" },
            .{ .name = "ref", .detail = "Bind element ref" },
            .{ .name = "bind", .detail = "Bind variable" },
            .{ .name = "placeholder", .detail = "Placeholder text" },
            .{ .name = "onChange", .detail = "Change handler" },
            .{ .name = "onEvent", .detail = "Event handler" },
            .{ .name = "hover", .detail = "Hover styles" },
            .{ .name = "hoverScale", .detail = "Scale on hover" },
            .{ .name = "hoverBackground", .detail = "Hover bg color" },
            .{ .name = "hoverText", .detail = "Hover text color" },
            .{ .name = "transition", .detail = "CSS transition" },
            .{ .name = "duration", .detail = "Transition duration" },
            .{ .name = "animationEnter", .detail = "Enter animation" },
            .{ .name = "animationExit", .detail = "Exit animation" },
            .{ .name = "textDecoration", .detail = "Text decoration" },
            .{ .name = "whiteSpace", .detail = "White space mode" },
            .{ .name = "ellipsis", .detail = "Text overflow" },
            .{ .name = "caret", .detail = "Caret style" },
            .{ .name = "cursor", .detail = "Cursor style" },
            .{ .name = "outline", .detail = "Outline style" },
            .{ .name = "resize", .detail = "Resize behavior" },
            .{ .name = "id", .detail = "Element ID" },
        };
        for (methods) |m| self.addSuggestion(m.name, .vapor_method, m.detail);

        self.addSuggestion("px", .vapor_layout, "Pixels");
        self.addSuggestion("percent", .vapor_layout, "Percentage");
        self.addSuggestion("expand", .vapor_layout, "Fill available");
        self.addSuggestion("fit", .vapor_layout, "Fit content");
        self.addSuggestion("hex", .vapor_layout, "Hex color");
        self.addSuggestion("white", .vapor_layout, "White");
        self.addSuggestion("black", .vapor_layout, "Black");
        self.addSuggestion("transparent", .vapor_layout, "Transparent");
        self.addSuggestion("palette", .vapor_layout, "Theme palette");
        self.addSuggestion("none", .vapor_layout, "None");
    }

    fn addSizingValues(self: *Self) void {
        self.addSuggestion(".px()", .vapor_method, "Pixels");
        self.addSuggestion(".percent(100)", .vapor_method, "Percentage");
        self.addSuggestion(".percent(50)", .vapor_method, "Half");
        self.addSuggestion(".expand", .vapor_method, "Fill available");
        self.addSuggestion(".fit", .vapor_method, "Fit content");
        self.addSuggestion(".full", .vapor_method, "100% both axes");
        self.addSuggestion(".grow", .vapor_method, "Grow to fill");
    }

    fn addColorValues(self: *Self) void {
        self.addSuggestion(".hex(\"#\")", .vapor_method, "Hex color");
        self.addSuggestion(".white", .vapor_method, "White");
        self.addSuggestion(".black", .vapor_method, "Black");
        self.addSuggestion(".transparent", .vapor_method, "Transparent");
        self.addSuggestion(".palette(.tint)", .vapor_method, "Theme tint");
        self.addSuggestion(".palette(.text_color)", .vapor_method, "Theme text");
        self.addSuggestion(".palette(.background)", .vapor_method, "Theme bg");
        self.addSuggestion(".transparentize(.black, 0.5)", .vapor_method, "Semi-transparent");
    }

    fn addLayoutValues(self: *Self) void {
        const layouts = [_][]const u8{
            ".center",           ".left_center",   ".right_center",
            ".top_left",         ".top_center",    ".top_right",
            ".bottom_left",      ".bottom_center", ".bottom_right",
            ".x_between_center", ".x_between_top",
        };
        for (layouts) |l| self.addSuggestion(l, .vapor_layout, "Layout");
    }

    fn addPaddingValues(self: *Self) void {
        self.addSuggestion(".all()", .vapor_method, "All sides");
        self.addSuggestion(".xy(,)", .vapor_method, "Horizontal, vertical");
        self.addSuggestion(".tblr(,,,)", .vapor_method, "Top, bottom, left, right");
        self.addSuggestion(".horizontal()", .vapor_method, "Left and right");
        self.addSuggestion(".top()", .vapor_method, "Top only");
    }

    fn addBorderValues(self: *Self) void {
        self.addSuggestion(".none", .vapor_method, "No border");
        self.addSuggestion(".simple(.palette(.border_color))", .vapor_method, "Simple border");
        self.addSuggestion(".round(.hex(\"\"), .all())", .vapor_method, "Rounded border");
        self.addSuggestion(".bottom(1, .palette(.border_color))", .vapor_method, "Bottom border");
        self.addSuggestion(".top(1, .palette(.border_color))", .vapor_method, "Top border");
    }

    fn addImportTargets(self: *Self) void {
        self.addSuggestion("\"std\"", .snippet, "Standard library");
        self.addSuggestion("\"vapor\"", .snippet, "Vapor framework");
        self.addSuggestion("\"vaporize\"", .snippet, "Vaporize library");
        self.addSuggestion("\"opaque_ui\"", .snippet, "Opaque UI library");
    }

    // ========================================================================
    // Partial word extraction (unchanged)
    // ========================================================================

    fn extractPartialWord(self: *Self, text: []const u8, cursor_pos: usize) void {
        if (cursor_pos == 0 or text.len == 0) {
            self.partial_word = "";
            self.partial_start = 0;
            return;
        }

        const safe_cursor = @min(cursor_pos, text.len);
        var start = safe_cursor;

        while (start > 0) {
            const c = text[start - 1];
            if (std.ascii.isAlphanumeric(c) or c == '_' or c == '@') {
                start -= 1;
            } else break;
        }

        self.partial_start = start;
        self.partial_word = if (start < safe_cursor) text[start..safe_cursor] else "";
    }

    // ========================================================================
    // Filtering & Scoring (unchanged)
    // ========================================================================

    fn filterSuggestions(self: *Self) void {
        self.filtered.clearRetainingCapacity();

        if (self.partial_word.len == 0) {
            const count = @min(self.suggestions.items.len, self.max_suggestions);
            for (self.suggestions.items[0..count]) |s| {
                self.filtered.append(s) catch {};
            }
            self.visible = self.filtered.items.len > 0;
            return;
        }

        var partial_lower_buf: [128]u8 = undefined;
        const partial_len = @min(self.partial_word.len, 128);
        for (self.partial_word[0..partial_len], 0..) |c, i| {
            partial_lower_buf[i] = std.ascii.toLower(c);
        }
        const partial_lower = partial_lower_buf[0..partial_len];

        for (self.suggestions.items) |s| {
            var text_lower_buf: [128]u8 = undefined;
            const text_len = @min(s.text.len, 128);
            for (s.text[0..text_len], 0..) |c, i| {
                text_lower_buf[i] = std.ascii.toLower(c);
            }
            const text_lower = text_lower_buf[0..text_len];

            var suggestion_copy = s;

            if (std.mem.eql(u8, text_lower, partial_lower)) continue;

            if (std.mem.startsWith(u8, text_lower, partial_lower)) {
                // Boost user-defined symbols slightly
                const base: u32 = switch (s.kind) {
                    .field, .user_function, .user_variable, .enum_value => 110,
                    else => 100,
                };
                suggestion_copy.score = base + @as(u32, @intCast(100 -| @min(s.text.len, 100)));
                self.filtered.append(suggestion_copy) catch {};
            } else if (fuzzyMatch(partial_lower, text_lower)) {
                const base: u32 = switch (s.kind) {
                    .field, .user_function, .user_variable, .enum_value => 60,
                    else => 50,
                };
                suggestion_copy.score = base + @as(u32, @intCast(50 -| @min(s.text.len, 50)));
                self.filtered.append(suggestion_copy) catch {};
            }
        }

        std.mem.sort(Suggestion, self.filtered.items, {}, struct {
            fn lessThan(_: void, a: Suggestion, b: Suggestion) bool {
                return a.score > b.score;
            }
        }.lessThan);

        if (self.filtered.items.len > self.max_suggestions) {
            self.filtered.shrinkRetainingCapacity(self.max_suggestions);
        }

        self.visible = self.filtered.items.len > 0;
    }

    // ========================================================================
    // Public Interface (unchanged)
    // ========================================================================

    pub fn update(self: *Self, text: []const u8, cursor_pos: usize, x: f32, y: f32) void {
        self.cursor_x = x;
        self.cursor_y = y;
        self.generateSuggestions(text, cursor_pos);
        self.visible = self.filtered.items.len > 0;
        self.selected_index = 0;
    }

    pub fn show(self: *Self, text: []const u8, cursor_pos: usize, x: f32, y: f32) void {
        self.update(text, cursor_pos, x, y);
        self.visible = true;
    }

    pub fn hide(self: *Self) void {
        self.visible = false;
        self.selected_index = 0;
    }

    pub fn moveUp(self: *Self) void {
        if (self.selected_index > 0) {
            self.selected_index -= 1;
        } else if (self.filtered.items.len > 0) {
            self.selected_index = self.filtered.items.len - 1;
        }
    }

    pub fn moveDown(self: *Self) void {
        if (self.filtered.items.len > 0) {
            self.selected_index = (self.selected_index + 1) % self.filtered.items.len;
        }
    }

    pub fn getSelected(self: *Self) ?Suggestion {
        if (self.filtered.items.len == 0) return null;
        return self.filtered.items[self.selected_index];
    }

    pub fn getInsertText(self: *Self) ?[]const u8 {
        const selected = self.getSelected() orelse return null;
        return selected.insert_text orelse selected.text;
    }

    pub fn getPartialStart(self: *Self) usize {
        return self.partial_start;
    }

    // ========================================================================
    // Rendering (updated with new kind colors/icons)
    // ========================================================================

    pub fn render(self: *Self) void {
        if (!self.visible or self.filtered.items.len == 0) return;

        const dropdown_width: f32 = 320; // slightly wider for type info
        const item_height: f32 = 30;
        const visible_count = @min(self.filtered.items.len, 8);
        const max_height: f32 = item_height * @as(f32, @floatFromInt(visible_count));
        const pad: f32 = 4;

        Stack()
            .pos(.tl(.px(self.cursor_y + 24), .px(self.cursor_x), .absolute))
            .height(.px(max_height + pad * 2))
            .width(.px(dropdown_width))
            .background(.hex("#1e1e1e"))
            .border(.{ .thickness = .all(1), .color = .hex("#3d3d3d"), .style = .solid })
            .radius(.all(6))
            .padding(.all(pad))
            .scroll(.scroll_y())
            .zIndex(1000)
            .children({
            for (self.filtered.items, 0..) |suggestion, idx| {
                const is_selected = idx == self.selected_index;

                Row()
                    .height(.px(item_height))
                    .width(.percent(100))
                    .layout(.left_center)
                    .padding(.xy(8, 4))
                    .background(if (is_selected) .transparentize(.hex("#C2FE0A"), 0.3) else .transparent)
                    .radius(.all(4))
                    .pointer()
                    .hover(.{
                    .background = if (is_selected) .hex("#094771") else .hex("#2a2a2a"),
                }).children({
                    // Kind badge
                    Box()
                        .size(.square_px(20))
                        .layout(.center)
                        .radius(.all(3))
                        .margin(.r(8))
                        .children({
                        Icon(suggestion.kind.icon())
                            .font(12, 600, suggestion.kind.color())
                            .end();
                    });

                    // Suggestion text
                    Box()
                        .size(.{ .width = .grow, .height = .percent(100) })
                        .layout(.left_center)
                        .children({
                        Text(suggestion.text)
                            .fontFamily("DM Mono, monospace")
                            .font(13, if (is_selected) 500 else 400, .hex("#e0e0e0"))
                            .end();
                    });

                    // Kind label
                    Text(suggestion.kind.label())
                        .font(10, 400, .hex("#666666"))
                        .margin(.l(8))
                        .end();

                    // Detail (type info)
                    if (suggestion.detail) |detail| {
                        Text(detail)
                            .font(10, 400, .hex("#555555"))
                            .margin(.l(4))
                            .end();
                    }
                });
            }
        });

        // Hint bar
        Box()
            .pos(.tl(.px(self.cursor_y + 24 + max_height + pad * 2 + 4), .px(self.cursor_x), .absolute))
            .size(.{ .width = .px(dropdown_width), .height = .px(22) })
            .layout(.center)
            .background(.hex("#252525"))
            .radius(.all(4))
            .zIndex(1000)
            .children({
            Text("↑↓ navigate · Tab accept · Esc dismiss")
                .font(10, 400, .hex("#555555"))
                .end();
        });
    }
};

// ============================================================================
// Helpers
// ============================================================================

fn fuzzyMatch(pattern: []const u8, text: []const u8) bool {
    if (pattern.len == 0) return true;
    if (pattern.len > text.len) return false;

    var pi: usize = 0;
    for (text) |c| {
        if (c == pattern[pi]) {
            pi += 1;
            if (pi == pattern.len) return true;
        }
    }
    return false;
}
