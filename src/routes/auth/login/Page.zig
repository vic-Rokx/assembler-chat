const std = @import("std");
const Vapor = @import("vapor");
const Text = Vapor.Text;
const Row = Vapor.Row;
const Center = Vapor.Center;
const Stack = Vapor.Stack;
const Opaque = @import("opaque_ui");
const Tabs = Opaque.Tabs;
const Field = Opaque.Field;
const Button = Opaque.Button;
const KeyStone = Vapor.KeyStone;
const utils = Vapor.utils;
const Validation = @import("vaporize").Validation;
const ValidationError = @import("vaporize").ValidationError;
const backend = @import("../../backend.zig");

pub var login: Login = .{
    .login_title = "Login into Assembler",
    .login_subtitle = "Login into your Assembler account.",
    .create_account_title = "Create Assembler Account",
    .create_account_subtitle = "Create an Assembler account to login",
};

const Login = @This();
login_title: []const u8 = "Login",
login_subtitle: []const u8 = "Login to your account",
create_account_title: []const u8 = "Create Account",
create_account_subtitle: []const u8 = "Create an account to login",

var hovered: ?*const Vapor.IconTokens = null;

pub const Details = struct {
    name: []const u8 = "",
    email: []const u8 = "",
    password: []const u8 = "password",
};

var details: Details = .{};

const key =
    \\<svg xmlns="http://www.w3.org/2000/svg" width="20" height="20" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1" stroke-linecap="round" stroke-linejoin="round" class="lucide lucide-key-icon lucide-key"><path d="m15.5 7.5 2.3 2.3a1 1 0 0 0 1.4 0l2.1-2.1a1 1 0 0 0 0-1.4L19 4"/><path d="m21 2-9.6 9.6"/><circle cx="7.5" cy="15.5" r="5.5"/></svg>
;

pub fn init() void {
    Vapor.Page(.{ .src = @src() }, render, null);
}

fn submit() void {
    createUser();
    if (KeyStone.isAuthenticated()) {
        Vapor.print("Already logged in", .{});
    } else {
        Vapor.print("Logging in", .{});
    }
}

const fetch = Vapor.Kit.Fetch.fetch;
fn createAccount() void {
    const payload = utils.stringify(details, .frame) catch unreachable;
    fetch(backend.url("/user"), .{
        .method = .POST,
        .credentials = "include",
        .body = payload,
        .body_type = .json,
    }).handle(createdAccount);
}

fn createdAccount(resp: Vapor.Kit.Response) void {
    if (resp.isOk()) {
        Vapor.println("Account created {s}", .{resp.Ok.body});
    }
}

fn validateSession(resp: Vapor.Kit.Response) void {
    if (resp.isOk()) {
        Vapor.println("Session validated {s}", .{resp.Ok.body});
    }
}

fn Card() Vapor.Builder(.pure) {
    return Stack()
        .background(.transparentizeHex(.palette(.background), 0.5))
        .border(.simple(.palette(.border_color_light)))
        // .border(.round(.palette(.border_color_light), .all(12)))
        .width(.percent(30))
        .padding(.all(16))
        .layout(.top_left)
        .spacing(16);
}

fn onHover(icon: *const Vapor.IconTokens, _: *Vapor.Event) void {
    hovered = icon;
}

fn onLeave(_: *Vapor.Event) void {
    hovered = null;
}

fn loginWithProvider(provider: KeyStone.Provider) void {
    KeyStone.signInWithOauth(provider);
}

fn AuthBtn(args: KeyStone.Provider, icon: *const Vapor.IconTokens) void {
    Button(loginWithProvider, .{args})
        .size(.hw_px(36, 36))
        .layout(.center)
        .background(.transparentizeHex(.black, 0.8))
        .border(.round(.black, .all(8)))
        .pointer()
        .fontColor(.white)
        .hover(.{
            .background = .yellow,
            .text_color = .black,
        })
        .onEvent(.pointerenter, onHover, .{icon})
        .onLeave(onLeave, .{})
        .children({
        Vapor.Icon(icon)
            .fontSize(18)
            .end();
    });
}

fn payment() void {
    Vapor.Kit.fetch(backend.url("/checkout"), handlePayment, .{
        .method = .POST,
        .credentials = "include",
        .headers = .{
            .content_type = "application/x-www-form-urlencoded",
        },
    });
}

fn handlePayment(resp: Vapor.Kit.Response) void {
    switch (resp) {
        .ok => |data| {
            Vapor.println("Payment data {any}", .{data.body});
            Vapor.Kit.setWindowLocation(data.body);
        },
        .err => |err| {
            Vapor.println("Failed to fetch payment data: {s}", .{err.message});
        },
    }
    // Vapor.cycle();
}

fn onChange(evt: *Vapor.Event) void {
    evt.preventDefault();
    Vapor.print("onChange {s}", .{evt.text()});
}

pub const Auth = struct {
    name: []const u8,
    email: []const u8,
    power: i32,
};

fn createUser() void {
    const user = Auth{
        .name = details.name,
        .email = details.email,
        .power = 1111,
    };
    fetch(backend.url("/api/users"), .{
        .method = .POST,
        .credentials = "include",
        .body = utils.stringify(user, .frame) catch unreachable,
        .body_type = .json,
    }).handle(handleCreatedUser);
}

fn handleCreatedUser(resp: Vapor.Kit.Response) void {
    if (resp.isOk()) {
        Vapor.println("User created {s}", .{resp.Ok.body});
    }
}

pub fn render() void {
    const google = KeyStone.keystone.clients.google;
    const github = KeyStone.keystone.clients.github;
    const apple = KeyStone.keystone.clients.apple;
    const auth_providers = if (google != null or github != null or apple != null) true else false;
    Stack()
        .center()
        .size(.full)
        .children({
        var active_index: usize = 0;
        Row()
            .width(.percent(30))
            .layout(.left_center)
            .children({
            active_index = Tabs.NavBar("login_tabs", &.{ "Login", "Create Account" });
        });
        switch (active_index) {
            0 => {
                Card().children({
                    Stack()
                        .width(.percent(100))
                        .spacing(8)
                        .children({
                        Text(login.login_title)
                            .font(20, 100, .palette(.text))
                            .end();
                        Text(login.login_subtitle)
                            .font(14, 100, .palette(.text))
                            .end();
                    });

                    if (auth_providers) {
                        Row()
                            .width(.percent(100))
                            .spacing(16)
                            .layout(.left_center)
                            .children({
                            for (KeyStone.configuredProviders()) |provider| {
                                const icon: Vapor.IconType = switch (provider) {
                                    .google => .google,
                                    .github => .github,
                                    .apple => .apple,
                                    else => {
                                        continue;
                                    },
                                };
                                AuthBtn(provider, icon);
                            }
                        });
                    }

                    Stack()
                        .width(.percent(100))
                        .spacing(16)
                        .children({
                        Field.render(.{ .label = "Name", .value = .{ .string = &details.name }, .type = .string, .id = "name" });
                        Field.render(.{ .label = "Email", .value = .{ .email = &details.email }, .type = .email, .id = "email" });
                        Field.render(.{ .label = "Password", .value = .{ .password = &details.password }, .type = .password, .id = "password" });
                    });
                    Row()
                        .layout(.right_center)
                        .width(.percent(100))
                        .children({
                        Button(submit, .{})
                            .animation("glitch")
                            .background(.transparentizeHex(.black, 0.8))
                            .border(.round(.black, .all(8)))
                            .padding(.all(6))
                            .pointer()
                            .children({
                            Text("Login")
                                .font(16, 300, .palette(.text))
                                .fontFamily("IBM Plex Sans,monospace")
                                .end();
                            Vapor.Svg(.{ .svg = key })
                                .stroke(.palette(.text))
                                .fill(.palette(.background))
                                .end();
                        });
                    });
                });
            },
            1 => {
                Card().children({
                    Stack()
                        .width(.percent(100))
                        .spacing(8)
                        .children({
                        Text(login.create_account_title)
                            .font(16, 700, .palette(.text))
                            .end();
                        Text(login.create_account_subtitle)
                            .font(14, 300, .palette(.text))
                            .end();
                    });
                    Stack()
                        .width(.percent(100))
                        .spacing(16)
                        .children({
                        Field.render(.{ .label = "Email", .value = .{ .email = &details.email }, .type = .email });
                        Field.render(.{ .label = "Password", .value = .{ .password = &details.password }, .type = .password });
                    });
                    Row()
                        .layout(.right_center)
                        .width(.percent(100))
                        .children({
                        Button(createAccount, .{})
                            .animation("glitch")
                            .background(.transparentizeHex(.black, 0.8))
                            .border(.round(.black, .all(8)))
                            .padding(.all(6))
                            .pointer()
                            .children({
                            Text("Create Account")
                                .font(16, 300, .palette(.text))
                                .fontFamily("IBM Plex Sans,monospace")
                                .end();
                            Vapor.Icon(.person_rolodex)
                                .font(16, 700, .palette(.text))
                                .end();
                        });
                    });
                });
            },
            else => {},
        }
    });
}
