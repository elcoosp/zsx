# AGENTS.md — repository operating manual

This file is the entry point for autonomous agents and humans working on ZSX.
Keep it under 300 lines. See `docs/ZSX_MASTER_PLAN.md` for the long-term plan and
`docs/STATE.md` for the current status.

## What ZSX is

ZSX turns `.zsx` files (Zig outer, `zsx!{ <markup> }` inner) into plain Zig at
build time. There is no runtime parser in release binaries. The generated file
lives in `.zig-cache` and is imported by module name.

## Repository map

| Path | Purpose |
|---|---|
| `src/rt/parser.zig` | recursive-descent markup parser |
| `src/rt/preprocess.zig` | scan Zig source for `zsx!{…}` blocks |
| `src/rt/codegen.zig` | AST → plain Zig emitter |
| `src/rt/style.zig` | runtime class → `Style` resolver |
| `src/rt/diag.zig` | structured diagnostics (`ZSX0xxx`, spans) |
| `src/rt/scan.zig` | tolerant markup tokenizer (tooling front-end) |
| `src/rt/checker.zig` | structural checker (`zsx check`) + tooling barrel |
| `src/rt/fmt.zig` | native formatter (`zsx fmt`) |
| `src/lib/style.zig` | comptime class → `Style` resolver (components) |
| `src/gen.zig` | `zsx-gen` host executable |
| `zsx.zig` | `addViews` / `addViewsLocal` build helpers |
| `src/cli.zig` | `zsx` CLI (`fmt`, `check`, `gen`, …) |
| `src/lib/shadcn.zig` | shadcn-inspired components |
| `src/adapters/*.zig` | dvui, nanoui, html backends + stubs |
| `src/views/*.zsx` | demo views used by tests and goldens |
| `src/tests/*.zig` | split test suites (M0 0.6) |
| `spec/golden/` | committed golden output of `zsx-gen` |
| `bench/` | benchmark harness + committed baseline |
| `tools/` | build-time helper executables (`check-meta`, `golden`, `bench`) |
| `docs/adr/` | architecture decision records |
| `docs/rfc/` | user-facing change proposals |
| `examples/consumer/` | fetchable-path consumer example |
| `examples/checker/` | checker-as-library consumer example |

## Commands

```bash
zig build test              # unit + view tests
zig build check-meta        # version / component-count consistency
zig build check-docs        # required docs exist + relative links resolve
zig build golden            # diff generated views against spec/golden
zig build golden -Dupdate-golden   # regenerate goldens (review the diff!)
zig build bench-smoke       # fast benchmark sanity check
zig build bench             # full benchmark, writes bench/baseline.json
zig build zsx -Dcmd=fmt   # run the ZSX CLI
zig build zsx -Dcmd=check
zig build build-app-dvui -Dreal=true    # macOS/Linux with SDL3 + freetype
zig build build-app-nanoui -Dreal=true  # macOS only
```

The local gate (run before every PR) is:

```bash
zig build test && zig build check-meta && zig build golden && zig build bench-smoke
```

`zsx fmt --check` / `zsx check` are the native Zig implementations (M1/M2)
and run in CI on every push; the Python scripts under `scripts/` are kept
only for reference and are no longer invoked.

## Work loop (binding)

1. Read this file, `docs/STATE.md`, and the work package (WP) in the master plan.
2. Write or extend tests first (failing). For bugs, add a reproducer.
3. Implement the smallest change that passes.
4. Run the local gate.
5. Update docs, `CHANGELOG.md`, and `docs/STATE.md`.
6. Small PRs (≤ ~600 changed lines excluding goldens). One WP per PR.
7. If a decision is needed, write an ADR/RFC with options and a recommendation.

## Definition of done

- Tests green on the CI matrix.
- New behaviour has unit tests; compiler changes have golden tests.
- No benchmark regression > 2 % without justification.
- Docs updated; examples compile.
- Public API changes have an RFC reference and a CHANGELOG entry (plus a
  codemod during 0.x).
- No new warnings; no `TODO` without an issue ID.

## Conventions

- Zig 0.17.x. Support `current` and `current-1` per
  `docs/adr/0002-zig-version-policy.md`; compatibility shims live in
  `src/compat.zig`.
- Never process Zig or markup source with substring/regex heuristics. Decide on
  tokens/AST.
- Never add global mutable state in adapters or runtime code.
- Never copy-paste control-flow or style logic; share one implementation.
- Unknown classes and unknown props must be build errors, not silent no-ops.
- Do not loosen a test without an ADR.

## Known gotchas (Zig 0.17)

- `std.process.Init` replaces the old `main` signature; read args via
  `init.minimal.args.toSlice(arena)` and file I/O via `init.io`.
- `std.Io.Dir.cwd().readFileAlloc(io, path, allocator, .limited(n))`.
- `std.process.run(gpa, io, .{ .argv = … })` returns stdout/stderr buffers; the
  caller owns them.
- File writes use `createFile(io, path, .{ .truncate = true })` then
  `writeStreamingAll(io, bytes)`.
- Existing parser quirks are documented reproducers in `src/tests/reproducers.zig`.

## Flake policy

- CI must be deterministic. Any test that needs a window, GPU, or network is
  labelled and does not block the stub-backend jobs.
- A flaky test is quarantined by opening an issue, adding `skip` with the issue
  ID in the skip reason, and linking it in `docs/STATE.md`.
- Real-backend jobs (DVUI, Nanoui) are allowed to be slower; they fail the build
  only on compile/link errors, not on pixel timings.
