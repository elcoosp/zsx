# Consumer demo

Proves zsx is fetchable — **no fork**, no `_gen.zig` in source tree.

## Structure

```
examples/consumer/
├── build.zig.zon   ← declares zsx as a dependency
├── build.zig       ← @import("zsx").addViews(b, opts)
└── src/
    ├── main.zig    ← @import("home"), @import("about")
    ├── shadcn.zig  ← consumer-provided components
    ├── stub.zig    ← consumer-provided adapter
    └── views/
        ├── home.zsx
        └── about.zsx
```

Note: **no `_gen.zig` anywhere.** Generated views live in `.zig-cache`.

## Run it

```bash
cd examples/consumer
zig build run
```

## What happens

1. `build.zig` calls `zsx.addViews(b, .{...})`
2. zsx builds `zsx-gen` (compiled for host) from its own `src/gen.zig`
3. `zsx-gen` reads each `.zsx` via `std.Io.Dir`, preprocesses, writes `.zig` into a build-managed output dir (`.zig-cache`)
4. Each generated file is wrapped in `b.createModule({ .root_source_file = out_path })`
5. Consumer wires those modules via `main_mod.addImport("home", ...)`
6. `main.zig` calls `home.view(stub.Adapter, &c, &ctx)`

## For external consumption

Replace the `.path` dep in `build.zig.zon` with a git URL and hash:

```zig
.dependencies = .{
    .zsx = .{
        .url = "git+https://github.com/elcoosp/zsx#v0.1.0",
        .hash = "zsx-0.1.0-AAAA...",
    },
},
```

That's the one line that changes between "local example" and "real dependency."

## Contract

Generated `.zig` files are placed in `.zig-cache`, not `src/views/`. Therefore, `.zsx` files must use **named imports**:

```zsx
const shadcn = @import("shadcn");   // ✓ works
```

Not **relative imports**:

```zsx
const shadcn = @import("../lib/shadcn.zig");  // ✗ breaks
```

Relative imports are resolved relative to the file's location. The generated file has no stable location. Named imports are resolved via `mod.addImport(name, module)`, wired by the consumer's `build.zig`.

This is the one rule that changes from in-repo usage.
