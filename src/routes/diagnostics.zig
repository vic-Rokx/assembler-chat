//! The playground's compile errors, read from the backend's 500 body:
//!
//!     src/main.zig:5:5: error: use of undeclared identifier 'notDeclared'
//!         notDeclared();
//!         ^~~~~~~~~~~
//!
//! Only what points into the editor's file is returned: an error inside
//! vapor's own sources has no line in the editor to mark, though a note
//! in `src/main.zig` usually says which call led there.
const std = @import("std");

pub const Diagnostic = struct {
    kind: enum { @"error", note },
    /// 1-based, like the editor's tokens.
    line: usize,
    column: usize,
    message: []const u8,
};

pub fn iterate(body: []const u8) Iterator {
    return .{ .lines = std.mem.splitScalar(u8, body, '\n') };
}

pub const Iterator = struct {
    lines: std.mem.SplitIterator(u8, .scalar),

    pub fn next(it: *Iterator) ?Diagnostic {
        while (it.lines.next()) |line| {
            if (parse(std.mem.trimEnd(u8, line, "\r"))) |diagnostic| return diagnostic;
        }
        return null;
    }
};

const editor_file = "src/main.zig:";

fn parse(line: []const u8) ?Diagnostic {
    if (!std.mem.startsWith(u8, line, editor_file)) return null;
    var parts = std.mem.splitScalar(u8, line[editor_file.len..], ':');
    const line_number = std.fmt.parseInt(usize, parts.next() orelse return null, 10) catch return null;
    const column = std.fmt.parseInt(usize, parts.next() orelse return null, 10) catch return null;
    const rest = parts.rest();
    inline for (.{ .@"error", .note }) |kind| {
        const label = " " ++ @tagName(kind) ++ ": ";
        if (std.mem.startsWith(u8, rest, label)) {
            return .{ .kind = kind, .line = line_number, .column = column, .message = rest[label.len..] };
        }
    }
    return null;
}

const testing = std.testing;

test "every error and note in the editor's file, in order, past line 255" {
    var it = iterate(
        \\src/main.zig:5:5: error: use of undeclared identifier 'notDeclared'
        \\    notDeclared();
        \\    ^~~~~~~~~~~
        \\zig-pkg/vapor-3.1.2/src/lib/Shadow.zig:1:1: note: struct declared here
        \\src/main.zig:300:17: error: expected type 'u32', found 'bool'
        \\src/main.zig:12:9: note: called from here
    );
    const expected = [_]Diagnostic{
        .{ .kind = .@"error", .line = 5, .column = 5, .message = "use of undeclared identifier 'notDeclared'" },
        .{ .kind = .@"error", .line = 300, .column = 17, .message = "expected type 'u32', found 'bool'" },
        .{ .kind = .note, .line = 12, .column = 9, .message = "called from here" },
    };
    for (expected) |want| {
        const got = it.next() orelse return error.TooFew;
        try testing.expectEqual(want.kind, got.kind);
        try testing.expectEqual(want.line, got.line);
        try testing.expectEqual(want.column, got.column);
        try testing.expectEqualStrings(want.message, got.message);
    }
    try testing.expectEqual(@as(?Diagnostic, null), it.next());
}

test "bodies without a located diagnostic give none" {
    for ([_][]const u8{
        "error: the build took too long and was stopped",
        "error: too many builds are running; try again shortly",
        "src/main.zig:x:5: error: not a number",
        "src/main.zig:5:5: warning: not an error",
        "",
    }) |body| {
        var it = iterate(body);
        try testing.expectEqual(@as(?Diagnostic, null), it.next());
    }
}
