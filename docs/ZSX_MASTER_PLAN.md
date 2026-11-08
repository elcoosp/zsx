# ZSX Master Plan — from v0.2 prototype to a v1 ecosystem standard

> **Audience:** autonomous AI implementation agents (and the humans supervising them).
> **Horizon:** ~36 months, 14 milestones, 4 phases, 5 parallel tracks.
> **Status of this document:** proposal. Every numeric target is an *initial target* to be calibrated by the M0 baseline; every "decision" is a *recommended default* to be ratified through an ADR/RFC (see §5.4). Nothing here has been measured by running the code — the audit in §2 is from a static read of the repository at commit `5a75f33`.

---

## 0. How to read and use this plan

1. Read §1–§4 once (vision, audit, architecture). They are the "why".
2. Read §5 (Agent Operating Protocol) before touching code. It is binding.
3. Execute milestones in order inside a phase; milestones in different tracks (§7) run in parallel.
4. Every work package (WP) has: **ID · Why · Scope · Deliverables · Acceptance**. A WP is done only when *all* acceptance bullets are checked **and** the global Definition of Done (§5.3) holds.
5. Size legend: **S** ≤ ½ agent-day · **M** 1–2 · **L** 3–5 · **XL** 1–2 agent-weeks. XL items must be split into ≤ L PRs before starting.
6. Anything marked **[SPIKE]** is a time-boxed experiment whose output is a written ADR plus a go/no-go, not production code.
7. Anything marked **[RFC]** needs a ratified RFC before implementation. The agent writes the RFC; a human (or the designated review agent plus a 7-day comment window) accepts it.

---

## 1. Vision, thesis, and what "v1 = amazing" means

### 1.1 Thesis

**Write UI once as declarative markup inside Zig; compile it ahead-of-time into the exact code an expert would have hand-written for each target — with a toolchain (formatter, linter, LSP, hot reload, test harness, devtools) that makes it the best UI authoring experience in any systems language.**

ZSX's differentiators, in priority order:

1. **Zero-cost output.** No runtime parser, no VDOM, no interpreter, no hidden allocation. Generated code ≈ hand-written code.
2. **Toolchain-grade DX.** Errors point at your `.zsx` line. Editor support is first-class. Save → pixels is sub-second.
3. **One source, many strategies.** The same view compiles to *immediate-mode* calls (dvui, imgui, raylib, TUI), *static HTML* (SSR), and *retained fine-grained DOM ops* (Wasm) — chosen per build, not per rewrite.
4. **Compile-time correctness.** Typed props, unknown-class errors, accessibility lints, capability checks per backend — all at build time.
5. **A real component ecosystem.** Headless behaviours + themeable skins, installable shadcn-style (`zsx add dialog`), accessible by default.

### 1.2 The v1 bar (exit criteria for the whole program)

v1.0 ships only when **all** are true:

| # | Criterion | Measure (initial target) |
|---|---|---|
| V1 | Stable public API | Frozen grammar + backend contract + `zsx-ui` API; semver; 12-month compat promise |
| V2 | Diagnostics | 100 % of compile errors originating in `.zsx` markup report `.zsx:line:col`; ≥ 95 % of Zig compiler errors in generated code are remapped to `.zsx` lines |
| V3 | Editor | LSP with diagnostics, completion (tags/props/classes/ctx members), hover, go-to-def, rename, format, semantic tokens; tree-sitter grammar; VS Code, Zed, Neovim, Helix packages |
| V4 | Speed (author) | Warm hot-reload save→visible ≤ 300 ms on the reference app (calibrate in M9) |
| V5 | Speed (build) | `zsx-gen` ≥ 20 MB/s end-to-end per core; 1 000-line view generated in < 10 ms; added Zig compile time ≤ 15 % over hand-written equivalent |
| V6 | Speed (runtime) | Immediate backends: **0 heap allocations per steady-state frame** (asserted in tests); generated code within 5 % of hand-written on the zsx-bench suite; 10 000-row table scroll at display refresh on reference hardware |
| V7 | Size | Hello-world web build ≤ 20 KB gzip (Wasm+JS glue) target; native binary overhead vs hand-written ≤ 2 % |
| V8 | Backends | Tier-1 (full conformance, CI on all OSes): headless/software, web (SSR + Wasm retained), dvui, TUI. Tier-2: raylib, cimgui, nanoui. |
| V9 | Components | `zsx-ui` ≥ 60 components, every one with: a11y role/keyboard spec, light/dark theme, headless test, docs page, visual regression baseline |
| V10 | Quality | ≥ 90 % line coverage on compiler crates; parser/formatter fuzzed ≥ 10⁹ executions per release; zero known soundness bugs in codegen; reproducible builds |
| V11 | Adoption proof | ≥ 5 non-trivial reference apps (incl. one > 20 kLOC of `.zsx`), ≥ 3 external projects in production, migration codemod from every 0.x grammar |
| V12 | Docs | Book + API reference (generated) + in-browser playground (zsx-gen compiled to Wasm) + cookbook of ≥ 50 recipes |

---

## 2. Baseline audit (what exists, what is wrong)

Static read of: `src/rt/{parser,preprocess,codegen,style}.zig`, `src/gen.zig`, `zsx.zig`, `build.zig`, `build.zig.zon`, `src/adapters/*`, `src/lib/*`, `scripts/*`, CI, docs, examples.

### 2.1 Size and shape

~5.4 kLOC total. The compiler proper (parser 258 + preprocess 92 + codegen 565 + style 209) is ≈ 1.1 kLOC. Three adapters (dvui 330, html 307, nanoui 489), one component file (480), one 960-line `root.zig` holding most tests, two Python scripts (`zsx-fmt.py`, `zsx-check.py`). This is a credible *proof of concept* with good instincts (build-time generation, `.zig-cache` output, fetchable via `addViews`).

### 2.2 Findings — correctness and robustness

| ID | Finding | Evidence | Severity |
|---|---|---|---|
| F1 | **Widget-ID arithmetic can overflow.** `real = fileBase * 10_000_000_000_000 + base`, `fileBase = file_index*10_000 + block`. `usize` max ≈ 1.8·10¹⁹ ⇒ overflow at roughly ≥ 184 `.zsx` files. IDs also depend on *file order in `.paths`*, so reordering files changes identity (breaks persisted widget state). Loop depth hard-capped at 3. | `codegen.zig` constants + `idExpr` | High (verify with a test) |
| F2 | **Duplicated control-flow code.** `emitChildren` and `emitContentChildren` are near-copies; the latter hard-codes `idx_0` and loop depth 0 ⇒ ID collisions and wrong nesting inside slot/content bodies. | `codegen.zig` | High |
| F3 | **Slot/content bodies cannot capture locals.** Hoisted `inline fn render_*(ui, c, ctx)` only receive those three params, so a child inside `{for … as item}` that references `item` inside a component's content cannot compile. | `emitSlotComponent`, `emitElement` | High (design flaw) |
| F4 | **Textual hacks in codegen.** Unused-param discards via substring search (`usesParam` looks for `"ui."`, `"c,"` …), `needs_std` via `indexOf("std.")`, post-hoc string surgery in `fixDiscardPrefixes`. False positives/negatives are guaranteed. | `codegen.zig`, `preprocess.zig` | Medium |
| F5 | **Parser fragility.** Attribute separator accepts only `' '` (tabs/newlines between attributes appear to fail). Brace matching in `{expr}` ignores string/char literals and comments (`{"}"}` breaks). No entity/escape model for text. `loc()` is O(n) per call. No error recovery (first error aborts). No comments in markup. No spread attributes. | `parser.zig` | High for DX |
| F6 | **Preprocessor is a hand-rolled Zig lexer.** It skips strings/comments but not multiline strings (`\\`), and strips preceding spaces by byte-trimming. Any `zsx!{` text it mis-detects is silently rewritten. | `preprocess.zig` | Medium |
| F7 | **Unknown props are silently accepted.** `componentPropsLiteral` emits every attribute as a struct field; components read them via `@hasField`. A typo (`varient="x"`) compiles and does nothing. Anonymous-struct duck typing (`anytype` everywhere) means no IDE help and poor errors. | `codegen.zig`, `shadcn.zig` | High for DX |
| F8 | **Event model is minimal.** Only `on_click={ctx.method()}`, zero-arg, rewritten to `@field(@TypeOf(ctx.*), "m")`. No arguments, no per-item handlers in loops, no other events (change, key, focus, hover, drag). HTML adapter's `button` always returns `false` ⇒ HTML is static-only. | `normalizeClickHandler`, `html.zig` | High |
| F9 | **Two divergent style engines.** `rt/style.zig` (runtime, used by generator) and `lib/style.zig` (comptime, used by components) are hand-duplicated if/else chains over ~30 colors; no `m-*`, no variants (`hover:`, `dark:`, `md:`), no arbitrary values, no theme tokens. | both files | High (maintenance + capability) |
| F10 | **No source mapping.** Zig compile errors in generated code point into `.zig-cache/<hash>/home.zig`, not `.zsx`. Only *parser* errors are mapped. This is the single biggest DX gap. | architecture | Critical |
| F11 | **Three parsers.** Zig parser + Python checker + Python formatter each re-implement the grammar; drift is inevitable. Python is also an extra toolchain dependency for a Zig project. | `scripts/*.py` | Medium |
| F12 | **Distribution flaw.** `build.zig.zon` lists `dvui` and `nanoui` as non-lazy dependencies, so *every consumer of `zsx` fetches both toolkits*. `addViews` needs every path listed explicitly (no globbing). Version drift: `.zon` says `0.0.1`, README/CHANGELOG say `0.2.0`; README says both "15" and "20" components. Dependencies pinned to `ref=main` commits of pre-1.0 projects. | `build.zig.zon`, README | Medium |
| F13 | **Adapters are duck-typed, not contract-checked.** They reflect over `opts` with `@hasField`; no formal primitive signature, no capability metadata, no conformance tests. Nanoui keeps a global `static var` hash map of text buffers (not thread-safe; never freed). | `adapters/*` | Medium |
| F14 | **Capability gaps in the primitive surface.** Only 12 primitives. Missing: scroll, image, icon, select/list, grid, overlays/popovers/portals, focus management, keyboard/IME events, a11y, animation, clipboard, drag-drop, virtualization, theming. | `adapters/*` | Strategic |
| F15 | **Test strategy is shallow.** One 960-line test file; no golden tests for generated code; no fuzzing; no property tests; no benchmarks; real-backend CI and screenshots are macOS/Metal only. | `root.zig`, CI | High |
| F16 | **Toolchain coupling.** Pinned to Zig 0.17.x; `docs/zig-skill.md` lists 17 gotchas — evidence the API surface moves under the project. No compat layer or version policy. | docs | Medium |
| F17 | **`zsx!{}` is statement-only, void-returning.** Cannot be used in expression position, cannot return a reusable view value, cannot take typed children/slot parameters, and a single root element is required per block. | `preprocess.zig` | Strategic |

### 2.3 What is worth keeping (do not regress)

- Build-time generation into `.zig-cache`, consumer imports by module name.
- Source-spanned parse errors.
- Control-flow-in-markup (`{if}`, `{for}`, `{switch}`) lowering to literal Zig control flow.
- Unknown class = build error (not silent).
- Pluggable resolver idea; shadcn-style component philosophy; stub adapters for fast tests.
- Honest README ("Not quite TSX") and non-hype tone.

### 2.4 Decisions in the old ROADMAP that this plan deliberately revisits

| Old decision | New position | Rationale |
|---|---|---|
| "Rejected: Backend trait / Capabilities module" | Re-introduce a **declarative, zero-runtime** `Backend` contract + capability flags, *consumed at build/comptime only* | The rejected design was a runtime dispatch layer. Contract + capability metadata gives conformance tests, per-backend lints and generated support matrices without dispatch. |
| "Non-goal: reactive layer" | **Optional** `zsx.state` signals, lowered *only* for retained backends; immediate backends keep plain Zig state | The web target is not competitive without fine-grained updates. Immediate mode stays zero-cost; reactivity is opt-in and compiled away where unused. |
| "Non-goal: routing/state/lifecycle" | Keep routing out of core; ship `zsx-router` and `zsx-store` as *optional packages* | Ecosystem standard needs blessed answers without bloating core. |
| "Out of scope: tree-sitter / LSP (priority G, low)" | Promoted to **P0** (Milestone M3) | DX is the product. |
| "`{endif}` etc. aliases" | Removed in v1 (codemod provided) | Single canonical syntax. |

---

## 3. Target architecture

### 3.1 Package split (all MIT, all semver, lazy deps everywhere)

```
zsx                  compiler + CLI (zsx gen|fmt|check|lsp|doc|migrate|init|add|doctor|bench)
zsx-rt               tiny comptime-only runtime helpers (props checking, ids, callbacks, state)
zsx-layout           pure-Zig flex/grid layout engine (used by backends lacking layout)
zsx-raster           software renderer (headless, deterministic) + text shaping hooks
zsx-test             test harness: queries by role/text, event sim, a11y snapshots, pixel diff
zsx-ui               headless behaviours + skins (≥ 60 components), icon set, themes
zsx-router, zsx-store, zsx-i18n   optional
zsx-backend-dvui | -web | -tui | -raylib | -cimgui | -nanoui | -headless     one package each
zsx-tree-sitter      grammar + queries + highlight tests
zsx-editor-*         vscode, zed, nvim, helix
zsx-bench            benchmark suite + dashboard generator
```

Consumers add `zsx` plus *only* the backends they use. No transitive toolkit downloads.

### 3.2 Compiler pipeline (v1)

```
.zsx source
  │  L0  Lossless lexer           → tokens (with trivia), byte-exact roundtrip
  │  L1  Zig-side scan            → replace each zsx!{…} with a placeholder expr,
  │                                  parse remainder with std.zig.Ast (scopes, fn sigs,
  │                                  decl names, true syntax errors)            [SPIKE S1]
  │  L2  Markup CST parser        → lossless CST, error-recovering, incremental-ready
  │  L3  AST + name resolution    → components, props types, scopes, captures
  │  L4  HIR (typed render IR)    → static/dynamic split, stable IDs, a11y facts,
  │                                  dependency sets, capability requirements
  │  L5  Passes                   → lint, a11y check, style resolve+intern, hoist statics,
  │                                  dead-style elimination, capture analysis
  │  L6  Lowering (per strategy)  → immediate | static-html | retained-dom
  │  L7  Emit                     → *line-preserving* Zig + sourcemap + manifest.json
  ▼
.zig-cache/<hash>/<name>.zig  (+ .zsxmap, + .manifest)
```

Key invariants:

- **I1 Line preservation.** Container-level declarations in Zig are order-independent, so hoisted helpers go at end-of-file and each markup element's generated statements start on the source line of the element. Zig error line numbers then equal `.zsx` line numbers; a thin wrapper only needs to swap the cache path for the source path. A `.zsxmap` provides column-accurate mapping for the LSP. **[SPIKE S2]**
- **I2 One grammar source.** The grammar is specified once (EBNF in `docs/spec/grammar.ebnf`) with a conformance corpus (`spec/corpus/*.zsx` + expected CST/AST dumps). The Zig parser, formatter, LSP, and tree-sitter grammar are all tested against that corpus.
- **I3 Determinism.** Generation is a pure function of inputs; output is byte-identical across OS/host/thread-count.
- **I4 No semantic guessing via substrings.** Everything is decided on tokens/AST.
- **I5 Zero hidden runtime cost.** Anything that costs at runtime is visible in generated code and in `zsx check --explain-cost`.

### 3.3 HIR sketch

```
View        := Node*
Node        := Intrinsic{kind, props, children}      -- stack/row/grid/scroll/text/image/input/…
             | Call{component, props, slots}         -- typed props, slot params
             | Text{static|dynamic expr}
             | If{cond, then, else_ifs, else}
             | For{iter, binding, index, key?, body, empty?}   -- keyed by default when key given
             | Switch{expr, cases, default}
             | Let{name, expr, body}                 -- scoped bindings (replaces ad-hoc locals)
             | Portal{target, body}                  -- overlays, dialogs, tooltips
             | SlotDef{name, params, body}
             | Fragment{children}
Every node: span, stable_id:u64, a11y{role,label_src}, deps:{state paths}, caps:{required capabilities}
```

### 3.4 Strategies (same HIR, different lowerings)

| Strategy | Targets | Output |
|---|---|---|
| `immediate` | dvui, cimgui, raylib, TUI, headless | direct builder calls each frame, no allocations, no retained tree |
| `static_html` | SSR / static sites / email-ish | string writer calls, escaping, a11y attributes |
| `retained` | Wasm DOM, future native retained | static template + minimal binding table; fine-grained patches from signals; no VDOM |

### 3.5 Backend contract v1

Each backend exports `pub const Backend = struct { … }` satisfying a **declared** interface, plus `pub const caps: Capabilities`. `zsx-rt` provides `comptime verifyBackend(B)` that produces readable `@compileError`s (missing primitive, wrong signature, missing capability). A **conformance suite** (`zsx-test`) runs one shared set of ≥ 300 behaviour tests against every backend (via its headless/stub mode where real windows are impossible). Support matrices in the docs are *generated* from `caps` + conformance results.

### 3.6 Component model

- Props are real Zig structs: `pub const Props = struct { variant: Variant = .primary, on_press: ?Callback(void) = null, … }`. Generated code constructs `Props` with named-field initialization — unknown/misspelled fields are Zig errors, and the diagnostics layer upgrades them to "did you mean `variant`?" at the `.zsx` location.
- Components are plain Zig functions `fn Name(ctx, ui, props, slots) void` (immediate) or `fn Name(...) zsx.View` (expression form). The compiler extracts a **manifest** (props, slots, events, a11y role) for LSP/docs via a tiny comptime-introspection build step (`zsx-manifest`).
- **Headless behaviours** (state machines: dialog, menu, combobox, tabs, tooltip, …) are separated from **skins** (styling). Skins can be replaced per theme.

### 3.7 Style system v1

- One utility-class engine, one source of truth, **generated tables** (palette × shades, spacing, radii, shadows, typography scale, breakpoints) → emitted as `zsx-style/tables.zig` by a generator script written in Zig.
- Supports: arbitrary values (`w-[240px]`), negative values, margins, flex/grid, borders, shadows, opacity, transitions metadata; variants `hover: focus: active: disabled: dark: sm: md: lg: first: last:`; design tokens via `theme.zon`; `class={zsx.cls(.{ .base, .when(cond, "bg-red-500") })}` with **comptime-known candidate set** (so every possible class is validated and interned at build time).
- Output: interned `Style` structs in a `.rodata` table; views reference style by index. Dead-style elimination removes unused entries.
- HTML backend can also emit a real CSS file from the interned set (deterministic atomic CSS).

---

## 4. Principles for every decision

1. **Measure first.** No optimization without a benchmark in `zsx-bench`; no claim in docs without a reproducible script.
2. **Make the wrong thing a compile error.**
3. **Boring output.** Generated Zig should look like something a senior Zig developer would write.
4. **Escape hatches everywhere.** Any generated construct can be replaced by hand-written Zig.
5. **Backends are cheap to add** (< 1 kLOC for an immediate backend, conformance suite tells you when you're done).
6. **Docs are code.** Examples in docs are compiled and tested in CI.
7. **Small PRs, strong gates.** Agents ship fast *because* the gates are strict.

---

## 5. Agent Operating Protocol (binding)

### 5.1 Repository memory (agents lose context between sessions)

Create and maintain, from M0:

- `AGENTS.md` — conventions, commands, directory map, "how to run everything", gotchas. ≤ 300 lines.
- `docs/STATE.md` — living status: current milestone, open WPs, last green commit, known flakiness. Updated in every PR that completes a WP.
- `docs/adr/NNNN-title.md` — architecture decision records (context, options, decision, consequences, status).
- `docs/rfc/NNNN-title.md` — user-facing changes (grammar, public API, backend contract).
- `docs/zig-skill.md` — keep extending (Zig version gotchas, verbatim error → fix).

### 5.2 Work loop

```
1. Read AGENTS.md + docs/STATE.md + the WP.
2. Write/extend tests FIRST (failing). For bugs: reproducer test.
3. Implement the smallest change that passes.
4. Run the local gate:  zig build test && zsx fmt --check && zsx check && zig build bench-smoke
5. Update docs (+ doc tests), CHANGELOG, STATE.md.
6. Open a PR ≤ ~600 changed lines (excluding goldens/generated). One WP per PR; XL → split.
7. If a decision is needed → ADR/RFC with options + recommended default; do not guess silently.
```

### 5.3 Global Definition of Done

- [ ] All tests green on the full CI matrix (Linux/macOS/Windows where applicable).
- [ ] New behaviour has unit tests; compiler changes have **golden** tests; parser/format changes have **corpus + fuzz** coverage.
- [ ] No benchmark regression > 2 % (instruction-count metric) unless justified in the PR and approved.
- [ ] Docs updated; examples compile (`zig build docs-test`).
- [ ] Public API changes have an RFC reference and a CHANGELOG entry (+ codemod during 0.x).
- [ ] No new compiler warnings; no `TODO` without an issue ID.
- [ ] Generated code diff reviewed (goldens show it).

### 5.4 Escalation (stop and ask a human)

Public naming of language constructs; license/legal; security-sensitive design; adding a dependency; dropping a platform; any change that makes a Tier-1 criterion in §1.2 unattainable; ≥ 2 failed attempts at the same WP.

### 5.5 Parallelization map

Agents may work concurrently on: (parser/CST) ∥ (backend work) ∥ (components) ∥ (docs/site) ∥ (bench). Sync points are the **milestone gates** (end of M2, M4, M7, M10, M12). Shared interfaces (HIR schema, backend contract) are frozen via RFC before dependants start.

### 5.6 Anti-patterns agents must avoid

- Substring/regex processing of Zig or markup source.
- New global mutable state in adapters or runtime.
- Copy-pasting control-flow or style logic (F2/F9 happened this way).
- "Fixing" a test by loosening it without an ADR.
- Large "refactor + feature" PRs.

---

## 6. Roadmap overview

| Phase | Months | Milestones | Theme |
|---|---|---|---|
| **P0 Foundations** | 0–2 | M0 | Ground truth, safety net, process |
| **P1 Compiler 2.0** | 2–10 | M1, M2, M3 | Lossless front-end, typed IR, diagnostics + editor |
| **P2 Runtime & Backends** | 8–20 | M4, M5, M6, M7 | Backend contract, headless, styles, immediate GA, web retained |
| **P3 Ecosystem & Excellence** | 18–29 | M8, M9, M10 | `zsx-ui`, hot reload/devtools/playground, performance program |
| **P4 Hardening → v1** | 28–36 | M11, M12, M13 | Freeze, security, docs, RC, v1.0 |

```
M0 ─▶ M1 ─▶ M2 ─▶ M3 ───────────────┐
              │      └─▶ M9 ──────────┤
              └─▶ M4 ─▶ M5 ─▶ M6 ─▶ M7 ─▶ M8 ─▶ M10 ─▶ M11 ─▶ M12 ─▶ M13 (v1.0)
```

Release train during 0.x: a tagged release at the end of every milestone (0.3 … 0.15), plus monthly patch releases. Breaking changes are allowed in 0.x **only** with an RFC + codemod.

---

## M0 — Ground truth (months 0–2)

**Goal:** make the existing code safe to change: baseline numbers, safety net, fixes for the worst latent bugs, process in place.

| WP | Title | Size | Why / Scope | Acceptance |
|---|---|---|---|---|
| 0.1 | `AGENTS.md`, `STATE.md`, ADR/RFC templates | S | §5.1 | Files exist; CI link-checks them |
| 0.2 | Version & metadata hygiene | S | F12: align `.zon` version/README/CHANGELOG; single source of truth for version & component count (generated into README by a script) | `zig build check-meta` fails on drift |
| 0.3 | Lazy dependencies | M | Mark `dvui`/`nanoui` `.lazy = true`; only fetched when the relevant step is requested; verify `examples/consumer` fetches neither | Consumer `zig build` with empty cache downloads only `zsx`; CI test asserts it |
| 0.4 | Reproducer tests for F1/F2/F3/F5 | M | Failing-first tests: 200-file overflow, loop-in-slot ID collision, slot capturing loop var, newline/tab between attributes, `{"}"}` expression | Each reproducer committed as `expectFail` with issue link, then fixed in M1/M2 |
| 0.5 | Golden-test harness for codegen | M | `zig build golden` renders every `src/views/*.zsx` through `zsx-gen`, diffs against `spec/golden/*.zig`; `-Dupdate-golden` to regenerate | Goldens committed; CI fails on unexpected diff |
| 0.6 | Split `root.zig` tests | M | Move 960 lines into per-feature test files; remove `root.zig` as test hub | No test lost (count preserved), runtime unchanged |
| 0.7 | Benchmark harness skeleton (`zsx-bench`) | L | Deterministic metrics: **instruction counts** (via `perf stat`/valgrind where available; wall-clock as fallback), peak RSS, binary size, generated LOC. Initial benches: gen throughput on synthetic 1k/10k-line files; stub-adapter frame cost for 100/1k/10k widgets; compile time of the playground | `zig build bench` outputs JSON; CI uploads artifact; **M0 baseline committed** (`bench/baseline.json`) |
| 0.8 | CI matrix | M | Ubuntu, macOS, Windows for compiler + stub backends; Linux real-dvui job with SDL3 via apt; cache strategy | All green; documented flake policy |
| 0.9 | Replace Python tooling with a stub `zsx` CLI | M | `zsx fmt`/`zsx check` subcommands that for now *wrap* the Python (temporary) so CI/docs only reference `zsx …` | Docs updated; Python marked deprecated |
| 0.10 | Zig-version policy ADR | S | Support `current` and `current-1` Zig release; compat shims live in one file `src/compat.zig`; `docs/zig-skill.md` becomes CI-tested where possible | ADR accepted |

**Gate M0:** baseline committed; reproducers exist; consumer path downloads only `zsx`.

---

## M1 — Lossless front-end (months 2–5)

**Goal:** one real parser, shared by compiler/formatter/linter/LSP/tree-sitter, with error recovery and a spec.

### Spikes (first 2 weeks)

- **S1 — Zig-side parsing via `std.zig.Ast` placeholders.** Replace each `zsx!{…}` by a syntactically valid placeholder (`zsx_hole_N()` / `@as(zsx.View, undefined)` depending on position), parse the remainder with `std.zig.Ast`, obtain: enclosing function signature, parameter names/types, declared locals visible at the hole, container-level decls, and exact syntax errors in the Zig parts. **Go/no-go:** works for 100 % of files in the repo + a corpus of ≥ 200 real Zig files with injected holes. Fallback: a faithful `std.zig.Tokenizer`-based scanner (never substring).
- **S2 — Line-preserving emission.** Prototype emitting the current playground such that line N in generated == line N in `.zsx` for ≥ 95 % of statements; hoisted helpers at EOF. **Go/no-go:** a deliberately broken prop produces an error whose line number matches the `.zsx` line after path swap. Fallback: sourcemap-only remapping.

### Work packages

| WP | Title | Size | Scope | Acceptance |
|---|---|---|---|---|
| 1.1 | **[RFC-0001] ZSX v1 grammar** | L | Decide: expression-position `zsx!{}`; fragments; `{for … as x, i key=…}{:empty}{/for}`; `{if}`/`{:else if}`/`{:else}`; `{switch}`; `{let x = …}`; `{#snippet}`/slot params; event syntax `on:click={…}` with args/closures; attribute spread `{...props}`; comments `{/* */}`; text escapes; tabs/newlines in tags; namespaced attrs (`bind:`, `aria-`, `on:`, `class:`); tag rules (lowercase = intrinsic, Uppercase/dotted = component). Rename `<label>` → `<text>`. Remove legacy `{endif}` etc. | Accepted RFC + `docs/spec/grammar.ebnf` + ≥ 150 corpus files |
| 1.2 | Lossless lexer | M | Tokens with trivia, UTF-8 aware, byte offsets + line index (binary search, fixes O(n) `loc`) | Roundtrip: `concat(tokens) == source` for entire corpus + fuzz |
| 1.3 | Markup CST parser with error recovery | XL→3×L | Recursive descent, synchronizes on `>`/`}`/closing tags; produces CST with error nodes; multiple diagnostics per file; string/char/comment-aware brace matching (F5) | Corpus pass; fuzz 10⁸ execs no crash/hang; each error has code `ZSX0xxx`, span, help text |
| 1.4 | Zig-side scanner (S1 outcome) | L | Replace `preprocess.zig` scanning; multiline strings, raw strings, nested comments handled; real Zig syntax errors surfaced with `.zsx` positions | All repo views + 200-file corpus pass; reproducer 0.4 for F6 green |
| 1.5 | CST → AST lowering | M | Normalization (whitespace text collapse rules per RFC), attribute canonicalization, spans retained | AST dump tests (`spec/ast/*.txt`) |
| 1.6 | **Formatter in Zig** | L | Idempotent, comment-preserving, configurable width, Zig side untouched (byte-exact); formatting driven by CST | `fmt(fmt(x)) == fmt(x)` on corpus+fuzz; `parse(fmt(x)) ≅ parse(x)`; golden style tests; Python fmt deleted |
| 1.7 | **Checker in Zig** | M | Structural + lint framework (rule IDs, severities, `// zsx-ignore`); first rules: unused binding, empty `{for}` body, text directly in `column` | Python check deleted; 100 % of previous checks ported; perf < 20 ms for 1k lines |
| 1.8 | Error-message quality pass | M | Rustc-style rendering (code frame, labels, notes, did-you-mean via edit distance) | Snapshot tests of ≥ 60 error cases |
| 1.9 | Property/fuzz infrastructure | M | Grammar-based generator for valid markup; mutation fuzzer for invalid; run with Zig's fuzzing support where available else a bundled harness; nightly CI job | Corpus of crashes minimized + checked in |

**Gate M1:** Python removed; `zsx fmt/check` native; corpus + goldens green; no parser reproducer left open.

---

## M2 — HIR and Codegen 2.0 (months 4–8)

**Goal:** a typed, scope-aware IR and a codegen without substring hacks; fix F1–F4, F7, F8, F17; ship typed props and a real event system.

| WP | Title | Size | Scope | Acceptance |
|---|---|---|---|---|
| 2.1 | **HIR definition + builder** | L | §3.3; stable node IDs; static/dynamic classification; dependency sets (initially coarse: referenced `ctx` paths) | HIR dump goldens; invariants checker pass |
| 2.2 | **Stable ID scheme** | M | `id = hash64(file_stable_key, structural_path, key?)`; loops mix `key` or index; no overflow, no dependence on `.paths` order | Property test: 10 000 files, 0 collisions in a node-level sample; reorder test passes; F1 reproducer green |
| 2.3 | Scopes and captures | L | Generator-introduced names (`for`, `let`, slot params) + Zig locals/params from S1; capture analysis by identifier tokens; emit slot bodies as generated local structs taking a *capture tuple* | F3 reproducer green: slot content inside `{for}` can use `item` |
| 2.4 | Unified control-flow lowering | M | One implementation shared by element bodies and slot bodies; arbitrary loop depth; keyed loops | `emitContentChildren` deleted; F2 reproducer green |
| 2.5 | Typed props | XL→L+L+M | Generated code builds `Component.Props{…}` by named fields; `zsx-rt.props` comptime helpers: required-field errors, defaults, enum string coercion (`variant="primary"` → `.primary`), callback adaptation | F7: typo'd prop is an error with did-you-mean at `.zsx` line |
| 2.6 | Event system v1 | L | `on:click={ctx.save()}`, `on:click={ctx.remove(item.id)}`, `on:change={ctx.setName}`, inline closures via generated capture structs; events: click, change, input, submit, key, focus/blur, hover, drag (capability-gated). `Callback(T)` type with zero-alloc representation (fn ptr + captured tuple by value) | Handler-in-loop test; HTML/immediate parity tests; F8 addressed |
| 2.7 | Expression-position `zsx!{}` and `zsx.View` | L | `return zsx!{…};`, `const v = zsx!{…};`, passing views as props | RFC-0001 semantics; goldens |
| 2.8 | Emitter with I1 line preservation + `.zsxmap` | XL→3×L | Implements S2; emits sourcemap (VLQ or binary), manifest JSON (props/slots/events) | ≥ 95 % statements line-exact; mapping unit tests; manifest schema versioned |
| 2.9 | Remove all substring heuristics | M | Unused-param discards and `std` imports decided from HIR | `grep -R "indexOf" src/rt/codegen*` clean; goldens unchanged except intended |
| 2.10 | `zsx.addViews` v2 | M | Globs (`.dir = "src/views"`), per-view options, strategy selection, dependency tracking for incremental rebuild, `.imports` ergonomics, `addViewsLocal` removed (use same path) | Consumer example uses glob; adding a file requires no build.zig edit |
| 2.11 | `zsx migrate` codemod 0.2→0.3 | M | Rewrites legacy syntax (`on_click=` → `on:click=`, `<label>` → `<text>`, `{endif}`→`{/if}`) using CST, lossless | Corpus of old views round-trips and compiles |
| 2.12 | Compile-time budget guardrails | M | Detect pathological comptime growth (`@setEvalBranchQuota` use, huge anon-struct types); report in `zsx check --explain-cost` | Playground compile time recorded vs baseline; alarms in CI |

**Gate M2:** all Phase-0 reproducers closed; goldens stable; `zsx-gen` throughput ≥ baseline ×3 (target; calibrate); generated code has no `anytype` for props.

---

## M3 — DX core: CLI, diagnostics remap, LSP, editors (months 6–10)

**Goal:** make errors, editing and discovery excellent. This is the milestone that makes people *talk* about ZSX.

| WP | Title | Size | Scope | Acceptance |
|---|---|---|---|---|
| 3.1 | **`zsx` CLI** | L | `gen`, `fmt`, `check`, `lsp`, `doc`, `migrate`, `init`, `add`, `doctor`, `build` (wrapper), `watch`; machine-readable `--format=json` | Man page + `--help` snapshot tests |
| 3.2 | **Diagnostics remapping wrapper** | L | `zsx build` runs `zig build`, parses compiler diagnostics, rewrites paths/lines via `.zsxmap`, re-renders with code frames. For plain `zig build`, I1 makes lines already correct and the cache path is explained in a one-line note | ≥ 95 % of a 100-case "broken view" suite yields correct `.zsx:line:col` |
| 3.3 | **LSP v1 (shadow-document architecture)** | XL | Server maintains virtual Zig docs + `.zsxmap`, **proxies ZLS** for Zig semantics (hover, definition, completion inside `{expr}`), adds markup-aware features: tag/prop/slot/event completion (from manifest), class completion + hover showing resolved style, diagnostics (parser + lint + remapped Zig), code actions (wrap in `{if}`, extract component, add missing prop), rename (components/props), semantic tokens, folding, format | LSP conformance tests (scripted client) ≥ 150; latency p95 < 50 ms on a 2k-line file for non-ZLS features |
| 3.4 | Incremental reparse | L | Re-lex/re-parse damaged region only | Benchmark: edit in 5k-line file < 2 ms |
| 3.5 | **Tree-sitter grammar** | L | Injections: Zig outer, markup inner; highlights, indents, folds, locals, `injections.scm` so Zig highlights inside `{expr}` | Corpus parity test: tree-sitter parse succeeds on 100 % corpus; highlight snapshot tests |
| 3.6 | Editor packages | L | VS Code (marketplace), Zed extension, Neovim plugin (+ nvim-treesitter PR), Helix queries | Install-and-smoke CI per editor where automatable |
| 3.7 | `zsx init` / `zsx add` | M | Project templates (`app`, `lib`, `web`, `tui`); `zsx add button dialog` copies component source (shadcn model) into the project w/ `zsx.zon` registry | Fresh project builds in < 60 s on CI |
| 3.8 | `zsx doctor` | S | Checks Zig version, SDL3, ZLS, editor setup | Snapshot tests |
| 3.9 | Docs: "Errors that teach" | M | Every error code gets a docs page with cause/fix/example; `zsx explain ZSX0123` | Docs coverage check: every emitted code has a page |

**Gate M3 (0.5 release, "DX alpha"):** a new user can install, `zsx init`, edit in their editor with live diagnostics and completion, and get `.zsx`-accurate errors. Record a 3-minute demo for the site.

---

## M4 — Backend contract, layout engine, headless & test harness (months 8–13)

**Goal:** formalize the backend interface; make testing UI a joy; produce a deterministic software renderer that doubles as the reference backend.

| WP | Title | Size | Scope | Acceptance |
|---|---|---|---|---|
| 4.1 | **[RFC-0002] Backend contract v1** | L | Primitive set v1 (layout: stack/row/grid/scroll/spacer/portal; content: text/rich-text/image/icon/canvas-hook; input: text-entry/textarea/checkbox/radio/slider/select/toggle; feedback: progress/skeleton/spinner; overlay; focus/keyboard/IME/clipboard hooks; a11y node emission; animation hooks) with exact signatures, ownership rules, id semantics, capability flags | Accepted RFC; `verifyBackend` implemented |
| 4.2 | `zsx-rt` verify + capability lints | M | Readable comptime errors; generator emits `requires_caps` in manifest; build error if a view uses an unsupported capability for the chosen backend (with `fallback` attribute escape) | Negative-compile tests (≥ 30) |
| 4.3 | **`zsx-layout`** | XL | Pure-Zig flexbox (+ grid subset) engine: no allocation per frame (arena or fixed pools), text measurement callback, min/max/aspect, gap, wrap, align, absolute; **differential tests against a real browser** (Playwright in CI generating reference boxes for ≥ 500 random layouts) | ≥ 99 % of random layouts match within 0.5 px; benchmark vs naive baseline |
| 4.4 | **`zsx-raster` software renderer** | XL | Deterministic CPU rasterizer (AA rect/rrect/border/shadow/clip, text via pluggable glyph source, images) → RGBA buffer; same output on every OS | Golden PNGs byte-identical across Linux/macOS/Windows |
| 4.5 | **Headless backend** | L | Implements contract on `zsx-layout` + `zsx-raster`; produces a11y tree + draw list + optional PNG | Passes conformance suite v1 |
| 4.6 | **Conformance suite** | XL | ≥ 300 behaviour tests expressed once (view + script + expected a11y-tree/draw-list), run against every backend in its testable mode | Suite runs in < 60 s on headless; per-backend report JSON |
| 4.7 | **`zsx-test` harness** | L | Testing-Library-style: `getByRole(.button, .{.name="Save"})`, `click`, `type`, `press`, `expectText`, `snapshot(.a11y)`, `snapshot(.pixels, .{ .tolerance })`, fake clock for animations | Docs cookbook; used by all example tests |
| 4.8 | A11y tree in the IR | L | Roles, names, states; build-time lint: button/input without accessible name, focus-order traps, contrast check for resolvable color pairs | Lints active; false-positive rate tracked |
| 4.9 | Port existing adapters (dvui, nanoui, html) to contract v1 | L | Remove `@hasField` reflection in adapters; real option structs; fix nanoui global state (F13) | Existing playground output unchanged (goldens/pixels) |
| 4.10 | Visual-regression pipeline | M | Pixel diff with perceptual threshold; HTML diff report artifact; baseline update command with review gate | CI attaches report on failure |

**Gate M4:** headless is the reference backend; every other backend can be measured against it.

---

## M5 — Style & design system v1 (months 10–14)

**Goal:** one style engine, full utility coverage, tokens/themes, dark mode, variants — all resolved at build time and interned.

| WP | Title | Size | Scope | Acceptance |
|---|---|---|---|---|
| 5.1 | **[RFC-0003] Style language** | M | Supported utilities, variant syntax, arbitrary values, token references (`bg-primary`), dynamic class composition (`zsx.cls`), what is *intentionally* unsupported (no cascade) | Accepted RFC |
| 5.2 | Table generator | M | `tools/gen-style-tables.zig` → palette (22 hues × 11 shades), spacing, radii, shadows, font sizes/weights, breakpoints | Tables checked in; regeneration is deterministic |
| 5.3 | **Unified engine (kill F9)** | L | Single implementation used by generator *and* comptime component code (shared file compiled for both) | `lib/style.zig` and `rt/style.zig` merged; golden parity |
| 5.4 | Utilities: spacing/margin/size/flex/grid/border/shadow/opacity/overflow/position/z/typography | XL→3×L | Full coverage list in RFC; each utility has unit tests + conformance tests per backend | Coverage matrix doc auto-generated; unsupported-on-backend utilities flagged by caps lint |
| 5.5 | Variants & states | L | `hover:`, `focus:`, `active:`, `disabled:`, `dark:`, breakpoints, `first:/last:/odd:/even:`; lowered to per-backend state handling (immediate: query widget state; web: CSS or class toggles) | Variant conformance tests |
| 5.6 | Theme tokens (`theme.zon`) | L | Tokens (colors, radius, spacing, font stacks), light/dark, multiple named themes, runtime theme switch without regenerating views (token indirection table) | Switch-theme test; no allocation |
| 5.7 | Dynamic classes with comptime candidate sets | M | `class={zsx.cls(.{ "p-2", .when(ctx.busy, "opacity-50") })}`; all candidate strings validated and interned | Typo in any branch = build error |
| 5.8 | Style interning + dead-style elimination | M | `.rodata` table, index references, unused entries removed | Binary-size benchmark shows reduction vs inline structs |
| 5.9 | Atomic CSS emission for HTML/Web | M | Deterministic CSS from interned styles; content-hashed filename | Lighthouse-style size check in bench |
| 5.10 | Unknown-class DX | S | Did-you-mean + "this class exists with variant X" hints | Snapshot tests |

---

## M6 — Immediate-mode backends to GA (months 12–18)

**Goal:** four excellent immediate backends and a published tier policy.

**Tier policy.** *Tier 1:* full conformance, CI on Linux/macOS/Windows, perf-gated, release-blocking. *Tier 2:* conformance ≥ 90 %, CI build + stub tests, best-effort perf. *Tier 3:* experimental, no guarantees. Tier changes require an ADR.

| WP | Title | Size | Scope | Acceptance |
|---|---|---|---|---|
| 6.1 | **dvui backend → Tier 1** | XL | Full primitive set; scroll, overlays, focus, IME, a11y via AccessKit where dvui supports it; weight/typography fixes (known limitation today); real todo example windowed (listed "not yet" in README) | Conformance ≥ 98 %; Linux/macOS/Windows CI with Xvfb/offscreen SDL |
| 6.2 | **TUI backend (Tier 1)** | XL | ANSI/terminfo renderer using `zsx-layout`; mouse + keyboard; unicode width; truecolor/256/16 fallback; resize; a11y = semantic text mode | Runs `zsx-ui` showcase in terminal; conformance ≥ 95 %; snapshot tests of cell grids |
| 6.3 | raylib backend (Tier 2) | L | Resolve the "no usable pub fn surface" blocker by binding via C API or maintained wrapper (ADR); uses `zsx-layout` | Conformance ≥ 90 %; playground screenshot |
| 6.4 | cimgui backend (Tier 2) | L | Immediate-mode mapping (structurally close to dvui) | Conformance ≥ 90 % |
| 6.5 | nanoui backend → Tier 2 | M | Contract v1, remove global state; macOS CI | Conformance ≥ 90 % |
| 6.6 | Backend authoring kit | M | `zsx init --backend`, template + checklist + conformance runner; docs "write a backend in a day" | A community-style backend (e.g., SDL_Renderer direct) built from the kit in < 1 kLOC as dogfood |
| 6.7 | Zero-allocation proof | M | `zsx-test` `expectNoAllocs(frame)` using a counting allocator wired through backend contexts | All Tier-1 immediate backends pass for the showcase and todo apps |
| 6.8 | Support matrix generator | S | Docs page from caps + conformance JSON | Auto-updated in CI |
| 6.9 | Cross-backend example parity | M | `playground` renders pixel-comparable (within tolerance) across headless/dvui/raylib | Report in CI |

---

## M7 — Web: static, SSR, retained + fine-grained reactivity (months 14–20)

**Goal:** a first-class web story with tiny output — the ecosystem's strongest differentiator.

| WP | Title | Size | Scope | Acceptance |
|---|---|---|---|---|
| 7.1 | **[RFC-0004] `zsx.state` signals** | L | `Signal(T)`, `Memo`, `Effect`, `Store`; **identical API on immediate backends** (plain variable, zero overhead) and retained backends (tracked); no hidden allocation (arena per scope/component); explicit ownership; batching | Accepted RFC with semantics tests spec |
| 7.2 | Dependency analysis in HIR | L | Dynamic holes get exact dependency sets; classify static vs dynamic; hoist statics | HIR dump goldens; "static ratio" metric in `check --explain-cost` |
| 7.3 | `static_html` lowering | L | SSR string output, escaping, attributes, a11y, streaming writer; deterministic | HTML conformance + XSS test suite |
| 7.4 | **`retained` lowering** | XL | Template clone + binding table; each dynamic hole → one targeted op (`setText`, `setAttr`, `setClass`, list reconcile for keyed `{for}`); no VDOM | Benchmark vs. hand-written DOM ops within 10 % |
| 7.5 | **Wasm DOM backend** | XL | Zig → wasm32; minimal JS glue (generated, ≤ 3 KB gzip target), event delegation, batched DOM ops via shared memory command buffer | Hello world ≤ 20 KB gzip target; krausest-style benchmark runnable in browser |
| 7.6 | Hydration / islands | L | SSR output + `data-zsx-id` anchors; hydrate only interactive islands; progressive enhancement | Hydration mismatch detector; tests |
| 7.7 | Dev server (`zsx web dev`) | L | Static serve, rebuild on change, error overlay with remapped diagnostics, HMR (module swap + state preservation where possible) | Edit→browser update < 500 ms target |
| 7.8 | Web a11y + forms | M | ARIA from IR, native form semantics, labels, live regions | axe-core CI run clean on showcase |
| 7.9 | `zsx-router` (optional) | L | Typed routes, history, nested layouts; works SSR + client | Example SPA + SSG site |
| 7.10 | Bundle/size budgets | M | `zsx web build --report`; CI budget gates | Budgets enforced |

**Gate M7 (0.9 "Platform beta"):** the same `.zsx` builds to dvui, TUI, SSR HTML and Wasm retained, with conformance reports for each.

---

## M8 — `zsx-ui` component platform (months 18–26)

**Goal:** the shadcn-for-systems-languages: accessible, themeable, installable, tested.

Architecture: *headless behaviour* (state machine + keyboard + a11y contract) → *skin* (style) → *composition* (compound components with slots).

| WP | Title | Size | Components / scope |
|---|---|---|---|
| 8.1 | Headless core | XL | Focus manager, roving tabindex, typeahead, dismissable layers, positioning engine (flip/shift/arrow), portals, scroll lock, id registry |
| 8.2 | Primitives | L | Stack, Grid, Scroll, Spacer, Separator, Image, Icon, Text, Heading, Link, Kbd, Code, AspectRatio |
| 8.3 | Forms | XL | Button, IconButton, Input, Textarea, NumberInput, PasswordInput, Checkbox, RadioGroup, Switch, Slider, RangeSlider, Select, Combobox, DatePicker, TimePicker, ColorPicker, FileDrop, Form + validation, Field/Label/Description/Error |
| 8.4 | Overlays | XL | Dialog, AlertDialog, Drawer/Sheet, Popover, Tooltip, HoverCard, DropdownMenu, ContextMenu, Menubar, Toast, CommandPalette |
| 8.5 | Navigation | L | Tabs, Breadcrumb, Pagination, Sidebar, NavigationMenu, Stepper, Accordion, Collapsible |
| 8.6 | Data | XL | Table (sort/select/resize/sticky), **VirtualList/VirtualGrid** (fixed + variable size), Tree, DataGrid (edit-in-place), Calendar, Chart primitives (line/bar/area/pie/scatter via canvas hook) |
| 8.7 | Feedback | M | Alert, Badge, Progress, Spinner, Skeleton, EmptyState, Banner |
| 8.8 | Text | XL | Rich text rendering, selectable text, text editing widget with IME, bidi/complex-script hooks (pluggable shaper), markdown renderer component |
| 8.9 | Animation | L | Spring/tween primitives, `transition-*` classes, presence (enter/exit), reduced-motion support; deterministic under fake clock |
| 8.10 | Icons | M | Tree-shaken icon set (generated Zig vector paths), `zsx add icon <name>` |
| 8.11 | i18n | L | `zsx-i18n`: ICU-subset messages at build time, `<Trans>` component, plural/number/date, RTL layout flip |
| 8.12 | Theme gallery | M | ≥ 6 shipped themes, light/dark, high-contrast, density modes |
| 8.13 | Per-component quality bar | ongoing | Each component ships: a11y spec + automated checks; keyboard tests; headless tests; visual baselines on ≥ 2 backends; docs with live playground; size/perf entry in `zsx-bench` |

Quality bar is enforced by a `zig build component-audit` step that fails if any item is missing.

---

## M9 — Developer loop: hot reload, devtools, playground (months 20–25)

| WP | Title | Size | Scope | Acceptance |
|---|---|---|---|---|
| 9.1 | **[SPIKE] Hot reload architecture** | L | Dev-only build: UI layer as shared library behind a stable C-ABI `frame(state_ptr, backend_vtable)`; a `DevBackend` implements the contract via vtable (dynamic dispatch *only in dev*); host app owns state. Fallbacks: (a) fast incremental rebuild + restart with state snapshot via `zsx.Persist`; (b) Wasm module swap on web | ADR with measured latency on reference app; go/no-go |
| 9.2 | `zsx dev` | XL | Watches `.zsx`, regenerates only changed views, rebuilds shared lib, swaps; error overlay in-app with remapped diagnostics; preserves widget focus/scroll via stable IDs | Warm save→visible ≤ 300 ms (V4) on reference app; target to be recalibrated from the spike |
| 9.3 | **Inspector / devtools** | XL | Attach over a local socket: element tree (HIR-aware, shows `.zsx` source spans), computed style with originating classes, props/state, event log, a11y tree view, frame timeline, layout-bounds overlay, "jump to source" in editor | Works on dvui, TUI (side panel), web |
| 9.4 | Profiler overlay | L | Per-frame CPU/layout/draw time, widget counts, allocation counters (debug), flamegraph export | Overhead < 1 % when disabled (compiled out) |
| 9.5 | Time-travel / state recorder | L | Record inputs + state snapshots, deterministic replay (used by tests too) | Replay reproduces frames bit-exactly on headless |
| 9.6 | **In-browser playground** | XL | Compile `zsx-gen` to Wasm; live parse → HIR → HTML backend preview; share by URL; shows generated Zig side-by-side; runs entirely client-side | Cold load < 2 s; 1k-line edit → preview < 100 ms |
| 9.7 | Storybook-like component explorer | L | `zsx storybook`: lists components from manifests, knobs auto-generated from `Props`, a11y panel, visual regression hooks | Used for `zsx-ui` docs |

---

## M10 — Performance excellence program (months 24–29)

**Goal:** be demonstrably the fastest *and* most ergonomic option; defend it with CI.

### 10.A Benchmark suites (`zsx-bench`)

| Suite | What | Metrics |
|---|---|---|
| `compile/` | Generator throughput (10 → 100 000 lines), memory, parallel scaling; Zig compile time delta vs hand-written for 10/100/1000-component apps | instr counts, wall, RSS |
| `frame/` | Per backend: 100 / 1k / 10k / 100k widgets; static vs dynamic ratios; deep nesting; keyed list churn | ns/frame (instr counts), allocs/frame, cache misses (where measurable) |
| `size/` | Hello, todo, dashboard, showcase: native stripped size, wasm raw/gzip/brotli | bytes |
| `apps/` | **Todo, 10k-row table, text editor, chat feed, dashboard, drawing canvas** — each implemented in ZSX *and* hand-written against the same backend (and, where meaningful, against reference implementations in other UI stacks) | frame time, memory, LOC (ergonomics metric) |
| `web/` | krausest-style row operations (create/update/swap/remove/clear 1k–10k rows), startup, memory | ms, KB |
| `latency/` | input→pixel latency in headless virtual clock; hot-reload latency; LSP request latency | ms |

### 10.B Work packages

| WP | Title | Size | Scope |
|---|---|---|---|
| 10.1 | Bench dashboard + regression gate | L | Static site from JSON history; per-commit trend; PR comment bot; threshold config; noise handling by instruction counts & repeated runs |
| 10.2 | Generated-code optimization passes | XL | Static hoisting (constant `Style`s and strings), coalescing adjacent static siblings, inlining small components, eliminating dead branches on comptime-known conditions, ID folding, avoiding redundant `defer` frames |
| 10.3 | Layout caching & dirty regions | XL | Per-node layout cache keyed by constraints+content hash; skip re-layout when subtree inputs unchanged; partial redraw for backends that support it |
| 10.4 | Virtualization everywhere | L | `VirtualList` integrated with layout cache; O(visible) per frame |
| 10.5 | Text performance | L | Shaping cache, glyph atlas sharing, measurement memoization |
| 10.6 | Compile-time performance | L | Reduce comptime work in generated code (prefer concrete structs over `anytype` chains), shard large views into multiple modules automatically, parallel gen |
| 10.7 | Binary size diet | M | Style interning, `-Doptimize=ReleaseSmall` profile, strip unused backend paths via caps |
| 10.8 | Comparative report | M | Reproducible scripts + published methodology; **no marketing claim without a script in repo** |
| 10.9 | Performance budget doc | S | Per-component and per-primitive budgets; `component-audit` checks them |

**Gate M10:** V5/V6/V7 targets met or ADR-justified revision.

---

## M11 — Stabilization, security, compatibility (months 28–32)

| WP | Title | Size | Scope |
|---|---|---|---|
| 11.1 | API surface inventory + freeze RFC | L | Machine-extracted public API (compiler options, CLI flags, grammar, manifest schema, backend contract, `zsx-rt`, `zsx-ui`) → `api/v1.json`; `zsx api-diff` blocks accidental breaks |
| 11.2 | Deprecation sweep | M | Remove everything flagged since 0.3; codemods for every removal |
| 11.3 | Fuzz hardening | L | 24/7 fuzzing of lexer/parser/formatter/emitter/LSP protocol; crash triage SLA; ≥ 10⁹ execs per release |
| 11.4 | Differential testing of codegen | L | Random HIR generator → emit → compile → run in headless; compare against a reference interpreter of HIR (test-only) | 
| 11.5 | Security review | L | Threat model (malicious `.zsx` in dependency, build-time code execution, SSR XSS, wasm sandbox boundaries, LSP path handling); documented; fixes |
| 11.6 | Supply chain | M | Reproducible builds verified in CI (two builders, byte-identical), signed release artifacts, SBOM, pinned dependency hashes, vendoring policy |
| 11.7 | Zig-version compatibility matrix | M | CI over `current` and `current-1`; compat shim coverage; documented upgrade playbook |
| 11.8 | Platform matrix | M | Windows/macOS/Linux × x86_64/aarch64; wasm32; document unsupported combos |
| 11.9 | Accessibility audit | L | External or structured audit against WCAG 2.2 AA for `zsx-ui` on web and a documented best-effort for native |
| 11.10 | Long-run stability tests | M | Soak tests (24 h headless churn), memory-growth detection, leak checks |

---

## M12 — Documentation, showcase, community (months 28–34)

| WP | Title | Size | Scope |
|---|---|---|---|
| 12.1 | The ZSX Book | XL | Tutorial (build a real app, one chapter per concept), concepts, backends, styling, testing, performance, internals ("how the compiler works"), cookbook (≥ 50 recipes); every snippet compiled by `docs-test` |
| 12.2 | Generated API reference | L | From manifests + doc comments; versioned |
| 12.3 | Reference apps | XL | (1) Todo/notes (small), (2) analytics dashboard (web + native), (3) code/text editor, (4) chat client, (5) **> 20 kLOC production-style app** (dogfood; used for perf + LSP scale testing). Each with tests and bench entries |
| 12.4 | Website | L | Landing, playground, docs, benchmark dashboard, showcase gallery |
| 12.5 | Migration guides | M | From hand-written dvui/imgui code; from other UI paradigms (conceptual guides) |
| 12.6 | Governance | M | `GOVERNANCE.md`, RFC process, maintainers ladder, Code of Conduct, security policy, release policy, LTS policy (v1.x supported ≥ 24 months), trademark/branding note |
| 12.7 | Contributor experience | M | "Good first issue" curation, dev container, `zsx doctor --contributor`, architecture tour doc |
| 12.8 | Early-adopter program | M | Recruit ≥ 3 external projects for RC feedback; weekly triage |
| 12.9 | Talks/articles kit | S | Technical deep-dives: line-preserving codegen, shadow-document LSP, zero-alloc immediate UI, Wasm retained without VDOM |

---

## M13 — Release candidates → v1.0 (months 33–36)

| WP | Title | Scope | Acceptance |
|---|---|---|---|
| 13.1 | RC1 | Feature freeze; all V-criteria scored | Public scorecard (§1.2) with evidence links |
| 13.2 | RC bug-bash | Triage; only fixes, doc and perf-regression repairs | Zero P0/P1 open for 14 consecutive days |
| 13.3 | RC2…n | Iterate on early-adopter feedback | Exit when two consecutive RCs ship with no API changes |
| 13.4 | v1.0.0 | Tag, signed artifacts, announcement, docs pinned to 1.0, migration guides live | All V1–V12 met (or explicitly waived by ADR with rationale published) |
| 13.5 | 1.x policy | Quarterly minor releases, security patch SLA (≤ 7 days critical), LTS branch | Policy published |

---

## 7. Continuous tracks (run through all phases)

| Track | Owner agent type | Standing duties |
|---|---|---|
| **T-Quality** | test agent | Corpus growth, fuzz triage, flake budget (< 0.5 %), coverage ratchet (never decreases), mutation testing on parser/emitter quarterly |
| **T-Perf** | perf agent | Bench dashboard hygiene, weekly regression review, perf ADRs |
| **T-Docs** | docs agent | Doc-tests green, error-code pages, changelog quality, glossary |
| **T-Compat** | compat agent | Zig nightly watch, upstream dvui/SDL/raylib/cimgui updates, shim maintenance, dependency bumps in small PRs |
| **T-Community** | triage agent + humans | Issue labeling, RFC facilitation, response-time SLO (< 72 h first response) |

---

## 8. Breaking-change ledger (0.2 → 1.0)

Each item ships with a codemod (`zsx migrate`) except where noted.

1. Legacy control-flow aliases removed (`{endif}`, `{endfor}`, `{endswitch}`).
2. `on_click={ctx.m()}` → `on:click={…}` with arguments/closures; `on_*` removed.
3. `<label>` → `<text>` (frees `label` for form semantics).
4. Props are typed structs; unknown/misspelled props are errors (no codemod; compiler suggests fixes).
5. `view(ui, c, ctx)` convention → typed component signature and `zsx.View`; `anytype` ctx replaced by explicit context types.
6. Widget-ID scheme replaced (persisted widget state keyed by old IDs is invalidated once; documented).
7. `zsx.addViews`/`addViewsLocal` → `zsx.addViews` v2 (globbing, strategies).
8. Monolithic repo → package split; backends/components in separate packages; `shadcn` module → `zsx-ui` (`zsx add`).
9. Python scripts removed; `zsx fmt/check` replace them.
10. Style engine unified: `m-*` now supported; any class previously relied on as "ignored" becomes an error if unknown.
11. Minimum Zig version policy (current, current-1).

---

## 9. ADR/RFC backlog (agents write these; humans ratify)

| # | Title | Needed by |
|---|---|---|
| ADR-1 | Zig version support policy | M0 |
| ADR-2 | Use `std.zig.Ast` placeholder strategy vs tokenizer scanner | M1 (S1) |
| ADR-3 | Line-preserving emission vs sourcemap-only | M1 (S2) |
| RFC-0001 | v1 grammar | M1 |
| RFC-0002 | Backend contract v1 + capabilities | M4 |
| RFC-0003 | Style language | M5 |
| RFC-0004 | Signals/state model | M7 |
| ADR-4 | Hot-reload architecture | M9 (spike) |
| ADR-5 | Text shaping/IME strategy per backend | M6/M8 |
| ADR-6 | Allocation model (arena per frame vs scope) | M4 |
| ADR-7 | Tier policy and promotion criteria | M6 |
| ADR-8 | A11y strategy per platform (AccessKit/ARIA/TUI) | M4 |
| RFC-0005 | `zsx-ui` component API conventions | M8 |
| RFC-0006 | Public API freeze set | M11 |

---

## 10. Risk register

| Risk | Likelihood | Impact | Mitigation |
|---|---|---|---|
| Zig stdlib/compiler churn breaks the toolchain | High | High | ADR-1 policy, `compat.zig`, nightly canary CI (T-Compat), tiny dependency surface |
| `std.zig.Ast` placeholder approach fails on edge cases | Medium | Medium | S1 spike with tokenizer fallback decided up-front |
| Line-preserving emission too constrained | Medium | Medium | S2 spike; sourcemap fallback is already planned |
| Upstream toolkits (dvui, nanoui, raylib wrappers) change or stall | High | Medium | Pin + lazy deps; thin adapters; backend kit lowers cost of replacing one |
| Scope explosion (60 components, 6 backends, LSP, web, hot reload) | High | High | Strict milestone gates; Tier policy; features cut by ADR rather than quality; component-audit gate |
| Hot reload infeasible in Zig with acceptable latency | Medium | Medium | Spike first; fallbacks (restart + state snapshot, wasm swap) satisfy V4 on web at least; V4 may be revised by ADR |
| Reactivity model complicates the clean immediate story | Medium | High | RFC-0004 requires *identical semantics* on immediate (plain var) and retained; conformance tests enforce it |
| Comptime blow-up / compile times | Medium | High | Budgets in CI (`explain-cost`), prefer concrete structs, shard views |
| Agent quality drift (silent regressions, over-engineering) | Medium | High | Goldens, fuzz, bench gates, coverage ratchet, small PRs, mandatory ADR for decisions, periodic independent review agent |
| Bus factor / maintainership | Medium | High | Governance (M12.6), docs of internals, contributor ladder |
| Accessibility on native toolkits limited by upstream | High | Medium | Document honestly per backend; Tier-1 web + TUI deliver full a11y; AccessKit where available |

---

## 11. First 90 days — concrete agent backlog (ordered)

**Weeks 1–2 (M0 core):** 0.1, 0.2, 0.3, 0.5, 0.6 → green CI with goldens; consumer fetches only `zsx`.
**Weeks 3–4:** 0.4 reproducers, 0.7 bench skeleton + baseline, 0.8 CI matrix, 0.10 ADR-1.
**Weeks 5–6:** M1 spikes S1 and S2; write ADR-2, ADR-3; draft RFC-0001.
**Weeks 7–10:** 1.2 lexer, 1.3 parser (in 3 PRs), corpus ≥ 150 files, fuzz infra 1.9.
**Weeks 11–13:** 1.4 Zig-side scanner, 1.5 AST, 1.6 formatter; retire Python fmt.
**Exit of day 90:** native `zsx fmt`, new parser with recovery and multi-error output, F5/F6 fixed, F1/F2/F3 reproducers ready for M2.

---

## 12. Illustrative target DX (syntax is *not final*; RFC-0001 decides)

```zsx
// src/views/todo_list.zsx
const ui = @import("zsx-ui");
const Todo = @import("model.zig").Todo;

pub const Props = struct {
    items: []const Todo,
    on_toggle: zsx.Callback(u32),
    on_remove: zsx.Callback(u32),
};

pub fn TodoList(ctx: *App, props: Props) zsx.View {
    return zsx!{
        <ui.Stack gap={2} class="p-4 md:p-6 dark:bg-slate-900">
            <ui.Input bind:value={ctx.query} placeholder="Search…" aria-label="Search todos" />

            {for props.items as todo, i key={todo.id}}
                <ui.Row class="items-center gap-2 hover:bg-slate-100">
                    <ui.Checkbox checked={todo.done} on:change={props.on_toggle.call(todo.id)}>
                        {todo.title}
                    </ui.Checkbox>
                    <ui.Button variant="ghost" on:click={props.on_remove.call(todo.id)}>Delete</ui.Button>
                </ui.Row>
            {:empty}
                <ui.EmptyState title="Nothing to do" />
            {/for}
        </ui.Stack>
    };
}
```

What the toolchain gives you for this file: a mistyped `variant="gost"` is an error at that exact `.zsx` column with a did-you-mean; hovering `dark:bg-slate-900` shows the resolved color; `todo` inside the slot just works (capture analysis); the same file builds to dvui, TUI, SSR HTML and Wasm; `zsx dev` shows edits in < 300 ms (target); `zsx-test` can `getByRole(.checkbox, .{ .name = "Buy milk" })` and click it headlessly.

---

## 13. Success metrics dashboard (reviewed quarterly)

- **Product:** V1–V12 scorecard (§1.2), updated automatically where measurable.
- **Health:** CI duration, flake rate, coverage, fuzz execs, open P0/P1, mean PR size, time-to-first-review.
- **Adoption:** package fetches, template inits (opt-in telemetry **off by default**, or use fetch counts only), external projects listed, contributors, Discord/forum activity.
- **Perf:** trend lines from `zsx-bench`; any 3-week upward drift triggers a perf ADR.

---

*End of plan. First action for the implementing agent: create `AGENTS.md` and `docs/STATE.md` (WP-0.1), then proceed down §11.*
