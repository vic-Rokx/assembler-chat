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
            .{ .name = "keystone", .module = vapor_dep.module("keystone") },
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

    // The playground's frame runs other people's builds, so it gets an
    // origin of its own: from there it cannot read this app's storage,
    // where users keep their API keys.
    const playground_url = b.option([]const u8, "playground_url", "URL of playground.html, served from an origin other than the app's (e.g. https://play.example.com/playground.html)") orelse "http://localhost:5174/playground.html";
    const build_options = b.addOptions();
    build_options.addOption([]const u8, "backend_base_url", backend_base_url);
    build_options.addOption([]const u8, "playground_url", playground_url);
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
    const app_imports: []const std.Build.Module.Import = &.{
        .{ .name = "vapor", .module = vapor_module },
        .{ .name = "theme", .module = theme_module },
        .{ .name = "config", .module = config_module },
        .{ .name = "vaporize", .module = vaporize_module },
        .{ .name = "opaque_ui", .module = opaque_ui_module },
        .{ .name = "build_options", .module = build_options_module },
        .{ .name = "keystone", .module = vapor_dep.module("keystone") },
    };

    const exe_mod = b.createModule(.{
        .root_source_file = b.path("src/main.zig"),
        .target = wasm_target,
        .optimize = optimize,
        .imports = app_imports,
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

    // vapor's JS runtime, served beside the wasm.
    b.getInstallStep().dependOn(&b.addInstallBinFile(vapor_dep.namedLazyPath("runtime"), "bundle.min.js").step);
    b.getInstallStep().dependOn(&b.addInstallBinFile(vapor_dep.namedLazyPath("runtime-browser"), "browser.min.js").step);

    // ---------------------
    //  Site: zig-out/site/, what a static host serves
    // ---------------------
    // The app: index.html for every route (404.html too, for hosts that
    // fall back to it), the runtime and the wasm where they are loaded
    // from. playground.html is for the frame's origin (`playground_url`),
    // which can serve this same folder.
    const site_step = b.step("site", "Assemble zig-out/site/ for a static host (the app, and playground.html for the frame's origin)");
    const site_dir: std.Build.InstallDir = .{ .custom = "site" };
    for ([_][]const u8{ "index.html", "404.html" }) |name| {
        site_step.dependOn(&b.addInstallFileWithDir(b.path("template.html"), site_dir, name).step);
    }
    site_step.dependOn(&b.addInstallFileWithDir(vapor_dep.namedLazyPath("runtime"), site_dir, "bundle.min.js").step);
    site_step.dependOn(&b.addInstallFileWithDir(vapor_dep.namedLazyPath("runtime-browser"), site_dir, "browser.min.js").step);
    site_step.dependOn(&b.addInstallFileWithDir(exe.getEmittedBin(), site_dir, "zig-out/bin/vapor.wasm").step);
    site_step.dependOn(&b.addInstallFileWithDir(b.path("playground.html"), site_dir, "playground.html").step);
    site_step.dependOn(&b.addInstallFileWithDir(b.path("robots.txt"), site_dir, "robots.txt").step);
    site_step.dependOn(&b.addInstallDirectory(.{
        .source_dir = b.path("assets"),
        .install_dir = site_dir,
        .install_subdir = "assets",
        .exclude_extensions = &.{".DS_Store"},
    }).step);

    // ---------------------
    //  Check: compiles every route, used or not (src/check.zig)
    // ---------------------
    const check_obj = b.addObject(.{
        .name = "assembler-check",
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/check.zig"),
            .target = wasm_target,
            .optimize = optimize,
            .imports = app_imports,
        }),
    });
    const check_step = b.step("check", "Type-check every route, including ones no page uses yet");
    check_step.dependOn(&check_obj.step);

    // ---------------------
    //  Unit tests: logic that needs no browser, run on the host
    // ---------------------
    const unit_tests = b.addTest(.{
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/routes/diagnostics.zig"),
            .target = b.graph.host,
            .optimize = optimize,
        }),
    });
    const test_step = b.step("test", "Run the unit tests");
    test_step.dependOn(&b.addRunArtifact(unit_tests).step);

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
