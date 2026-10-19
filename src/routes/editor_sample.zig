const std = @import("std");
const Vapor = @import("vapor");
const Stack = Vapor.Stack;
const Row = Vapor.Row;
const Text = Vapor.Text;
const TextFmt = Vapor.TextFmt;
const Button = Vapor.Button;
const TextField = Vapor.TextField;
const TextArea = Vapor.TextArea;
const Center = Vapor.Center;
const Icon = Vapor.Icon;
const Spacer = Vapor.Spacer;

// Theme - Brutalist Mirror's Edge inspired
pub const Theme = struct {
    pub const primary = Vapor.Types.Color.hex("#FF0000"); // Bold red
    pub const secondary = Vapor.Types.Color.hex("#0066FF"); // Electric blue
    pub const accent = Vapor.Types.Color.hex("#FFFF00"); // Sharp yellow
    pub const black = Vapor.Types.Color.hex("#000000");
    pub const white = Vapor.Types.Color.hex("#FFFFFF");
    pub const gray_100 = Vapor.Types.Color.hex("#F5F5F5");
    pub const gray_200 = Vapor.Types.Color.hex("#E0E0E0");
    pub const gray_300 = Vapor.Types.Color.hex("#BDBDBD");
    pub const gray_800 = Vapor.Types.Color.hex("#424242");
    pub const shadow = Vapor.Types.Color.hex("#00000033");
};

// Data structures
const Note = struct {
    id: u32,
    title: []const u8,
    content: []const u8,
    preview: []const u8,
};

// State
var notes = Vapor.persist.Array(Note);
var next_id: u32 = 1;
var selected_id: ?u32 = null;
var title_input: []const u8 = "";
var editor_content: []const u8 = "";
var preview_content: []const u8 = "";
var is_editing: bool = false;

export fn init() void {
    Vapor.init(.{});
    Vapor.Page(.{ .route = "/" }, render, null);
    // Add a sample note
    notes.append(.{
        .id = next_id,
        .title = Vapor.persist.dupe("Welcome to Notes"),
        .content = Vapor.persist.dupe("# Welcome\n\nThis is a **brutalist** notes app.\n\n## Features\n- Clean geometric design\n- Bold colors\n- Markdown support"),
        .preview = Vapor.persist.dupe(""),
    });
    next_id += 1;
}

fn createNote() void {
    const new_id = next_id;
    notes.append(.{
        .id = new_id,
        .title = Vapor.persist.dupe("Untitled Note"),
        .content = Vapor.persist.dupe(""),
        .preview = Vapor.persist.dupe(""),
    });
    next_id += 1;
    selectNote(new_id);
}

fn selectNote(id: u32) void {
    selected_id = id;
    is_editing = false;

    for (notes.items) |note| {
        if (note.id == id) {
            title_input = note.title;
            editor_content = note.content;
            preview_content = note.content;
            break;
        }
    }
}

fn deleteNote(id: u32) void {
    var i: usize = 0;
    while (i < notes.items.len) : (i += 1) {
        if (notes.items[i].id == id) {
            _ = notes.orderedRemove(i);
            if (selected_id == id) {
                selected_id = null;
                title_input = "";
                editor_content = "";
                preview_content = "";
            }
            break;
        }
    }
}

fn saveNote() void {
    if (selected_id) |id| {
        for (notes.items) |*note| {
            if (note.id == id) {
                note.title = Vapor.persist.dupe(title_input);
                note.content = Vapor.persist.dupe(editor_content);
                note.preview = Vapor.persist.dupe(editor_content);
                is_editing = false;
                preview_content = editor_content;
                break;
            }
        }
    }
}

fn startEditing() void {
    is_editing = true;
}

fn cancelEditing() void {
    if (selected_id) |id| {
        for (notes.items) |note| {
            if (note.id == id) {
                title_input = note.title;
                editor_content = note.content;
                preview_content = note.content;
                is_editing = false;
                break;
            }
        }
    }
}

fn renderSidebar() void {
    Stack()
        .width(.px(280))
        .height(.percent(100))
        .background(Theme.black)
        .border(.simple(Theme.primary))
        .children({

        // Header
        Stack()
            .padding(.all(20))
            .background(Theme.primary)
            .border(.bottom(4, Theme.black))
            .children({
            Text("NOTES")
                .font(24, 900, Theme.black)
                .fontFamily("monospace")
                .end();

            Text("BRUTALIST EDITOR")
                .font(10, 700, Theme.black)
                .fontFamily("monospace")
                .mt(4)
                .end();
        });

        // New note button
        Button(createNote, .{})
            .padding(.all(16))
            .background(Theme.secondary)
            .border(.bottom(3, Theme.black))
            .pointer()
            .hoverBackground(Theme.accent)
            .children({
            Row()
                .spacing(8)
                .layout(.center)
                .children({
                Text("[+]")
                    .font(16, 900, Theme.black)
                    .fontFamily("monospace")
                    .end();

                Text("NEW NOTE")
                    .font(12, 700, Theme.black)
                    .fontFamily("monospace")
                    .end();
            });
        });

        // Notes list
        Stack()
            .scroll(.scroll_y())
            .height(.expand)
            .children({
            if (notes.items.len == 0) {
                Stack()
                    .padding(.all(20))
                    .children({
                    Text("NO NOTES")
                        .font(12, 700, Theme.gray_300)
                        .fontFamily("monospace")
                        .end();
                });
            } else {
                for (notes.items) |note| {
                    renderNoteItem(note);
                }
            }
        });
    });
}

fn renderNoteItem(note: Note) void {
    const is_selected = if (selected_id) |id| id == note.id else false;

    Stack()
        .padding(.all(16))
        .background(if (is_selected) Theme.primary else Theme.black)
        .border(.bottom(2, if (is_selected) Theme.black else Theme.gray_800))
        .pointer()
        .hoverBackground(if (is_selected) Theme.primary else Theme.gray_800)
        .children({
        Button(selectNote, .{note.id})
            .width(.percent(100))
            .layout(.left_center)
            .children({
            Stack()
                .spacing(4)
                .width(.percent(100))
                .children({
                Text(note.title)
                    .font(14, 700, if (is_selected) Theme.black else Theme.white)
                    .fontFamily("monospace")
                    .end();

                // Preview first line
                const preview_text = if (note.content.len > 40)
                    note.content[0..40]
                else
                    note.content;

                Text(preview_text)
                    .font(11, 400, if (is_selected) Theme.gray_800 else Theme.gray_300)
                    .fontFamily("monospace")
                    .end();
            });
        });

        // Delete button
        Button(deleteNote, .{note.id})
            .padding(.all(4))
            .mt(8)
            .background(Vapor.Types.Color.transparent)
            .border(.simple(if (is_selected) Theme.black else Theme.primary))
            .pointer()
            .hoverBackground(Theme.primary)
            .children({
            Text("[DELETE]")
                .font(10, 700, if (is_selected) Theme.black else Theme.primary)
                .fontFamily("monospace")
                .end();
        });
    });
}

fn renderEditor() void {
    Stack()
        .width(.expand)
        .height(.percent(100))
        .background(Theme.gray_100)
        .border(.simple(Theme.black))
        .children({
        if (selected_id == null) {
            Center()
                .height(.percent(100))
                .children({
                Stack()
                    .spacing(16)
                    .layout(.center)
                    .children({
                    Text("[ SELECT A NOTE ]")
                        .font(24, 900, Theme.black)
                        .fontFamily("monospace")
                        .end();

                    Text("OR CREATE A NEW ONE")
                        .font(14, 700, Theme.gray_300)
                        .fontFamily("monospace")
                        .end();
                });
            });
        } else {
            // Top bar with title and actions
            Stack()
                .padding(.all(20))
                .background(Theme.white)
                .border(.bottom(4, Theme.black))
                .children({
                Row()
                    .layout(.x_between_center)
                    .spacing(16)
                    .children({
                    if (is_editing) {
                        TextField(.string)
                            .bind(&title_input)
                            .width(.expand)
                            .padding(.all(12))
                            .background(Theme.gray_100)
                            .border(.simple(Theme.black))
                            .font(18, 900, Theme.black)
                            .fontFamily("monospace")
                            .end();
                    } else {
                        Text(title_input)
                            .font(18, 900, Theme.black)
                            .fontFamily("monospace")
                            .end();
                    }

                    Row()
                        .spacing(8)
                        .children({
                        if (is_editing) {
                            Button(saveNote, .{})
                                .padding(.tblr(8, 8, 16, 16))
                                .background(Theme.primary)
                                .border(.simple(Theme.black))
                                .pointer()
                                .hoverScale()
                                .children({
                                Text("[SAVE]")
                                    .font(12, 700, Theme.black)
                                    .fontFamily("monospace")
                                    .end();
                            });

                            Button(cancelEditing, .{})
                                .padding(.tblr(8, 8, 16, 16))
                                .background(Theme.gray_200)
                                .border(.simple(Theme.black))
                                .pointer()
                                .hoverScale()
                                .children({
                                Text("[CANCEL]")
                                    .font(12, 700, Theme.black)
                                    .fontFamily("monospace")
                                    .end();
                            });
                        } else {
                            Button(startEditing, .{})
                                .padding(.tblr(8, 8, 16, 16))
                                .background(Theme.secondary)
                                .border(.simple(Theme.black))
                                .pointer()
                                .hoverScale()
                                .children({
                                Text("[EDIT]")
                                    .font(12, 700, Theme.black)
                                    .fontFamily("monospace")
                                    .end();
                            });
                        }
                    });
                });
            });

            // Content area
            if (is_editing) {
                Stack()
                    .height(.expand)
                    .padding(.all(20))
                    .children({
                    TextArea()
                        .bind(&editor_content)
                        .width(.percent(100))
                        .height(.percent(100))
                        .padding(.all(16))
                        .background(Theme.white)
                        .border(.simple(Theme.black))
                        .font(14, 400, Theme.black)
                        .fontFamily("monospace")
                        .whiteSpace(.pre)
                        .caret(.{ .color = Theme.primary, .type = .line })
                        .end();
                });
            } else {
                Stack()
                    .height(.expand)
                    .padding(.all(20))
                    .scroll(.scroll_y())
                    .children({
                    Stack()
                        .padding(.all(24))
                        .background(Theme.white)
                        .border(.simple(Theme.black))
                        .shadow(.card(Theme.shadow))
                        .children({
                        renderMarkdownPreview(preview_content);
                    });
                });
            }
        }
    });
}

fn renderMarkdownPreview(content: []const u8) void {
    // Simple markdown rendering
    var lines = Vapor.Kit.split(content, "\n");

    while (lines.next()) |line| {
        if (line.len == 0) {
            Spacer(12).end();
            continue;
        }

        // Headings
        if (Vapor.Kit.startsWith(line, "# ")) {
            Text(line[2..])
                .font(28, 900, Theme.black)
                .fontFamily("monospace")
                .mb(16)
                .end();
        } else if (Vapor.Kit.startsWith(line, "## ")) {
            Text(line[3..])
                .font(22, 900, Theme.black)
                .fontFamily("monospace")
                .mb(12)
                .end();
        } else if (Vapor.Kit.startsWith(line, "### ")) {
            Text(line[4..])
                .font(18, 700, Theme.black)
                .fontFamily("monospace")
                .mb(10)
                .end();
        } else if (Vapor.Kit.startsWith(line, "- ")) {
            Row()
                .spacing(8)
                .mb(8)
                .children({
                Text("[•]")
                    .font(14, 700, Theme.primary)
                    .fontFamily("monospace")
                    .end();

                Text(line[2..])
                    .font(14, 400, Theme.black)
                    .fontFamily("monospace")
                    .end();
            });
        } else {
            // Regular text with bold/italic support
            Text(line)
                .font(14, 400, Theme.black)
                .fontFamily("monospace")
                .mb(8)
                .end();
        }
    }
}

fn render() void {
    Row()
        .width(.percent(100))
        .height(.percent(100))
        .background(Theme.black)
        .children({
        renderSidebar();
        renderEditor();
    });
}
