const std = @import("std");
const Vapor = @import("vapor");
const Center = Vapor.Center;
const Button = Vapor.Button;
const Text = Vapor.Text;
const TextFmt = Vapor.TextFmt;
const TextField = Vapor.TextField;
const Heading = Vapor.Heading;
const Chat = @import("routes/Assembler.zig");
const Vaporize = @import("vaporize");
const Theme = @import("theme");
const Opaque = @import("opaque_ui");
const Playground = @import("routes/Playground_state_switch.zig");
const Planner = @import("routes/Planner.zig");
const Settings = @import("routes/Settings.zig");
const Callback = @import("routes/auth/callback/Page.zig");
const Login = @import("routes/auth/login/Page.zig");
const KeyStone = @import("keystone");
const backend = @import("routes/backend.zig");

// Initialize Vapor
pub var vaporize: Vaporize.Compiler = undefined;

fn registerLayouts() void {
    Vapor.registerLayout("/", layout, .{}) catch unreachable;
    Vapor.registerLayout("/auth", Clear, .{ .reset = true }) catch unreachable;
}

fn Clear(page: Vapor.PageFn) void {
    page();
}

fn layout(page: Vapor.PageFn) void {
    Vapor.Row()
        .width(.percent(100)).height(.percent(100))
        .background(.palette(.background))
        .children({
        Chat.renderSidebar();
        page();
        Opaque.Toast.renderStack();
    });
}

pub export fn init() void {
    Vapor.init(.{});
    vaporize = Vaporize.init(Vapor.arena(.persist), .{}) catch unreachable; // this causes issues

    Login.init();
    Callback.init();

    Vapor.Animation.new();
    KeyStone.init(.{
        .clients = .{
            .google = .{ .client_id = "403015953227-ed9i03idht6bvapcp8esnf0bgen24nl6.apps.googleusercontent.com" },
        },
        .hook_path = "/auth/callback",
        .backend_url = backend.baseUrl(),
    });

    registerLayouts();

    Chat.init();
    Playground.init();
    Planner.init();
    Settings.init();
    // Components.init();

    Opaque.initAnimations();
    Opaque.new();
    Opaque.OverlayManager.init();
    // Opaque.new();
    // buildLogoDrawAnimations();

    // Global style variables
    Vapor.setGlobalStyleVariables(.{ // Adds 11kb
        .themes = &.{
            Vapor.ThemeDefinition{ .name = "light", .theme = Theme.Light, .default = true },
            Vapor.ThemeDefinition{ .name = "dark", .theme = Theme.Dark },
        },
    });
}

const Animation = Vapor.Animation;

pub fn buildLogoDrawAnimations() void {
    // Each line gets its own animation: strokeDashoffset from line_length to 0
    // The stagger is achieved by giving each line a different delay based on X position.
    //
    // Line data: { name, length, delay_ms }
    // Sorted by midpoint-X so they draw left to right over ~3 seconds.

    const Line = struct { name: []const u8, length: f32, delay_ms: u32 };

    const lines = [_]Line{
        .{ .name = "ld00", .length = 222, .delay_ms = 0 }, // x1=2 vertical
        // Group 1: x ≈ 0–2 (far left vertical)
        .{ .name = "ld01", .length = 222, .delay_ms = 20 }, // x1=2 vertical
        // Group 2: x ≈ 0–177 (bottom connector)
        .{ .name = "ld48", .length = 177, .delay_ms = 50 }, // bottom line 177→0
        // Group 3: x ≈ 0–222 (top horizontal)
        .{ .name = "ld02", .length = 222, .delay_ms = 80 }, // top line 0→222
        // Group 4: x ≈ 220 (right side of first letter)
        .{ .name = "ld03", .length = 222, .delay_ms = 200 }, // x=220 vertical 226→4
        // Group 5: x ≈ 222–467 (bottom horizontal)
        .{ .name = "ld04", .length = 245, .delay_ms = 300 }, // 222→467 bottom
        // Group 6: x ≈ 247–467 (mid horizontal)
        .{ .name = "ld06", .length = 220, .delay_ms = 350 }, // 467→247 mid
        // Group 7: x ≈ 249 vertical
        .{ .name = "ld07", .length = 111, .delay_ms = 380 }, // 249 vert
        // Group 8: x ≈ 247–467 top
        .{ .name = "ld08", .length = 220, .delay_ms = 400 }, // 247→467 top
        // Group 9: x ≈ 467–490 connector
        .{ .name = "ld09", .length = 23, .delay_ms = 450 }, // small connector
        // Group 10: x ≈ 469 vertical
        .{ .name = "ld05", .length = 111, .delay_ms = 460 }, // 469 vert
        // Group 11: x ≈ 490–735 bottom
        .{ .name = "ld12", .length = 245, .delay_ms = 500 },
        // Group 12: x = 492 vertical
        .{ .name = "ld19", .length = 226, .delay_ms = 520 },
        // Group 13: x ≈ 515–735 mid
        .{ .name = "ld14", .length = 220, .delay_ms = 560 },
        // Group 14: x = 517 vertical
        .{ .name = "ld15", .length = 111, .delay_ms = 580 },
        // Group 15: x ≈ 515–735 top
        .{ .name = "ld17", .length = 220, .delay_ms = 600 },
        // Group 16: x ≈ 735–758 connector
        .{ .name = "ld18", .length = 23, .delay_ms = 650 },
        // Group 17: x = 737 vertical
        .{ .name = "ld13", .length = 111, .delay_ms = 660 },
        // Group 18: x = 760 vertical
        .{ .name = "ld20", .length = 223, .delay_ms = 700 },
        // Group 19: x ≈ 758–983 top
        .{ .name = "ld29", .length = 225, .delay_ms = 720 },
        // Group 20: x ≈ 758–983 mid
        .{ .name = "ld30", .length = 225, .delay_ms = 740 },
        // Group 21: x ≈ 758–980 bottom
        .{ .name = "ld28", .length = 222, .delay_ms = 760 },
        // Group 22: x = 981 vertical
        .{ .name = "ld16", .length = 108, .delay_ms = 800 },
        // Group 23: x ≈ 980–1003 connector
        .{ .name = "ld10", .length = 23, .delay_ms = 820 },
        // Group 24: x = 1005 vertical
        .{ .name = "ld21", .length = 223, .delay_ms = 850 },
        // Group 25: x ≈ 1003–1225 top
        .{ .name = "ld27", .length = 222, .delay_ms = 880 },
        // Group 26: x = 1116 vertical
        .{ .name = "ld25", .length = 223, .delay_ms = 950 },
        // Group 27: x ≈ 1225–1447 mid
        .{ .name = "ld47", .length = 222, .delay_ms = 1000 },
        // Group 28: x = 1227 vertical
        .{ .name = "ld26", .length = 223, .delay_ms = 1020 },
        // Group 29: x ≈ 1225–1408 top
        .{ .name = "ld40", .length = 183, .delay_ms = 1050 },
        // Group 30: x ≈ 1225–1447 bottom
        .{ .name = "ld39", .length = 222, .delay_ms = 1080 },
        // Group 31: x = 1406 vertical
        .{ .name = "ld37", .length = 108, .delay_ms = 1150 },
        // Group 32: x ≈ 1447–1470 connector
        .{ .name = "ld35", .length = 23, .delay_ms = 1200 },
        // Group 33: x = 1449 vertical
        .{ .name = "ld38", .length = 111, .delay_ms = 1220 },
        // Group 34: x = 1472 vertical
        .{ .name = "ld24", .length = 223, .delay_ms = 1250 },
        // Group 35: x ≈ 1470–1590 connector
        .{ .name = "ld41", .length = 120, .delay_ms = 1300 },
        // Group 36: x ≈ 1590–1613 connector
        .{ .name = "ld36", .length = 23, .delay_ms = 1350 },
        // Group 37: x = 1615 vertical
        .{ .name = "ld31", .length = 223, .delay_ms = 1400 },
        // Group 38: x ≈ 1613–1839 top
        .{ .name = "ld33", .length = 226, .delay_ms = 1430 },
        // Group 39: x ≈ 1613–1839 mid
        .{ .name = "ld34", .length = 226, .delay_ms = 1460 },
        // Group 40: x ≈ 1613–1835 bottom
        .{ .name = "ld32", .length = 222, .delay_ms = 1490 },
        // Group 41: x = 1837 vertical (short)
        .{ .name = "ld22", .length = 106, .delay_ms = 1550 },
        // Group 42: x ≈ 1835–1858 connectors
        .{ .name = "ld11", .length = 23, .delay_ms = 1570 },
        .{ .name = "ld46", .length = 23, .delay_ms = 1570 },
        // Group 43: x = 1860 vertical
        .{ .name = "ld23", .length = 223, .delay_ms = 1600 },
        .{ .name = "ld43", .length = 227, .delay_ms = 1600 },
        // Group 44: x ≈ 1858–2018 top
        .{ .name = "ld44", .length = 160, .delay_ms = 1650 },
        // Group 45: x ≈ 1858–2060 mid
        .{ .name = "ld45", .length = 202, .delay_ms = 1700 },
        // Group 46: x = 2020 vertical
        .{ .name = "ld42", .length = 111, .delay_ms = 1800 },
        // Group 47: x = 2061 vertical
        .{ .name = "ld49", .length = 114, .delay_ms = 1850 },
    };

    var anims = Vapor.persist.array(Animation);
    for (lines) |line| {
        const anim = Animation.init(line.name)
            .at(0).set(.strokeDashoffset, line.length)
            .at(100).set(.strokeDashoffset, 0)
            .duration(400)
            .delay(line.delay_ms)
            .easing(.easeOut);
        // .fill(.forwards);
        // .build();
        anims.append(anim);
    }

    for (anims.items) |anim| {
        anim.build();
    }
}

pub const std_options = std.Options{
    .log_level = .debug,
    .logFn = Vapor.lib.log,
};
