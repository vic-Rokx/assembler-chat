// Theme.zig
const std = @import("std");
const Vapor = @import("vapor");
const Color = Vapor.Types.Color;
pub const Mode = enum(u8) {
    light,
    dark,
};

pub const ThemeTokens = enum(u8) {
    none,
    text,
    background,
    tint,
    disabled,
    code_is_added_color,
    danger,
    code_function_color,
    code_keyword_color,
    code_number_color,
    code_string_color,
    code_comment_color,
    code_text_color,
    code_tint_color,
    border_color_light,
    text_muted,
    light_text,
    code_component_color,
    code_operator_color,
    code_identifier_color,
    highlight_color,
};

pub const Colors = struct {
    text: Color,
    background: Color,
    tint: Color,
    disabled: Color,
    code_is_added_color: Color,
    danger: Color,
    code_function_color: Color,
    code_keyword_color: Color,
    code_number_color: Color,
    code_string_color: Color,
    code_comment_color: Color,
    code_text_color: Color,
    code_tint_color: Color,
    border_color_light: Color,
    text_muted: Color,
    light_text: Color,
    code_component_color: Color,
    code_operator_color: Color,
    code_identifier_color: Color,
    code_type_color: Color,
    highlight_color: Color,
    chart_bar_color: Color,
};

pub const Light = Colors{
    .text = .black,
    .background = .white,
    .tint = .hex("#002bff"),
    .danger = .hex("#FF0000"),
    .code_number_color = .hex("#002bff"),
    .border_color_light = .hex("#E8E8E8"),

    .code_text_color = .hex("#E4E7EE"),
    .code_function_color = .hex("#FFED84"),
    .code_keyword_color = .hex("#002bff"),
    .disabled = .hex("#A2A2A2"),
    .light_text = .hex("#B7B7B7"),
    .code_tint_color = .hex("#84FFED"),
    .code_comment_color = .hex("#A9A9A9"),
    .code_string_color = .hex("#C4A262"),
    .highlight_color = .hex("#F3F3F3"),
    .code_type_color = .hex("#7D7684"),
    .code_component_color = .hex("#FF00FF"),
    .code_operator_color = .hex("#565656"),
    .code_identifier_color = .hex("#2E3B5A"),
    .code_is_added_color = .hex("#16DF8F"),
    .chart_bar_color = .hex("#212121"),
    .text_muted = .hex("#71717a"),
};

pub const Dark = Colors{
    .text = .hex("#EAEAEA"),
    .background = .hex("#0F0F0F"),
    .danger = .hex("#FF0000"),
    .tint = .hex("#FFF200"),
    .code_number_color = .hex("#002bff"),
    .border_color_light = .hex("#E8E8E8"),

    .code_text_color = .hex("#E4E7EE"),
    .code_function_color = .hex("#FFED84"),
    .code_keyword_color = .hex("#002bff"),
    .disabled = .hex("#A2A2A2"),
    .light_text = .hex("#B7B7B7"),
    .code_tint_color = .hex("#84FFED"),
    .code_comment_color = .hex("#A9A9A9"),
    .code_string_color = .hex("#C4A262"),
    .code_type_color = .hex("#7D7684"),
    .code_component_color = .hex("#FF00FF"),
    .code_operator_color = .hex("#565656"),
    .code_identifier_color = .hex("#2E3B5A"),
    .code_is_added_color = .hex("#16DF8F"),
    .highlight_color = .hex("#F3F3F3"),
    .chart_bar_color = .hex("#212121"),
    .text_muted = .hex("#71717a"),
};

pub var mode: Mode = .light;

pub export fn setTheme(new_mode: Mode) void {
    mode = new_mode;
}

pub fn toggleTheme() void {
    mode = switch (mode) {
        .dark => .light,
        .light => .dark,
    };
    Vapor.lib.store("theme", @tagName(mode));
    Vapor.lib.toggleTheme();
}
