// ============================================================================
// ZIG SEMANTIC ANALYZER — Lightweight type extraction for playground autocomplete
// ============================================================================
//
// This module scans user code to extract:
//   - Struct definitions (fields, methods, nested types)
//   - Enum definitions (values)
//   - Variable/constant declarations with their types
//   - Function declarations (params, return types)
//   - Import aliases
//
// It then resolves dot-completion chains:  `myVar.field.subfield`
// by walking the type graph built from the source.
//
// This is NOT a full Zig compiler — it's heuristic parsing designed
// to be "good enough" for a playground autocomplete experience.
// ============================================================================

const std = @import("std");
const Allocator = std.mem.Allocator;

// ============================================================================
// Data Types
// ============================================================================

pub const FieldInfo = struct {
    name: []const u8,
    type_name: []const u8, // e.g. "u32", "[]const u8", "MyStruct", "?MyType"
    default_value: ?[]const u8 = null,
    doc: ?[]const u8 = null,
};

pub const MethodInfo = struct {
    name: []const u8,
    params: []const ParamInfo,
    return_type: []const u8,
    is_public: bool,
    doc: ?[]const u8 = null,
};

pub const ParamInfo = struct {
    name: []const u8,
    type_name: []const u8,
};

pub const EnumValue = struct {
    name: []const u8,
    doc: ?[]const u8 = null,
};

pub const TypeKind = enum {
    struct_type,
    enum_type,
    union_type,
    alias, // const Foo = Bar;
    import, // const std = @import("std");
    primitive,
    unknown,
};

pub const TypeInfo = struct {
    name: []const u8,
    kind: TypeKind,
    fields: []const FieldInfo,
    methods: []const MethodInfo,
    enum_values: []const EnumValue,
    is_public: bool,
    /// For aliases: the target type name
    alias_target: ?[]const u8 = null,
};

pub const VarInfo = struct {
    name: []const u8,
    type_name: []const u8, // resolved type name, e.g. "MyStruct"
    is_const: bool,
    scope_depth: usize, // 0 = top-level
};

pub const FnInfo = struct {
    name: []const u8,
    params: []const ParamInfo,
    return_type: []const u8,
    is_public: bool,
};

pub const CompletionItem = struct {
    label: []const u8,
    kind: CompletionKind,
    detail: ?[]const u8 = null,
    insert_text: ?[]const u8 = null,
};

pub const CompletionKind = enum {
    field,
    method,
    enum_value,
    variable,
    constant,
    function,
    type_name,
    module,
    keyword,
    snippet,
};

// ============================================================================
// Semantic Analyzer
// ============================================================================

pub const ZigSemanticAnalyzer = struct {
    allocator: Allocator,
    types: std.StringHashMap(TypeInfo),
    variables: std.array_list.Managed(VarInfo),
    functions: std.array_list.Managed(FnInfo),
    /// Scratch buffer for intermediate parsing
    scratch: std.array_list.Managed(u8),

    const Self = @This();

    pub fn init(allocator: Allocator) Self {
        return .{
            .allocator = allocator,
            .types = std.StringHashMap(TypeInfo).init(allocator),
            .variables = std.array_list.Managed(VarInfo).init(allocator),
            .functions = std.array_list.Managed(FnInfo).init(allocator),
            .scratch = std.array_list.Managed(u8).init(allocator),
        };
    }

    pub fn deinit(self: *Self) void {
        self.types.deinit();
        self.variables.deinit();
        self.functions.deinit();
        self.scratch.deinit();
    }

    // ========================================================================
    // Full analysis pass — call this after every edit (or debounced)
    // ========================================================================

    pub fn analyze(self: *Self, source: []const u8) void {
        self.types.clearRetainingCapacity();
        self.variables.clearRetainingCapacity();
        self.functions.clearRetainingCapacity();

        var pos: usize = 0;
        var scope_depth: usize = 0;

        while (pos < source.len) {
            // Track brace depth for scope
            if (source[pos] == '{') {
                scope_depth += 1;
                pos += 1;
                continue;
            }
            if (source[pos] == '}') {
                if (scope_depth > 0) scope_depth -= 1;
                pos += 1;
                continue;
            }

            // Skip comments
            if (pos + 1 < source.len and source[pos] == '/' and source[pos + 1] == '/') {
                pos = skipToEndOfLine(source, pos);
                continue;
            }

            // Skip string literals
            if (source[pos] == '"') {
                pos = skipString(source, pos);
                continue;
            }

            // Skip char literals
            if (source[pos] == '\'') {
                pos = skipCharLiteral(source, pos);
                continue;
            }

            // Try to parse declarations at any scope level
            const is_pub = matchKeyword(source, pos, "pub");
            const decl_start = if (is_pub) skipWhitespace(source, pos + 3) else pos;

            // const/var declarations
            if (matchKeyword(source, decl_start, "const") or matchKeyword(source, decl_start, "var")) {
                const is_const = matchKeyword(source, decl_start, "const");
                const after_kw = skipWhitespace(source, decl_start + (if (is_const) @as(usize, 5) else 3));
                const name_end = scanIdentifier(source, after_kw);

                if (name_end > after_kw) {
                    const name = source[after_kw..name_end];
                    const after_name = skipWhitespace(source, name_end);

                    // Check for type annotation: `const foo: Type = ...`
                    var type_name: []const u8 = "";
                    var after_type = after_name;

                    if (after_name < source.len and source[after_name] == ':') {
                        const type_start = skipWhitespace(source, after_name + 1);
                        const type_end = scanTypeExpression(source, type_start);
                        if (type_end > type_start) {
                            type_name = source[type_start..type_end];
                        }
                        after_type = skipWhitespace(source, type_end);
                    }

                    // Check for `= struct { ... }` or `= enum { ... }` or `= @import(...)`
                    if (after_type < source.len and source[after_type] == '=') {
                        const rhs_start = skipWhitespace(source, after_type + 1);

                        if (matchKeyword(source, rhs_start, "struct")) {
                            const struct_body_start = findChar(source, rhs_start, '{');
                            if (struct_body_start) |sbs| {
                                const struct_body_end = findMatchingBrace(source, sbs);
                                if (struct_body_end) |sbe| {
                                    self.parseStructBody(name, source[sbs + 1 .. sbe], is_pub);
                                    pos = sbe + 1;
                                    continue;
                                }
                            }
                        } else if (matchKeyword(source, rhs_start, "enum")) {
                            const enum_body_start = findChar(source, rhs_start, '{');
                            if (enum_body_start) |ebs| {
                                const enum_body_end = findMatchingBrace(source, ebs);
                                if (enum_body_end) |ebe| {
                                    self.parseEnumBody(name, source[ebs + 1 .. ebe], is_pub);
                                    pos = ebe + 1;
                                    continue;
                                }
                            }
                        } else if (matchKeyword(source, rhs_start, "union")) {
                            const union_body_start = findChar(source, rhs_start, '{');
                            if (union_body_start) |ubs| {
                                const union_body_end = findMatchingBrace(source, ubs);
                                if (union_body_end) |ube| {
                                    self.parseStructBody(name, source[ubs + 1 .. ube], is_pub);
                                    pos = ube + 1;
                                    continue;
                                }
                            }
                        } else if (source.len > rhs_start + 7 and std.mem.startsWith(u8, source[rhs_start..], "@import")) {
                            // const std = @import("std");
                            const paren_start = findChar(source, rhs_start, '(');
                            if (paren_start) |ps| {
                                const paren_end = findChar(source, ps, ')');
                                if (paren_end) |pe| {
                                    const import_content = std.mem.trim(u8, source[ps + 1 .. pe], " \t\"");
                                    self.types.put(name, .{
                                        .name = name,
                                        .kind = .import,
                                        .fields = &.{},
                                        .methods = &.{},
                                        .enum_values = &.{},
                                        .is_public = is_pub,
                                        .alias_target = import_content,
                                    }) catch {};
                                    pos = pe + 1;
                                    continue;
                                }
                            }
                        } else {
                            // const foo = SomeType{ ... } or const foo = expr;
                            // Try to infer type from RHS identifier
                            const rhs_ident_end = scanIdentifier(source, rhs_start);
                            if (rhs_ident_end > rhs_start) {
                                const rhs_ident = source[rhs_start..rhs_ident_end];
                                // Check if next char is `{` — then it's a struct literal
                                const after_rhs_ident = skipWhitespace(source, rhs_ident_end);
                                if (after_rhs_ident < source.len and source[after_rhs_ident] == '{') {
                                    if (type_name.len == 0) {
                                        type_name = rhs_ident;
                                    }
                                } else if (type_name.len == 0) {
                                    // const foo = bar — type is the same as bar's type (maybe)
                                    type_name = rhs_ident;
                                }
                            }
                        }

                        self.variables.append(.{
                            .name = name,
                            .type_name = type_name,
                            .is_const = is_const,
                            .scope_depth = scope_depth,
                        }) catch {};
                    } else if (type_name.len > 0) {
                        // Declaration with type annotation but maybe no initializer (function params extracted elsewhere)
                        self.variables.append(.{
                            .name = name,
                            .type_name = type_name,
                            .is_const = is_const,
                            .scope_depth = scope_depth,
                        }) catch {};
                    }
                }
            }

            // fn declarations
            if (matchKeyword(source, decl_start, "fn")) {
                const after_fn = skipWhitespace(source, decl_start + 2);
                const fn_name_end = scanIdentifier(source, after_fn);
                if (fn_name_end > after_fn) {
                    const fn_name = source[after_fn..fn_name_end];
                    const params = self.parseFnParams(source, fn_name_end);
                    const return_type = self.parseFnReturnType(source, fn_name_end);

                    self.functions.append(.{
                        .name = fn_name,
                        .params = params,
                        .return_type = return_type,
                        .is_public = is_pub,
                    }) catch {};
                }
            }

            pos += 1;
        }
    }

    // ========================================================================
    // Struct body parser
    // ========================================================================

    fn parseStructBody(self: *Self, name: []const u8, body: []const u8, is_pub: bool) void {
        var fields = std.array_list.Managed(FieldInfo).init(self.allocator);
        var methods = std.array_list.Managed(MethodInfo).init(self.allocator);

        var pos: usize = 0;
        while (pos < body.len) {
            pos = skipWhitespaceAndComments(body, pos);
            if (pos >= body.len) break;

            // Skip nested braces (function bodies, nested structs)
            if (body[pos] == '{') {
                const end = findMatchingBrace(body, pos);
                pos = if (end) |e| e + 1 else pos + 1;
                continue;
            }

            // Check for method: `pub fn` or `fn`
            const method_pub = matchKeyword(body, pos, "pub");
            const method_start = if (method_pub) skipWhitespace(body, pos + 3) else pos;

            if (matchKeyword(body, method_start, "fn")) {
                const after_fn = skipWhitespace(body, method_start + 2);
                const mname_end = scanIdentifier(body, after_fn);
                if (mname_end > after_fn) {
                    const mname = body[after_fn..mname_end];
                    const params = self.parseFnParams(body, mname_end);
                    const ret = self.parseFnReturnType(body, mname_end);
                    methods.append(.{
                        .name = mname,
                        .params = params,
                        .return_type = ret,
                        .is_public = method_pub,
                    }) catch {};

                    // Skip past the function body
                    const fn_body_start = findChar(body, mname_end, '{');
                    if (fn_body_start) |fbs| {
                        const fn_body_end = findMatchingBrace(body, fbs);
                        pos = if (fn_body_end) |fbe| fbe + 1 else fbs + 1;
                    } else {
                        pos = mname_end;
                    }
                    continue;
                }
            }

            // Check for field: `name: Type` or `name: Type = default,`
            const field_name_end = scanIdentifier(body, pos);
            if (field_name_end > pos) {
                const field_name = body[pos..field_name_end];
                const after_field_name = skipWhitespace(body, field_name_end);

                if (after_field_name < body.len and body[after_field_name] == ':') {
                    const type_start = skipWhitespace(body, after_field_name + 1);
                    const type_end = scanFieldType(body, type_start);
                    if (type_end > type_start) {
                        const field_type = body[type_start..type_end];

                        // Check for default value
                        var default: ?[]const u8 = null;
                        const after_type = skipWhitespace(body, type_end);
                        if (after_type < body.len and body[after_type] == '=') {
                            const val_start = skipWhitespace(body, after_type + 1);
                            const val_end = scanUntilCommaOrNewline(body, val_start);
                            if (val_end > val_start) {
                                default = body[val_start..val_end];
                            }
                        }

                        fields.append(.{
                            .name = field_name,
                            .type_name = field_type,
                            .default_value = default,
                        }) catch {};

                        // Advance past the comma
                        pos = scanUntilCommaOrNewline(body, type_end);
                        if (pos < body.len and body[pos] == ',') pos += 1;
                        continue;
                    }
                }
            }

            pos += 1;
        }

        self.types.put(name, .{
            .name = name,
            .kind = .struct_type,
            .fields = fields.toOwnedSlice() catch &.{},
            .methods = methods.toOwnedSlice() catch &.{},
            .enum_values = &.{},
            .is_public = is_pub,
        }) catch {};
    }

    // ========================================================================
    // Enum body parser
    // ========================================================================

    fn parseEnumBody(self: *Self, name: []const u8, body: []const u8, is_pub: bool) void {
        var values = std.array_list.Managed(EnumValue).init(self.allocator);
        var methods = std.array_list.Managed(MethodInfo).init(self.allocator);

        var pos: usize = 0;
        while (pos < body.len) {
            pos = skipWhitespaceAndComments(body, pos);
            if (pos >= body.len) break;

            // Skip nested braces
            if (body[pos] == '{') {
                const end = findMatchingBrace(body, pos);
                pos = if (end) |e| e + 1 else pos + 1;
                continue;
            }

            // Check for method
            const method_pub = matchKeyword(body, pos, "pub");
            const method_start = if (method_pub) skipWhitespace(body, pos + 3) else pos;

            if (matchKeyword(body, method_start, "fn")) {
                const after_fn = skipWhitespace(body, method_start + 2);
                const mname_end = scanIdentifier(body, after_fn);
                if (mname_end > after_fn) {
                    const mname = body[after_fn..mname_end];
                    const params = self.parseFnParams(body, mname_end);
                    const ret = self.parseFnReturnType(body, mname_end);
                    methods.append(.{
                        .name = mname,
                        .params = params,
                        .return_type = ret,
                        .is_public = method_pub,
                    }) catch {};
                    const fn_body_start = findChar(body, mname_end, '{');
                    if (fn_body_start) |fbs| {
                        const fn_body_end = findMatchingBrace(body, fbs);
                        pos = if (fn_body_end) |fbe| fbe + 1 else fbs + 1;
                    } else {
                        pos = mname_end;
                    }
                    continue;
                }
            }

            // Enum value: `.name,` or `name,`
            var val_start = pos;
            if (val_start < body.len and body[val_start] == '.') val_start += 1;

            const val_name_end = scanIdentifier(body, val_start);
            if (val_name_end > val_start) {
                const val_name = body[val_start..val_name_end];
                // Make sure this looks like an enum value (followed by , or = or } or whitespace)
                const after_val = skipWhitespace(body, val_name_end);
                if (after_val >= body.len or body[after_val] == ',' or body[after_val] == '}' or body[after_val] == '=') {
                    values.append(.{ .name = val_name }) catch {};
                }
                pos = scanUntilCommaOrNewline(body, val_name_end);
                if (pos < body.len and body[pos] == ',') pos += 1;
                continue;
            }

            pos += 1;
        }

        self.types.put(name, .{
            .name = name,
            .kind = .enum_type,
            .fields = &.{},
            .methods = methods.toOwnedSlice() catch &.{},
            .enum_values = values.toOwnedSlice() catch &.{},
            .is_public = is_pub,
        }) catch {};
    }

    // ========================================================================
    // Function parameter / return type parsing
    // ========================================================================

    fn parseFnParams(self: *Self, source: []const u8, after_name: usize) []const ParamInfo {
        const paren_start = findChar(source, after_name, '(') orelse return &.{};
        const paren_end = findMatchingParen(source, paren_start) orelse return &.{};
        const params_text = source[paren_start + 1 .. paren_end];

        var params = std.array_list.Managed(ParamInfo).init(self.allocator);
        var iter = std.mem.splitScalar(u8, params_text, ',');
        while (iter.next()) |param_raw| {
            const param = std.mem.trim(u8, param_raw, " \t\n\r");
            if (param.len == 0) continue;

            // param format: `name: Type` or just `Type`
            if (std.mem.indexOf(u8, param, ":")) |colon| {
                const pname = std.mem.trim(u8, param[0..colon], " \t");
                const ptype = std.mem.trim(u8, param[colon + 1 ..], " \t");
                params.append(.{ .name = pname, .type_name = ptype }) catch {};
            } else {
                // Positional type only
                params.append(.{ .name = "_", .type_name = param }) catch {};
            }
        }

        return params.toOwnedSlice() catch &.{};
    }

    fn parseFnReturnType(self: *Self, source: []const u8, after_name: usize) []const u8 {
        _ = self;
        // Find `)` then scan for return type before `{`
        const paren_start = findChar(source, after_name, '(') orelse return "void";
        const paren_end = findMatchingParen(source, paren_start) orelse return "void";

        var pos = skipWhitespace(source, paren_end + 1);

        // Skip optional `!` for error union
        var has_error = false;
        if (pos < source.len and source[pos] == '!') {
            has_error = true;
            pos = skipWhitespace(source, pos + 1);
        }

        // Scan return type identifier
        const ret_start = pos;
        const ret_end = scanTypeExpression(source, ret_start);
        if (ret_end > ret_start) {
            const ret = source[ret_start..ret_end];
            if (has_error) {
                // We'd need allocPrint but let's just return the base type
                return ret;
            }
            return ret;
        }

        return "void";
    }

    // ========================================================================
    // DOT COMPLETION RESOLUTION
    //
    // Given `foo.bar.` at cursor, resolve the chain:
    //   1. Look up `foo` in variables → get its type
    //   2. Look up that type in types → get field `bar` → get bar's type
    //   3. Look up bar's type → return its fields/methods
    // ========================================================================

    pub fn resolveDotChain(self: *Self, source: []const u8, cursor_pos: usize) ?*const TypeInfo {
        // Extract the chain tokens before cursor: e.g. "foo.bar." → ["foo", "bar"]
        const chain = self.extractDotChain(source, cursor_pos);
        if (chain.len == 0) return null;

        // Resolve first token — could be a variable name or a type name
        var current_type: ?*const TypeInfo = null;
        const first = chain[0];

        // Check variables
        for (self.variables.items) |v| {
            if (std.mem.eql(u8, v.name, first)) {
                current_type = self.resolveTypeName(v.type_name);
                break;
            }
        }

        // Check types directly (e.g. `MyStruct.`)
        if (current_type == null) {
            if (self.types.getPtr(first)) |t| {
                current_type = t;
            }
        }

        if (current_type == null) return null;

        // Walk the rest of the chain
        var i: usize = 1;
        while (i < chain.len) : (i += 1) {
            const field_name = chain[i];
            var found = false;

            // Look in fields
            for (current_type.?.fields) |field| {
                if (std.mem.eql(u8, field.name, field_name)) {
                    current_type = self.resolveTypeName(field.type_name);
                    found = true;
                    break;
                }
            }

            if (!found) {
                // Look in methods — return type becomes the new type
                for (current_type.?.methods) |method| {
                    if (std.mem.eql(u8, method.name, field_name)) {
                        current_type = self.resolveTypeName(method.return_type);
                        found = true;
                        break;
                    }
                }
            }

            if (!found or current_type == null) return null;
        }

        return current_type;
    }

    fn resolveTypeName(self: *Self, type_name: []const u8) ?*const TypeInfo {
        // Strip optional `?` prefix
        const clean = if (type_name.len > 0 and type_name[0] == '?')
            type_name[1..]
        else
            type_name;

        // Strip pointer prefixes `*`, `*const`, `[]`, `[]const`
        var stripped = clean;
        if (std.mem.startsWith(u8, stripped, "[]const ")) {
            stripped = stripped[8..];
        } else if (std.mem.startsWith(u8, stripped, "[]")) {
            stripped = stripped[2..];
        } else if (std.mem.startsWith(u8, stripped, "*const ")) {
            stripped = stripped[7..];
        } else if (stripped.len > 0 and stripped[0] == '*') {
            stripped = stripped[1..];
        }

        if (self.types.getPtr(stripped)) |t| {
            // Follow aliases
            if (t.kind == .alias) {
                if (t.alias_target) |target| {
                    return self.resolveTypeName(target);
                }
            }
            return t;
        }

        return null;
    }

    fn extractDotChain(self: *Self, source: []const u8, cursor_pos: usize) []const []const u8 {
        if (cursor_pos == 0) return &.{};
        const safe_pos = @min(cursor_pos, source.len);

        // Walk backwards from cursor, collecting identifiers separated by dots
        var tokens = std.array_list.Managed([]const u8).init(self.allocator);
        var pos = safe_pos;

        // If cursor is right after `.`, skip it
        if (pos > 0 and source[pos - 1] == '.') {
            pos -= 1;
        }

        // Now walk back collecting `identifier.identifier.identifier`
        while (pos > 0) {
            // Scan backwards for identifier end
            const ident_end = pos;
            while (pos > 0 and (std.ascii.isAlphanumeric(source[pos - 1]) or source[pos - 1] == '_')) {
                pos -= 1;
            }
            if (pos == ident_end) break; // no identifier found

            tokens.append(source[pos..ident_end]) catch break;

            // Check for dot before this identifier
            if (pos > 0 and source[pos - 1] == '.') {
                pos -= 1;
            } else {
                break;
            }
        }

        // Reverse the tokens (we collected them right-to-left)
        const items = tokens.toOwnedSlice() catch return &.{};
        std.mem.reverse([]const u8, items);
        return items;
    }

    // ========================================================================
    // Struct literal detection: `T{ .field` → find T, return its fields
    // ========================================================================

    fn findStructLiteralType(self: *Self, source: []const u8, cursor_pos: usize) ?*const TypeInfo {
        // From cursor, scan backwards past the partial word and the dot
        var pos = @min(cursor_pos, source.len);

        // Skip back past partial word (e.g. "na" in ".na")
        while (pos > 0 and (std.ascii.isAlphanumeric(source[pos - 1]) or source[pos - 1] == '_')) {
            pos -= 1;
        }

        // Skip back past the dot
        if (pos > 0 and source[pos - 1] == '.') {
            pos -= 1;
        } else {
            return null;
        }

        // Skip whitespace/newlines/commas (there could be other fields before this one)
        // We need to find the opening `{` at the right brace depth
        var brace_depth: i32 = 0;
        while (pos > 0) {
            pos -= 1;
            const c = source[pos];

            if (c == '}') {
                brace_depth += 1;
            } else if (c == '{') {
                if (brace_depth == 0) {
                    // Found the opening brace — now look for a type name before it
                    var before = pos;
                    // Skip whitespace before {
                    while (before > 0 and (source[before - 1] == ' ' or source[before - 1] == '\t' or source[before - 1] == '\n')) {
                        before -= 1;
                    }

                    // Scan backwards for the type name identifier
                    const ident_end = before;
                    while (before > 0 and (std.ascii.isAlphanumeric(source[before - 1]) or source[before - 1] == '_')) {
                        before -= 1;
                    }

                    if (before < ident_end) {
                        const type_name = source[before..ident_end];
                        return self.resolveTypeName(type_name);
                    }
                    return null;
                }
                brace_depth -= 1;
            }
            // Skip over string literals going backwards (rough heuristic)
            if (c == '"') {
                while (pos > 0 and source[pos - 1] != '"') pos -= 1;
                if (pos > 0) pos -= 1;
            }
        }
        return null;
    }

    // ========================================================================
    // Generate completions for a dot position
    // ========================================================================

    pub fn completionsForDot(self: *Self, source: []const u8, cursor_pos: usize) []const CompletionItem {
        // Try regular dot chain first (e.g. `foo.bar.`)
        var resolved = self.resolveDotChain(source, cursor_pos);

        // If that failed, try struct literal context (e.g. `T{ .field`)
        if (resolved == null) {
            resolved = self.findStructLiteralType(source, cursor_pos);
        }

        const typ = resolved orelse return &.{};

        var items = std.array_list.Managed(CompletionItem).init(self.allocator);

        // Add fields
        for (typ.fields) |field| {
            items.append(.{
                .label = field.name,
                .kind = .field,
                .detail = field.type_name,
            }) catch {};
        }

        // Add methods
        for (typ.methods) |method| {
            items.append(.{
                .label = method.name,
                .kind = .method,
                .detail = method.return_type,
            }) catch {};
        }

        // Add enum values
        for (typ.enum_values) |ev| {
            items.append(.{
                .label = ev.name,
                .kind = .enum_value,
                .detail = typ.name,
            }) catch {};
        }

        return items.toOwnedSlice() catch &.{};
    }

    // ========================================================================
    // Get all user-defined symbols for general completion
    // ========================================================================

    pub fn allUserSymbols(self: *Self) []const CompletionItem {
        var items = std.array_list.Managed(CompletionItem).init(self.allocator);

        // Types
        var type_iter = self.types.iterator();
        while (type_iter.next()) |entry| {
            const t = entry.value_ptr;
            const kind: CompletionKind = switch (t.kind) {
                .struct_type => .type_name,
                .enum_type => .type_name,
                .union_type => .type_name,
                .alias => .type_name,
                .import => .module,
                else => .type_name,
            };
            items.append(.{
                .label = t.name,
                .kind = kind,
                .detail = switch (t.kind) {
                    .struct_type => "struct",
                    .enum_type => "enum",
                    .union_type => "union",
                    .alias => "alias",
                    .import => "import",
                    else => null,
                },
            }) catch {};
        }

        // Variables
        for (self.variables.items) |v| {
            items.append(.{
                .label = v.name,
                .kind = if (v.is_const) .constant else .variable,
                .detail = if (v.type_name.len > 0) v.type_name else null,
            }) catch {};
        }

        // Functions
        for (self.functions.items) |f| {
            items.append(.{
                .label = f.name,
                .kind = .function,
                .detail = f.return_type,
            }) catch {};
        }

        return items.toOwnedSlice() catch &.{};
    }

    // ========================================================================
    // Get completions for enum literal context (`.foo`)
    // e.g. in a function call where the parameter type is a known enum
    // ========================================================================

    pub fn completionsForEnumLiteral(self: *Self) []const CompletionItem {
        var items = std.array_list.Managed(CompletionItem).init(self.allocator);

        // Offer all known enum values from all enum types
        var type_iter = self.types.iterator();
        while (type_iter.next()) |entry| {
            const t = entry.value_ptr;
            if (t.kind == .enum_type) {
                for (t.enum_values) |ev| {
                    items.append(.{
                        .label = ev.name,
                        .kind = .enum_value,
                        .detail = t.name,
                    }) catch {};
                }
            }
        }

        return items.toOwnedSlice() catch &.{};
    }
};

// ============================================================================
// Scanning helpers — simple character-level utilities
// ============================================================================

fn skipWhitespace(source: []const u8, pos: usize) usize {
    var p = pos;
    while (p < source.len and (source[p] == ' ' or source[p] == '\t' or source[p] == '\n' or source[p] == '\r')) {
        p += 1;
    }
    return p;
}

fn skipWhitespaceAndComments(source: []const u8, pos: usize) usize {
    var p = pos;
    while (p < source.len) {
        if (source[p] == ' ' or source[p] == '\t' or source[p] == '\n' or source[p] == '\r') {
            p += 1;
        } else if (p + 1 < source.len and source[p] == '/' and source[p + 1] == '/') {
            p = skipToEndOfLine(source, p);
        } else {
            break;
        }
    }
    return p;
}

fn skipToEndOfLine(source: []const u8, pos: usize) usize {
    var p = pos;
    while (p < source.len and source[p] != '\n') p += 1;
    if (p < source.len) p += 1; // skip the newline
    return p;
}

fn skipString(source: []const u8, pos: usize) usize {
    if (pos >= source.len or source[pos] != '"') return pos;
    var p = pos + 1;
    while (p < source.len) {
        if (source[p] == '\\') {
            p += 2;
            continue;
        }
        if (source[p] == '"') return p + 1;
        p += 1;
    }
    return p;
}

fn skipCharLiteral(source: []const u8, pos: usize) usize {
    if (pos >= source.len or source[pos] != '\'') return pos;
    var p = pos + 1;
    if (p < source.len and source[p] == '\\') p += 1;
    p += 1; // the char itself
    if (p < source.len and source[p] == '\'') p += 1;
    return p;
}

fn scanIdentifier(source: []const u8, pos: usize) usize {
    var p = pos;
    if (p < source.len and (std.ascii.isAlphabetic(source[p]) or source[p] == '_')) {
        p += 1;
        while (p < source.len and (std.ascii.isAlphanumeric(source[p]) or source[p] == '_')) {
            p += 1;
        }
    }
    return p;
}

fn scanTypeExpression(source: []const u8, pos: usize) usize {
    var p = pos;

    // Handle optional `?`
    if (p < source.len and source[p] == '?') p += 1;

    // Handle pointer `*`
    if (p < source.len and source[p] == '*') {
        p += 1;
        // *const
        if (matchKeyword(source, p, "const")) p += 5;
        p = skipWhitespace(source, p);
    }

    // Handle slice `[]` or `[]const`
    if (p + 1 < source.len and source[p] == '[' and source[p + 1] == ']') {
        p += 2;
        if (matchKeyword(source, p, "const")) {
            p += 5;
        }
        p = skipWhitespace(source, p);
    }

    // Handle `!` for error unions
    if (p < source.len and source[p] == '!') p += 1;

    // The actual type identifier
    const ident_start = p;
    p = scanIdentifier(source, p);
    if (p == ident_start) return pos; // no identifier found

    // Handle `.` chained access (e.g. `std.mem.Allocator`)
    while (p < source.len and source[p] == '.') {
        p += 1;
        p = scanIdentifier(source, p);
    }

    return p;
}

fn scanFieldType(source: []const u8, pos: usize) usize {
    // Scan a type expression that ends at `,`, `=`, `}`, or newline
    var p = pos;
    var depth: i32 = 0;

    while (p < source.len) {
        const c = source[p];
        if (c == '(' or c == '[' or c == '{') {
            depth += 1;
        } else if (c == ')' or c == ']' or c == '}') {
            if (depth == 0) break;
            depth -= 1;
        } else if (depth == 0 and (c == ',' or c == '=')) {
            break;
        } else if (depth == 0 and c == '\n') {
            break;
        }
        p += 1;
    }

    // Trim trailing whitespace
    while (p > pos and (source[p - 1] == ' ' or source[p - 1] == '\t')) {
        p -= 1;
    }
    return p;
}

fn scanUntilCommaOrNewline(source: []const u8, pos: usize) usize {
    var p = pos;
    var depth: i32 = 0;
    while (p < source.len) {
        const c = source[p];
        if (c == '(' or c == '{' or c == '[') depth += 1;
        if (c == ')' or c == '}' or c == ']') {
            if (depth == 0) break;
            depth -= 1;
        }
        if (depth == 0 and (c == ',' or c == '\n')) break;
        p += 1;
    }
    return p;
}

fn matchKeyword(source: []const u8, pos: usize, keyword: []const u8) bool {
    if (pos + keyword.len > source.len) return false;
    if (!std.mem.eql(u8, source[pos .. pos + keyword.len], keyword)) return false;
    // Make sure it's not part of a larger identifier
    if (pos + keyword.len < source.len) {
        const next = source[pos + keyword.len];
        if (std.ascii.isAlphanumeric(next) or next == '_') return false;
    }
    return true;
}

fn findChar(source: []const u8, start: usize, char: u8) ?usize {
    var p = start;
    while (p < source.len) {
        if (source[p] == char) return p;
        // Skip strings
        if (source[p] == '"') {
            p = skipString(source, p);
            continue;
        }
        p += 1;
    }
    return null;
}

fn findMatchingBrace(source: []const u8, open_pos: usize) ?usize {
    if (open_pos >= source.len or source[open_pos] != '{') return null;
    var depth: i32 = 1;
    var p = open_pos + 1;
    while (p < source.len and depth > 0) {
        if (source[p] == '"') {
            p = skipString(source, p);
            continue;
        }
        if (source[p] == '\'') {
            p = skipCharLiteral(source, p);
            continue;
        }
        if (p + 1 < source.len and source[p] == '/' and source[p + 1] == '/') {
            p = skipToEndOfLine(source, p);
            continue;
        }
        if (source[p] == '{') depth += 1;
        if (source[p] == '}') depth -= 1;
        if (depth == 0) return p;
        p += 1;
    }
    return null;
}

fn findMatchingParen(source: []const u8, open_pos: usize) ?usize {
    if (open_pos >= source.len or source[open_pos] != '(') return null;
    var depth: i32 = 1;
    var p = open_pos + 1;
    while (p < source.len and depth > 0) {
        if (source[p] == '"') {
            p = skipString(source, p);
            continue;
        }
        if (source[p] == '(') depth += 1;
        if (source[p] == ')') depth -= 1;
        if (depth == 0) return p;
        p += 1;
    }
    return null;
}
