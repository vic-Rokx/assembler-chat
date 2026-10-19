// =============================================================================
// DATA — Templates, Learn sections, tag colors, option pills, model list
// =============================================================================

const Vapor = @import("vapor");

// =============================================================================
// TEMPLATES
// =============================================================================

pub const Template = struct {
    title: []const u8,
    description: []const u8,
    tag: []const u8,
    prompt: []const u8,
};

pub const TEMPLATES = [_]Template{
    .{ .title = "Counter", .description = "Increment / decrement with state", .tag = "basic", .prompt = "a counter component with increment, decrement and reset buttons" },
    .{ .title = "Login Form", .description = "Email + password with validation", .tag = "form", .prompt = "a login form with email and password fields, validation, and a submit button" },
    .{ .title = "Todo List", .description = "Add, complete, delete items", .tag = "state", .prompt = "a todo list with add, toggle complete, and delete functionality with item count" },
    .{ .title = "Sidebar Nav", .description = "Collapsible nav with icons", .tag = "layout", .prompt = "a collapsible sidebar navigation with icons and labels that expands on hover" },
    .{ .title = "Data Table", .description = "Sortable rows with pagination", .tag = "data", .prompt = "a data table with sortable columns, row selection, and pagination controls" },
    .{ .title = "Search Bar", .description = "Live filter with debounce", .tag = "input", .prompt = "a search bar that filters a list of items in real-time as you type" },
    .{ .title = "Modal Dialog", .description = "Overlay with backdrop dismiss", .tag = "overlay", .prompt = "a modal dialog with backdrop, title, content area, and close button" },
    .{ .title = "Dropdown Menu", .description = "Trigger + options list", .tag = "overlay", .prompt = "a dropdown menu with a trigger button and a list of selectable options" },
    .{ .title = "Tab Panel", .description = "Switchable content sections", .tag = "layout", .prompt = "a tab panel with 3 tabs and corresponding content sections" },
    .{ .title = "File Upload", .description = "Drag-and-drop with progress", .tag = "input", .prompt = "a file upload component with drag-and-drop zone and upload progress indicator" },
    .{ .title = "Notification", .description = "Toast stack with auto-dismiss", .tag = "feedback", .prompt = "a notification toast system with success, error, warning types and auto-dismiss" },
    .{ .title = "Settings Panel", .description = "Grouped toggles and inputs", .tag = "form", .prompt = "a settings panel with toggle switches, text inputs, and grouped sections" },
};

pub const TagColor = struct {
    tag: []const u8,
    bg: []const u8,
    fg: []const u8,
};

pub const TAG_COLORS = [_]TagColor{
    .{ .tag = "basic", .bg = "#E8F4FD", .fg = "#1B6CA8" },
    .{ .tag = "form", .bg = "#FDF0E8", .fg = "#A85C1B" },
    .{ .tag = "state", .bg = "#EBF8F0", .fg = "#1B7A3E" },
    .{ .tag = "layout", .bg = "#F3EBF8", .fg = "#6B1B8A" },
    .{ .tag = "data", .bg = "#FDF5E8", .fg = "#A87B1B" },
    .{ .tag = "input", .bg = "#E8EEF8", .fg = "#1B3A6B" },
    .{ .tag = "overlay", .bg = "#F8E8E8", .fg = "#8A1B1B" },
    .{ .tag = "feedback", .bg = "#F8F3E8", .fg = "#7A5C1B" },
};

// =============================================================================
// LEARN
// =============================================================================

pub const LearnItem = struct {
    title: []const u8,
    description: []const u8,
    prompt: []const u8,
};

pub const LearnSection = struct {
    title: []const u8,
    items: []const LearnItem,
};

pub const LEARN_SECTIONS = [_]LearnSection{
    .{
        .title = "Core Concepts",
        .items = &.{
            .{ .title = "State Management", .description = "Module-level vars, atomic reactivity", .prompt = "show a simple example of state management in Vapor with a counter and a derived text label" },
            .{ .title = "Event Handlers", .description = "Button, onEvent patterns", .prompt = "show all event handler patterns: Button, Button with args, onEvent with context" },
            .{ .title = "Memory Arenas", .description = "frame vs view vs persist lifetimes", .prompt = "demonstrate .frame .view and .persist arena usage with a practical example" },
            .{ .title = "Dynamic Arrays", .description = "Vapor.array, append, remove", .prompt = "show how to use Vapor.array to build a dynamic list with add and remove" },
        },
    },
    .{
        .title = "Layout System",
        .items = &.{
            .{ .title = "Row vs Stack", .description = "Row vs column containers", .prompt = "show the difference between Row (row) and Stack (column) with labelled visual examples" },
            .{ .title = "Layout Tokens", .description = ".center .top_left .x_between_center", .prompt = "demonstrate all layout alignment tokens with labelled boxes" },
            .{ .title = "Sizing & Expand", .description = ".px .percent .expand .fit .full", .prompt = "show all sizing options with examples: px, percent, expand, fit, full" },
            .{ .title = "Padding & Margin", .description = ".all .xy .tblr individual sides", .prompt = "show padding and margin options with visual spacing examples" },
        },
    },
    .{
        .title = "Patterns",
        .items = &.{
            .{ .title = "Loading / Error / Content", .description = "3-state async pattern", .prompt = "show the loading / error / content pattern with a simulated fetch" },
            .{ .title = "Conditional Rendering", .description = "if blocks, hidden, wrappers", .prompt = "show conditional rendering patterns including if, .hidden(), and Row wrappers" },
            .{ .title = "List Rendering", .description = "for loops inside .children", .prompt = "show how to render a list with for loops, index capture, and Button" },
            .{ .title = "Form Handling", .description = "TextField, copy strings, Enter", .prompt = "a complete form with TextField, Enter key submit, and string copying to persist" },
        },
    },
};

// =============================================================================
// OPTION PILLS & MODELS
// =============================================================================

pub const Pill = struct {
    label: []const u8,
    icon: Vapor.IconType,
};

pub const OPTION_PILLS = [_]Pill{
    .{ .label = "assembler", .icon = .columns_gap },
    .{ .label = "orchastrate", .icon = .cassette },
    .{ .label = "create", .icon = .code_slash },
    .{ .label = "learn", .icon = .hammer },
    .{ .label = "model", .icon = .robot },
};

pub const MODELS = [_][]const u8{
    "claude-opus-4-6",
    "claude-sonnet-4-6",
    "claude-sonnet-4-5",
    "claude-haiku-4-5",
    "gpt-5",
    "gpt-5-mini",
};

pub const FILES = [_][]const u8{
    "Add Files or Folders",
};
