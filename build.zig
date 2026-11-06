const std = @import("std");
const ast = @import("src/ast.zig");
const zsx_parser = @import("src/parser.zig");
const style_mod = @import("src/style.zig");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const zsx_files = [_][]const u8{
        "src/views/demo.zsx",
        "src/views/component_demo.zsx",
        "src/views/shadcn_demo.zsx",
        "src/views/shadcn_lib_demo.zsx",
        "src/views/onclick_demo.zsx",
        "src/views/struct_loop_demo.zsx",
        "src/views/card_if_demo.zsx",
        "src/views/else_if_demo.zsx",
        "src/views/fragment_demo.zsx",
        "src/views/class_override_demo.zsx",
        "src/views/nested_card_demo.zsx",
        "src/views/dashboard.zsx",
        "src/views/extended_styles_demo.zsx",
    };

    inline for (zsx_files, 0..) |path, file_idx| {
        const raw = @embedFile(path);
        const source = comptime trimSpace(raw);
        const generated = comptime generateView(source, path, file_idx);
        const out_path = comptime deriveOutputName(path);
        writeIfChanged(b, out_path, generated) catch |err| {
            std.debug.print("zsx: write {s}: {}\n", .{ out_path, err });
            @panic("zsx codegen write failed");
        };
    }

    const zsx_mod = b.addModule("zsx", .{
        .root_source_file = b.path("src/root.zig"),
        .target = target,
        .optimize = optimize,
    });

    const test_step = b.step("test", "Run unit tests");
    const tests = b.addTest(.{ .root_module = zsx_mod });
    test_step.dependOn(&b.addRunArtifact(tests).step);

    const hello_mod = b.createModule(.{
        .root_source_file = b.path("src/hello.zig"),
        .target = target,
        .optimize = optimize,
    });
    const hello_exe = b.addExecutable(.{ .name = "zsx-hello", .root_module = hello_mod });
    const hello_run = b.addRunArtifact(hello_exe);
    hello_run.has_side_effects = true;
    const example_step = b.step("example", "Run the hello example");
    example_step.dependOn(&hello_run.step);

    const nanoui_hello_mod = b.createModule(.{
        .root_source_file = b.path("src/nanoui_hello.zig"),
        .target = target,
        .optimize = optimize,
    });
    const nanoui_hello_exe = b.addExecutable(.{ .name = "zsx-nanoui-hello", .root_module = nanoui_hello_mod });
    const nanoui_hello_run = b.addRunArtifact(nanoui_hello_exe);
    nanoui_hello_run.has_side_effects = true;
    const nanoui_example_step = b.step("example-nanoui", "Run the nanoui example");
    nanoui_example_step.dependOn(&nanoui_hello_run.step);

    const dvui_dep = b.dependency("dvui", .{
        .target = target,
        .optimize = optimize,
        .backend = .sdl3,
    });
    const real_hello_mod = b.createModule(.{
        .root_source_file = b.path("src/hello_dvui.zig"),
        .target = target,
        .optimize = optimize,
    });
    real_hello_mod.addImport("dvui", dvui_dep.module("dvui_sdl3"));
    real_hello_mod.addImport("sdl-backend", dvui_dep.module("sdl3"));
    const real_hello_exe = b.addExecutable(.{ .name = "zsx-hello-dvui", .root_module = real_hello_mod });
    const install_real = b.addInstallArtifact(real_hello_exe, .{});
    b.getInstallStep().dependOn(&install_real.step);
    const build_app_step = b.step("build-app-dvui", "Build DVUI binary (real backend)");
    build_app_step.dependOn(&install_real.step);

    const nanoui_dep = b.dependency("nanoui", .{
        .target = target,
        .optimize = optimize,
    });
    const real_nanoui_mod = b.createModule(.{
        .root_source_file = b.path("src/hello_nanoui.zig"),
        .target = target,
        .optimize = optimize,
        .link_libc = true,
    });
    real_nanoui_mod.addImport("nanoui", nanoui_dep.module("nanoui"));
    const real_nanoui_exe = b.addExecutable(.{ .name = "zsx-hello-nanoui", .root_module = real_nanoui_mod });
    const install_real_nanoui = b.addInstallArtifact(real_nanoui_exe, .{});
    b.getInstallStep().dependOn(&install_real_nanoui.step);
    const build_app_nanoui_step = b.step("build-app-nanoui", "Build the real nanoui app");
    build_app_nanoui_step.dependOn(&install_real_nanoui.step);
    const build_app_alias = b.step("build-app", "Alias for build-app-dvui");
    build_app_alias.dependOn(&install_real.step);
    const build_all_step = b.step("build-all", "Build both real binaries");
    build_all_step.dependOn(&install_real.step);
    build_all_step.dependOn(&install_real_nanoui.step);

    const real_hello_release_mod = b.createModule(.{
        .root_source_file = b.path("src/hello_dvui.zig"),
        .target = target,
        .optimize = .ReleaseSafe,
    });
    real_hello_release_mod.addImport("dvui", dvui_dep.module("dvui_sdl3"));
    real_hello_release_mod.addImport("sdl-backend", dvui_dep.module("sdl3"));
    const real_hello_release_exe = b.addExecutable(.{ .name = "zsx-hello-dvui-release", .root_module = real_hello_release_mod });
    const install_real_release = b.addInstallArtifact(real_hello_release_exe, .{});
    const build_app_release_step = b.step("build-app-dvui-release", "Build DVUI binary, ReleaseSafe");
    build_app_release_step.dependOn(&install_real_release.step);
}

const EmitResult = struct {
    code: []const u8,
    preamble: []const u8,
    next_id: usize,
};

fn isWs(c: u8) bool {
    return c == ' ' or c == '\t' or c == '\n' or c == '\r';
}

fn trimSpace(comptime s: []const u8) []const u8 {
    var start: usize = 0;
    while (start < s.len and isWs(s[start])) start += 1;
    var end = s.len;
    while (end > start and isWs(s[end - 1])) end -= 1;
    return s[start..end];
}

fn isWhitespaceOnly(comptime s: []const u8) bool {
    for (s) |c| if (!isWs(c)) return false;
    return true;
}

fn isUpper(c: u8) bool {
    return c >= 'A' and c <= 'Z';
}

fn hasElementChildren(comptime el: ast.Element) bool {
    inline for (el.children) |c| {
        switch (c) {
            .element => return true,
            else => continue,
        }
    }
    return false;
}

fn hasTextChild(comptime el: ast.Element) bool {
    inline for (el.children) |c| {
        switch (c) {
            .text => |t| {
                if (comptime !isWhitespaceOnly(t)) return true;
            },
            .expression => return true,
            .element => continue,
        }
    }
    return false;
}

fn writeIfChanged(b: *std.Build, path: []const u8, content: []const u8) !void {
    const io = b.graph.io;
    const dir = std.Io.Dir.cwd();
    if (dir.readFileAlloc(io, path, std.heap.page_allocator, .limited(1 << 20))) |existing| {
        defer std.heap.page_allocator.free(existing);
        if (std.mem.eql(u8, existing, content)) return;
    } else |_| {}
    try dir.writeFile(io, .{
        .sub_path = path,
        .data = content,
        .flags = .{ .truncate = true },
    });
}

fn deriveOutputName(comptime input_path: []const u8) []const u8 {
    const stem = input_path[0 .. input_path.len - ".zsx".len];
    return stem ++ "_gen.zig";
}

fn fmtInt(comptime n: u32) []const u8 {
    return comptime blk: {
        if (n == 0) break :blk "0";
        var tmp: [12]u8 = undefined;
        var len: usize = 0;
        var v = n;
        while (v > 0) {
            tmp[len] = '0' + @as(u8, @intCast(v % 10));
            v /= 10;
            len += 1;
        }
        var out: [12]u8 = undefined;
        for (0..len) |i| out[i] = tmp[len - 1 - i];
        const result: [len]u8 = out[0..len].*;
        break :blk &result;
    };
}

fn fmtF32(comptime v: f32) []const u8 {
    const iv: u32 = @intFromFloat(v);
    return fmtInt(iv);
}

fn fmtUsize(comptime n: usize) []const u8 {
    return comptime blk: {
        if (n == 0) break :blk "0";
        var tmp: [20]u8 = undefined;
        var len: usize = 0;
        var v = n;
        while (v > 0) {
            tmp[len] = '0' + @as(u8, @intCast(v % 10));
            v /= 10;
            len += 1;
        }
        var out: [20]u8 = undefined;
        for (0..len) |i| out[i] = tmp[len - 1 - i];
        const result: [len]u8 = out[0..len].*;
        break :blk &result;
    };
}

fn idExpr(comptime base_id: usize, comptime loop_depth: usize) []const u8 {
    @setEvalBranchQuota(200_000);
    if (loop_depth == 0) return fmtUsize(base_id);
    var expr: []const u8 = fmtUsize(base_id) ++ " + idx_0";
    comptime var j: usize = 1;
    comptime var factor: usize = 1000;
    inline while (j < loop_depth) : (j += 1) {
        expr = expr ++ " + idx_" ++ fmtInt(@intCast(j)) ++ " * " ++ fmtUsize(factor);
        factor *= 1000;
    }
    return expr;
}

fn generateView(comptime source: []const u8, comptime path: []const u8, comptime file_index: usize) []const u8 {
    @setEvalBranchQuota(500_000);
    const root = comptime zsx_parser.parse(source);
    const result = comptime emitElement(root, 1, 0, 0, file_index);
    var out: []const u8 = "";
    out = out ++ "// generated by zsx from " ++ path ++ "\n";
    out = out ++ "// regenerate with: zig build\n";
    out = out ++ "// do not edit by hand\n\n";
    out = out ++ result.preamble;
    out = out ++ "pub fn view(ui: anytype, c: anytype, ctx: anytype) void {\n";
    const ui_used = comptime std.mem.indexOf(u8, result.code, "ui.") != null or
        std.mem.indexOf(u8, result.code, "ui,") != null or
        std.mem.indexOf(u8, result.code, "ui)") != null;
    const c_used = comptime std.mem.indexOf(u8, result.code, "(c,") != null or
        std.mem.indexOf(u8, result.code, ", c,") != null or
        std.mem.indexOf(u8, result.code, "(c)") != null;
    const ctx_used = comptime std.mem.indexOf(u8, result.code, "ctx.") != null;
    if (!ui_used) {
        out = out ++ "    _ = ui;\n";
    }
    if (!c_used) {
        out = out ++ "    _ = c;\n";
    }
    if (!ctx_used) {
        out = out ++ "    _ = ctx;\n";
    }
    out = out ++ result.code;
    out = out ++ "}\n";
    return out;
}

fn emitElement(comptime el: ast.Element, comptime level: usize, comptime start_id: usize, comptime loop_depth: usize, comptime file_index: usize) EmitResult {
    @setEvalBranchQuota(500_000);

    if (comptime el.tag.len == 0) {
        return comptime emitChildren(el.children, level, start_id, loop_depth, file_index);
    }

    const indent = makeIndent(level);

    if (comptime std.mem.eql(u8, el.tag, "column")) {
        const box_name = "b_" ++ fmtInt(@intCast(start_id));
        const inner = comptime emitChildren(el.children, level + 1, start_id + 1, loop_depth, file_index);
        var out: []const u8 = "";
        out = out ++ indent ++ "{\n";
        out = out ++ indent ++ "    var " ++ box_name ++ " = ui.column(c, " ++ optsLiteral(el, start_id, loop_depth, file_index) ++ ");\n";
        out = out ++ indent ++ "    defer " ++ box_name ++ ".end();\n";
        out = out ++ inner.code;
        out = out ++ indent ++ "}\n";
        return .{ .code = out, .preamble = inner.preamble, .next_id = inner.next_id };
    } else if (comptime std.mem.eql(u8, el.tag, "row")) {
        const box_name = "b_" ++ fmtInt(@intCast(start_id));
        const inner = comptime emitChildren(el.children, level + 1, start_id + 1, loop_depth, file_index);
        var out: []const u8 = "";
        out = out ++ indent ++ "{\n";
        out = out ++ indent ++ "    var " ++ box_name ++ " = ui.row(c, " ++ optsLiteral(el, start_id, loop_depth, file_index) ++ ");\n";
        out = out ++ indent ++ "    defer " ++ box_name ++ ".end();\n";
        out = out ++ inner.code;
        out = out ++ indent ++ "}\n";
        return .{ .code = out, .preamble = inner.preamble, .next_id = inner.next_id };
    } else if (comptime std.mem.eql(u8, el.tag, "label")) {
        const text = firstTextLiteral(el);
        return .{
            .code = indent ++ "ui.text(c, " ++ text ++ ", " ++ optsLiteral(el, start_id, loop_depth, file_index) ++ ");\n",
            .preamble = "",
            .next_id = start_id + 1,
        };
    } else if (comptime std.mem.eql(u8, el.tag, "button")) {
        const text = firstTextLiteral(el);
        const opts = optsLiteral(el, start_id, loop_depth, file_index);
        if (comptime findAttr(el, "on_click")) |handler| {
            return .{
                .code = indent ++ "if (ui.button(c, " ++ text ++ ", " ++ opts ++ ")) " ++ handler ++ ";\n",
                .preamble = "",
                .next_id = start_id + 1,
            };
        }
        return .{
            .code = indent ++ "_ = ui.button(c, " ++ text ++ ", " ++ opts ++ ");\n",
            .preamble = "",
            .next_id = start_id + 1,
        };
    } else if (comptime isUpper(el.tag[0])) {
        if (comptime !hasElementChildren(el) and !hasTextChild(el)) {
            @compileError("zsx: <" ++ el.tag ++ "> component must have children");
        }
        if (comptime hasElementChildren(el)) {
            const inner = comptime emitContentChildren(el.children, 1, start_id + 1, file_index);
            const my_id = inner.next_id;
            const render_name = "render_" ++ el.tag ++ "_" ++ fmtInt(@intCast(my_id));
            var decl: []const u8 = "";
            decl = decl ++ "inline fn " ++ render_name ++ "(ui: anytype, c: anytype, ctx: anytype) void {\n";
            const ui_used = comptime std.mem.indexOf(u8, inner.code, "ui.") != null;
            const c_used = comptime std.mem.indexOf(u8, inner.code, "(c,") != null or std.mem.indexOf(u8, inner.code, "(c)") != null;
            const ctx_used = comptime std.mem.indexOf(u8, inner.code, "ctx.") != null;
            if (!ui_used) decl = decl ++ "    _ = ui;\n";
            if (!c_used) decl = decl ++ "    _ = c;\n";
            if (!ctx_used) decl = decl ++ "    _ = ctx;\n";
            decl = decl ++ inner.code;
            decl = decl ++ "}\n\n";
            return .{
                .code = indent ++ "ctx." ++ el.tag ++ "(ui, c, " ++ componentPropsLiteral(el, false, start_id, loop_depth, file_index) ++ ", " ++ render_name ++ ");\n",
                .preamble = inner.preamble ++ decl,
                .next_id = my_id + 1,
            };
        } else {
            return .{
                .code = indent ++ "ctx." ++ el.tag ++ "(ui, c, " ++ componentPropsLiteral(el, true, start_id, loop_depth, file_index) ++ ");\n",
                .preamble = "",
                .next_id = start_id + 1,
            };
        }
    } else {
        @compileError("zsx: unsupported tag: " ++ el.tag);
    }
}

fn emitChildren(comptime children: []const ast.Child, comptime start_level: usize, comptime start_id: usize, comptime incoming_loop_depth: usize, comptime file_index: usize) EmitResult {
    @setEvalBranchQuota(500_000);
    var code: []const u8 = "";
    var preamble: []const u8 = "";
    var level: usize = start_level;
    var id: usize = start_id;
    var cur_depth: usize = incoming_loop_depth;
    comptime var stack: [32]u8 = undefined;
    comptime var stack_depth: usize = 0;

    for (children) |child| {
        switch (child) {
            .element => |el| {
                const r = comptime emitElement(el, level, id, cur_depth, file_index);
                code = code ++ r.code;
                preamble = preamble ++ r.preamble;
                id = r.next_id;
            },
            .text => |t| {
                if (comptime isWhitespaceOnly(t)) continue;
                @compileError("zsx: bare text child; wrap in <label>");
            },
            .expression => |e| {
                if (comptime std.mem.startsWith(u8, e, "if ")) {
                    const cond = comptime std.mem.trim(u8, e[3..], " \t\n\r");
                    if (comptime cond.len == 0) @compileError("zsx: {if } empty");
                    if (stack_depth >= 32) @compileError("zsx: nesting exceeds 32");
                    code = code ++ makeIndent(level) ++ "if (" ++ cond ++ ") {\n";
                    stack[stack_depth] = 'i';
                    stack_depth += 1;
                    level += 1;
                } else if (comptime std.mem.startsWith(u8, e, "for ") and std.mem.indexOf(u8, e, " as ") != null) {
                    const body = comptime std.mem.trim(u8, e[4..], " \t\n\r");
                    const as_idx = comptime std.mem.indexOf(u8, body, " as ").?;
                    const items = comptime std.mem.trim(u8, body[0..as_idx], " \t\n\r");
                    const binding = comptime std.mem.trim(u8, body[as_idx + 4 ..], " \t\n\r");
                    if (comptime items.len == 0) @compileError("zsx: {for} empty items");
                    if (comptime binding.len == 0) @compileError("zsx: {for} empty binding");
                    if (cur_depth >= 3) @compileError("zsx: loop depth exceeds 3");
                    const idx = "idx_" ++ fmtInt(@intCast(cur_depth));
                    code = code ++ makeIndent(level) ++ "for (" ++ items ++ ", 0..) |" ++ binding ++ ", " ++ idx ++ "| {\n";
                    stack[stack_depth] = 'f';
                    stack_depth += 1;
                    level += 1;
                    cur_depth += 1;
                } else if (comptime std.mem.startsWith(u8, e, "else if ")) {
                    if (comptime stack_depth == 0) @compileError("zsx: {else if} without {if}");
                    const top = comptime stack[stack_depth - 1];
                    if (comptime top != 'i' and top != 'e') @compileError("zsx: {else if} unmatched");
                    const ei_cond = comptime std.mem.trim(u8, e[8..], " \t\n\r");
                    if (comptime ei_cond.len == 0) @compileError("zsx: {else if} empty");
                    level -= 1;
                    code = code ++ makeIndent(level) ++ "} else if (" ++ ei_cond ++ ") {\n";
                    level += 1;
                } else if (comptime std.mem.eql(u8, e, "else")) {
                    if (comptime stack_depth == 0) @compileError("zsx: {else} without {if}");
                    if (comptime stack[stack_depth - 1] != 'i') @compileError("zsx: {else} unmatched");
                    stack[stack_depth - 1] = 'e';
                    level -= 1;
                    code = code ++ makeIndent(level) ++ "} else {\n";
                    level += 1;
                } else if (comptime std.mem.eql(u8, e, "endif")) {
                    if (comptime stack_depth == 0) @compileError("zsx: {endif} without {if}");
                    const top = comptime stack[stack_depth - 1];
                    if (comptime top != 'i' and top != 'e') @compileError("zsx: {endif} unmatched");
                    stack_depth -= 1;
                    level -= 1;
                    code = code ++ makeIndent(level) ++ "}\n";
                } else if (comptime std.mem.eql(u8, e, "endfor")) {
                    if (comptime stack_depth == 0) @compileError("zsx: {endfor} without {for}");
                    if (comptime stack[stack_depth - 1] != 'f') @compileError("zsx: {endfor} unmatched");
                    stack_depth -= 1;
                    level -= 1;
                    cur_depth -= 1;
                    code = code ++ makeIndent(level) ++ "}\n";
                } else {
                    @compileError("zsx: unsupported {" ++ e ++ "}");
                }
            },
        }
    }
    if (comptime stack_depth != 0) @compileError("zsx: unclosed control-flow");
    return .{ .code = code, .preamble = preamble, .next_id = id };
}

fn emitContentChildren(comptime children: []const ast.Child, comptime start_level: usize, comptime start_id: usize, comptime file_index: usize) EmitResult {
    @setEvalBranchQuota(500_000);
    var code: []const u8 = "";
    var preamble: []const u8 = "";
    var level: usize = start_level;
    var id: usize = start_id;
    comptime var stack: [32]u8 = undefined;
    comptime var stack_depth: usize = 0;
    for (children) |child| {
        switch (child) {
            .element => |el| {
                const r = comptime emitElement(el, level, id, 0, file_index);
                code = code ++ r.code;
                preamble = preamble ++ r.preamble;
                id = r.next_id;
            },
            .text => |t| {
                if (comptime isWhitespaceOnly(t)) continue;
                code = code ++ makeIndent(level) ++ "ui.text(c, \"" ++ escapeString(t) ++ "\", .{});\n";
            },
            .expression => |e| {
                if (comptime std.mem.startsWith(u8, e, "if ")) {
                    const cond = comptime std.mem.trim(u8, e[3..], " \t\n\r");
                    if (comptime cond.len == 0) @compileError("zsx: {if } empty");
                    if (stack_depth >= 32) @compileError("zsx: nesting exceeds 32");
                    code = code ++ makeIndent(level) ++ "if (" ++ cond ++ ") {\n";
                    stack[stack_depth] = 'i';
                    stack_depth += 1;
                    level += 1;
                } else if (comptime std.mem.startsWith(u8, e, "for ") and std.mem.indexOf(u8, e, " as ") != null) {
                    const body = comptime std.mem.trim(u8, e[4..], " \t\n\r");
                    const as_idx = comptime std.mem.indexOf(u8, body, " as ").?;
                    const items = comptime std.mem.trim(u8, body[0..as_idx], " \t\n\r");
                    const binding = comptime std.mem.trim(u8, body[as_idx + 4 ..], " \t\n\r");
                    if (comptime items.len == 0) @compileError("zsx: {for} empty");
                    if (comptime binding.len == 0) @compileError("zsx: {for} empty binding");
                    if (stack_depth >= 32) @compileError("zsx: nesting exceeds 32");
                    code = code ++ makeIndent(level) ++ "for (" ++ items ++ ", 0..) |" ++ binding ++ ", idx_0| {\n";
                    stack[stack_depth] = 'f';
                    stack_depth += 1;
                    level += 1;
                } else if (comptime std.mem.startsWith(u8, e, "else if ")) {
                    if (comptime stack_depth == 0) @compileError("zsx: {else if} without {if}");
                    const top = comptime stack[stack_depth - 1];
                    if (comptime top != 'i' and top != 'e') @compileError("zsx: {else if} unmatched");
                    const ei_cond = comptime std.mem.trim(u8, e[8..], " \t\n\r");
                    level -= 1;
                    code = code ++ makeIndent(level) ++ "} else if (" ++ ei_cond ++ ") {\n";
                    level += 1;
                } else if (comptime std.mem.eql(u8, e, "else")) {
                    if (comptime stack_depth == 0) @compileError("zsx: {else} without {if}");
                    if (comptime stack[stack_depth - 1] != 'i') @compileError("zsx: {else} unmatched");
                    stack[stack_depth - 1] = 'e';
                    level -= 1;
                    code = code ++ makeIndent(level) ++ "} else {\n";
                    level += 1;
                } else if (comptime std.mem.eql(u8, e, "endif")) {
                    if (comptime stack_depth == 0) @compileError("zsx: {endif} without {if}");
                    const top = comptime stack[stack_depth - 1];
                    if (comptime top != 'i' and top != 'e') @compileError("zsx: {endif} unmatched");
                    stack_depth -= 1;
                    level -= 1;
                    code = code ++ makeIndent(level) ++ "}\n";
                } else if (comptime std.mem.eql(u8, e, "endfor")) {
                    if (comptime stack_depth == 0) @compileError("zsx: {endfor} without {for}");
                    if (comptime stack[stack_depth - 1] != 'f') @compileError("zsx: {endfor} unmatched");
                    stack_depth -= 1;
                    level -= 1;
                    code = code ++ makeIndent(level) ++ "}\n";
                } else {
                    code = code ++ makeIndent(level) ++ "ui.text(c, " ++ e ++ ", .{});\n";
                }
            },
        }
    }
    if (comptime stack_depth != 0) @compileError("zsx: unclosed control-flow");
    return .{ .code = code, .preamble = preamble, .next_id = id };
}

fn makeIndent(comptime level: usize) []const u8 {
    const spaces: []const u8 = "                                                                ";
    return spaces[0 .. level * 4];
}

fn escapeString(comptime s: []const u8) []const u8 {
    var out: []const u8 = "";
    for (s) |ch| {
        if (ch == '"' or ch == '\\') out = out ++ "\\";
        out = out ++ [_]u8{ch};
    }
    return out;
}

fn firstTextLiteral(comptime el: ast.Element) []const u8 {
    inline for (el.children) |c| {
        switch (c) {
            .text => |t| {
                if (comptime isWhitespaceOnly(t)) continue;
                return "\"" ++ escapeString(t) ++ "\"";
            },
            .expression => |e| return e,
            .element => continue,
        }
    }
    return "\"\"";
}

fn normalizeClickHandler(comptime expr: []const u8) []const u8 {
    const trimmed = comptime std.mem.trim(u8, expr, " \t\n\r");
    if (!std.mem.startsWith(u8, trimmed, "ctx.")) {
        @compileError("zsx: on_click must start with ctx.");
    }
    if (!std.mem.endsWith(u8, trimmed, "()")) {
        @compileError("zsx: on_click must be a call");
    }
    const method = trimmed[4 .. trimmed.len - 2];
    return "@field(@TypeOf(ctx.*), \"" ++ method ++ "\")";
}

fn componentPropsLiteral(comptime el: ast.Element, comptime include_text: bool, comptime start_id: usize, comptime loop_depth: usize, comptime file_index: usize) []const u8 {
    @setEvalBranchQuota(500_000);
    const base_id = file_index * 100000 + start_id;
    var out: []const u8 = ".{";
    var sep: []const u8 = "";
    out = out ++ sep ++ ".id_extra = " ++ idExpr(base_id, loop_depth);
    sep = ", ";
    inline for (el.attributes) |attr| {
        out = out ++ sep ++ "." ++ attr.name ++ " = ";
        if (comptime std.mem.eql(u8, attr.name, "on_click")) {
            switch (attr.value) {
                .expression => |e| out = out ++ normalizeClickHandler(e),
                else => out = out ++ "undefined",
            }
        } else {
            switch (attr.value) {
                .boolean => out = out ++ "true",
                .string => |s| out = out ++ "\"" ++ escapeString(s) ++ "\"",
                .expression => |e| out = out ++ e,
            }
        }
        sep = ", ";
    }
    if (include_text and comptime hasTextChild(el)) {
        const text = firstTextLiteral(el);
        if (text.len > 2) {
            out = out ++ sep ++ ".text = " ++ text;
            sep = ", ";
        }
    }
    return out ++ "}";
}

fn optsLiteral(comptime el: ast.Element, comptime start_id: usize, comptime loop_depth: usize, comptime file_index: usize) []const u8 {
    @setEvalBranchQuota(500_000);
    const style = comptime style_mod.styleFrom(el);
    const base_id = file_index * 100000 + start_id;
    var out: []const u8 = ".{";
    var sep: []const u8 = "";
    out = out ++ sep ++ ".id_extra = " ++ idExpr(base_id, loop_depth);
    sep = ", ";
    if (style.background) |c| {
        out = out ++ sep ++ ".color_fill = .{ .r = " ++ fmtInt(c.r) ++ ", .g = " ++ fmtInt(c.g) ++ ", .b = " ++ fmtInt(c.b) ++ ", .a = " ++ fmtInt(c.a) ++ " }";
        sep = ", ";
    }
    if (style.foreground) |c| {
        out = out ++ sep ++ ".color_text = .{ .r = " ++ fmtInt(c.r) ++ ", .g = " ++ fmtInt(c.g) ++ ", .b = " ++ fmtInt(c.b) ++ ", .a = " ++ fmtInt(c.a) ++ " }";
        sep = ", ";
    }
    if (style.padding) |p| {
        out = out ++ sep ++ ".padding = .{ .x = " ++ fmtF32(p.x) ++ ", .y = " ++ fmtF32(p.y) ++ ", .w = " ++ fmtF32(p.w) ++ ", .h = " ++ fmtF32(p.h) ++ " }";
        sep = ", ";
    }
    if (style.radius) |r| {
        out = out ++ sep ++ ".radius = " ++ fmtF32(r);
        sep = ", ";
    }
    if (style.gap) |g| {
        out = out ++ sep ++ ".gap = " ++ fmtF32(g);
        sep = ", ";
    }
    if (style.expand) |ex| {
        const mapped: []const u8 = switch (ex) {
            .horizontal => ".horizontal",
            .vertical => ".vertical",
            .both => ".both",
            .none => ".none",
        };
        out = out ++ sep ++ ".expand = " ++ mapped;
        sep = ", ";
    }
    if (style.font_size) |fs| {
        out = out ++ sep ++ ".font_size = " ++ fmtF32(fs);
        sep = ", ";
    }
    if (style.font_weight) |fw| {
        const weight: u32 = switch (fw) {
            .regular => 400,
            .semibold => 600,
            .bold => 700,
        };
        out = out ++ sep ++ ".font_weight = " ++ fmtInt(weight);
        sep = ", ";
    }
    return out ++ "}";
}

fn findAttr(comptime el: ast.Element, comptime name: []const u8) ?[]const u8 {
    inline for (el.attributes) |attr| {
        if (comptime std.mem.eql(u8, attr.name, name)) {
            switch (attr.value) {
                .expression => |e| return e,
                else => return null,
            }
        }
    }
    return null;
}
