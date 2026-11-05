---
name: zig-build-0-17
description: Zig 0.17.0 build-system pitfalls and fixes discovered while setting up the zsx project. Use this when writing or debugging build.zig and build.zig.zon on Zig 0.17.x.
license: MIT
compatibility:
  - opencode
  - claude-code
metadata:
  version: "0.17.0"
  language: "zig"
  category: "build-system"
---

# Zig 0.17.0 Build System Skill

> **Version Scope**: Pinned to **Zig 0.17.0** / **0.17.1**.
> **Release Notes**: https://ziglang.org/download/0.17.0/release-notes.html

This skill captures the exact compile errors hit while bringing up a fresh Zig 0.17.0 project from an empty directory. Each entry is a real error message followed by the minimal fix. It complements the language-level `SKILL.md` with build-system specific knowledge.

---

## Critical: `build.zig.zon` Requires Enum Literal Name

The `name` field is an **enum literal**, not a string. Zig 0.17.0 removed string names entirely.

```
build.zig.zon:2:13: error: expected enum literal
    .name = "zsx",
            ^~~~~
```

**Fix**: replace `"zsx"` with `.zsx`.

```zig
.{
    .name = .zsx,
}
```

The enum literal must be a valid Zig identifier. It becomes the canonical package name used in dependency resolution, fingerprinting, and cache keys.

---

## Critical: `build.zig.zon` Requires `fingerprint`

`build.zig.zon` now requires a top-level `fingerprint` field. Missing it triggers an error that **suggests the exact value** to use.

```
build.zig.zon:1:2: error: missing top-level 'fingerprint' field; suggested value: 0xfcebe7afe7650afb
.{
 ^
```

**Fix**: add the suggested fingerprint verbatim.

```zig
.{
    .name = .zsx,
    .version = "0.0.1",
    .fingerprint = 0xfcebe7afe7650afb,
    .minimum_zig_version = "0.17.0",
    .paths = .{
        "build.zig",
        "build.zig.zon",
        "src",
    },
}
```

**Key behaviors**:

- The fingerprint is **content-derived** from the package name. Renaming the package or restructuring the manifest will produce a new suggested value.
- The suggested value appears in the error message — no need to compute it manually.
- `zig build` will **not** auto-insert the fingerprint. You must edit `build.zig.zon` yourself with the suggested value.
- Keep the fingerprint stable across versions of the package. It is a package identity, not a checksum of source.

---

## Critical: `addTest` Uses `root_module`, Not `root_source_file`

`Build.TestOptions` in 0.17.0 does not accept `root_source_file`, `target`, or `optimize` directly. It requires a pre-constructed `*Module`.

```
build.zig:15:10: error: no field named 'root_source_file' in struct 'Build.TestOptions'
        .root_source_file = b.path("src/root.zig"),
         ^~~~~~
/opt/homebrew/Cellar/zig/0.17.1/lib/zig/std/Build.zig:653:25: note: struct declared here
pub const TestOptions = struct {
```

**Fix**: construct a module with `b.addModule` (or `b.createModule`), then pass it as `root_module`.

```zig
const zsx_mod = b.addModule("zsx", .{
    .root_source_file = b.path("src/root.zig"),
    .target = target,
    .optimize = optimize,
});

const tests = b.addTest(.{
    .root_module = zsx_mod,
});
```

The same pattern applies to `addExecutable`, `addLibrary`, `addStaticLibrary`, and `addSharedLibrary` — they all take `.root_module = <*Module>` now. The flat `root_source_file` / `target` / `optimize` fields were removed from options structs in favor of module-level configuration.

---

## Critical: Unused Local Constants Are Hard Errors

Zig treats unused local `const` bindings as compile errors, not warnings. This bit us when a module was declared for use in tests but only referenced later.

```
build.zig:7:11: error: unused local constant
    const zsx_mod = b.addModule("zsx", .{
          ^~~~~~~
```

**Fix options**:

1. **Reference it** — pass it to `addTest` as `root_module` (preferred, since the module was created to be used).
2. **Discard it explicitly** — `_ = zsx_mod;` at end of scope (only if genuinely unused).
3. **Inline the expression** — remove the binding entirely.

The first option is nearly always correct in `build.zig`: if you create a module, you probably want to install it or wire it into a test/executable. If neither, delete the binding.

---

## Quick Reference: 0.16 to 0.17 Build API Migrations

| Old (0.16.x) | New (0.17.0) | Notes |
|---|---|---|
| `.name = "foo"` | `.name = .foo` | Enum literal, not string |
| `.fingerprint` absent | `.fingerprint = 0x...` | Required; value suggested by compiler |
| `addTest(.{ .root_source_file = ..., .target = ..., .optimize = ... })` | `addTest(.{ .root_module = mod })` | Module-first API |
| `addExecutable(.{ .root_source_file = ... })` | `addExecutable(.{ .root_module = mod })` | Same shift |
| `addModule` return unused | Must be referenced or discarded | Zig unused-local rule |
| `b.build_root` | `b.root` | Returns `Cache.Path` |
| `b.findProgram(...)` | `b.findProgramLazy(...)` | Avoids configure cache poisoning |
| `run_cmd.addArgs(args)` from `b.args` | `run_cmd.addPassthruArgs()` | Keeps configure cache pure |

---

## Canonical `build.zig` Template for Zig 0.17.0

Use this as the starting point for any new Zig 0.17.0 library or executable. It compiles cleanly with zero warnings on a fresh directory.

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
    const tests = b.addTest(.{
        .root_module = lib_mod,
    });
    test_step.dependOn(&b.addRunArtifact(tests).step);
}
```

For executables, add:

```zig
    const exe_mod = b.createModule(.{
        .root_source_file = b.path("src/main.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{
            .{ .name = "mylib", .module = lib_mod },
        },
    });

    const exe = b.addExecutable(.{
        .name = "myapp",
        .root_module = exe_mod,
    });
    b.installArtifact(exe);
```

---

## Canonical `build.zig.zon` Template for Zig 0.17.0

```zig
.{
    .name = .mylib,
    .version = "0.1.0",
    .fingerprint = 0x0000000000000000,
    .minimum_zig_version = "0.17.0",
    .paths = .{
        "build.zig",
        "build.zig.zon",
        "src",
    },
}
```

**Workflow for the fingerprint**:

1. Write the manifest with a placeholder `0x0000000000000000`.
2. Run `zig build`.
3. Copy the suggested value from the error message.
4. Paste it into `.fingerprint`.

The fingerprint is a **64-bit integer**, not a string, and must be written as a hex literal `0x...`.

---

## Common Error Message Reference

| Error Message | Root Cause | Fix |
|---|---|---|
| `expected enum literal` | `.name` is a string | Use `.name = .foo` |
| `missing top-level 'fingerprint' field` | Manifest lacks fingerprint | Add the suggested value verbatim |
| `no field named 'root_source_file' in struct 'Build.TestOptions'` | Old flat options API | Use `.root_module = mod` |
| `no field named 'root_source_file' in struct 'Build.ExecutableOptions'` | Same | Same |
| `unused local constant` | Binding never referenced | Pass to addTest/addExecutable, or `_ = x;` |
| `no field named 'build_root'` | Field renamed | Use `b.root` |
| `no member named 'pathList' in ...` | Path list API changed | Use `b.pathList(&.{ ... })` |

---

## Verification Checklist

Before committing any `build.zig` change on Zig 0.17.0:

1. `zig build` succeeds with zero warnings.
2. `zig build test` runs and all tests pass.
3. `build.zig.zon` has `.name` as enum literal, `.fingerprint` populated, `.minimum_zig_version = "0.17.0"`.
4. No unused local constants in `build.zig` — every `const` binding is referenced.
5. `addTest`, `addExecutable`, `addLibrary` all use `.root_module`.
6. `zig build --help` lists your custom steps (confirms `b.step` registration).

---

## Changelog

- **2026-11-04**: Initial curation after bringing up `zsx` from an empty directory. Captured four hard errors: enum-literal name, required fingerprint, `root_module` shift in test options, and unused-local-constant rule.

---

## `zig test <file>` Sets Module Root to the File's Parent

Running `zig test src/backends/dvui.zig` fails when that file contains `@import("../ast.zig")`:

```
error: import of file outside module path
const ast = @import("../ast.zig");
```

**Cause**: `zig test <file>` uses `<file>`'s **parent directory** as the module root. Relative imports that climb (`../`) are illegal because they leave the module. This is not a bug — it is the module boundary rule.

**Wrong gate**: `zig test src/backends/dvui.zig` — false signal, the backend's imports are illegal from that root.

**Correct gate**: route the file through `root.zig` (or any file at a high-enough module root) and run `zig build test`. In ZSX, `src/root.zig` contains:

```zig
test {
    _ = @import("backends/dvui.zig");
}
```

That forces the backend tests to be collected and executed by `zig build test`, with the module root at `src/`, where `../ast.zig` is `src/ast.zig` and resolves legally.

**Corollary**: any file with new tests must be reachable from `root.zig` before `zig build test` will execute those tests. A commit that adds tests to an unimported file passes compilation but runs zero tests — this is how a false positive happened during ZSX Phase 2.

## False Positive from `zig build test` Without Import

When a file with tests is not imported from `root.zig`, `zig build test` still reports success. The tests are silently skipped because they are not reachable from the module root.

Symptom: a commit passes `zig build test` but a subsequent change reveals the file's tests were never executed (they may have contained latent `@compileError` or `@import` errors).

Verification before committing any file with new tests:

1. The file is imported (directly or transitively) from `src/root.zig`.
2. `zig build test` passes.
3. `git diff` of `src/root.zig` at that commit includes the new import (or the import was already present).

Without (3), "tests pass" does not mean "the tests you added ran".

## Multiple `@compileError` Arms Fire in Non-Comptime Switch

When switching on a runtime-typed value, every arm is analyzed. A `@compileError` in a non-taken arm still fires.

```zig
for (el.children) |c| {
    switch (c) {
        .text => |t| return t,
        .element => continue,
        .expression => return null,
    }
}
```

If `c` is not comptime-known, the compiler analyzes `.text => return t` even when `c` is actually `.element`. That is fine if the arm has no `@compileError`. But if the arm is:

```zig
switch (c) {
    .element => |el| emitElement(el),
    .text => @compileError("text cannot be a direct child"),
    .expression => @compileError("expression children unsupported"),
}
```

the switch fires both `@compileError`s regardless of `c`'s actual tag.

**Fix**: force the switch value to be comptime-known.

- Use `inline for` for iteration so each `c` is comptime-bound.
- Use `comptime std.mem.eql(u8, el.tag, "column")` for tag checks so the `if`-chain prunes branches at analysis.
- Use `comptime` on function call arguments where the value must be known.

The rule: `@compileError` in a `switch` or `if` arm fires only if the arm is **analyzed**. Comptime-known control flow prunes unreachable arms; runtime control flow analyzes all of them.

## `orelse` Does Not Inject the Wrapped Type

Given `opts.padding: ?Rect`, this fails:

```zig
const cur = opts.padding orelse .{ .x = 0, .y = 0, .w = 0, .h = 0 };
```

```
error: incompatible types: 'Rect' and 'struct_1064'
```

`orelse` does not propagate the optional's payload type into the right operand. The anonymous struct infers as its own type.

**Fix**: annotate either side.

```zig
const cur: dvui.Rect = opts.padding orelse dvui.Rect{};
```

or

```zig
const cur: dvui.Rect = opts.padding orelse .{};
```

Both give the struct literal the expected type.

## `std.fmt.parseFloat` Is Unreliable at Comptime

`parseFloat` can fail or error at comptime for inputs that succeed at runtime. Do not rely on it for values that must be comptime-known (numeric attributes in a markup parser, for example).

**Fix**: write a manual digit scanner for non-negative integers:

```zig
fn parseNumeric(comptime s: []const u8) f32 {
    if (s.len == 0) @compileError("empty numeric attribute value");
    var result: f32 = 0;
    inline for (s) |ch| {
        if (ch < '0' or ch > '9') @compileError("non-numeric attribute value: '" ++ s ++ "'");
        result = result * 10.0 + @as(f32, @floatFromInt(ch - '0'));
    }
    return result;
}
```

The `inline for` makes each `ch` comptime-bound. The `if` bounds check is comptime-resolvable. `@compileError` fires only for genuinely non-numeric input. Extend with sign and decimal handling if the target attribute set requires it.

## Comptime String Tokenization via `inline while`

`std.mem.tokenizeScalar` returns a runtime iterator. Inside a comptime function it usually works, but only when the input is comptime-known and the function is forced to comptime. To make the intent explicit and the failure mode obvious, hand-roll a tokenizer with `comptime var` index and `inline while`:

```zig
fn applyClasses(opts: *Options, comptime class: []const u8) void {
    comptime var i: usize = 0;
    inline while (i < class.len) {
        while (i < class.len and class[i] == ' ') i += 1;
        if (i >= class.len) break;
        const start = i;
        while (i < class.len and class[i] != ' ') i += 1;
        const token = class[start..i];
        // compare token against known classes
    }
}
```

`comptime var` + `inline while` + runtime `while` for inner scans evaluate at comptime because the outer loop is unrolled. No dependence on `parseFloat`, `tokenizeScalar`, or any std API whose comptime behavior is undefined.

---

## Nanoui Backend Notes

Confirmed against the stub used in `src/backends/nanoui.zig`. Real Nanoui API may differ. If the stub tests pass but a real integration fails, adjust the stub to match the real API and re-run the emitter.

### Backend Contract Divergence (Load-Bearing Finding)

DVUI's signature: `pub fn emit(comptime element: ast.Element) void`. Self-contained.

Nanoui's signature: `pub fn emit(comptime element: ast.Element, ctx: *Context) void`. Requires a context because `ui.div(c)` and `ui.text(c, ...)` all take `*ui.Context`.

**These are incompatible.** The aspirational `Backend(Impl)` in `src/backend.zig` cannot assume a context-free `emit`. Two options for Phase 3.5:

1. Universal contract takes `*Context` that DVUI wraps as an empty struct.
2. Two contract variants: `BackendStateless` and `BackendStateful`.

The current state is that each backend defines its own signature. That is honest but not unified. The unification is Phase 3.5.

### Per-Tag Capabilities (Load-Bearing Finding)

Nanoui's `ui.button` is variant-driven: `opts.variant = .primary | .danger | .ghost`. There is no `opts.bg` or `opts.color`. DVUI's `button` accepts `Options` with `color_fill` and `color_text` directly.

**Capabilities are per-tag, not per-backend.** "Background is supported" is not a meaningful claim when it is true for `div` but false for `button` within the same backend. The flat `Capabilities` struct in `src/capabilities.zig` is inadequate. Phase 3.5 needs a per-tag capability table.

### Stub-Driven Development

The Nanoui backend was implemented against a `StubNanoui` with a minimal API surface — `div`, `text`, `button`, and a `Div` with `.column()`, `.row()`, `.gap()`, `.p()`, `.px()`, `.py()`, `.rounded()`, `.bg()`, `.w()`, `.h()`, `.end()`.

Stub tests prove:

- The emitter recurses through nested elements correctly.
- Class strings route through `style_mod.styleFrom` and reach the builder chain.
- Capability table is coherent.
- Tag dispatch is correct.

Stub tests do **not** prove:

- The builder methods exist on real Nanoui's `Div` with those exact names.
- The `Context` struct has the shape the stub assumes.
- `.end()` is required.

If real Nanoui diverges, the fix is: update `StubNanoui` to match real API, re-run tests, adjust emitter until tests pass, then test against real Nanoui. The stub is the contract.

### Shared Style Module (src/style.zig)

`src/style.zig` is now the canonical home of:

- `Color`, `Spacing`, `FontWeight`, `Style` structs.
- `parseClasses(comptime []const u8) Style` — class-string parser.
- `parseNumeric(comptime []const u8) f32` — attribute expression parser.
- `firstText(comptime Element) ?[]const u8` — text extraction.
- `styleFrom(comptime Element) Style` — attribute + class merge.

DVUI backend still has local copies. **Tech debt**. Migrating DVUI to `style.zig` is Phase 3.5.

The `Style` struct is the prototype for the `StylePlan` IR. It has the right shape: flat, framework-agnostic, optional fields. Aeolus integration will extend it, not replace it.

### Nanoui Stub API Surface

For reference when writing similar backends, the minimal stub is:

```zig
pub const Context = struct {};
pub const Color = struct { r, g, b, a: u8 };
pub const Div = struct {
    pub fn column(self) Div;
    pub fn row(self) Div;
    pub fn gap(self, v: f32) Div;
    pub fn p(self, v: f32) Div;
    pub fn px(self, v: f32) Div;
    pub fn py(self, v: f32) Div;
    pub fn rounded(self, v: f32) Div;
    pub fn bg(self, c: Color) Div;
    pub fn w(self, v: f32) Div;
    pub fn h(self, v: f32) Div;
    pub fn end(self) void;
};
pub fn div(c: *Context) Div;
pub fn text(c: *Context, str: []const u8, opts: anytype) void;
pub fn button(c: *Context, label: []const u8, opts: anytype) ButtonResult;
```

This is the surface a "shadcn for Nanoui" would need to target. Confirm against real Nanoui before depending on it.
