# ZSX distribution

## Use as a dependency

```zig
// build.zig.zon
.dependencies = .{ .zsx = .{ .url = "git+https://github.com/elcoosp/zsx#v0.1.0", .hash = "..." } }
```

```zig
// build.zig
const zsx = @import("zsx");
const views = zsx.addViews(b, .{ .paths = &.{"src/views/home.zsx"}, .target = target, .optimize = optimize });
for (views) |v| app_mod.addImport(v.name, v.module);
```

```zig
// src/main.zig
const home = @import("home");
home.view(Adapter, &c, &ctx);
```

Generated `.zig` lands in `.zig-cache`. Never in your source tree. `examples/consumer/` is a working demo.

## Fork the repo

Fork if you need to modify the emitter.

## Pipeline

`.zsx` source → `zsx-gen` (build-time host binary) → `.zig` in `.zig-cache` → `b.createModule({ .root_source_file = ... })` → `@import("<name>")`.

`zsx!{ }` is not Zig syntax; the compiler never sees it.

## What you get

- `src/rt/` — runtime pipeline.
- `zsx.zig` — `addViews` / `addViewsLocal`.
- `src/gen.zig` — `zsx-gen` CLI.
- Three adapters: DVUI, Nanoui, HTML.
- 20 components in `src/lib/shadcn.zig`.
- `examples/consumer/` — working end-to-end.
