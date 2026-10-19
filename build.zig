const std = @import("std");

fn generateHtml(
    b: *std.Build,
    static: bool,
    atomic: bool,
    build_options_module: *std.Build.Module,
) *std.Build.Step {
    const target = b.graph.host;

    const optimize = std.builtin.OptimizeMode.Debug;

    // ---------------------
    //  Local modules
    // ---------------------
    const config_module = b.addModule("config", .{
        .root_source_file = b.path("src/config.zig"),
        .optimize = optimize,
    });

    // ---------------------
    //  Dependencies
    // ---------------------

    // Vapor — core framework
    const vapor_dep = b.dependency("vapor", .{
        .target = target,
        .optimize = optimize,
        .static = static,
        .atomic = atomic,
    });
    const vapor_module = vapor_dep.module("vapor");
    vapor_module.addImport("config", config_module);

    // Theme — styling layer (depends on vapor)
    const theme_module = b.addModule("theme", .{
        .root_source_file = b.path("src/Theme.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{
            .{ .name = "vapor", .module = vapor_module },
        },
    });
    vapor_module.addImport("theme", theme_module);

    // Vaporize — utility layer (depends on vapor)
    const vaporize_dep = b.dependency("vaporize", .{
        .target = target,
        .optimize = optimize,
    });
    const vaporize_module = vaporize_dep.module("vaporize");
    vaporize_module.addImport("vapor", vapor_module);

    // Opaque UI — component library (depends on vapor, theme, config)
    const opaque_ui_dep = b.dependency("opaque_ui", .{
        .target = target,
        .optimize = optimize,
    });
    const opaque_ui_module = opaque_ui_dep.module("opaque_ui");
    opaque_ui_module.addImport("vapor", vapor_module);
    opaque_ui_module.addImport("theme", theme_module);
    opaque_ui_module.addImport("config", config_module);

    const generator_mod = b.createModule(.{
        .root_source_file = b.path("src/generator.zig"),
        .target = target,
        .optimize = .Debug,
        .imports = &.{
            .{ .name = "vapor", .module = vapor_module },
            .{ .name = "theme", .module = theme_module }, // ADD THIS
            .{ .name = "config", .module = config_module },
            .{ .name = "vaporize", .module = vaporize_module },
            .{ .name = "opaque_ui", .module = opaque_ui_module },
            .{ .name = "build_options", .module = build_options_module },
        },
    });

    const generator_exe = b.addExecutable(.{
        .name = "generator",
        .root_module = generator_mod,
    });

    const run = b.addRunArtifact(generator_exe);
    return &run.step;
}

pub fn build(b: *std.Build) void {
    // ---------------------
    //  Build options
    // ---------------------
    const generate = b.option(bool, "generate", "Generate HTML") orelse false;
    const static = b.option(bool, "static", "Statically link the wasm module") orelse false;
    const atomic = b.option(bool, "atomic", "Atomically link the wasm module") orelse false;
    const backend_base_url = b.option([]const u8, "backend_base_url", "Backend base URL for client fetches (e.g. http://localhost:8080, https://api.example.com, or empty for same-origin)") orelse "http://localhost:8080";
    const optimize = b.standardOptimizeOption(.{});

    const wasm_target = b.standardTargetOptions(.{
        .default_target = .{ .cpu_arch = .wasm32, .os_tag = .wasi },
    });

    const build_options = b.addOptions();
    build_options.addOption([]const u8, "backend_base_url", backend_base_url);
    const build_options_module = build_options.createModule();

    // ---------------------
    //  Local modules
    // ---------------------
    const config_module = b.addModule("config", .{
        .root_source_file = b.path("src/config.zig"),
        .target = wasm_target,
        .optimize = optimize,
    });

    // ---------------------
    //  Dependencies
    // ---------------------

    // Vapor — core framework
    const vapor_dep = b.dependency("vapor", .{
        .target = wasm_target,
        .optimize = optimize,
        .static = static,
        .atomic = atomic,
    });
    const vapor_module = vapor_dep.module("vapor");
    vapor_module.addImport("config", config_module);

    // Theme — styling layer (depends on vapor)
    const theme_module = b.addModule("theme", .{
        .root_source_file = b.path("src/Theme.zig"),
        .target = wasm_target,
        .optimize = optimize,
        .imports = &.{
            .{ .name = "vapor", .module = vapor_module },
        },
    });
    vapor_module.addImport("theme", theme_module);

    // Vaporize — utility layer (depends on vapor)
    const vaporize_dep = b.dependency("vaporize", .{
        .target = wasm_target,
        .optimize = optimize,
    });
    const vaporize_module = vaporize_dep.module("vaporize");
    vaporize_module.addImport("vapor", vapor_module);

    // Opaque UI — component library (depends on vapor, theme, config)
    const opaque_ui_dep = b.dependency("opaque_ui", .{
        .target = wasm_target,
        .optimize = optimize,
    });
    const opaque_ui_module = opaque_ui_dep.module("opaque_ui");
    opaque_ui_module.addImport("vapor", vapor_module);
    opaque_ui_module.addImport("theme", theme_module);
    opaque_ui_module.addImport("config", config_module);

    // ---------------------
    //  Executable
    // ---------------------
    const exe_mod = b.createModule(.{
        .root_source_file = b.path("src/main.zig"),
        .target = wasm_target,
        .optimize = optimize,
        .imports = &.{
            .{ .name = "vapor", .module = vapor_module },
            .{ .name = "theme", .module = theme_module },
            .{ .name = "config", .module = config_module },
            .{ .name = "vaporize", .module = vaporize_module },
            .{ .name = "opaque_ui", .module = opaque_ui_module },
            .{ .name = "build_options", .module = build_options_module },
        },
    });

    const exe = b.addExecutable(.{
        .name = "vapor",
        .root_module = exe_mod,
    });

    // ---------------------
    //  Memory stack size
    // ---------------------
    exe.stack_size = 4 * 1024 * 1024;

    // ---------------------
    //  Disabling main entry point
    // ---------------------
    exe.entry = .disabled;

    // ---------------------
    //  Export all extern functions
    // ---------------------
    exe.rdynamic = true;

    b.installArtifact(exe);

    // ---------------------
    //  Run step
    // ---------------------
    const run_cmd = b.addRunArtifact(exe);
    run_cmd.step.dependOn(b.getInstallStep());

    if (b.args) |args| {
        run_cmd.addArgs(args);
    }

    const run_step = b.step("run", "Run the app");
    run_step.dependOn(&run_cmd.step);

    // Optional: wire up the HTML generator before compilation
    if (generate) {
        const gen_step = generateHtml(b, static, atomic, build_options_module);
        exe.step.dependOn(gen_step);
    }
}
