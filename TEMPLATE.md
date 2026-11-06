# ZSX is a template, not a fetched package

If you are looking for `zig fetch --save <zsx>`, that does not exist and will
not exist without breaking ZSX's core design.

## Why no package

ZSX's parser runs at **comptime** and its codegen writes `_gen.zig` files
back to the source tree. Two Zig facts make this incompatible with
`zig fetch`:

1. `@embedFile(path)` requires `path` to be a **comptime-known literal**. A
   fetched package cannot enumerate a *consumer's* `.zsx` files at compile
   time — that list lives in the consumer's `build.zig`.
2. `pub fn parse(comptime src: []const u8) Element` cannot be called with a
   runtime string.

A package that promised `zig fetch zsx` would need a runtime
`parse(allocator, src)`, which is slower at build time and larger at runtime.
That contradicts the whole reason ZSX exists. Templates preserve comptime.
Packages cannot.

## What you get when you fork

- Comptime `.zsx` parser (`src/parser.zig`): fragments, `if`/`else if`/`else`,
  `for`, nested components, `on_click` handler references.
- Codegen (`build.zig`): every `.zsx` becomes a `_gen.zig` with
  `pub fn view(ui, c, ctx) void`. Runs on `zig build`, writes only on change.
- Three adapters: `dvui.zig` (real DVUI + SDL3, 42 MB), `nanoui.zig` (real
  Nanoui + Metal, 4.4 MB), plus `StubDvui`/`StubNanoui` for fast tests.
- Component library (`src/lib/shadcn.zig`): `Button` (variant + class +
  on_click), `Badge` (color), `Card` (content function).
- ~15 demo `.zsx` files (`src/views/`).
- Two working binaries: `zsx-hello-real`, `zsx-hello-nanoui`.

## Start a project

    ./scripts/new-project.sh ~/code/my-app my-app
    cd ~/code/my-app
    zig build test           # fast stub-based tests, ~1s
    zig build build-app      # DVUI binary
    zig build build-app-nanoui  # Nanoui binary (macOS)

`new-project.sh` copies the tree, renames the package, generates a fresh
fingerprint, initializes a clean git repo you own. No dependency on upstream.

## When you add a view

1. Create `src/views/your_view.zsx`.
2. Add its path to `zsx_files` in `build.zig`.
3. `zig build test` — codegen runs, `_gen.zig` appears.
4. `@import("views/your_view_gen.zig").view(...)` from your Ctx code.

## Upstream changes

Add the original repo as a remote, `git fetch`, merge deliberately. No
automatic "pull this week's zsx" — you merge on your schedule.

## When a package would make sense

If Zig ever adds a build-step API that runs a comptime parser on
consumer-side source with source-line error spans, a package version
becomes viable. Until then, template.
