const std = @import("std");
const Vapor = @import("vapor");
const Center = Vapor.Center;
const Button = Vapor.Button;
const Text = Vapor.Text;
const TextFmt = Vapor.TextFmt;
const TextField = Vapor.TextField;
const Heading = Vapor.Heading;

// Initialize Vapor
export fn init() void {
    Vapor.init(.{});
    Vapor.Page(.{ .route = "/" }, Counter, null);
}

var counter: u32 = 0;
fn increment() void {
    counter += 1;
}

// No state management
var font_color: Vapor.Types.Color = .black;
var is_hovered: bool = false;

// Change font color on hover
fn changeFontColor(_: *Vapor.Event) void {
    is_hovered = !is_hovered;
    font_color = if (is_hovered) .vapor_blue else .black;
}

// Counter Component
fn Counter() void {

    // Create a centered column with a heading and a button
    Center().size(.full).direction(.column).items(.{
        Text("Vapor")
            .fontFamily("Bruno Ace")
            .inlineStyle("-webkit-text-stroke: 12px black;", .{})
            .shadow(.dropShadow(12, 12, 0, 0, .rgba(255, 0, 255, 0.7)))
            .duration(100)
            .transform(if (is_hovered) .directionScale(.up, 32, 1.1) else null)
            .font(120, 300, font_color),

        Center().spacing(32).width(.percent(100)).children({
            // Create a button with an increment function
            Vapor.Button(increment, .{})
                .duration(100)
                .onHover(changeFontColor, .{})
                .onLeave(changeFontColor, .{})
                .hover(.{
                    .background = .rgba(255, 0, 255, 0.7),
                    .text_color = .white,
                })
                .cursor(.pointer)
                .hw(.px(36), .px(120))
                .children({
                Text("Increment")
                    .inlineStyle("-webkit-text-stroke: 8px black;", .{})
                    .fontFamily("Bruno Ace")
                    .fontSize(16).end();
            });
            // Create a text field with a counter value
            Text(counter)
                .width(.px(48))
                .font(32, 700, .palette(.text)).end();
        }),
    });
}

pub const std_options = std.Options{
    .log_level = .debug,
    .logFn = Vapor.lib.log,
};
