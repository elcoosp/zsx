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

| Old | New |
|---|---|
| `.name = "foo"` | `.name = .foo` |
| no `fingerprint` | `.fingerprint = 0x...` required |
| `addTest(.{ .root_source_file = ... })` | `addTest(.{ .root_module = mod })` |
| `std.fs.cwd()` | `std.Io.Dir.cwd()` with explicit `io` |
| `readFileAlloc(a, path, max)` | `readFileAlloc(io, path, a, .limited(max))` |
| `writeFile(.{ .sub_path, .data })` | `writeFile(io, .{ .sub_path, .data, .flags })` |
| `b.build_root` | `b.root` |
| `b.findProgram` | `b.findProgramLazy` |
| `run.addArgs(b.args)` | `run.addPassthruArgs()` |
| `@intFromEnum` / `@enumFromInt` | `@backingInt` / `@fromBackingInt` |
| `[1]T{v} ** n` | `@splat(v)` |
| `i0` | `u0` |
| `@cImport` | external `translate_c` package |

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
