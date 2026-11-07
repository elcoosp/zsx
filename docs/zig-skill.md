---

name: zig-0-17
description: Zig 0.17.0 build-system, comptime, and test-harness pitfalls. Use when writing or debugging Zig 0.17.x code. Each entry is a real compiler error followed by the minimal fix.
license: MIT
compatibility:

- opencode
- claude-code
  metadata:
  version: "0.17.0"
  language: "zig"
  category: "programming-language"

---

# Zig 0.17.0 Skill

Version scope: 0.17.0 / 0.17.1. Every entry is a compiler error you can hit, followed by the minimal fix.

## Quick reference: 0.16 to 0.17

| Old                                     | New                                            |
| --------------------------------------- | ---------------------------------------------- |
| `.name = "foo"`                         | `.name = .foo`                                 |
| no `fingerprint`                        | `.fingerprint = 0x...` required                |
| `addTest(.{ .root_source_file = ... })` | `addTest(.{ .root_module = mod })`             |
| `std.fs.cwd()`                          | `std.Io.Dir.cwd()` with explicit `io`          |
| `readFileAlloc(a, path, max)`           | `readFileAlloc(io, path, a, .limited(max))`    |
| `writeFile(.{ .sub_path, .data })`      | `writeFile(io, .{ .sub_path, .data, .flags })` |
| `b.build_root`                          | `b.root`                                       |
| `b.findProgram`                         | `b.findProgramLazy`                            |
| `run.addArgs(b.args)`                   | `run.addPassthruArgs()`                        |
| `@intFromEnum` / `@enumFromInt`         | `@backingInt` / `@fromBackingInt`              |
| `[1]T{v} ** n`                          | `@splat(v)`                                    |
| `i0`                                    | `u0`                                           |
| `@cImport`                              | external `translate_c` package                 |

## Build system

### `build.zig.zon`: name is an enum literal

```
error: expected enum literal
    .name = "foo",
            ^~~~~
```

Fix: `.name = .foo`.

### `build.zig.zon`: fingerprint is required

```
error: missing top-level 'fingerprint' field; suggested value: 0xfcebe7afe7650afb
```

Fix: paste the suggested value. `zig build` does not insert it automatically. The fingerprint derives from the package name; renaming invalidates it.

```zig
.{
    .name = .foo,
    .version = "0.1.0",
    .fingerprint = 0xfcebe7afe7650afb,
    .minimum_zig_version = "0.17.0",
    .paths = .{ "build.zig", "build.zig.zon", "src" },
}
```

### `addTest` / `addExecutable` / `addLibrary` take `.root_module`

```
error: no field named 'root_source_file' in struct 'Build.TestOptions'
```

Fix: build a module first, pass it as `.root_module`.

```zig
const lib_mod = b.addModule("mylib", .{
    .root_source_file = b.path("src/root.zig"),
    .target = target,
    .optimize = optimize,
});
const tests = b.addTest(.{ .root_module = lib_mod });
```

Same for `addExecutable`, `addLibrary`, `addStaticLibrary`, `addSharedLibrary`.

### Unused local constants and function parameters are errors

```
error: unused local constant
    const unused_thing = b.addModule(...);

error: unused function parameter
    pub fn f(x: anytype) void { ... }
```

Fix: reference them, inline them, or `_ = x;` at the top of the function body.

```zig
pub fn column(c: anytype, opts: anytype) Box {
    _ = c;  // unused in this adapter body
    return openBox(opts);
}
```

### Filesystem in `build.zig`: `std.Io.Dir.cwd()` + `b.graph.io`

`std.fs.cwd()` does not exist in 0.17. `std.fs` moved to `std.Io`; every operation takes an `io` instance.

```zig
const io = b.graph.io;
const dir = std.Io.Dir.cwd();

// read — limit is mandatory
if (dir.readFileAlloc(io, path, allocator, .limited(1 << 20))) |bytes| {
    defer allocator.free(bytes);
} else |_| {}

// write
try dir.writeFile(io, .{
    .sub_path = path,
    .data = bytes,
    .flags = .{ .truncate = true },
});

// file handle form
const f = try dir.createFile(io, path, .{ .truncate = true });
defer f.close(io);
try f.writeStreamingAll(io, bytes);
```

`error.FileTooBig` is now `error.StreamTooLong`.

## Test harness

### `zig test <file>` sets module root to the file's parent

```
error: import of file outside module path
    const ast = @import("../ast.zig");
```

`zig test src/subdir/file.zig` uses `src/subdir/` as module root. Any `../` import leaves the module and is illegal. Not a bug; it is the module boundary rule.

For files with `../` imports, the only valid gate is `zig build test` **after** wiring the file through `root.zig` (or a file at a high-enough root).

### `zig build test` only traverses files reachable from `.root_module`

If `src/root.zig` does not import `src/backends/foo.zig`, its tests never run. `zig build test` still reports success. This is a **false positive** for tests in unimported files.

Add an aggregator in `root.zig`:

```zig
test { _ = @import("backends/foo.zig"); }
test { _ = @import("adapters/bar.zig"); }
```

### Verification checklist for adding tests

1. File is imported (directly or transitively) from `root.zig`.
2. `zig build test` passes.
3. The commit adding the test also adds (or confirms) the import in `root.zig`.

Without step 3, "tests pass" does not mean "the tests you added ran."

## Comptime

### Comptime var pointers cannot escape to runtime

```
error: runtime value contains reference to comptime var
    return comptime blk: { ... };
note: comptime var pointers are not available at runtime
```

A parser that mutates `var buf: [N]T` inside `comptime blk:` and returns `buf[0..n]` produces slices pointing to comptime-var storage. That is fine if the result is consumed entirely at comptime. The moment any caller materializes it as a runtime value, Zig rejects the whole chain — including callers that previously compiled.

Three fixes:

1. **Consume entirely at comptime.** Caller wraps usage in `comptime { ... }`. Value never becomes runtime-typed.
2. **Build `comptime Elem{ ... }` literals** from `&.{...}` array literals (comptime const, not var). Safe to materialize.
3. **Codegen.** Emit a `.zig` file with literal AST nodes; those are comptime-const and materialize cleanly.

```zig
// WRONG: parse returns slices into comptime var buffer
const el = comptime parse("...");  // el has runtime type -> materialize -> error

// OK: literal built from comptime-const arrays
const el = comptime Elem{
    .tag = "div",
    .attributes = &.{ .{ .name = "class", .value = .{ .string = "p-4" } } },
    .children = &.{},
};
```

### `@compileError` fires during analysis, not just execution

A `@compileError` in an `if` or `switch` arm fires whenever the arm is analyzed, even if the branch would never be taken at runtime.

```zig
// WRONG: fires for every element whose child is .element
for (el.children) |c| {
    switch (c) {
        .element => |el| emit(el),
        .text => @compileError("no bare text"),  // analyzed even when c is .element
    }
}
```

Fixes:

- Use `inline for` so each iteration's binding is comptime-known.
- Use `comptime std.mem.eql(u8, tag, "column")` for tag checks so the `if`-chain prunes.
- Use `comptime` on call arguments where the branch depends on them.

### `inline for` for comptime-bound switch iteration

For `switch (c)` where each arm must resolve per-iteration at comptime, `for` is not enough — the loop variable is not comptime-bound. `inline for` unrolls and each `c` is comptime.

```zig
inline for (el.children) |c| {
    switch (c) {
        .text => |t| return t,
        .element => continue,
    }
}
```

### `orelse` does not propagate wrapped type

```
error: incompatible types: 'Rect' and 'struct_1064'
    const cur = opts.padding orelse .{ .x = 0, .y = 0, .w = 0, .h = 0 };
```

`orelse` does not inject the payload type into its right operand. The anonymous struct infers its own type. Fix: annotate either side.

```zig
const cur: dvui.Rect = opts.padding orelse dvui.Rect{};
// or
const cur: dvui.Rect = opts.padding orelse .{};
```

### `std.fmt.parseFloat` unreliable at comptime

`parseFloat` can fail or error at comptime for inputs that succeed at runtime. Do not use it in code paths that must be comptime-evaluated (numeric attribute parsing, config constants).

```zig
fn parseNumeric(comptime s: []const u8) f32 {
    if (s.len == 0) @compileError("empty numeric value");
    var result: f32 = 0;
    inline for (s) |ch| {
        if (ch < '0' or ch > '9') @compileError("non-numeric: " ++ s);
        result = result * 10.0 + @as(f32, @floatFromInt(ch - '0'));
    }
    return result;
}
```

Handles non-negative integers only. Extend with sign/decimal scanners if needed.

### `std.fmt.comptimePrint` branch quota explosion

```
error: evaluation exceeded 3000 backwards branches
    _ = mem.print(&buf, fmt, args) catch unreachable;
note: use @setEvalBranchQuota() to raise the limit
```

`comptimePrint` runs `mem.print`, a general format interpreter. Each `{d}` uses dozens of branches. Concatenating ~20 formats exhausts the default 3000-branch budget.

Fix: dedicated integer formatter for `u8`/`u32`/`f32-to-int`.

```zig
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
```

~2 branches per digit instead of hundreds. `@setEvalBranchQuota(100_000)` at the top of any comptime function is cheap insurance even with `fmtInt`.

### `comptime blk: { ... break :blk &array; }` for comptime strings

`const result: [len]u8 = out[0..len].*;` converts a runtime-length slice to a fixed-size array. `&result` is a comptime-const pointer, coerces to `[]const u8`. No comptime-var escape, no branch blowup.

This is the pattern for comptime string building:

```zig
fn escapeString(comptime s: []const u8) []const u8 {
    var out: []const u8 = "";
    for (s) |ch| {
        if (ch == '"' or ch == '\\') out = out ++ "\\";
        out = out ++ [_]u8{ch};
    }
    return out;
}
```

`out = out ++ "..."` inside a comptime function is fine — each concat produces a new comptime string literal, not a mutable buffer.

### Comptime utility with comptime-var return: do not import into runtime tests

A function that returns a value backed by `comptime var` storage cannot appear in a runtime test suite. Importing the file from `root.zig` (which becomes the runtime test root) triggers the escape error.

Two options:

1. Test only at comptime: `comptime { _ = @import("util.zig"); }` or drop the test block and rely on caller tests.
2. Exercise via callers that consume the result entirely at comptime — codegen, macro expansion, etc.

## External dependency workflow

### Discover real API from `zig-pkg/` before writing a stub

`zig fetch --save git+https://...` populates `zig-pkg/<name>-<version>-<hash>/`. Read the real signatures before writing any stub or adapter.

```bash
find zig-pkg/<name>-*/src -maxdepth 1 -name '*.zig'
grep -n 'pub fn (text|button|div)' zig-pkg/<name>-*/src/*.zig
sed -n '1,80p' zig-pkg/<name>-*/src/types.zig
```

Stub tests prove internal consistency, not API compatibility. Fabricated stub types (`Color{r,g,b,a:u8}` when real is `f32`, `opts:anytype` when real takes a concrete struct) produce a green suite that fails the moment real types are wired in.

### Pin minor versions

`#main` resolves to whatever HEAD is at fetch time. Pin a tag: `git+https://...#v0.12.0`. `0.x` libraries break across minor releases.

## Canonical templates

### `build.zig`

```zig
const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const lib_mod = b.addModule("mylib", .{
        .root_source_file = b.path("src/root.zig"),
        .target = target,
        .optimize = optimize,
    });

    const test_step = b.step("test", "Run unit tests");
    const tests = b.addTest(.{ .root_module = lib_mod });
    test_step.dependOn(&b.addRunArtifact(tests).step);
}
```

For executables:

```zig
const exe_mod = b.createModule(.{
    .root_source_file = b.path("src/main.zig"),
    .target = target,
    .optimize = optimize,
    .imports = &.{ .{ .name = "mylib", .module = lib_mod } },
});
const exe = b.addExecutable(.{ .name = "myapp", .root_module = exe_mod });
b.installArtifact(exe);
```

### `build.zig.zon`

```zig
.{
    .name = .mylib,
    .version = "0.1.0",
    .fingerprint = 0x0000000000000000,
    .minimum_zig_version = "0.17.0",
    .paths = .{ "build.zig", "build.zig.zon", "src" },
}
```

Fingerprint workflow: write `0x0000000000000000`, run `zig build`, copy suggested value from error.

## Verification checklist

Before committing any Zig change on 0.17:

1. `zig build` succeeds with zero warnings.
2. `zig build test` passes.
3. `build.zig.zon` has `.name` as enum literal, `.fingerprint` populated, `.minimum_zig_version = "0.17.0"`.
4. No unused `const` bindings or function parameters.
5. All `addTest`/`addExecutable`/`addLibrary` use `.root_module`.
6. Every file with a `test` block is reachable from `root.zig`.
7. `.gitignore` includes `.zig-cache/`, `zig-out/`, `zig-pkg/`.

## Build system: addUpdateSourceFiles for source-tree writes

Writing files from `build.zig` via `Dir.writeFile` is an **undeclared side effect** — Zig's Maker cannot track it. Delete a generated file, configure cache warm, `pub fn build()` does not re-run, file stays missing, compile fails "file not found". The `rm -rf .zig-cache` workaround discards the whole build cache to fix one undeclared dependency.

Correct API:

    const update = b.addUpdateSourceFiles();
    inline for (sources) |src| {
        const generated = comptime generate(src);
        update.addBytesToSource(generated, "out/gen.zig");
    }
    const gen_step = b.step("gen", "regenerate");
    gen_step.dependOn(&update.step);
    tests.step.dependOn(&update.step);
    exe.step.dependOn(&update.step);
    b.getInstallStep().dependOn(&update.step);

Generated files become declared outputs. Delete one, step dirty, re-runs, file regenerated. No cache nuke. Second build with no changes, step cached, zero cost. `addUpdateSourceFiles` respects content and mtime.

Diagnostic: if you find yourself running `rm -rf .zig-cache` to fix "file not found", that file was produced by `Dir.writeFile` from `build.zig`. Convert to `addUpdateSourceFiles`.

## Build system: has_side_effects = true on Run steps

`b.addRunArtifact(exe)` caches by input hash. Unchanged exe, Zig skips execution entirely. Step whose purpose is to produce output (files, terminal output, screenshots) silently does nothing.

    const run = b.addRunArtifact(exe);
    run.has_side_effects = true;
    const step = b.step("demo", "run demo");
    step.dependOn(&run.step);

Symptoms: step prints nothing, exits 0, no files. Works once then never again. Fresh clone works, subsequent invocations do not.

Required for any step whose observable output is not a file in `zig-out/` — console output, screenshots, network calls. `addRunArtifact` on `addTest` executables already sets it internally; user-defined run steps need it explicitly.

## Comptime signature detection: @typeInfo(fn).params.len

    const F = @typeInfo(@TypeOf(ui.textField)).@"fn";
    if (F.params.len >= 3) {
        _ = ui.textField(c, buffer, opts);
    } else {
        _ = ui.textField(c, opts);
    }

Both branches analyzed at comptime, only taken branch emitted. Useful for library API evolution, multi-backend adapters, stub vs real differences. Both branches must type-check against the same fn; if neither matches, the error names the real signature.

## Structural dispatch: @hasDecl and @hasField

Check at comptime, prune unreachable branch:

    if (@hasDecl(dvui, "TextEntryWidget")) {
        var init = dvui.TextEntryWidget.InitOptions{};
        _ = dvui.textEntry(@src(), init, optionsFrom(dvui, opts));
    } else {
        dvui.textEntry(@src(), buffer, opts);
    }

Same for fields, with the load-bearing two-level check:

    if (@hasField(@TypeOf(opts), "color_fill")) {
        if (@hasField(dvui_mod.Options, "color_fill")) {
            o.color_fill = opts.color_fill;
        }
    }

Source has field AND destination has field. Without destination check, compiles against stub, fails against real backend.

## Optional types: three distinct patterns

    // 1. Nullable value: unwrap required
    const c = opts.color_fill;
    if (c) |color| o.color_fill = color;

    // 2. Non-null with default: always present
    const w: u32 = opts.font_weight;

    // 3. Structurally optional: field may not exist
    if (@hasField(@TypeOf(opts), "color_fill")) { ... }

Pattern 1 fails at comptime with "optional type '?Color' does not support field access" if you write `c.r`. Fix: `if (c) |color| color.r` or `c.?.r`. Pattern 3 cannot be replaced by `?T` — no slot to store null.

## Reading a library's own tests as ground truth

When unsure how to use a third-party feature, read the library's tests. dvui screenshots in `src/testing.zig`, dvui headless backend in `build.zig` (`.backend = .testing`), nanoui headless snapshot in `src/dev.zig`. Drill: `grep -rn 'pub fn' <dep>/src/` for top-level, then `grep -rn '<fn_name>' <dep>/src/` for test call sites.

## Zig 0.17 @splat for array initialization

    // Old (0.16)
    var buf: [64]u8 = [_]u8{0} ** 64;
    // New (0.17)
    var buf: [64]u8 = @splat(0);

Works for any comptime length and value. Nested `@splat(@splat(1.0))` for `[N][M]f32`. `zig fmt` does not migrate; search for `**` in array init contexts.

## Never patch zig-pkg/ — adapt or wrap

When a third-party library's API does not fit, the fix is always in the adapter, never in `zig-pkg/<lib>-*/src/`. The library is a read-only cache entry. Modifying it:

- Breaks on `zig fetch` (new hash, old hash orphaned)
- Breaks for every other consumer of the project
- Disappears on `rm -rf .zig-cache` or `rm -rf zig-pkg`
- Silently diverges from the pinned URL hash

If the API is genuinely wrong for your use case, options in order:

1. `@hasDecl` / `@hasField` dispatch to a compatible shape
2. Wrapper that constructs the library's expected type from yours
3. Runtime state cache to bridge across calls (e.g., persistent `TextBuffer` keyed by widget id)
4. File an upstream issue
5. Fork the library

Never option 0 (edit `zig-pkg/`). Compile errors that reference paths inside `zig-pkg/` are the compiler naming the *library's* API — that is documentation of the expected shape, not permission to change it.

## Optional argument unwrap before @intCast

`@intCast(?usize)` fails with "expected integer or vector, found '?usize'". Unwrap first:

    const n: u64 = @intCast(opts.id_extra orelse 0);

If the field might be either `?T` or `T` depending on caller version, dispatch at comptime:

    const n: u64 = blk: {
        if (!@hasField(@TypeOf(opts), "id_extra")) break :blk 0;
        const raw = opts.id_extra;
        if (@typeInfo(@TypeOf(raw)) == .optional) {
            break :blk @as(u64, @intCast(raw orelse 0));
        }
        break :blk @as(u64, @intCast(raw));
    };

`orelse` on a non-optional is a compile error, so the branch must be pruned with `@typeInfo` — not blind `orelse`.

## var vs const: never-mutated locals are hard errors

Zig 0.17 rejects `var` locals that are never mutated. The check runs at
compile time, not lint time — a never-mutated `var` is a **compile error**,
not a warning.

    error: local variable is never mutated
        var init = dvui.Progress_InitOptions{ .percent = 50 };
            ^~~~
    note: consider using 'const'

`var` in Zig means "will be mutated after initialization." The compiler
verifies this. If the variable is only read, use `const`:

    // WRONG — will not compile if `init` is never mutated
    var init = dvui.Progress_InitOptions{ .percent = 50 };
    dvui.progress(@src(), init, opts);

    // RIGHT
    const init = dvui.Progress_InitOptions{ .percent = 50 };
    dvui.progress(@src(), init, opts);

Same rule for function parameters. `var` parameter that is never mutated
is a compile error too. Use `_ = param;` in the body if the parameter is
intentionally unused, or remove it from the signature.

Common false-reflex: writing `var` because "it's a struct, might need to
mutate fields later." Zig's whole point is that `var` is a promise the
compiler enforces. Declare `const` first, upgrade to `var` only when a
mutation is actually needed.

Related: `var x: T = undefined;` where `x` is later fully assigned without
reading is a different case — that IS considered mutated (from `undefined`
to a real value) and compiles. The "never mutated" error is about `var`
locals initialized to a concrete value and then only read.

## var vs const: never-mutated locals are hard errors

Zig 0.17 rejects `var` locals that are never mutated. The check runs at
compile time, not lint time — a never-mutated `var` is a **compile error**,
not a warning.

    error: local variable is never mutated
        var init = dvui.Progress_InitOptions{ .percent = 50 };
            ^~~~
    note: consider using 'const'

`var` in Zig means "will be mutated after initialization." The compiler
verifies this. If the variable is only read, use `const`:

    // WRONG — will not compile if `init` is never mutated
    var init = dvui.Progress_InitOptions{ .percent = 50 };
    dvui.progress(@src(), init, opts);

    // RIGHT
    const init = dvui.Progress_InitOptions{ .percent = 50 };
    dvui.progress(@src(), init, opts);

Same rule for function parameters. `var` parameter that is never mutated
is a compile error too. Use `_ = param;` in the body if the parameter is
intentionally unused, or remove it from the signature.

Common false-reflex: writing `var` because "it's a struct, might need to
mutate fields later." Zig's whole point is that `var` is a promise the
compiler enforces. Declare `const` first, upgrade to `var` only when a
mutation is actually needed.

Related: `var x: T = undefined;` where `x` is later fully assigned without
reading is a different case — that IS considered mutated (from `undefined`
to a real value) and compiles. The "never mutated" error is about `var`
locals initialized to a concrete value and then only read.

## macOS: capture a specific window with CoreGraphics and screencapture

AppleScript (`System Events`) is not reliable for SDL3 apps launched from a
shell. It often cannot find the window by PID, returns wrong bounds (full
screen instead of window), and `set position of window` **moves other
applications' windows** — actively destructive.

The native path uses two macOS primitives:

1. **`CGWindowListCopyWindowInfo`** — a CoreGraphics C API that enumerates
   every window in the window server, keyed by `kCGWindowOwnerPID`. This is
   the underlying API that System Events wraps, but it works regardless of
   process registration or bundle presence.
2. **`screencapture -l <windowID>`** — captures exactly that window's pixels,
   composited without other windows, with no repositioning or activation.

### The Swift one-liner

Swift ships with macOS and can call CoreGraphics directly:

    WINDOW_ID=$(swift -e '
    import CoreGraphics
    import Foundation
    let pid = Int32($PID)
    guard let list = CGWindowListCopyWindowInfo(.optionOnScreenOnly, kCGNullWindowID) as? [[String: Any]] else {
        exit(1)
    }
    for w in list {
        if let owner = w[kCGWindowOwnerPID as String] as? Int32, owner == pid {
            if let num = w[kCGWindowNumber as String] as? UInt32 {
                print(num)
                exit(0)
            }
        }
    }
    exit(1)
    ' 2>/dev/null)

Then:

    screencapture -x -o -l "$WINDOW_ID" /tmp/out.png

### Why not Python/Quartz

`/usr/bin/python3` on macOS may lack PyObjC (`import Quartz` fails on some
macOS versions without `pip install`). Swift is guaranteed present (part of
Command Line Tools) and calls the same API. No third-party dependencies.

### Why not `screencapture -R`

`-R x,y,w,h` captures a **region of the screen**, not a window. Any overlapping
window (your editor, a browser) appears in the image. `-l <windowID>` captures
only that window's pixels regardless of z-order.

### Permissions

- **Screen Recording** is required for `screencapture` to read window pixels.
  macOS caches the permission per process — restart the terminal after granting.
- **Accessibility** is *not* required for this path (only for AppleScript-based
  window manipulation, which we do not do).

### Polling

SDL3 apps take 2-3 seconds to create their window. Poll `CGWindowListCopyWindowInfo`
for up to 5 seconds after launch. A single `sleep 2` races the window creation
on slower machines.

## Python regex catastrophic backtracking on multi-KB files

A regex like `(?:.*\n)*?        \}\n` used to match "everything up to the next
closing brace at this indent" is **O(2^n)** on large files. The `.*` inside
`(?:...)*?` makes the engine try every possible partition of every line
before giving up. On a 12KB file, this hangs for minutes or forever — no
error, no partial output, just a hung process.

    # HANGS on multi-KB files
    pattern = re.compile(
        r'        pub fn skeleton\(c: anytype, opts: anytype\) void \{\n(?:.*\n)*?        \}\n',
        re.DOTALL
    )

### The rule

**Never use `.*` or `(?:.*\n)*` to match a variable-length block on files
over ~2KB.** Regex for block matching is only safe when the block length is
bounded and small.

### The fix: line-based scanning

Read the file as lines, find the start line by substring match, then scan
forward counting braces until depth returns to zero:

    with open(path) as f:
        lines = f.readlines()

    start_idx = None
    for i, line in enumerate(lines):
        if 'pub fn skeleton(' in line:
            start_idx = i
            break

    depth = 0
    end_idx = None
    for i in range(start_idx, len(lines)):
        depth += lines[i].count('{')
        depth -= lines[i].count('}')
        if depth == 0 and i > start_idx:
            end_idx = i
            break

    lines[start_idx:end_idx+1] = [new_content]
    with open(path, 'w') as f:
        f.writelines(lines)

This is **O(n) linear** in file size. No backtracking, no hang, no hidden
catastrophic failure mode.

### When brace counting is not enough

If the block has braces inside strings or comments, brace counting is wrong.
For Zig source that has been through `zig fmt`, this is rare — string literals
and comments are usually on their own lines or balanced. If in doubt, fall
back to a proper tokenizer or a byte-level scan that tracks `"` and `//`
state (the approach used in `zig fmt` itself).

### Detection

If a bash script calling `python3 <<EOF` hangs with no output and no error,
the most likely cause is regex backtracking. Kill the process with
`pkill -9 -f python3`, then rewrite the block-finding logic as a line scan.

### Related: timeout is not on macOS

`timeout` is GNU coreutils, not part of macOS. Portable replacement:

    run_with_timeout() {
        local secs="$1"; shift
        "$@" &
        local pid=$!
        ( sleep "$secs"; kill -9 "$pid" 2>/dev/null; touch "/tmp/.t.$pid" ) &
        local watchdog=$!
        wait "$pid" 2>/dev/null
        local rc=$?
        kill -9 "$watchdog" 2>/dev/null
        wait "$watchdog" 2>/dev/null || true
        [ -f "/tmp/.t.$pid" ] && { rm -f "/tmp/.t.$pid"; return 124; }
        return $rc
    }

Always wrap `zig build test`, `zig build build-app-*`, and any `python3`
heredoc in `run_with_timeout` so hangs surface as exit 124 instead of
blocking the terminal.
