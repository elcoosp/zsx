# Changelog

## [0.4.0] — 2026-11-14

### Fixed
- **F1 — widget IDs no longer overflow or depend on build order (M2 WP 2.2).**
  IDs are now `@truncate(hash64(src_key, block_index, structural_path))`;
  loop indices are mixed with wrapping arithmetic. Reordering `.paths` no
  longer renames widgets, and the old ~184-file overflow is gone. See
  `docs/adr/0003-scope-aware-codegen.md`.
- **F2 — one control-flow lowering (M2 WP 2.4).** `emitContentChildren` is
  deleted; `emitChildren` is shared by element and slot/content bodies with
  unbounded loop depth and distinct `idx_N` per loop, so nested loops inside a
  slot no longer collide on identity.
- **F3 — slot/content bodies capture loop locals (M2 WP 2.3).** A body emitted
  inside `{for … as item}` now becomes a container-level generic capture
  struct (`ZsxBody_N(T…)`) constructed at the call site, instead of an
  uncaptured hoisted `fn(ui, c, ctx)`. `shadcn.invokeSlot` accepts both plain
  functions and capture structs.
- Unused-parameter discards in generated bodies are decided by an
  identifier-token scan over the body rather than substring probes.

- **F4 — `std` import detection is token-based (M2 WP 2.9).** `preprocess`
  tokenizes the generated body and looks for identifier `std` followed by `.`
  (and `@import("std")` in pass-through Zig), so text/string literals such as
  `"std.out"` no longer inject an import. This closes the last substring
  heuristic in the compiler path.
- **Event handlers v1 (M2 WP 2.6).** `on:<event>` is accepted alongside
  `on_<event>`. Component handlers accept arbitrary Zig expressions and
  arguments (`on:click={ctx.remove(item)}`); expressions inside `{for}` capture
  the loop binding through `ZsxHandler_N` structs. `shadcn.invokeHandler`
  dispatches function and capture-struct handlers; `Button` uses it. See
  `docs/adr/0004-event-handlers-v1.md`.

- **F7 — unknown props on built-in components are errors (M2 WP 2.5, first
  slice).** A registry (`src/rt/registry.zig`) lists the props of every
  `shadcn` component; the checker reports `ZSX0013 unknown_prop` with a
  did-you-mean help line, and `zsx-gen` runs the same check, so a typo fails
  the build at its `.zsx` line. `--no-prop-check` opts out. See
  `docs/adr/0005-component-prop-registry.md`.

- **`zsx.addViews` v2 directory discovery (M2 WP 2.10).** `.dir = "src/views"`
  discovers every `*.zsx` (sorted, with `.exclude`), and
  `dependOnDirectoryMetadata` re-runs configure when files are added/removed,
  so adding a view needs no `build.zig` edit. `zsx.discoverViews` is exported;
  the repo gate and `examples/consumer` use it. See
  `docs/adr/0006-addviews-directory-discovery.md`.

- **Compile-cost guardrails (M2 WP 2.12).** `src/rt/cost.zig` counts markup
  elements/components/attributes, element and control-flow depth, events and
  `@setEvalBranchQuota` occurrences (token-based), and produces a
  deterministic weighted score. `zsx check --explain-cost` prints per-file and
  total reports; `--cost-budget N` fails CI when the total exceeds `N`.
  Exported as `zsx.cost`; README documents both flags.

- **`zsx migrate` codemod (M2 WP 2.11).** `src/rt/migrate.zig` rewrites
  `on_click=` → `on:click=` (plus the other known events) and legacy
  `{endif}`/`{endfor}`/`{endswitch}` closers, locating edits with the tolerant
  scanner and applying them to the original bytes. `zsx migrate`
  (`--write`/`--check`, default dry-run) is idempotent and leaves the Zig side
  byte-exact; exported as `zsx.migrate`.

### Added
- **Zig-side scanner hardening (M1 WP 1.4 slice).** The lossless
  front-end now recognizes Zig multiline strings (`\\` line runs) and nested
  block comments, so `zsx!{` text inside either is never mistaken for a real
  block. `preprocess` and `findBlocks` inherit the fix from the shared
  scanner; the F6 reproducer is green and lossless round-trips remain
  byte-exact. Deferred: `std.zig.Ast` syntax-error remapping and the external
  200-file Zig corpus.
- **Property/fuzz infrastructure (M1 WP 1.9 slice).** `src/rt/fuzz.zig`
  drives a grammar-shaped valid generator plus byte mutations through the
  scanner, CST parser, checker, lowering and formatter. `zig build fuzz`
  runs 20 000 cases (`-Dfuzz-iterations`, `-Dfuzz-seed`), the normal test
  suite keeps a deterministic 200-case smoke, and a nightly workflow runs
  10⁶. On failure the harness saves the input under `spec/fuzz/failures/`
  and exits non-zero. Fuzzing immediately exposed two CST span bugs, both
  fixed: unclosed frames now end at their last child instead of collapsing
  to a zero-width span, `{/…}` closers are appended only after inner frames
  unwind, and control keywords (`if`/`for`/`switch`, including `for … as`)
  accept newlines and tabs as separators instead of only a single space.
- **Checker lints (M1 WP 1.7 slice).** Three warnings ride the existing token
  pass: unused `{for … as name}` bindings (`ZSX0020`), empty `{for}` bodies
  (`ZSX0021`), and raw text directly inside `<column>` (`ZSX0022`).
  `zsx check --no-lint` disables them; `// zsx-ignore ZSX0022` on the line
  directly above `zsx!{` suppresses matching warnings for that block. Lints
  add no second parse, so `check_1k` stays ≈ 0.29 ms/1k lines.
- **Diagnostic snapshots (M1 WP 1.8 slice).**
  `spec/diagnostics/snapshots.txt` pins rendered headers, help lines, gutters
  and caret windows for every code at context 0–3; the snapshot test checks
  each case actually emits its expected code.
- **CST-driven formatter (M1 WP 1.6 slice).** Valid markup is reindented from
  the CST: nesting depth comes from tree containment (nested `</Card>` is
  attributed to the inner node, closers sit at their container's depth),
  not from the file's current indentation. Malformed markup keeps the old
  scanner fallback so `zsx fmt` still normalizes broken files. The committed
  corpus stays byte-for-byte canonical, and every valid fixture still proves
  `parse(fmt(x)) ≅ parse(x)`.
- **CST lowering in the compiler path (M1 WP 1.5 slice).** `cst.lowerBlock`
  turns the recovery CST back into the AST codegen consumes (control-flow
  markers flattened to the sibling stream codegen expects). `preprocess` now
  parses each block through the CST instead of `parser.zig`, so the compiler
  and tooling share one parser. Goldens are byte-identical. Trade-off: `gen_1k`
  throughput is ≈ 60 MB/s (from ≈ 75) because a CST tree is built and lowered;
  accepted for the single-parser architecture, to be recovered with the
  CST-as-AST/line-preserving emitter work. `spec/ast/*.txt` dump goldens
  cover roots, attributes, text and flattened control markers. The grammar
  suite also checks `parse(fmt(x)) ≅ parse(x)` on all valid fixtures.
- **CST parser with recovery (M1 WP 1.3 slice).** `src/rt/cst.zig` turns scanner
  tokens into a span-carrying tree (elements, fragments, text, expressions,
  control flow, branch markers, error tokens) and never aborts: mismatches
  unwind to the nearest opener, every implicitly closed frame gets a
  diagnostic, and junk becomes an `error_token`. `treeIsOrdered` enforces
  child-span containment. The whole valid grammar corpus parses clean.
- **Lossless markup tokens (M1 WP 1.2 slice).** `scan.Token` gained
  `isTrivia`/`kindName` and `scan.coversSource`: tokens and trivia tile the
  markup block byte-for-byte. UTF-8 text/attributes pass through unchanged; a
  deterministic 5 000-case fuzz test and the 150-file grammar corpus assert
  coverage. Junk inside an opening tag now owns the whole tag span, fixing an
  out-of-order/overlapping token span.
- **RFC-0001 conformance corpus (150 files).** `spec/grammar/{valid,invalid}`
  with 102 valid and 48 invalid sources; invalid files name their expected
  `ZSX0xxx` code on line 1. `src/tests/grammar.zig` checks every valid file
  clean, preprocess-deterministic and fmt-idempotent, and every invalid file
  for its expected diagnostic. Valid fixtures are canonical `zsx fmt` output;
  `spec/grammar/invalid/` is skipped by the default `check`/`fmt` file scan
  (the conformance test still runs it).
- **Formatter: multi-line opening tags** no longer crash (`formatMarkup`
  indexed an empty token line for continuation attribute lines); continuation
  lines are now preserved byte-exact. Regression test added.
- **Root-shape diagnostics (RFC-0001 S1).** `zsx check` now rejects more than
  one root per block (`ZSX0014`), text/expressions/control flow outside the
  root (`ZSX0015`), and empty blocks (`ZSX0016`), matching what codegen has
  always required. Fragment-level `checkMarkup` keeps the old permissive
  default.

### Docs
- **RFC-0001 markup grammar v1.** `docs/rfc/0001-markup-grammar.md` plus the
  normative `docs/spec/grammar.ebnf`: block boundary, lexical classes,
  attributes/events, control flow, slots, semantics S1–S8, the `ZSX0xxx`
  error table and recovery rules. Status: draft; WP 1.1 remains open until
  review, the ≥150-file conformance corpus and the CST parser land.

### Added
- `codegen.stableNodeId`; ADRs 0003 (scope-aware codegen), 0004 (events v1),
  0005 (prop registry) and 0006 (`addViews` discovery).
- `src/rt/migrate.zig`, CLI `zsx migrate`, `zsx.migrate`.
- `src/rt/cost.zig` (`cost.analyze` / `Report.score`), CLI `--explain-cost` and
  `--cost-budget`, `zsx.cost`.
- `zsx.discoverViews`; `Options.dir` / `Options.exclude`.
- `src/rt/registry.zig` (component prop table, lookup, suggestions) and
  `diag.List.errHelp` / `ZSX0013`.
- `codegen.buildHandler`, `isEventAttr`, `attrFieldName`; `preprocess.mentionsStd`
  / `importsStd`.
- Views `slot_capture_demo.zsx`, `slot_loop_demo.zsx`, `event_args_demo.zsx`
  and end-to-end tests (including handler-in-loop).
- `spec/golden/{slot_capture_demo,slot_loop_demo,event_args_demo}.zig`.
- F4 reproducer in `src/tests/reproducers.zig` (token vs substring).

### Changed
- Goldens regenerated for the new ID scheme and loop lowering.
- F1/F2/F3/F4 reproducers in `src/tests/reproducers.zig` now assert the fixed
  behaviour.
- `zsx-gen` validates each source with the checker before emitting code.
- Checker defaults (`check_props`), CLI (`--no-prop-check`) and the README
  validation section updated.
- `shadcn.Button` invokes `on_click` via `invokeHandler`; plain `ctx.method()`
  handlers still lower to a hoisted function.

## [0.3.0] — 2026-11-09

### Added
- **Lossless front-end (M1, spikes S1 + S2).** `src/rt/lossless.zig`: one
  string-, char- and comment-aware pass partitions a `.zsx` file into typed,
  byte-exact segments (`zig_text`, `string`, `char_literal`, `line_comment`,
  `block_comment`, `zsx_block`), and `Document.render` re-emits the source
  byte-for-byte. Exported as `zsx.lossless` and via the checker barrel;
  consumer demo `examples/lossless/`; bench case `lossless_1k`.
- **Machine-readable diagnostics (M1).** `zsx check --format json` prints one
  compact JSON document on stdout (`diag.List.toJson`) with stable `ZSX0xxx`
  codes, names, severities, line/col and byte spans; exit codes are
  unchanged. Library consumers call `list.toJson()` directly; demoed in
  `examples/checker/`.
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
- `src/rt/preprocess.zig` delegates block detection to the lossless
  front-end; its two private Zig-side scanners and five skip helpers are gone
  (one scanner instead of drifting copies — master-plan finding F11). Goldens
  are byte-identical.
- `zig build bench` validates the generator inside the timing loop; the
  redundant post-loop preprocess call is removed, and `lossless_1k` joins the
  suite.
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
