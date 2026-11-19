# ZSX — current state

Updated at the end of every PR that completes a work package. Sanitized for
agents: assume your context does not include the previous session.

## Snapshot

| Field | Value |
|---|---|
| Current milestone | **M2 slice — F1/F2/F3/F4/F7 closed; events v1; addViews v2; cost + migrate** |
| Last known green commit | see `git log -1`; local gate is the source of truth |
| Release train | 0.4.0 = M2 codegen slice (IDs, one lowering, captures, events v1, prop checks) |
| Zig versions | 0.17.1 (`current`); policy in `docs/adr/0002-zig-version-policy.md` |
| Open milestone blockers | None |

## M0 work packages

| WP | Status | Notes |
|---|---|---|
| 0.1 Memory + ADR/RFC templates | done | `AGENTS.md`, this file, `docs/adr/0000-template.md`, `docs/rfc/0000-template.md`; `zig build check-docs` link-checks them |
| 0.2 Version/metadata hygiene | done | `VERSION` is the source of truth; `zig build check-meta` |
| 0.3 Lazy dependencies | done | `.lazy = true`; real backends are opt-in via `-Dreal=true`, so tests/consumer fetch neither |
| 0.4 Reproducer tests | done | `src/tests/reproducers.zig` pins fixed behaviour for F1, F2, F3, F4, F5 |
| 0.5 Golden harness | done | `zig build golden`; committed baselines in `spec/golden/` |
| 0.6 Split root tests | done | tests live under `src/tests/`; `src/root.zig` is a thin aggregator |
| 0.7 Benchmark skeleton | done | `zig build bench` writes `bench/baseline.json`; `bench-smoke` is the fast gate |
| 0.8 CI matrix | done | Ubuntu + macOS + Windows stub jobs; consumer lazy-dependency assertion; Linux real-DVUI job with SDL3; flake policy in `AGENTS.md` |
| 0.9 `zsx` CLI stub | superseded | wrappers replaced by native `check`/`fmt` (M1/M2); Python scripts unused |
| 0.10 Zig-version policy | done | ADR 0002 + `src/compat.zig` |

## M1/M2 tooling front-end (this handoff)

| WP | Status | Notes |
|---|---|---|
| 1.4 Zig-side scanner (slice) | first slice | `src/rt/lossless.zig` now segments Zig **multiline strings** (`\\` line runs) and supports **nested block comments**, so a `zsx!{` inside either no longer becomes a false block. `preprocess`/`findBlocks` inherit the fix (one scanner, F11). F6 reproducer green; synthetic + committed-view round-trips stay byte-exact. Deferred: S1 outcome of surfacing `std.zig.Ast` syntax errors with `.zsx` positions and the 200-file external Zig corpus |
| 1.5 CST → AST lowering | first slice | `cst.lowerBlock` flattens CST control/branch/close markers back into the existing `ast.Element` stream; `preprocess` now uses CST + lowering instead of the fail-fast parser, so **the compiler path has one recovery-capable parser**. Goldens are byte-identical; `spec/ast/*.txt` dumps (`src/rt/astdump.zig`) pin the flat AST stream (elements/fragments, attrs, text, control markers) and cover top-level whitespace + root-shape errors; the formatter suite now checks `parse(fmt(x)) ≅ parse(x)` (normalized dumps) over all 102 valid corpus files. Perf: `gen_1k` ≈ 60 MB/s (was ≈ 75) for the extra tree/lowering; accepted for the single-parser architecture, recovery planned in the CST-as-AST/2.8 work. Deferred: AST source spans (still CST-only), retiring `parser.zig`, comment/snippet nodes |
| 1.3 CST parser | first slice | `src/rt/cst.zig`: token-driven tree (`block`/`element`/`fragment`/text/expression/control/branch/error nodes) with spans and attributes, nearest-opener recovery, multiple diagnostics, junk/error nodes; `treeIsOrdered` checks child spans. Valid corpus asserts zero CST diagnostics. Deferred: wire checker to the CST, root-shape/class/prop rules (still checker-only), 10⁸ fuzz |
| 1.2 Lossless lexer | done (tokens) | `scan.Token` spans tile the block exactly (`scan.coversSource`), trivia is explicit (`Token.isTrivia`), UTF-8 bytes pass through unchanged, and a deterministic 5 000-case fuzz test plus the 150-file grammar corpus assert the invariant. Bug fixed: junk inside an opening tag now owns the whole tag span instead of appearing before the open-tag token (overlap). `diag.LineIndex` already does binary search. Deferred: a dedicated standalone lexer type and its token classes (`{let}`, comments) once the CST lands |
| 1.1 Grammar RFC | draft | `docs/rfc/0001-markup-grammar.md` + normative `docs/spec/grammar.ebnf`: block boundary, tags/attributes, events, control flow, slots, semantics S1–S8, diagnostic table and error recovery. S1 is enforced by `zsx check` (`ZSX0014`–`ZSX0016`); codegen already required one root. 150-file conformance corpus (`spec/grammar/`, 102 valid + 48 invalid) with `src/tests/grammar.zig` runner; valid fixtures are canonical fmt output, invalid fixtures are skipped by default CLI scans; fixed a fmt crash on multi-line opening tags. Deferred: RFC review/acceptance, committed generated-body goldens, fuzz, CST parser, unresolved U1–U7 |
| 1.7 Checker in Zig (slice) | done | `src/rt/checker.zig`: tolerant scanner (`scan.zig`), rule set with `ZSX0xxx` codes, `diag.zig` diagnostic type (spans, severities, help); unknown classes read `style.isKnownClass` — no duplicated table. Lint framework: warnings `ZSX0020` unused loop binding, `ZSX0021` empty `{for}` body, `ZSX0022` text directly in `<column>`, `--no-lint`, and `// zsx-ignore <code>` on the line above `zsx!{`. Lints ride the existing token pass (no second parse), `check_1k` ≈ 0.29 ms/1k lines (target < 20 ms). `zsx check` CLI native; exit codes 0/1/2 parity |
| 1.6 Formatter in Zig (slice) | done | `src/rt/fmt.zig`: valid markup reindented from the CST (`cstDepthAt` uses node containment; closers match their own tag), malformed markup falls back to the scanner; idempotent, committed corpus byte-for-byte (`src/tests/fmt.zig`), `parse(fmt(x)) ≅ parse(x)` over the valid corpus; `zsx fmt` CLI native (`--check`/`--write`) |
| 1.8 Diagnostics quality (slice) | done | `src/rt/render.zig`: `render.Renderer` turns a diagnostic + source into the annotated snippet (header, help line, gutter, caret span). Exported as `zsx.render`; `zsx check` prints frames; demo in `examples/render/`; `spec/diagnostics/snapshots.txt` renders every code (`ZSX0001`–`ZSX0016`, `ZSX0020`–`ZSX0022`) at context 0–3, generated/compared by `src/tests/diagnostics_snapshot.zig`; bench case `render_1k` |
| 1.9 Property/fuzz infrastructure | first slice | `src/rt/fuzz.zig` generates valid markup from the RFC grammar (elements/fragments, attributes, text/expressions, nested `{if}`/`{for}`/`{switch}`) and byte-mutates each case. Invariants: scanner tokens tile the source, CST spans stay ordered/contained, checker never crashes, lowering rejects (not crashes on) invalid roots, and `fmt` is idempotent on clean parses. `zig build fuzz` (`-Dfuzz-iterations`, `-Dfuzz-seed`) runs 20 000 cases; `src/tests/fuzz.zig` keeps a 200-case deterministic smoke in `zig build test`; nightly `.github/workflows/fuzz.yml` runs 10⁶. Fuzzing already found and fixed three front-end bugs: unclosed frames kept zero-width spans around their children, a `{/…}` closer was appended before unwinding inner frames, and control keywords only accepted a literal space before their arguments (newline/tab forms were misclassified). Deferred: coverage-guided runs, minimization, 10⁸/10⁹ campaigns |
| Public API | done | `zsx.zig` exports `diag` / `scan` / `checker` / `fmt` / `render` + `checkSource`; `examples/checker/` and `examples/render/` consume it as a library (run + tests) |
| F5 (brace/string) | fixed | Both quirks closed in the fail-fast parser: string-aware expression matching and whitespace-tolerant attribute separators, sharing `scan.matchBrace` (one matcher, no drift). Reproducer tests flipped to the fixed behaviour; goldens byte-identical |
| Python removal | partial | CLI no longer spawns python3; scripts kept on disk for reference, deletion is a maintainer call |
| Lossless front-end (S1 + S2) | done | `src/rt/lossless.zig`: one string/char/comment-aware pass partitions a `.zsx` file into typed byte-exact segments; `Document.render` re-emits byte-for-byte (property-tested over all 20 committed views). `preprocess` and `findBlocks` consume it — one Zig-side scanner instead of two drifting copies (F11 shrinks by one). Public as `zsx.lossless` + `checker.lossless`; `examples/lossless/`; bench `lossless_1k` ≈ 35 µs/1k lines |
| JSON diagnostics | done | `diag.List.toJson` + `zsx check --format json`: compact single-line JSON on stdout with stable `ZSX0xxx` codes/names/severities/spans; exit codes presentation-independent; demoed in `examples/checker/`; unit tests pin the exact document shape |
| Docs drift | fixed | AGENTS repo map now lists `examples/render/` (shipped earlier but never recorded) plus the new lossless row and example |

## Known flakiness / quarantine

None. Real-backend jobs fail only on compile/link errors, not pixel timings
(see the flake policy in `AGENTS.md`).

## M2 codegen slice (this handoff)

| WP | Status | Notes |
|---|---|---|
| 2.2 Stable ID scheme | done | `codegen.stableNodeId` = hash64(src_key, block, structural path); loop indices mixed with `+%`/`*%` then `@truncate` to `usize`. No `.paths`-order dependence, no ~184-file overflow. F1 reproducer asserts the fixed behaviour |
| 2.4 Unified control flow | done | `emitContentChildren` deleted; one `emitChildren` with a `TextMode` and an unbounded `Loop` stack. Nested loops get distinct `idx_N`; F2 reproducer green, `slot_loop_demo` exercises it end-to-end |
| 2.3 Scopes and captures | done (loop locals) | Bodies inside `{for}` become container-level generic capture structs (`ZsxBody_N(T…)`) constructed at the call site; `shadcn.invokeSlot` accepts functions or capture structs. `slot_capture_demo` compiles and renders. `{let}` bindings and S1 Zig locals remain for full 2.3 |
| F4 substring guesses | done | Unused-parameter discards use an identifier-token scan; `usesParam`/`fixDiscardPrefixes`/`FILE_STRIDE` removed. `preprocess.mentionsStd`/`importsStd` now tokenize (`std` + `.`, `@import("std")`) instead of `indexOf` |
| 2.5 Typed props | first slice | `src/rt/registry.zig` lists built-in props; checker emits `ZSX0013 unknown_prop` with did-you-mean, and `zsx-gen` fails the build at the `.zsx` line. `--no-prop-check` opts out. Deferred: generated `Component.Props` values / removing `anytype` |
| 2.6 Event handlers v1 | done (first slice) | `on:<event>` accepted; component handlers take arbitrary expressions/arguments; loop-captured handlers emit `ZsxHandler_N` structs; `shadcn.invokeHandler` dispatches. `event_args_demo` covers intrinsic + component + handler-in-loop. Deferred: bare method refs, `Callback(T)`, non-click adapter wiring |
| 2.9 Remove substring heuristics | done | No `indexOf` in the compiler path decides semantics; goldens unchanged except new view |
| 2.10 `addViews` v2 | first slice | `.dir` discovery (sorted, `.exclude`), `discoverViews`, configure dependency on directory metadata; repo `build.zig` + consumer example use it. Deferred: per-view options/strategy, recursive dirs, removing `addViewsLocal` |
| 2.11 `zsx migrate` codemod | done | `src/rt/migrate.zig` + `zsx migrate` (`--write`/`--check`/dry-run): `on_click=` → `on:click=` for known events, legacy closers → current form; token offsets, byte-exact Zig side, idempotent. Deferred: `<label>` → `<text>` (no `<text>` intrinsic yet) |
| 2.12 Compile-cost guardrails | done | `src/rt/cost.zig` token-based report (elements/components/attrs/depth/events/`@setEvalBranchQuota`) + deterministic score; `zsx check --explain-cost`, `--cost-budget N` for CI. Deferred: recording playground compile time in `bench/baseline.json` and a dedicated CI job |
| ADR | done | `docs/adr/0003-scope-aware-codegen.md`, `0004-event-handlers-v1.md`, `0005-component-prop-registry.md`, `0006-addviews-directory-discovery.md` |

## Next milestone

Remaining M2 items before the M2 gate: the rest of typed props — generated code
building `Component.Props{…}` and removing `anytype` (2.5); the rest of the event system — bare
method refs, `Callback(T)`, adapter events beyond click (2.6); expression-
position `zsx!{}` (2.7); line-preserving emission + `.zsxmap` (2.8); and the
rest of `addViews` v2 (per-view options, strategy selection). Then
M1 full scope on top of the S1+S2 front-end: review and accept RFC-0001
(`docs/rfc/0001-markup-grammar.md`, `docs/spec/grammar.ebnf`), build the
≥150-file conformance corpus and runner, then the CST parser with error
recovery and AST lowering.
