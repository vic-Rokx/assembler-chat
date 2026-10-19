const std = @import("std");
const Vapor = @import("vapor");

pub fn init() void {
    Vapor.Page(.{ .src = @src() }, render, null);
}

fn render() void {
    Vapor.Row()
        .width(.expand)
        .height(.percent(100))
        .children({});
}
