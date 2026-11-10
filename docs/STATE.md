# ZSX — current state

Updated at the end of every PR that completes a work package. Sanitized for
agents: assume your context does not include the previous session.

## Snapshot

| Field | Value |
|---|---|
| Current milestone | **M0 — Ground truth** (implemented, awaiting gate confirmation on CI) |
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
| 0.9 `zsx` CLI stub | done | wrappers around the Python tools until M1 |
| 0.10 Zig-version policy | done | ADR 0002 + `src/compat.zig` |

## Known flakiness / quarantine

None. Real-backend jobs fail only on compile/link errors, not pixel timings
(see the flake policy in `AGENTS.md`).

## Next milestone

M1 — Lossless front-end. Start with spikes S1 (Zig-side parsing via
`std.zig.Ast` placeholders) and S2 (line-preserving emission), then RFC-0001.
