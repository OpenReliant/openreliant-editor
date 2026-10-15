//! The inspector's forms: a record's display name and the fields of its table, each with the
//! control its kind takes (`game.FieldKind`), a global's starting value, and a trigger's subject,
//! condition and the values it checks. A change goes into the source through the game's profile,
//! as one step of the editor's undo, once the frame is drawn (`Document.queue`).

const std = @import("std");

const App = @import("app.zig").App;
const Document = @import("mission/document.zig").Document;
const game = @import("game.zig");
const source_edit = @import("mission/edit.zig");
const panels = @import("panels.zig");
const ui = @import("ui.zig");
const fonts = ui.fonts;
const gui = ui.gui;
const theme = ui.theme;
const widgets = ui.widgets;
const px = gui.px;

/// The space between the boxes of one row, such as a vector's.
const row_gap = 4;
/// The space between a field's label and its control.
const label_gap = 8;

/// The form of a record but a trigger: its display name, the name it's declared under, a global's
/// starting value, and its table's fields, with the Scene design's labels.
pub fn record(app: *App, document: *Document, known: game.Outline, shown: game.Record, off: ?widgets.Disabled) void {
    const form: Form = .{ .app = app, .document = document, .known = known, .shown = shown, .off = off, .label_width = 84 };
    widgets.sectionHeading(panels.capitalNoun(shown.section));
    gui.space(9);
    if (shown.section != .curves and !std.mem.eql(u8, shown.word, "handler")) {
        form.label("Name", false);
        if (widgets.textField("name", shown.display, .{ .disabled = off })) |typed| form.apply(.{ .display = typed });
    }
    form.label("Declared as", false);
    _ = widgets.frame("declared", .{ .label = shown.name, .mono_label = true, .chevron = false });
    if (shown.section == .globals) {
        form.label("Value", false);
        if (widgets.textField("value", shown.detail, .{ .number = true, .disabled = off })) |typed| {
            if (form.numberText(typed)) |value| form.apply(.{ .value = value });
        }
    }
    const specs = document.profile.fields(shown);
    var index: usize = 0;
    while (index < specs.len) {
        const spec = specs[index];
        if (spec.heading) |heading| {
            gui.space(9);
            widgets.sectionHeading(heading);
            gui.space(9);
        }
        if (spec.row) |row| {
            // The fields that share the row, as a ship's angles do.
            var end = index + 1;
            while (end < specs.len and specs[end].row != null and std.mem.eql(u8, specs[end].row.?, row)) end += 1;
            form.numberRow(row, specs[index..end]);
            index = end;
            continue;
        }
        form.field(spec, spec.label orelse labelOf(spec.name), false);
        index += 1;
    }
}

/// A trigger's form: what it watches, its condition and the values it checks, how it repeats,
/// and whether it's deferred, with the Script design's labels, wide enough for the values' names.
pub fn trigger(app: *App, document: *Document, known: game.Outline, shown: game.Record, off: ?widgets.Disabled) void {
    const form: Form = .{ .app = app, .document = document, .known = known, .shown = shown, .off = off, .label_width = 96 };
    widgets.sectionHeading("Trigger");
    gui.space(9);
    form.label("Watches", false);
    const subject = known.named(shown.subject);
    if (form.pickRecord("watches", document.profile.fieldKind("Entity").record, true, if (subject) |found| found.* else null, shown.subject)) |chosen| {
        form.apply(.{ .subject = chosen orelse "nil" });
    }

    form.label("Condition", false);
    const allocator = gui.frameAllocator();
    var conditions: std.ArrayList(widgets.Choice) = .empty;
    for (app.language.words) |word| if (word.kind == .condition) {
        conditions.append(allocator, .{ .label = word.name, .mono = true }) catch break;
    };
    if (widgets.pick("condition", .{ .label = shown.condition, .mono_label = true, .disabled = off }, conditions.items)) |index| {
        form.apply(.{ .condition = conditions.items[index].label });
    }
    if (app.language.find(shown.condition)) |word| {
        form.note(gui.print("{s} · {s}", .{ word.source, word.about }));
        // The values the condition's events carry, which the trigger can check.
        for (word.parameters) |parameter| {
            const spec: game.FieldForm = .{ .name = parameter.name, .about = parameter.label, .kind = document.profile.fieldKind(parameter.type) };
            form.field(spec, parameter.name, true);
        }
    }

    const repeats = fieldOf(shown, "repeats");
    const repeat_index: usize = if (repeats) |given| (if (std.mem.eql(u8, given.value, "\"always\"")) 1 else if (std.mem.eql(u8, given.value, "\"once\"")) 0 else 2) else 0;
    form.label("Repeats", false);
    if (widgets.segmented("repeats", &.{ "Once", "Always", "Counted" }, repeat_index, off)) |chosen| if (chosen != repeat_index) {
        const value: ?[]const u8 = switch (chosen) {
            0 => null,
            1 => "\"always\"",
            else => "{ counted = 1 }",
        };
        if (value != null or repeats != null) form.set("repeats", value);
    };
    for (document.profile.fields(shown)) |spec| if (std.mem.eql(u8, spec.name, "component")) form.field(spec, labelOf(spec.name), false);
    form.label("Deferred", false);
    const deferred = fieldOf(shown, "deferred");
    const checked = if (deferred) |given| std.mem.eql(u8, given.value, "true") else false;
    if (widgets.checkbox("deferred", "Run on scheduler", checked, off)) form.set("deferred", if (checked) null else "true");
}

/// What a form works on, and how it lays out its labels.
const Form = struct {
    app: *App,
    document: *Document,
    known: game.Outline,
    shown: game.Record,
    off: ?widgets.Disabled,
    /// The width of its labels, in design pixels.
    label_width: f32,

    fn label(form: Form, text: []const u8, mono: bool) void {
        widgets.fieldLabelWidth(text, mono, form.label_width);
    }

    /// A line of text under the controls, as a condition's description or the angles' unit.
    fn note(form: Form, text: []const u8) void {
        const left = gui.cursor().x;
        gui.setCursor(.{ .x = left + px(form.label_width + label_gap), .y = gui.cursor().y });
        widgets.caption(text, theme.text_dim, fonts.size.small, .regular);
        gui.setCursor(.{ .x = left, .y = gui.cursor().y + px(3) });
    }

    /// A field's row: its label, in code's letters for a name the script uses, and the control its
    /// kind takes.
    fn field(form: Form, spec: game.FieldForm, text: []const u8, mono: bool) void {
        form.label(text, mono);
        gui.tooltip(spec.about);
        gui.pushId(spec.name);
        defer gui.popId();
        const given = fieldOf(form.shown, spec.name);
        switch (spec.kind) {
            .record => |sections| {
                const target = if (given) |found| (if (found.names_record) form.known.named(found.value) else null) else null;
                const current = if (target) |found| found.* else null;
                if (form.pickRecord("record", sections, spec.optional, current, if (given) |found| found.value else "none")) |chosen| {
                    if (chosen != null or given != null) form.set(spec.name, chosen);
                }
            },
            .value => |type_name| {
                var names: std.ArrayList([]const u8) = .empty;
                for (form.app.language.words) |word| if (word.kind == .value and std.mem.eql(u8, word.type, type_name)) {
                    names.append(gui.frameAllocator(), word.name) catch break;
                };
                form.pickName(spec, given, names.items);
            },
            .strings => |names| form.pickName(spec, given, names),
            .vector => form.vector(spec, given),
            .number => if (widgets.textField("number", if (given) |found| found.value else "", .{ .number = true, .hint = if (spec.optional) "none" else null, .disabled = form.off })) |typed| {
                if (std.mem.trim(u8, typed, " ").len == 0 and spec.optional) {
                    if (given != null) form.set(spec.name, null);
                } else if (form.numberText(typed)) |value| form.set(spec.name, value);
            },
            .boolean => {
                const checked = if (given) |found| std.mem.eql(u8, found.value, "true") else false;
                if (widgets.checkbox("boolean", "", checked, form.off)) form.set(spec.name, if (checked) null else "true");
            },
            .source => if (widgets.textField("source", if (given) |found| found.source else "", .{ .mono = true, .hint = "none", .disabled = form.off })) |typed| {
                const trimmed = std.mem.trim(u8, typed, " ");
                if (trimmed.len == 0) {
                    if (given != null) form.set(spec.name, null);
                } else form.set(spec.name, trimmed);
            },
        }
    }

    /// A vector's three boxes, X, Y and Z in their colours. A vector left out shows the origin.
    fn vector(form: Form, spec: game.FieldForm, given: ?game.Field) void {
        var values: [3]f64 = @splat(0);
        if (given) |found| parseVector(found.value, &values);
        const tags = [3]widgets.Tag{
            .{ .letter = "X", .color = theme.axis_x },
            .{ .letter = "Y", .color = theme.axis_y },
            .{ .letter = "Z", .color = theme.axis_z },
        };
        const at = gui.cursor();
        const each = (gui.available().x - px(row_gap) * 2) / 3;
        for (tags, 0..) |tag, axis| {
            gui.setCursor(.{ .x = at.x + @as(f32, @floatFromInt(axis)) * (each + px(row_gap)), .y = at.y });
            gui.pushIdInt(axis);
            defer gui.popId();
            const typed = widgets.textField("axis", gui.print("{d}", .{values[axis]}), .{ .number = true, .tag = tag, .width = each, .disabled = form.off }) orelse continue;
            values[axis] = std.fmt.parseFloat(f64, std.mem.trim(u8, typed, " ")) catch {
                form.app.toasts.push(.info, "Not a number", typed);
                continue;
            };
            form.set(spec.name, source_edit.vector(gui.frameAllocator(), &values) catch return);
        }
    }

    /// Number fields that share a row, each with its letter, as a ship's angles, and the last
    /// one's note under them. A field left out shows 0.
    fn numberRow(form: Form, text: []const u8, specs: []const game.FieldForm) void {
        form.label(text, false);
        gui.tooltip(specs[0].about);
        const at = gui.cursor();
        const count: f32 = @floatFromInt(specs.len);
        const each = (gui.available().x - px(row_gap) * (count - 1)) / count;
        for (specs, 0..) |spec, place| {
            gui.setCursor(.{ .x = at.x + @as(f32, @floatFromInt(place)) * (each + px(row_gap)), .y = at.y });
            gui.pushId(spec.name);
            defer gui.popId();
            const given = fieldOf(form.shown, spec.name);
            const tag: widgets.Tag = .{ .letter = spec.letter, .color = theme.axis_off, .text = theme.text };
            if (widgets.textField("number", if (given) |found| found.value else "0", .{ .number = true, .tag = tag, .width = each, .disabled = form.off })) |typed| {
                if (form.numberText(typed)) |value| form.set(spec.name, value);
            }
        }
        if (specs[specs.len - 1].note) |shown| form.note(shown);
    }

    /// The list of a field that takes one of `names`, such as a ship type or a wing, written as a
    /// string, with `none` first where it can be left out.
    fn pickName(form: Form, spec: game.FieldForm, given: ?game.Field, names: []const []const u8) void {
        const allocator = gui.frameAllocator();
        var choices: std.ArrayList(widgets.Choice) = .empty;
        if (spec.optional) choices.append(allocator, .{ .label = "none", .dim = true }) catch return;
        for (names) |name| choices.append(allocator, .{ .label = name, .mono = true }) catch return;
        const frame: widgets.Frame = if (given) |found|
            .{ .label = std.mem.trim(u8, found.value, "\""), .mono_label = true, .disabled = form.off }
        else
            .{ .label = "none", .dim_label = true, .disabled = form.off };
        const index = widgets.pick("name", frame, choices.items) orelse return;
        if (spec.optional and index == 0) {
            if (given != null) form.set(spec.name, null);
            return;
        }
        form.set(spec.name, source_edit.string(allocator, choices.items[index].label) catch return);
    }

    /// The list of the records of `sections`, with `none` first where the value can be left out:
    /// the name of the record chosen, or null for `none`, once one is chosen. `current` is the
    /// record the value names; `value`, the value as the source writes it, shows where it names
    /// none.
    fn pickRecord(form: Form, id: []const u8, sections: []const game.Section, optional: bool, current: ?game.Record, value: []const u8) ??[]const u8 {
        const allocator = gui.frameAllocator();
        var choices: std.ArrayList(widgets.Choice) = .empty;
        var names: std.ArrayList(?[]const u8) = .empty;
        if (optional) {
            choices.append(allocator, .{ .label = "none", .dim = true }) catch return null;
            names.append(allocator, null) catch return null;
        }
        for (form.known.records) |candidate| {
            if (candidate.name.len == 0 or std.mem.findScalar(game.Section, sections, candidate.section) == null) continue;
            choices.append(allocator, .{ .label = candidate.title, .detail = candidate.name, .mark = markOf(candidate) }) catch return null;
            names.append(allocator, candidate.name) catch return null;
        }
        const frame: widgets.Frame = if (current) |found|
            .{ .label = found.title, .detail = found.name, .mark = markOf(found), .disabled = form.off }
        else if (std.mem.eql(u8, value, "none") or std.mem.eql(u8, value, "nil"))
            .{ .label = "none", .dim_label = true, .disabled = form.off }
        else
            .{ .label = value, .mono_label = true, .disabled = form.off };
        const index = widgets.pick(id, frame, choices.items) orelse return null;
        return names.items[index];
    }

    /// Sets the field `name` of the record's table to `value`, or takes it out with null.
    fn set(form: Form, name: []const u8, value: ?[]const u8) void {
        form.apply(.{ .field = .{ .name = name, .value = value } });
    }

    /// Asks for `edit` to the record, which the app makes once the frame is drawn.
    fn apply(form: Form, edit: game.Edit) void {
        form.document.queue(.{ .edit = .{ .section = form.shown.section, .index = form.shown.index, .edit = edit } });
    }

    /// `typed` as mission source writes a number, or null where it isn't one, which a toast says.
    fn numberText(form: Form, typed: []const u8) ?[]const u8 {
        const value = std.fmt.parseFloat(f64, std.mem.trim(u8, typed, " ")) catch {
            form.app.toasts.push(.info, "Not a number", typed);
            return null;
        };
        return source_edit.number(gui.frameAllocator(), value) catch null;
    }
};

/// A record's mark in a list: a flight group's colour, or its section's icon in its group's.
fn markOf(shown: game.Record) widgets.RowMark {
    if (shown.section == .flight_groups) return .{ .swatch = panels.groupColor(shown) };
    return .{ .icon = .{ .icon = panels.sectionIcon(shown.section), .color = panels.groupColor(shown) } };
}

/// The field `name` of `shown`'s table, if it gives one.
fn fieldOf(shown: game.Record, name: []const u8) ?game.Field {
    for (shown.fields) |given| if (std.mem.eql(u8, given.name, name)) return given;
    return null;
}

/// A field's label from its name: `component` as `Component`, and `_` as a space.
fn labelOf(name: []const u8) []const u8 {
    const made = gui.frameAllocator().dupe(u8, name) catch return name;
    std.mem.replaceScalar(u8, made, '_', ' ');
    if (made.len > 0) made[0] = std.ascii.toUpper(made[0]);
    return made;
}

/// The numbers of a vector as the outline shows it, `{ -2000, 0, 42000 }`, into `values`; the ones
/// it doesn't give stay as they are.
fn parseVector(text: []const u8, values: *[3]f64) void {
    var parts = std.mem.tokenizeAny(u8, text, "{}, ");
    for (values) |*value| {
        const part = parts.next() orelse return;
        value.* = std.fmt.parseFloat(f64, part) catch return;
    }
}

test labelOf {
    try std.testing.expectEqualStrings("Formation point", labelOf("formation_point"));
}

test parseVector {
    var values: [3]f64 = @splat(0);
    parseVector("{ -2000, 0, 42000.5 }", &values);
    try std.testing.expectEqual([3]f64{ -2000, 0, 42000.5 }, values);
    parseVector("…", &values);
    try std.testing.expectEqual([3]f64{ -2000, 0, 42000.5 }, values);
}
