# ADR 0005 — Component prop registry (typed-props foundation, F7)

- Status: accepted
- Date: 2026-11-14
- Work package: M2 WP 2.5 (first slice)

## Context

`componentPropsLiteral` emitted every markup attribute as a struct field, and
components read them with `@hasField`, so a typo such as
`<Button varient="primary">` compiled and silently did nothing (finding F7).
The generator runs before Zig type checking and has no type information about
the component, so it cannot ask Zig which fields `Props` has.

The master plan's end state is a real `Component.Props` struct that generated
code builds by named fields. That requires a call-convention migration
(components become namespaces exposing `Props`, every context forwards the
type) which is a larger, separate change.

## Decision

1. Add `src/rt/registry.zig`: a closed, data-only table of the built-in
   components (`Button`, `Card`, …) with their non-event props, common props
   (`class`, `id_extra`) and slot fields. Events are accepted by prefix
   (`on_*` / `on:*`).
2. The registry resolves `Button` and `shadcn.Button` / `ui.Button`; any other
   namespace is ignored so user components are not second-guessed.
3. The checker validates component attributes and emits **errors**
   (`ZSX0013 unknown_prop`) with a did-you-mean help line computed from edit
   distance. `--no-prop-check` is the escape hatch.
4. `zsx-gen` runs the same checker before preprocessing. A bad prop therefore
   fails the build with the `.zsx` location and suggestion, not just `zsx
   check`.
5. The table is the single source of truth: the checker, `zsx-gen` and future
   tooling consume it; a unit test pins the lookup/accept/suggest behaviour.

## Consequences

- F7 is closed for built-in components at build time, with a source span and
  suggestion, while user components keep duck-typed props until the typed
  call convention lands.
- Adding a prop to a built-in component requires updating `registry.zig`
  (`src/tests/checker.zig` covers the happy path; `zsx build test` regenerates
  every view through `zsx-gen`, so a missing entry fails the gate).
- `zsx-gen` is slightly slower per file (it tokenizes/scan for diagnostics
  once), but the benchmark harness measures the preprocess pipeline, not the
  executable, so `bench-smoke` is unaffected.

## Deferred

- `Component.Props` values in generated code and removal of `anytype` props
  (M2 gate item 2.5).
- Required-prop validation: it needs child/slot knowledge to avoid flagging
  `text` on components that receive their text from children.
- Prop manifests for LSP completion (WP 3.3) consume this table later.
