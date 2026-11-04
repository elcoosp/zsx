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
