# ADR 0002 — Zig version support policy

- **Status:** accepted
- **Date:** 2026-11-09
- **Deciders:** ZSX maintainers
- **Related:** WP 0.10, finding F16

## Context

ZSX targets a moving Zig pre-1.0 toolchain. The repository is pinned to Zig
0.17.x and `docs/zig-skill.md` already records 17 API changes that broke builds
while the project was being written. There was no explicit promise about which
Zig releases a ZSX release supports, and compatibility code had no home.

## Options considered

1. **Track only the latest Zig release.** Least code, but every Zig release
   breaks downstream users until they upgrade — unacceptable for a toolchain
   dependency.
2. **Support `current` and `current-1` (recommended).** CI tests the newest
   release and the previous one. Any API difference is isolated in
   `src/compat.zig`; runtime/comptime code imports the shim instead of branching
   on `@import("builtin").zig_version` at each callsite.
3. **Support every Zig release since 0.13.** Rejected: multi-version shims would
   dominate the compiler and CI cost.

## Decision

A ZSX minor release supports the latest stable Zig release at the time of the
release (`current`) and the immediately preceding release (`current-1`).
`build.zig.zon` records the oldest supported version in `minimum_zig_version`.
All compatibility shims live in `src/compat.zig`, which exposes version-neutral
helpers. CI runs the local gate on both versions. Supporting `current-2` is a
best-effort courtesy, not a gate.

When Zig makes a breaking change:

1. Add the shim to `src/compat.zig`.
2. Keep the old branch green in the same PR.
3. Record the verbatim compiler error and fix in `docs/zig-skill.md`.

## Consequences

- Positive: users can upgrade Zig without being forced to upgrade ZSX; upgrade
  work is localized and tested.
- Negative: two CI legs; every hosted release must be tested twice; shims carry
  a small abstraction cost.
- Follow-up: the release checklist must state which two Zig versions were
  tested.
