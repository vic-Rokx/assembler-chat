// src/generator.zig
const std = @import("std");
const App = @import("main.zig");

// Import your shared framework/component modules
const Vapor = @import("vapor");
const theme = @import("theme");

pub fn main() !void {
    App.init();
    Vapor.lib.generate();
    // 1. Create an instance of your root component or app
    //    (This code is hypothetical and depends on your framework's API)
    //    const site_vdom = my_framework.render(theme.DocumentationSite, allocator);

    // 2. Walk the virtual DOM or component tree to extract text
    //    var extracted_strings = std.ArrayList(MyString).init(allocator);
    //    try walkAndExtractText(site_vdom, &extracted_strings);

    // 3. Write the extracted text to a JSON file

    // var json_writer = std.json.writeStream(file.writer(), .{}, .{ .whitespace = .indent_2 });
    // try json_writer.write(extracted_strings.items);

    std.debug.print("\nSuccessfully generated Static Pages /static\n", .{});
}
