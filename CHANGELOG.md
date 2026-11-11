# Changelog

## [0.3.0] — 2026-11-09

### Added
- **M0 ground-truth tooling.** `AGENTS.md`, `docs/STATE.md`, ADR/RFC templates,
  `zig build check-meta`, `zig build check-docs`, `zig build golden`,
  `zig build bench` / `bench-smoke`, and a `zsx` CLI stub.
- `spec/golden/*.zig` — committed golden output for all 20 views.
- `bench/baseline.json` — committed generator-throughput baseline.
- `src/tests/` — per-feature test suites; `src/root.zig` is now a thin
  aggregator.
- `src/tests/reproducers.zig` — pinned reproducers for F1, F2, F3, F5.
- `src/compat.zig` and ADR 0002 — Zig `current` / `current-1` support policy.
- `VERSION` — single source of truth for release metadata.
- **Code-frame diagnostic rendering (M1).** `src/rt/render.zig`: build a
  `render.Renderer` once per file, then every `diag.Diagnostic` renders as the
  annotated snippet a developer reads — `path:line:col: severity[ZSX0xxx]`
  header, optional `  help:` line, source lines with a caret span clamped to
  the line. Exported as `zsx.render` from the package root; `zsx check` now
  prints frames; new consumer demo `examples/render/`; new `render_1k` case in
  `zig build bench`.

### Changed
- `dvui` and `nanoui` are lazy dependencies; `zig build test` and the consumer
  example no longer fetch either toolkit.
- `build.zig.zon` version aligned with the README and CHANGELOG (was `0.0.1`).
- CI now runs Ubuntu, macOS, and Windows stub jobs plus Linux real-DVUI build.
- `tools/golden.zig` normalizes goldens through the canonical Zig formatter
  (`std.zig.Ast` + `renderAlloc`), so committed goldens are always
  `zig fmt`-clean and a tree-wide `zig fmt --check` can never drift from
  `zig build golden`; all 20 goldens regenerated fmt-clean.
- Vendored example adapters (`examples/{consumer,todo}/src/{stub,shadcn}.zig`)
  are now `zig fmt`-clean.
- `src/rt/scan.zig` exposes the string-aware matcher as free functions
  (`matchBrace`, `skipString`, `skipChar`); the fail-fast parser consumes the
  same implementation.

### Fixed
- **F5 closed in the fail-fast parser** (`src/rt/parser.zig`): expression
  matching is string-aware (`{"}"}` no longer splits the expression) and
  attribute separators accept any whitespace (tabs/newlines between
  attributes used to be parse errors). The two F5 reproducers in
  `src/tests/reproducers.zig` now pin the fixed behaviour; goldens are
  byte-identical.

### Deprecated
- `scripts/zsx-fmt.py` and `scripts/zsx-check.py` now sit behind `zsx fmt` /
  `zsx check`; the native implementations replace them in M1.

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
