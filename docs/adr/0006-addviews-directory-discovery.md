# ADR 0006 — `addViews` directory discovery

- Status: accepted
- Date: 2026-11-14
- Work package: M2 WP 2.10 (first slice)

## Context

`zsx.addViews` required an explicit `.paths` array. Adding a view meant editing
`build.zig`; the repo itself carried a 23-entry list and the consumer example a
two-entry list. Finding F12 called this out. The master plan's v2 API asks for
`.dir = "src/views"` so a new file is picked up automatically.

## Decision

1. `Options` gains `.dir: ?[]const u8` and `.exclude: []const []const u8`
   (file names). `.paths` becomes optional; both merge and are sorted by path,
   so file indices and generated module names are deterministic.
2. `zsx.discoverViews(b, dir, exclude)` is exported for callers that need the
   same list (the repo's own `golden` step).
3. `discoverViews` calls `b.dependOnDirectoryMetadata(b.path(dir))`. Without
   it Zig caches the configure phase and would miss newly added files; with it,
   creating/deleting a file re-runs configure and the new view appears. This
   is the only correct way to make configure-time globbing responsive.
4. Module name = file stem, as before. Duplicate stems across directories are
   the consumer's responsibility (same rule as the explicit list).
5. `examples/consumer` and the repo `build.zig` now use `.dir`.

## Consequences

- Adding `src/views/foo.zsx` requires no `build.zig` edit; `zig build test`
  and `zig build golden` include it after the configure re-run.
- Directory metadata (not contents) is tracked, so content edits do not rerun
  configure; the generator's own input dependency handles those.
- Discovery is non-recursive; nested view trees can pass multiple `.dir`
  values? Not yet — `.exclude` plus `.paths` covers current needs, and a
  recursive option is a future addition.
- `zsx-gen` still receives `--file-index` positionally; sorting keeps IDs and
  goldens stable across filesystem iteration order.

## Alternatives considered

- **Recursive walk at configure time:** more convenience, more surprising
  module names; deferred until a real nested layout exists.
- **Make-time generated import list:** Zig requires module imports at configure
  time, so this cannot produce new module bindings without reconfiguration.
