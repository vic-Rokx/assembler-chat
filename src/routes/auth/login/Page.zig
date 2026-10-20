const std = @import("std");
const Vapor = @import("vapor");
const Text = Vapor.Text;
const Row = Vapor.Row;
const Stack = Vapor.Stack;
const Opaque = @import("opaque_ui");
const Button = Opaque.Button;
const KeyStone = @import("keystone");
const backend = @import("../../backend.zig");

pub var login: Login = .{
    .login_title = "Login into Assembler",
    .login_subtitle = "Sign in with your Google account. Your first sign-in creates your Assembler account.",
};

const Login = @This();
login_title: []const u8 = "Login",
login_subtitle: []const u8 = "Login to your account",

var hovered: ?Vapor.IconTokens = null;

pub fn init() void {
    Vapor.Page(.{ .src = @src() }, render, null);
}

fn signOut() void {
    KeyStone.signOut();
}

fn Card() Vapor.Builder(.pure) {
    return Stack()
        .background(.transparentize(.palette(.background), 0.5))
        .border(.thin(.palette(.border_color_light)))
        // .border(.round(.palette(.border_color_light), .all(12)))
        .width(.percent(30))
        .padding(.all(16))
        .layout(.top_left)
        .spacing(16);
}

fn onHover(icon: Vapor.IconTokens, _: *Vapor.Event) void {
    hovered = icon;
}

fn onLeave(_: *Vapor.Event) void {
    hovered = null;
}

fn loginWithProvider(provider: KeyStone.Provider) void {
    KeyStone.signInWithOauth(provider);
}

fn AuthBtn(args: KeyStone.Provider, icon: Vapor.IconTokens) void {
    Button(loginWithProvider, .{args})
        .size(.hwPx(36, 36))
        .layout(.center)
        .background(.transparentize(.black, 0.8))
        .border(.round(.black, .all(8)))
        .pointer()
        .textColor(.white)
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
    Vapor.fetch(backend.url("/checkout"), .{
        .method = .POST,
        .credentials = "include",
        .headers = .{
            .content_type = "application/x-www-form-urlencoded",
        },
    }).handle(handlePayment, .{});
}

fn handlePayment(resp: Vapor.Fetch.Result) void {
    switch (resp) {
        .ok => |data| {
            Vapor.println("Payment data {any}", .{data.body});
            Vapor.redirect(data.body);
        },
        .err => |err| {
            Vapor.println("Failed to fetch payment data: {s}", .{err.message});
        },
    }
    // Vapor.cycle();
}

pub fn render() void {
    const auth = KeyStone.getAuthState();
    Stack()
        .center()
        .size(.full)
        .children({
        Card().children({
            switch (auth.state) {
                .signed_in => signedIn(auth),
                .loading => Text("Signing in…").font(14, 300, .palette(.text)).end(),
                .signed_out => signedOut(auth),
            }
        });
    });
}

fn signedIn(auth: KeyStone.AuthSnapshot) void {
    const user = if (auth.session) |session| session.user else null;
    Stack()
        .width(.percent(100))
        .spacing(8)
        .children({
        Text("Signed in").font(20, 100, .palette(.text)).end();
        if (user) |u| {
            Text(u.name).font(14, 300, .palette(.text)).end();
            Text(u.email).font(14, 100, .palette(.text)).end();
        }
    });
    Row()
        .layout(.right_center)
        .width(.percent(100))
        .children({
        Button(signOut, .{})
            .background(.transparentize(.black, 0.8))
            .border(.round(.black, .all(8)))
            .padding(.all(6))
            .pointer()
            .children({
            Text("Sign out")
                .font(16, 300, .palette(.text))
                .fontFamily("IBM Plex Sans,monospace")
                .end();
        });
    });
}

fn signedOut(auth: KeyStone.AuthSnapshot) void {
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
        if (auth.err) |err| {
            Text(Vapor.frame.fmt("Sign-in failed ({s}). Try again.", .{err}))
                .font(14, 300, .palette(.text))
                .end();
        }
    });

    Row()
        .width(.percent(100))
        .spacing(16)
        .layout(.left_center)
        .children({
        for (KeyStone.configuredProviders()) |provider| {
            const icon: Vapor.IconTokens = switch (provider) {
                .google => .google,
                .github => .github,
                .apple => .apple,
                else => continue,
            };
            AuthBtn(provider, icon);
        }
    });
}
