# ADR 0001 — Single source of truth for version and component count

- **Status:** accepted
- **Date:** 2026-11-09
- **Deciders:** ZSX maintainers
- **Related:** WP 0.2, finding F12

## Context

`build.zig.zon` said `0.0.1`, `CHANGELOG.md` said `0.2.0`, and `README.md` said
both "15" and "20" components. Release metadata drifted because each file was
edited by hand and no gate checked their agreement.

## Options considered

1. **Keep hand-edited copies.** Simple, but guarantees future drift; the gate
   cannot distinguish a typo from an intended release.
2. **Generate every file from `build.zig.zon`.** Removes duplication, but makes
   Markdown diffs noisy and couples prose to the release script.
3. **One machine-readable `VERSION` file, checked against consumers
   (recommended).** The version is read from `VERSION`; `zig build check-meta`
   fails when `build.zig.zon`, the first `CHANGELOG.md` heading, or the
   `README.md` status line disagree. Component count is derived from
   `src/lib/shadcn.zig` and checked against `README.md`.

## Decision

`VERSION` is the source of truth. `zig build check-meta` compares it with
`build.zig.zon` and the prose files. Component count is computed from the number
of public component functions in `src/lib/shadcn.zig` and compared with the
README. CI runs the gate on every push and pull request.

## Consequences

- Positive: one intentional edit point; drift becomes a red build; component
  count cannot silently regress.
- Negative: contributors must run `zig build check-meta` (the local gate already
  includes it) or let CI tell them.
- Follow-up: when the release script lands, it should bump `VERSION` and prepend
  the changelog heading in one command.
