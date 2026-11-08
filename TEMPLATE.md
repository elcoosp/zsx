# ZSX distribution

## Update: zsx is now fetchable

Earlier versions of zsx only worked as a template — the codegen ran at comptime inside the consumer's `build.zig`, which meant it couldn't be a package. That's no longer true.

The runtime pipeline (`src/rt/`, `src/gen.zig`, `zsx.zig`) does codegen at **build-script runtime**, not comptime. A build script can read any file it wants, so it can read a consumer's `.zsx` sources. Generated `.zig` files land in `.zig-cache`, never in source tree.

See [`examples/consumer/`](examples/consumer/) for a working example. The integration is three things:

1. `.zsx` depends on `zsx` in `build.zig.zon`
2. `build.zig` calls `zsx.addViews(b, .{...})`
3. `main.zig` does `@import("home")` — the generated view

No fork. No vendored files. No `_gen.zig` in git.

## What about templates?

Templates are still useful when you want to:

- **Customize the pipeline** — modify `src/rt/codegen.zig` to emit different Zig, add new control-flow constructs, add backend-specific primitives
- **Sell a product** — forks can be licensed per customer, packages cannot
- **Own the history** — merge upstream changes deliberately instead of tracking versions

For 90% of "I want to build an app with ZSX", the fetchable path is right. Fork the repo only if you need to modify the compiler itself.

```bash
# Typical external consumer
mkdir my-app && cd my-app
zig init
# add zsx to build.zig.zon
# call zsx.addViews in build.zig
# write src/views/home.zsx
# write src/main.zig
zig build run
```

## What you get with a fork

- Comptime pipeline (still present in `build.zig`, all 132 tests pass)
- Runtime pipeline (`src/rt/` + `src/gen.zig`) — what makes fetchable work
- Both `src/adapters/dvui.zig` and `src/adapters/nanoui.zig` — swap them at the callsite
- `src/adapters/html.zig` — HTML output for web
- 15 component library in `src/lib/shadcn.zig` — or provide your own
- 18 demo views in `src/views/` — reference for what ZSX can express

## When to fork

If you need to change the **compiler itself** — the parser, the AST, the emitter, the preprocessor — you need a fork. That's not a bug, it's the boundary between "consumer" and "compiler contributor."

For everything else — building apps, adding components, writing views — the fetchable path handles it.

## When a package still doesn't make sense

There's a narrow case where a package would be worse than a template: if you want `@embedFile` semantics for `.zsx` sources (embed them in the binary, not generate `.zig`). That requires comptime parsing, which requires a fork.

`@embedFile` on `.zsx` isn't a typical requirement — but if it is yours, fork the repo and use the comptime pipeline. It's still here, unchanged.
