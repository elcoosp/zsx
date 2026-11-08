# Changelog

## [0.2.0] — 2026-11-09

### Added
- **5 new components**: `Label`, `Alert`, `Breadcrumb`, `Tabs`, `Pagination`. 20 total.
- **`scripts/init.sh`** — one-command project scaffold: copies `examples/consumer/`, patches `.path` relative to build root (realpath-aware for `/tmp` symlink), computes fingerprint, runs `git init`, verifies `zig build` succeeds.
- **DVUI screenshots** — `docs/screenshots/playground-dvui.png` showing 15 components rendered through a real SDL3 window.
- **Real DVUI/Nanoui visual verification** — both backends now have committed screenshots.

### Changed
- `Skeleton` adapter on DVUI: `background = true` + explicit `margin` so stacked bars paint and space correctly. Same class of fix as `TextEntry` (`min_size_content`).
- `Progress` and `Slider` on DVUI: explicit `min_size_content` (240×8 and 240×24) — DVUI widgets have no intrinsic width.
- `hello_dvui.zig`: window 700×1000, wrapped in `scrollArea` so content taller than the display remains reachable.
- **`src/rt/codegen.zig`**: `usesParam` takes `comptime name` (the `++ "."` concat required it). `fixDiscardPrefixes` now uses `usesParam` (6 patterns) instead of `ctx.`-only substring.

### Removed
- `src/snapshot_test.zig` no longer spawns `sips` (broken `std.process.Child.init` on Zig 0.17). Downscale is manual: `sips -Z 900 <in> --out <out>`.

### Fixed
- `Tabs` and `Pagination` take runtime `props: anytype` — they carry `*usize` pointers which can't be comptime-known.
- `Alert` is a leaf (title + text), not a container.
- `Color{...}` typed literals everywhere (anonymous `. { .r, .g, .b }` structs have no `.a` field).

## [0.1.0] — 2026-11-08

### Added
- Fetchable distribution: `zsx.addViews(b, opts)`. No fork.
- Runtime pipeline (`src/rt/`).
- `zsx-gen` CLI.
- `zsx.addViewsLocal` for in-repo.
- HTML adapter.
- Named slots.
- Path-qualified tags.
- Pluggable style resolver.
- `{switch}` control flow.
- DRY control flow syntax.
- Source-span errors.
- Zig 0.17 gotchas in `docs/zig-skill.md`.

### Removed
- Comptime pipeline.
- `src/views/*_gen.zig`.
