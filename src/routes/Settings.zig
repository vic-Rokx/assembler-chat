const std = @import("std");
const Vapor = @import("vapor");
const Row = Vapor.Row;
const Text = Vapor.Text;
const Stack = Vapor.Stack;
const Opaque = @import("opaque_ui");
const Theme = @import("theme");
const Auth = @import("../auth/auth.zig");
const Snippet = Opaque.Snippet;
const Modal = Opaque.Alert;

var code_snippet: Snippet = undefined;
var modal: Modal = undefined;
var tokens: ?TokenResponse = null;

pub fn init() void {
    Vapor.Page(.{ .route = "/settings" }, render, null);
    claude_api_token = Vapor.load([]const u8, "claude_api_token") orelse "";
    open_api_token = Vapor.load([]const u8, "open_api_token") orelse Vapor.load([]const u8, "openai_api_token") orelse "";
    vertex_access_token = Vapor.load([]const u8, "vertex_access_token") orelse "";
    gcp_project_id = Vapor.load([]const u8, "gcp_project_id") orelse "";
    code_snippet.init();
    modal = .init(RedirectModal);
    modal.border = .thin(.palette(.border_color_light));
    tokens = Vapor.load(TokenResponse, "codex-tokens") orelse null;
}

var device_code: DeviceCode = .{};
const DeviceCode = struct {
    device_auth_id: []const u8 = "device_auth_id",
    user_code: []const u8 = "user_code",
    interval: []const u8 = "interval",
    expires_at: []const u8 = "expires_at",
};

fn changeCodexSettings() void {
    Vapor.openTab("https://chatgpt.com/#settings/Security");
}

fn openDeviceCodeTab() void {
    Vapor.openTab("https://auth.openai.com/codex/device");
}

fn RedirectModal(_: *Modal) void {
    Stack()
        .width(.px(720))
        .padding(.all(24))
        .height(.percent(30))
        .padding(.all(16))
        .spacing(8)
        .children({
        Text("Codex Auth Setup")
            .fontSize(20)
            .fontWeight(400)
            .end();

        Text("1. Open the following Link in your browser and then 'Enable device code authorization for Codex'")
            .fontSize(16)
            .fontWeight(100)
            .end();

        Row()
            .width(.expand)
            .margin(.vertical(16))
            .layout(.right_center)
            .children({
            Opaque.Button(changeCodexSettings, .{})
                .background(.transparentize(.palette(.tint), 1))
                .height(.px(36))
                .padding(.xy(12, 6))
                .border(.thin(.palette(.border_color_light)))
                .pointer()
                .children({
                Text("Update Codex Settings")
                    .font(14, 300, .palette(.background))
                    .end();
            });
        });

        Text("2. Then copy the following code and paste it into the 'User Code' field in the 'Security' settings page by clicking the button below")
            .fontSize(16)
            .fontWeight(100)
            .end();
        code_snippet.code(device_code.user_code);

        Row()
            .width(.expand)
            .margin(.vertical(16))
            .layout(.right_center)
            .children({
            Opaque.Button(openDeviceCodeTab, .{})
                .background(.transparentize(.palette(.tint), 1))
                .height(.px(36))
                .padding(.xy(12, 6))
                .border(.thin(.palette(.border_color_light)))
                .pointer()
                .children({
                Text("Submit User Code")
                    .font(14, 300, .palette(.background))
                    .end();
            });
        });

        Text("⚠️ We do not store user codes, or any other information, this is purely for authentication purposes, so you can use Codex within the browser.")
            .fontSize(16)
            .textColor(.palette(.text))
            .fontWeight(300)
            .end();
    });
}

fn renderNav() void {
    Row()
        .width(.percent(100))
        .height(.px(60))
        .padding(.horizontal(20)).layout(.x_between_center)
        .background(.palette(.background))
        .children({
        Row().children({
            for (&[_][]const u8{ "S", "E", "T", "T", "I", "N", "G", "S" }, 0..) |c, i| {
                Stack()
                    .width(.px(16))
                    .transition(.{ .duration = 300, .timing = .ease, .properties = &.{ .opacity, .width } })
                    .layout(.center)
                    .pos(.relative)
                    .children({
                    Text(c)
                        .font(24, 100, .palette(.text))
                        .transform(if (i == 7) Vapor.Types.Transform.rotateXYZ(0, 180, 0) else .{})
                        .fontStyle(if (i == 7) .italic else .normal)
                        .ml(if (i == 7) 4 else 0)
                        .end();
                });
            }
        });
        Opaque.Button(saveToFile, .{})
            .background(.transparentize(.palette(.tint), 1))
            .height(.px(36))
            .padding(.xy(12, 6))
            .border(.thin(.palette(.border_color_light)))
            .pointer()
            .children({
            Text("Save")
                .font(14, 300, .palette(.background))
                .end();
        });
    });
}
var claude_api_token: []const u8 = "";
var open_api_token: []const u8 = "";
var gemeini_api_token: []const u8 = "";
var vertex_access_token: []const u8 = "";
var gcp_project_id: []const u8 = "";

fn saveToFile() void {
    Vapor.store("claude_api_token", claude_api_token);
    Vapor.store("open_api_token", open_api_token);
    Vapor.store("gcp_project_id", gcp_project_id);
    Vapor.store("vertex_access_token", vertex_access_token);
}

fn onMount() void {
    claude_api_token = Vapor.load([]const u8, "claude_api_token") orelse "";
    open_api_token = Vapor.load([]const u8, "open_api_token") orelse Vapor.load([]const u8, "openai_api_token") orelse "";
    vertex_access_token = Vapor.load([]const u8, "vertex_access_token") orelse "";
    gcp_project_id = Vapor.load([]const u8, "gcp_project_id") orelse "";
    Vapor.cycle();
}

var claude_api_token_edited: bool = false;
fn focus(evt: *Vapor.Event) void {
    _ = evt;
    claude_api_token_edited = true;
}

fn blur(evt: *Vapor.Event) void {
    _ = evt;
    claude_api_token_edited = false;
}

var open_api_token_edited: bool = false;
fn focusOpenAI(evt: *Vapor.Event) void {
    _ = evt;
    open_api_token_edited = true;
}

fn blurOpenAI(evt: *Vapor.Event) void {
    _ = evt;
    open_api_token_edited = false;
}

var vertex_access_token_edited: bool = false;
fn focusVertex(evt: *Vapor.Event) void {
    _ = evt;
    vertex_access_token_edited = true;
}

fn blurVertex(evt: *Vapor.Event) void {
    _ = evt;
    vertex_access_token_edited = false;
}

const fetch = Vapor.fetch;
fn fetchDeviceCode() void {
    fetch("https://auth.openai.com/api/accounts/deviceauth/usercode", .{
        .method = .POST,
        .extra_headers = &.{
            .{ .name = "Content-Type", .value = "application/json" },
        },
        .body =
        \\{"client_id":"app_EMoamEEZ73f0CkXaXp7hrann"}
        ,
    }).handle(handleDeviceCode, .{});
}

fn handleDeviceCode(resp: Vapor.Fetch.Result) void {
    switch (resp) {
        .ok => |ok| {
            std.log.info("ok {d}", .{ok.body.len});
            std.log.info("Handle Device Code Response: {s}", .{ok.body});
            const value = std.json.parseFromSliceLeaky(DeviceCode, Vapor.persist.arena(), ok.body, .{ .ignore_unknown_fields = true }) catch unreachable;
            device_code = value;
            Vapor.lib.timeout("polling token", 5000, pollForToken, .{});
            modal.open();
        },
        .err => |er| {
            std.log.err("err {s}", .{er.body});
            std.log.err("{s}", .{er.message});
        },
    }
}

fn pollForToken() void {
    const device_auth_id = device_code.device_auth_id;
    const user_code = device_code.user_code;
    const body = Vapor.frame.fmt(
        \\{{"device_auth_id":"{s}","user_code":"{s}"}}
    , .{ device_auth_id, user_code });

    fetch("https://auth.openai.com/api/accounts/deviceauth/token", .{
        .method = .POST,
        .extra_headers = &.{
            .{ .name = "Content-Type", .value = "application/json" },
        },
        .body = body,
    }).handle(handleTokenPoll, .{});
}

const PollResponse = struct {
    status: []const u8 = "status",
    user_code: []const u8 = "user_code",
    user_code_expiration: []const u8 = "user_code_expiration",
    authorization_code: []const u8 = "authorization_code",
    code_challenge: []const u8 = "code_challenge",
    code_verifier: []const u8 = "code_verifier",
};

fn handleTokenPoll(resp: Vapor.Fetch.Result) void {
    std.log.debug("POLLING", .{});
    switch (resp) {
        .ok => |ok| {
            std.log.info("ok {d}", .{ok.body.len});
            std.log.info("{s}", .{ok.body});
            const value = std.json.parseFromSliceLeaky(PollResponse, Vapor.frame.arena(), ok.body, .{ .ignore_unknown_fields = true }) catch unreachable;
            Vapor.lib.cancelTimeout("polling token");
            if (std.mem.eql(u8, value.status, "success")) {
                exchangeAuthCode(value.authorization_code, value.code_verifier);
            }
        },
        .err => |er| {
            std.log.err("{s}", .{er.body});
            Vapor.lib.timeout("polling token", 5000, pollForToken, .{});
        },
    }
}

fn exchangeAuthCode(authorization_code: []const u8, code_verifier: []const u8) void {
    const body = Vapor.frame.fmt(
        \\{{"grant_type":"authorization_code","code":"{s}","code_verifier":"{s}","client_id":"app_EMoamEEZ73f0CkXaXp7hrann","redirect_uri":"https://auth.openai.com/deviceauth/callback"}}
    , .{ authorization_code, code_verifier });

    fetch("https://auth.openai.com/oauth/token", .{
        .method = .POST,
        .extra_headers = &.{
            .{ .name = "Content-Type", .value = "application/json" },
        },
        .body = body,
    }).handle(handleTokenExchange, .{});
}

pub const TokenResponse = struct {
    access_token: []const u8,
    refresh_token: ?[]const u8 = null,
    id_token: ?[]const u8 = null,
    expires_in: i64,
    token_type: []const u8,
    scope: []const u8,

    pub fn deinit(self: TokenResponse, allocator: std.mem.Allocator) void {
        allocator.free(self.access_token);
        if (self.refresh_token) |refresh_token| allocator.free(refresh_token);
        if (self.id_token) |id_token| allocator.free(id_token);
        allocator.free(self.token_type);
    }
};

fn handleTokenExchange(resp: Vapor.Fetch.Result) void {
    switch (resp) {
        .ok => |ok| {
            std.log.info("ok {d}", .{ok.body.len});
            std.log.info("{s}", .{ok.body});
            Vapor.store("codex-tokens", ok.body);
            const value = std.json.parseFromSliceLeaky(TokenResponse, Vapor.frame.arena(), ok.body, .{ .ignore_unknown_fields = true }) catch unreachable;
            std.log.info("Token Response: {s}", .{value.access_token});
        },
        .err => |er| {
            std.log.err("{s}", .{er.message});
        },
    }
}

fn render() void {
    Stack()
        .onMount(onMount, .{})
        .onUpdate(onMount, .{})
        .width(.expand)
        .height(.percent(100))
        .children({
        renderNav();
        Stack()
            .width(.expand)
            .height(.expand)
            .spacing(32)
            .padding(.all(16))
            .children({
            Stack()
                .width(.expand)
                .spacing(16)
                .children({
                Text("OpenAI Configuration")
                    .fontSize(24)
                    .fontWeight(200)
                    .end();

                Opaque.Button(fetchDeviceCode, .{})
                    .background(.transparentize(.palette(.tint), 1))
                    .height(.px(36))
                    .padding(.xy(12, 6))
                    .border(.thin(.palette(.border_color_light)))
                    .pointer()
                    .children({
                    Text("Connect OpenAI Codex")
                        .font(14, 300, .palette(.background))
                        .end();
                });

                Opaque.Field.render(.{
                    .label = "OpenAI API Token",
                    .value = if (open_api_token_edited) .{ .password = &open_api_token } else .{ .string = &open_api_token },
                    .type = if (open_api_token_edited) .string else .password,
                    .on_focus = focusOpenAI,
                    .on_blur = blurOpenAI,
                    .focused = if (open_api_token_edited) true else false,
                });
            });

            // Row().width(.percent(100)).layout(.left_center).spacing(8).children({
            //     Vapor.Label("Theme").font(18, 100, .palette(.text)).end();
            //     Opaque.Switch.render("Theme", Theme.toggleTheme, .{});
            // });
            Stack()
                .width(.expand)
                .spacing(16)
                .children({
                Text("Claude Configuration")
                    .fontSize(24)
                    .fontWeight(200)
                    .end();

                Opaque.Field.render(.{
                    .label = "Claude API Token",
                    .value = if (claude_api_token_edited) .{ .password = &claude_api_token } else .{ .string = &claude_api_token },
                    .type = if (claude_api_token_edited) .string else .password,
                    .on_focus = focus,
                    .on_blur = blur,
                    .focused = if (claude_api_token_edited) true else false,
                });
            });

            Stack()
                .width(.expand)
                .spacing(16)
                .children({
                Text("Gemini Configuration")
                    .fontSize(24)
                    .fontWeight(200)
                    .end();

                Opaque.Field.render(.{ .label = "Gemini API Token", .value = .{ .password = &gemeini_api_token } });
                Opaque.Field.render(.{ .label = "GCP Project ID", .value = .{ .password = &gcp_project_id } });

                Opaque.Field.render(.{
                    .label = "Vertex Access Token",
                    .value = if (vertex_access_token_edited) .{ .password = &vertex_access_token } else .{ .string = &vertex_access_token },
                    .type = if (vertex_access_token_edited) .string else .password,
                    .on_focus = focusVertex,
                    .on_blur = blurVertex,
                    .focused = if (vertex_access_token_edited) true else false,
                });
            });
        });
        modal.render();
    });
}
