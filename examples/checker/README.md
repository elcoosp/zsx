# checker_demo — the ZSX tooling front-end as a library

`examples/consumer` shows the codegen path (`zsx.addViews` in your
`build.zig`). This example shows the other seam ZSX ships since M1: the
structural checker, the tolerant scanner, and structured diagnostics are
public API on the `zsx` package, so you can validate `.zsx` sources in tests,
codegen pipelines, or editor tooling without spawning `zsx check` as a
process.

```zig
const zsx = @import("zsx");

var list = zsx.diag.List.init(arena.allocator());
try zsx.checker.checkSource(arena.allocator(), source, "src/views/home.zsx", .{}, &list);
if (list.hasErrors()) { /* inspect list.items */ }
```

Every diagnostic carries a stable `ZSX0xxx` code (`ZSX0003` = unclosed tag,
`ZSX0006` = unclosed control flow, `ZSX0009` = unknown class warning, ...), a
severity, a 1-based line/col pair and byte span. `renderHeader` produces the
same `file:line:col: error[ZSX0003]: message` text the CLI prints.


The same report is available as machine-readable JSON — what
`zsx check --format json` prints to stdout, and what `list.toJson()`
returns as a library call:

```json
{"schema":1,"diagnostics":[{"code":"ZSX0003","name":"unclosed-tag","severity":"error","file":"bad.zsx","line":6,"col":18,"offset":150,"len":4,"message":"<row> never closed","help":"add `</row>` or make the element self-closing"}]}
```

Field order is fixed and the document is single-line, so CI jobs and editor
integrations can pin or diff it; `schema` bumps on any incompatible shape
change. The demo prints the JSON report for the broken fixture after the
text frames.

## Run

```bash
zig build run     # validate a clean and a broken view, print diagnostics
zig build test    # two smoke tests pinning the diagnostic counts
```

The broken fixture in `src/main.zig` has an unclosed `<row>`, an unclosed
`{if}`, and one unknown class — the demo prints all three before any compile
is attempted, which is the point: structural errors surface in milliseconds,
not in a 30-second `zig build test`.
