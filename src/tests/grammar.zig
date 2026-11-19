//! RFC-0001 grammar conformance corpus (M1 WP 1.1).
//!
//! Files live under `spec/grammar/` (the RFC acceptance location) and are
//! read at test time, so no build-time embed path games are needed. Valid
//! files must check clean, preprocess deterministically and format
//! idempotently; invalid files must produce the diagnostic code named in
//! their first line. Add a file and an entry below.

const std = @import("std");
const checker = @import("../rt/checker.zig");
const diag = @import("../rt/diag.zig");
const fmt = @import("../rt/fmt.zig");
const preprocess = @import("../rt/preprocess.zig");
const lossless = @import("../rt/lossless.zig");
const scan = @import("../rt/scan.zig");
const cst = @import("../rt/cst.zig");
const astdump = @import("../rt/astdump.zig");

const Case = struct { name: []const u8, path: []const u8 };
const BadCase = Case;

const valid = [_]Case{
    .{ .name = "000_label_plain", .path = "spec/grammar/valid/000_label_plain.zsx" },
    .{ .name = "001_column_classes", .path = "spec/grammar/valid/001_column_classes.zsx" },
    .{ .name = "002_row_nested", .path = "spec/grammar/valid/002_row_nested.zsx" },
    .{ .name = "003_fragment_siblings", .path = "spec/grammar/valid/003_fragment_siblings.zsx" },
    .{ .name = "004_button_click", .path = "spec/grammar/valid/004_button_click.zsx" },
    .{ .name = "005_button_legacy_event", .path = "spec/grammar/valid/005_button_legacy_event.zsx" },
    .{ .name = "006_component_button", .path = "spec/grammar/valid/006_component_button.zsx" },
    .{ .name = "007_component_dotted", .path = "spec/grammar/valid/007_component_dotted.zsx" },
    .{ .name = "008_card_slots", .path = "spec/grammar/valid/008_card_slots.zsx" },
    .{ .name = "009_section_slots", .path = "spec/grammar/valid/009_section_slots.zsx" },
    .{ .name = "010_if_else", .path = "spec/grammar/valid/010_if_else.zsx" },
    .{ .name = "011_else_if_chain", .path = "spec/grammar/valid/011_else_if_chain.zsx" },
    .{ .name = "012_for_loop", .path = "spec/grammar/valid/012_for_loop.zsx" },
    .{ .name = "013_nested_for", .path = "spec/grammar/valid/013_nested_for.zsx" },
    .{ .name = "014_switch_string", .path = "spec/grammar/valid/014_switch_string.zsx" },
    .{ .name = "015_switch_else", .path = "spec/grammar/valid/015_switch_else.zsx" },
    .{ .name = "016_self_closing_input", .path = "spec/grammar/valid/016_self_closing_input.zsx" },
    .{ .name = "017_attrs_mixed", .path = "spec/grammar/valid/017_attrs_mixed.zsx" },
    .{ .name = "018_text_expression", .path = "spec/grammar/valid/018_text_expression.zsx" },
    .{ .name = "019_multiline_attrs", .path = "spec/grammar/valid/019_multiline_attrs.zsx" },
    .{ .name = "020_fragment_control", .path = "spec/grammar/valid/020_fragment_control.zsx" },
    .{ .name = "021_spaced_control", .path = "spec/grammar/valid/021_spaced_control.zsx" },
    .{ .name = "022_loop_component_handler", .path = "spec/grammar/valid/022_loop_component_handler.zsx" },
    .{ .name = "023_component_text_content", .path = "spec/grammar/valid/023_component_text_content.zsx" },
    .{ .name = "024_nested_components", .path = "spec/grammar/valid/024_nested_components.zsx" },
    .{ .name = "025_label_plain", .path = "spec/grammar/valid/025_label_plain.zsx" },
    .{ .name = "026_column_classes", .path = "spec/grammar/valid/026_column_classes.zsx" },
    .{ .name = "027_row_nested", .path = "spec/grammar/valid/027_row_nested.zsx" },
    .{ .name = "028_fragment_siblings", .path = "spec/grammar/valid/028_fragment_siblings.zsx" },
    .{ .name = "029_button_click", .path = "spec/grammar/valid/029_button_click.zsx" },
    .{ .name = "030_button_legacy_event", .path = "spec/grammar/valid/030_button_legacy_event.zsx" },
    .{ .name = "031_component_button", .path = "spec/grammar/valid/031_component_button.zsx" },
    .{ .name = "032_component_dotted", .path = "spec/grammar/valid/032_component_dotted.zsx" },
    .{ .name = "033_card_slots", .path = "spec/grammar/valid/033_card_slots.zsx" },
    .{ .name = "034_section_slots", .path = "spec/grammar/valid/034_section_slots.zsx" },
    .{ .name = "035_if_else", .path = "spec/grammar/valid/035_if_else.zsx" },
    .{ .name = "036_else_if_chain", .path = "spec/grammar/valid/036_else_if_chain.zsx" },
    .{ .name = "037_for_loop", .path = "spec/grammar/valid/037_for_loop.zsx" },
    .{ .name = "038_nested_for", .path = "spec/grammar/valid/038_nested_for.zsx" },
    .{ .name = "039_switch_string", .path = "spec/grammar/valid/039_switch_string.zsx" },
    .{ .name = "040_switch_else", .path = "spec/grammar/valid/040_switch_else.zsx" },
    .{ .name = "041_self_closing_input", .path = "spec/grammar/valid/041_self_closing_input.zsx" },
    .{ .name = "042_attrs_mixed", .path = "spec/grammar/valid/042_attrs_mixed.zsx" },
    .{ .name = "043_text_expression", .path = "spec/grammar/valid/043_text_expression.zsx" },
    .{ .name = "044_multiline_attrs", .path = "spec/grammar/valid/044_multiline_attrs.zsx" },
    .{ .name = "045_fragment_control", .path = "spec/grammar/valid/045_fragment_control.zsx" },
    .{ .name = "046_spaced_control", .path = "spec/grammar/valid/046_spaced_control.zsx" },
    .{ .name = "047_loop_component_handler", .path = "spec/grammar/valid/047_loop_component_handler.zsx" },
    .{ .name = "048_component_text_content", .path = "spec/grammar/valid/048_component_text_content.zsx" },
    .{ .name = "049_nested_components", .path = "spec/grammar/valid/049_nested_components.zsx" },
    .{ .name = "050_label_plain", .path = "spec/grammar/valid/050_label_plain.zsx" },
    .{ .name = "051_column_classes", .path = "spec/grammar/valid/051_column_classes.zsx" },
    .{ .name = "052_row_nested", .path = "spec/grammar/valid/052_row_nested.zsx" },
    .{ .name = "053_fragment_siblings", .path = "spec/grammar/valid/053_fragment_siblings.zsx" },
    .{ .name = "054_button_click", .path = "spec/grammar/valid/054_button_click.zsx" },
    .{ .name = "055_button_legacy_event", .path = "spec/grammar/valid/055_button_legacy_event.zsx" },
    .{ .name = "056_component_button", .path = "spec/grammar/valid/056_component_button.zsx" },
    .{ .name = "057_component_dotted", .path = "spec/grammar/valid/057_component_dotted.zsx" },
    .{ .name = "058_card_slots", .path = "spec/grammar/valid/058_card_slots.zsx" },
    .{ .name = "059_section_slots", .path = "spec/grammar/valid/059_section_slots.zsx" },
    .{ .name = "060_if_else", .path = "spec/grammar/valid/060_if_else.zsx" },
    .{ .name = "061_else_if_chain", .path = "spec/grammar/valid/061_else_if_chain.zsx" },
    .{ .name = "062_for_loop", .path = "spec/grammar/valid/062_for_loop.zsx" },
    .{ .name = "063_nested_for", .path = "spec/grammar/valid/063_nested_for.zsx" },
    .{ .name = "064_switch_string", .path = "spec/grammar/valid/064_switch_string.zsx" },
    .{ .name = "065_switch_else", .path = "spec/grammar/valid/065_switch_else.zsx" },
    .{ .name = "066_self_closing_input", .path = "spec/grammar/valid/066_self_closing_input.zsx" },
    .{ .name = "067_attrs_mixed", .path = "spec/grammar/valid/067_attrs_mixed.zsx" },
    .{ .name = "068_text_expression", .path = "spec/grammar/valid/068_text_expression.zsx" },
    .{ .name = "069_multiline_attrs", .path = "spec/grammar/valid/069_multiline_attrs.zsx" },
    .{ .name = "070_fragment_control", .path = "spec/grammar/valid/070_fragment_control.zsx" },
    .{ .name = "071_spaced_control", .path = "spec/grammar/valid/071_spaced_control.zsx" },
    .{ .name = "072_loop_component_handler", .path = "spec/grammar/valid/072_loop_component_handler.zsx" },
    .{ .name = "073_component_text_content", .path = "spec/grammar/valid/073_component_text_content.zsx" },
    .{ .name = "074_nested_components", .path = "spec/grammar/valid/074_nested_components.zsx" },
    .{ .name = "075_label_plain", .path = "spec/grammar/valid/075_label_plain.zsx" },
    .{ .name = "076_column_classes", .path = "spec/grammar/valid/076_column_classes.zsx" },
    .{ .name = "077_row_nested", .path = "spec/grammar/valid/077_row_nested.zsx" },
    .{ .name = "078_fragment_siblings", .path = "spec/grammar/valid/078_fragment_siblings.zsx" },
    .{ .name = "079_button_click", .path = "spec/grammar/valid/079_button_click.zsx" },
    .{ .name = "080_button_legacy_event", .path = "spec/grammar/valid/080_button_legacy_event.zsx" },
    .{ .name = "081_component_button", .path = "spec/grammar/valid/081_component_button.zsx" },
    .{ .name = "082_component_dotted", .path = "spec/grammar/valid/082_component_dotted.zsx" },
    .{ .name = "083_card_slots", .path = "spec/grammar/valid/083_card_slots.zsx" },
    .{ .name = "084_section_slots", .path = "spec/grammar/valid/084_section_slots.zsx" },
    .{ .name = "085_if_else", .path = "spec/grammar/valid/085_if_else.zsx" },
    .{ .name = "086_else_if_chain", .path = "spec/grammar/valid/086_else_if_chain.zsx" },
    .{ .name = "087_for_loop", .path = "spec/grammar/valid/087_for_loop.zsx" },
    .{ .name = "088_nested_for", .path = "spec/grammar/valid/088_nested_for.zsx" },
    .{ .name = "089_switch_string", .path = "spec/grammar/valid/089_switch_string.zsx" },
    .{ .name = "090_switch_else", .path = "spec/grammar/valid/090_switch_else.zsx" },
    .{ .name = "091_self_closing_input", .path = "spec/grammar/valid/091_self_closing_input.zsx" },
    .{ .name = "092_attrs_mixed", .path = "spec/grammar/valid/092_attrs_mixed.zsx" },
    .{ .name = "093_text_expression", .path = "spec/grammar/valid/093_text_expression.zsx" },
    .{ .name = "094_multiline_attrs", .path = "spec/grammar/valid/094_multiline_attrs.zsx" },
    .{ .name = "095_fragment_control", .path = "spec/grammar/valid/095_fragment_control.zsx" },
    .{ .name = "096_spaced_control", .path = "spec/grammar/valid/096_spaced_control.zsx" },
    .{ .name = "097_loop_component_handler", .path = "spec/grammar/valid/097_loop_component_handler.zsx" },
    .{ .name = "098_component_text_content", .path = "spec/grammar/valid/098_component_text_content.zsx" },
    .{ .name = "099_nested_components", .path = "spec/grammar/valid/099_nested_components.zsx" },
    .{ .name = "100_empty_fragment", .path = "spec/grammar/valid/100_empty_fragment.zsx" },
    .{ .name = "101_component_self_closing", .path = "spec/grammar/valid/101_component_self_closing.zsx" },
};

const invalid = [_]struct { case: Case, expect: diag.Code }{
    .{ .case = .{ .name = "000_stray_close", .path = "spec/grammar/invalid/000_stray_close.zsx" }, .expect = .stray_close_tag },
    .{ .case = .{ .name = "001_tag_mismatch", .path = "spec/grammar/invalid/001_tag_mismatch.zsx" }, .expect = .tag_mismatch },
    .{ .case = .{ .name = "002_unclosed_tag", .path = "spec/grammar/invalid/002_unclosed_tag.zsx" }, .expect = .unclosed_tag },
    .{ .case = .{ .name = "003_stray_ctrl_close", .path = "spec/grammar/invalid/003_stray_ctrl_close.zsx" }, .expect = .stray_ctrl_close },
    .{ .case = .{ .name = "004_ctrl_mismatch", .path = "spec/grammar/invalid/004_ctrl_mismatch.zsx" }, .expect = .ctrl_mismatch },
    .{ .case = .{ .name = "005_unclosed_ctrl", .path = "spec/grammar/invalid/005_unclosed_ctrl.zsx" }, .expect = .unclosed_ctrl },
    .{ .case = .{ .name = "006_misplaced_else", .path = "spec/grammar/invalid/006_misplaced_else.zsx" }, .expect = .misplaced_else },
    .{ .case = .{ .name = "007_misplaced_case", .path = "spec/grammar/invalid/007_misplaced_case.zsx" }, .expect = .misplaced_case },
    .{ .case = .{ .name = "008_unknown_class", .path = "spec/grammar/invalid/008_unknown_class.zsx" }, .expect = .unknown_class },
    .{ .case = .{ .name = "009_legacy_alias", .path = "spec/grammar/invalid/009_legacy_alias.zsx" }, .expect = .legacy_alias },
    .{ .case = .{ .name = "010_junk_syntax", .path = "spec/grammar/invalid/010_junk_syntax.zsx" }, .expect = .junk_syntax },
    .{ .case = .{ .name = "011_unknown_prop", .path = "spec/grammar/invalid/011_unknown_prop.zsx" }, .expect = .unknown_prop },
    .{ .case = .{ .name = "012_multiple_roots", .path = "spec/grammar/invalid/012_multiple_roots.zsx" }, .expect = .multiple_roots },
    .{ .case = .{ .name = "013_top_level_text", .path = "spec/grammar/invalid/013_top_level_text.zsx" }, .expect = .stray_top_level },
    .{ .case = .{ .name = "014_missing_root", .path = "spec/grammar/invalid/014_missing_root.zsx" }, .expect = .missing_root },
    .{ .case = .{ .name = "015_stray_close", .path = "spec/grammar/invalid/015_stray_close.zsx" }, .expect = .stray_close_tag },
    .{ .case = .{ .name = "016_tag_mismatch", .path = "spec/grammar/invalid/016_tag_mismatch.zsx" }, .expect = .tag_mismatch },
    .{ .case = .{ .name = "017_unclosed_tag", .path = "spec/grammar/invalid/017_unclosed_tag.zsx" }, .expect = .unclosed_tag },
    .{ .case = .{ .name = "018_stray_ctrl_close", .path = "spec/grammar/invalid/018_stray_ctrl_close.zsx" }, .expect = .stray_ctrl_close },
    .{ .case = .{ .name = "019_ctrl_mismatch", .path = "spec/grammar/invalid/019_ctrl_mismatch.zsx" }, .expect = .ctrl_mismatch },
    .{ .case = .{ .name = "020_unclosed_ctrl", .path = "spec/grammar/invalid/020_unclosed_ctrl.zsx" }, .expect = .unclosed_ctrl },
    .{ .case = .{ .name = "021_misplaced_else", .path = "spec/grammar/invalid/021_misplaced_else.zsx" }, .expect = .misplaced_else },
    .{ .case = .{ .name = "022_misplaced_case", .path = "spec/grammar/invalid/022_misplaced_case.zsx" }, .expect = .misplaced_case },
    .{ .case = .{ .name = "023_unknown_class", .path = "spec/grammar/invalid/023_unknown_class.zsx" }, .expect = .unknown_class },
    .{ .case = .{ .name = "024_legacy_alias", .path = "spec/grammar/invalid/024_legacy_alias.zsx" }, .expect = .legacy_alias },
    .{ .case = .{ .name = "025_junk_syntax", .path = "spec/grammar/invalid/025_junk_syntax.zsx" }, .expect = .junk_syntax },
    .{ .case = .{ .name = "026_unknown_prop", .path = "spec/grammar/invalid/026_unknown_prop.zsx" }, .expect = .unknown_prop },
    .{ .case = .{ .name = "027_multiple_roots", .path = "spec/grammar/invalid/027_multiple_roots.zsx" }, .expect = .multiple_roots },
    .{ .case = .{ .name = "028_top_level_text", .path = "spec/grammar/invalid/028_top_level_text.zsx" }, .expect = .stray_top_level },
    .{ .case = .{ .name = "029_missing_root", .path = "spec/grammar/invalid/029_missing_root.zsx" }, .expect = .missing_root },
    .{ .case = .{ .name = "030_stray_close", .path = "spec/grammar/invalid/030_stray_close.zsx" }, .expect = .stray_close_tag },
    .{ .case = .{ .name = "031_tag_mismatch", .path = "spec/grammar/invalid/031_tag_mismatch.zsx" }, .expect = .tag_mismatch },
    .{ .case = .{ .name = "032_unclosed_tag", .path = "spec/grammar/invalid/032_unclosed_tag.zsx" }, .expect = .unclosed_tag },
    .{ .case = .{ .name = "033_stray_ctrl_close", .path = "spec/grammar/invalid/033_stray_ctrl_close.zsx" }, .expect = .stray_ctrl_close },
    .{ .case = .{ .name = "034_ctrl_mismatch", .path = "spec/grammar/invalid/034_ctrl_mismatch.zsx" }, .expect = .ctrl_mismatch },
    .{ .case = .{ .name = "035_unclosed_ctrl", .path = "spec/grammar/invalid/035_unclosed_ctrl.zsx" }, .expect = .unclosed_ctrl },
    .{ .case = .{ .name = "036_misplaced_else", .path = "spec/grammar/invalid/036_misplaced_else.zsx" }, .expect = .misplaced_else },
    .{ .case = .{ .name = "037_misplaced_case", .path = "spec/grammar/invalid/037_misplaced_case.zsx" }, .expect = .misplaced_case },
    .{ .case = .{ .name = "038_unknown_class", .path = "spec/grammar/invalid/038_unknown_class.zsx" }, .expect = .unknown_class },
    .{ .case = .{ .name = "039_legacy_alias", .path = "spec/grammar/invalid/039_legacy_alias.zsx" }, .expect = .legacy_alias },
    .{ .case = .{ .name = "040_junk_syntax", .path = "spec/grammar/invalid/040_junk_syntax.zsx" }, .expect = .junk_syntax },
    .{ .case = .{ .name = "041_unknown_prop", .path = "spec/grammar/invalid/041_unknown_prop.zsx" }, .expect = .unknown_prop },
    .{ .case = .{ .name = "042_multiple_roots", .path = "spec/grammar/invalid/042_multiple_roots.zsx" }, .expect = .multiple_roots },
    .{ .case = .{ .name = "043_top_level_text", .path = "spec/grammar/invalid/043_top_level_text.zsx" }, .expect = .stray_top_level },
    .{ .case = .{ .name = "044_missing_root", .path = "spec/grammar/invalid/044_missing_root.zsx" }, .expect = .missing_root },
    .{ .case = .{ .name = "045_unterminated_block", .path = "spec/grammar/invalid/045_unterminated_block.zsx" }, .expect = .unterminated_block },
    .{ .case = .{ .name = "046_unterminated_block", .path = "spec/grammar/invalid/046_unterminated_block.zsx" }, .expect = .unterminated_block },
    .{ .case = .{ .name = "047_unterminated_block", .path = "spec/grammar/invalid/047_unterminated_block.zsx" }, .expect = .unterminated_block },
};

fn read(a: std.mem.Allocator, path: []const u8) ![]u8 {
    return std.Io.Dir.cwd().readFileAlloc(std.testing.io, path, a, .limited(1 << 20));
}

/// M1 WP 1.3 slice: the CST parser accepts every valid fixture, emits no
/// diagnostics and keeps child spans ordered/contained.
fn expectCstClean(a: std.mem.Allocator, src: []const u8, name: []const u8) !void {
    const doc = try lossless.Document.init(a, src);
    const idx = try diag.LineIndex.build(a, src);
    for (doc.blocks) |blk| {
        if (!blk.closed) continue;
        var list = diag.List.init(a);
        const root = try cst.parse(a, doc.markup(blk), blk.markup_off, name, idx, &list);
        if (list.count() != 0) {
            std.debug.print("grammar cst: {s} produced {d} diagnostic(s)\n", .{ name, list.count() });
            for (list.items.items) |d| std.debug.print("  ZSX{d:0>4} {s}\n", .{ d.code.number(), d.message });
            return error.TestUnexpected;
        }
        if (!cst.treeIsOrdered(root)) {
            std.debug.print("grammar cst: {s} spans are not ordered/contained\n", .{name});
            return error.TestUnexpected;
        }
    }
}

/// M1 WP 1.2 invariant: markup tokens tile their block exactly (trivia
/// included), including on deliberately broken fixtures.
fn expectLossless(a: std.mem.Allocator, src: []const u8, name: []const u8) !void {
    const doc = try lossless.Document.init(a, src);
    for (doc.blocks) |blk| {
        if (!blk.closed) continue;
        const markup = doc.markup(blk);
        var sc = scan.Scanner.init(a, markup, blk.markup_off);
        const toks = try sc.run();
        if (!scan.coversSource(toks, markup, blk.markup_off)) {
            std.debug.print("grammar lossless: {s} tokens do not tile the block\n", .{name});
            return error.TestUnexpected;
        }
    }
}

/// Concatenated normalized dumps of every closed block in `src`.
fn normalizedAst(a: std.mem.Allocator, src: []const u8, name: []const u8) ![]u8 {
    const doc = try lossless.Document.init(a, src);
    const idx = try diag.LineIndex.build(a, src);
    var out = std.array_list.Managed(u8).init(a);
    for (doc.blocks) |blk| {
        if (!blk.closed) continue;
        var list = diag.List.init(a);
        const root = try cst.parse(a, doc.markup(blk), blk.markup_off, name, idx, &list);
        if (list.count() != 0) return error.TestUnexpected;
        const el = try cst.lowerBlock(a, root);
        try out.appendSlice(try astdump.dumpNormalized(a, el));
    }
    return out.toOwnedSlice();
}

test "grammar corpus: valid files check clean and compile deterministically" {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    const a = arena.allocator();
    for (valid) |c| {
        const src = read(a, c.path) catch |e| {
            std.debug.print("grammar valid: cannot read {s}: {s}\n", .{ c.path, @errorName(e) });
            return e;
        };
        try expectLossless(a, src, c.name);
        try expectCstClean(a, src, c.name);
        var list = diag.List.init(a);
        try checker.checkSource(a, src, c.path, .{}, &list);
        if (list.count() != 0) {
            std.debug.print("grammar valid: {s} produced {d} diagnostic(s)\n", .{ c.name, list.count() });
            for (list.items.items) |d| std.debug.print("  ZSX{d:0>4} {s}: {s}\n", .{ d.code.number(), d.message, d.help orelse "" });
            return error.TestUnexpected;
        }
        const once = try preprocess.preprocess(a, src, c.path, 0);
        const twice = try preprocess.preprocess(a, src, c.path, 0);
        try std.testing.expectEqualStrings(once, twice);
        const f1 = try fmt.formatSource(a, src, .{});
        const f2 = try fmt.formatSource(a, f1, .{});
        try std.testing.expectEqualStrings(f1, f2);
        // M1 WP 1.6 acceptance: parse(fmt(x)) ≅ parse(x). Formatting only
        // changes whitespace-only text, so compare the normalized AST dumps.
        const before = try normalizedAst(a, src, c.name);
        const after = try normalizedAst(a, f1, c.name);
        if (!std.mem.eql(u8, before, after)) {
            std.debug.print("grammar fmt: {s} changed the AST\n--- before\n{s}--- after\n{s}", .{ c.name, before, after });
            return error.TestUnexpected;
        }
    }
}

test "grammar corpus: invalid files report the expected code" {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    const a = arena.allocator();
    for (invalid) |c| {
        const src = read(a, c.case.path) catch |e| {
            std.debug.print("grammar invalid: cannot read {s}: {s}\n", .{ c.case.path, @errorName(e) });
            return e;
        };
        try expectLossless(a, src, c.case.name);
        var list = diag.List.init(a);
        try checker.checkSource(a, src, c.case.path, .{}, &list);
        var found = false;
        for (list.items.items) |d| {
            if (d.code == c.expect) {
                found = true;
                break;
            }
        }
        if (!found) {
            std.debug.print("grammar invalid: {s} expected ZSX{d:0>4}, got:\n", .{ c.case.name, c.expect.number() });
            for (list.items.items) |d| std.debug.print("  ZSX{d:0>4} {s}\n", .{ d.code.number(), d.message });
            return error.TestUnexpected;
        }
    }
}
