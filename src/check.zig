//! Compile-only gate: `zig build check` references every public declaration
//! of every route, so the compiler type-checks code no page reaches yet.
//! Zig only compiles what is used, so a route whose init is commented out
//! in main.zig would otherwise rot unnoticed. Add new route files below.
//! Left out: src/auth/ (the Codex command-line client; the app reaches only
//! chat.callCodex, through api.zig), the *_sample.zig files (playground
//! text, @embedFile'd) and routes/Playground.zig (an old copy main.zig no
//! longer imports).

const std = @import("std");

const files = .{
    @import("routes/Assembler.zig"),
    @import("routes/Planner.zig"),
    @import("routes/Playground_state_switch.zig"),
    @import("routes/Settings.zig"),
    @import("routes/api.zig"),
    @import("routes/auth/callback/Page.zig"),
    @import("routes/auth/login/Page.zig"),
    @import("routes/backend.zig"),
    @import("routes/data.zig"),
    @import("routes/zig_autocomplete.zig"),
    @import("routes/zig_semantic.zig"),
};

/// References every public declaration of `T`, recursing into the route
/// files' own container types. Generic functions are only named.
fn refAll(comptime T: type, comptime depth: usize) void {
    if (depth == 0) return;
    @setEvalBranchQuota(200_000);
    inline for (comptime std.meta.declarations(T)) |decl| {
        const Value = @TypeOf(@field(T, decl.name));
        if (Value == type) {
            const Decl = @field(T, decl.name);
            switch (@typeInfo(Decl)) {
                .@"struct", .@"enum", .@"union", .@"opaque" => {
                    if (comptime std.mem.startsWith(u8, @typeName(Decl), "routes.")) refAll(Decl, depth - 1);
                },
                else => {},
            }
            continue;
        }
        switch (@typeInfo(Value)) {
            .@"fn" => |info| {
                if (info.is_generic or info.is_var_args) {
                    _ = @field(T, decl.name);
                } else {
                    _ = &@field(T, decl.name);
                }
            },
            else => _ = @field(T, decl.name),
        }
    }
}

export fn __assembler_check() void {
    inline for (files) |file| refAll(file, 4);
}
