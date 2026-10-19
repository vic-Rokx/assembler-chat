// Planner
const Vaporize = @import("vaporize");
const Vapor = @import("vapor");
const Row = Vapor.Row;
const Divider = Vapor.Divider;
const TextArea = Vapor.TextArea;
const Root = @import("../main.zig");
const Opaque = @import("opaque_ui");
const Stack = Vapor.Stack;
const Text = Vapor.Text;

var markdown: Root.vaporize.MarkDown(.{}) = .{};
pub fn init() void {
    Vapor.Page(.{ .route = "/planner" }, render, null);
    const markdown_source = Vapor.load([]const u8, "assembler-plan") orelse "";
    markdown.compile(markdown_source) catch unreachable;
}

fn onChange(evt: *Vapor.Event) void {
    markdown.compile(evt.text()) catch unreachable;
    Vapor.store("assembler-plan", markdown.source);
    // saveToFile();
}

fn saveToFile() void {
    Vapor.store("assembler-plan", markdown.source);
}

pub fn loadPlanner(markdown_source: []const u8) void {
    markdown.compile(markdown_source) catch unreachable;
}

fn renderNav() void {
    Row()
        .width(.percent(100))
        .height(.px(60))
        .padding(.horizontal(20)).layout(.x_between_center)
        .background(.palette(.background))
        .children({
        Row().children({
            for (&[_][]const u8{ "P", "L", "A", "N", "N", "E", "R" }, 0..) |c, i| {
                Stack()
                    .width(.px(18))
                    .transition(.{ .duration = 300, .timing = .ease, .properties = &.{ .opacity, .width } })
                    .layout(.center)
                    .pos(.relative)
                    .children({
                    Text(c)
                        .font(24, 100, .palette(.text))
                        .transform(if (i == 6) Vapor.Types.Transform.rotateXYZ(0, 180, 0) else .{})
                        .fontStyle(if (i == 6) .italic else .normal)
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

pub fn render() void {
    Stack()
        .width(.expand)
        // .height(.percent(100))
        .children({
        renderNav();
        Vapor.Row()
            .border(.top(1, .palette(.border_color_light)))
            .width(.percent(100))
            .height(.percent(100))
            .background(.palette(.background))
            .children({
            TextArea()
                .bind(&markdown.source)
                .onChange(onChange, .{})
                .height(.percent(100))
                .width(.percent(60))
                .border(.none)
                .padding(.all(16))
                .placeholder("Write some markdown…")
                .fontSize(16)
                .end();
            Divider(1).background(.palette(.border_color_light)).end();
            Stack()
                .width(.percent(40))
                .height(.percent(100))
                .padding(.all(16))
                .children({
                markdown.render() catch unreachable;
            });
        });
    });
}
