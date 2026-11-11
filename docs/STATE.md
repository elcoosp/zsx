# ZSX — current state

Updated at the end of every PR that completes a work package. Sanitized for
agents: assume your context does not include the previous session.

## Snapshot

| Field | Value |
|---|---|
| Current milestone | **M1 lossless front-end (S1+S2) + machine-readable JSON diagnostics — implemented** |
| Last known green commit | see `git log -1`; local gate is the source of truth |
| Release train | 0.3.0 shipped at the M0 gate; next tag at M1 |
| Zig versions | 0.17.1 (`current`); policy in `docs/adr/0002-zig-version-policy.md` |
| Open milestone blockers | None for M0 |

## M0 work packages

| WP | Status | Notes |
|---|---|---|
| 0.1 Memory + ADR/RFC templates | done | `AGENTS.md`, this file, `docs/adr/0000-template.md`, `docs/rfc/0000-template.md`; `zig build check-docs` link-checks them |
| 0.2 Version/metadata hygiene | done | `VERSION` is the source of truth; `zig build check-meta` |
| 0.3 Lazy dependencies | done | `.lazy = true`; real backends are opt-in via `-Dreal=true`, so tests/consumer fetch neither |
| 0.4 Reproducer tests | done | `src/tests/reproducers.zig` documents F1, F2, F3, F5; fix in M1/M2 |
| 0.5 Golden harness | done | `zig build golden`; committed baselines in `spec/golden/` |
| 0.6 Split root tests | done | tests live under `src/tests/`; `src/root.zig` is a thin aggregator |
| 0.7 Benchmark skeleton | done | `zig build bench` writes `bench/baseline.json`; `bench-smoke` is the fast gate |
| 0.8 CI matrix | done | Ubuntu + macOS + Windows stub jobs; consumer lazy-dependency assertion; Linux real-DVUI job with SDL3; flake policy in `AGENTS.md` |
| 0.9 `zsx` CLI stub | superseded | wrappers replaced by native `check`/`fmt` (M1/M2); Python scripts unused |
| 0.10 Zig-version policy | done | ADR 0002 + `src/compat.zig` |

## M1/M2 tooling front-end (this handoff)

| WP | Status | Notes |
|---|---|---|
| 1.7 Checker in Zig (slice) | done | `src/rt/checker.zig`: tolerant scanner (`scan.zig`), rule set with `ZSX0xxx` codes, `diag.zig` diagnostic type (spans, severities, help); unknown classes read `style.isKnownClass` — no duplicated table. `zsx check` CLI native; exit codes 0/1/2 parity. Bench `check_1k` ≈ 0.3 ms/1k lines (target < 20 ms) |
| 1.6 Formatter in Zig (slice) | done | `src/rt/fmt.zig`: token-driven reprinter, idempotent, committed corpus byte-for-byte (`src/tests/fmt.zig`); `zsx fmt` CLI native (`--check`/`--write`) |
| Code-frame rendering (M1 slice) | done | `src/rt/render.zig`: `render.Renderer` turns a diagnostic + source into the annotated snippet (header, help line, gutter, caret span). Exported as `zsx.render`; `zsx check` prints frames; demo in `examples/render/`; bench case `render_1k` (≈ 0.5 ms/1k lines incl. the check) |
| Public API | done | `zsx.zig` exports `diag` / `scan` / `checker` / `fmt` / `render` + `checkSource`; `examples/checker/` and `examples/render/` consume it as a library (run + tests) |
| F5 (brace/string) | fixed | Both quirks closed in the fail-fast parser: string-aware expression matching and whitespace-tolerant attribute separators, sharing `scan.matchBrace` (one matcher, no drift). Reproducer tests flipped to the fixed behaviour; goldens byte-identical |
| Python removal | partial | CLI no longer spawns python3; scripts kept on disk for reference, deletion is a maintainer call |
| Lossless front-end (S1 + S2) | done | `src/rt/lossless.zig`: one string/char/comment-aware pass partitions a `.zsx` file into typed byte-exact segments; `Document.render` re-emits byte-for-byte (property-tested over all 20 committed views). `preprocess` and `findBlocks` consume it — one Zig-side scanner instead of two drifting copies (F11 shrinks by one). Public as `zsx.lossless` + `checker.lossless`; `examples/lossless/`; bench `lossless_1k` ≈ 35 µs/1k lines |
| JSON diagnostics | done | `diag.List.toJson` + `zsx check --format json`: compact single-line JSON on stdout with stable `ZSX0xxx` codes/names/severities/spans; exit codes presentation-independent; demoed in `examples/checker/`; unit tests pin the exact document shape |
| Docs drift | fixed | AGENTS repo map now lists `examples/render/` (shipped earlier but never recorded) plus the new lossless row and example |

## Known flakiness / quarantine

None. Real-backend jobs fail only on compile/link errors, not pixel timings
(see the flake policy in `AGENTS.md`).

## Next milestone

M1 full scope — Lossless front-end. S1 and S2 are now closed
(`src/rt/lossless.zig`, see the table above). Remaining: RFC-0001 (grammar
v1), the CST parser with error recovery on top of the lossless seam, and
closing the pinned reproducers F1/F2/F3 (F5 is already closed). F2/F3 need
one design decision first: hoisted slot-content helpers must receive the
surrounding loop locals as parameters (today they are `fn(ui, c, ctx)` and
cannot reference `idx_0`/bindings — see the F3 reproducer).
