//! Where Google sends the browser back after sign-in. KeyStone's hook on
//! this path posts the code to the backend; the page shows how it went.
const std = @import("std");
const Vapor = @import("vapor");
const KeyStone = @import("keystone");

pub fn init() void {
    Vapor.Page(.{ .src = @src() }, render, null);
}

fn render() void {
    const auth = KeyStone.getAuthState();
    Vapor.Stack()
        .center()
        .size(.full)
        .spacing(12)
        .children({
        switch (auth.state) {
            .loading => Vapor.Text("Signing in…").font(16, 300, .palette(.text)).end(),
            .signed_in => {
                Vapor.Text("Signed in").font(16, 300, .palette(.text)).end();
                Vapor.Link(.{ .url = "/" }).children({
                    Vapor.Text("Continue to Assembler").font(14, 300, .palette(.text)).end();
                });
            },
            .signed_out => {
                Vapor.Text(Vapor.frame.fmt("Sign-in failed ({s})", .{auth.err orelse "unknown"}))
                    .font(16, 300, .palette(.text))
                    .end();
                Vapor.Link(.{ .url = "/auth/login" }).children({
                    Vapor.Text("Back to login").font(14, 300, .palette(.text)).end();
                });
            },
        }
    });
}
