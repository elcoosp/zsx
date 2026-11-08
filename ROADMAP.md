# ZSX Roadmap

The architecture is settled. This document describes what shipped, what
was explicitly rejected, and what remains. Every "shipped" item is in the
codebase today; every "rejected" item was tried and removed.

## Where ZSX is heading

TSX for Zig: TypeScript's `.tsx` proves that markup can live inside a
programming language's source file without being a separate file format,
a runtime parser, or a template language. ZSX targets the same shape for
Zig.

Three invariants:

1. A `.zsx` file is a **superset of Zig**. It looks like a Zig file and
   compiles down to one, but `zsx!{ <markup> }` is not Zig syntax — the
   preprocessor expands each block into plain Zig before the compiler sees
   the file. Same mechanism as Svelte (`.svelte` → `.js`) or SCSS
   (`.scss` → `.css`), not TSX (`.tsx` → `.js` where the compiler
   natively understands JSX).
2. The comptime preprocessor expands each block to plain Zig builder
   calls (`ui.column(c, .{...})`, `ctx.Button(ui, c, .{...})`,
   `shadcn.Button(ctx, ui, c, .{...})`) at compile time. Release binaries
   contain no parser.
3. Components are ordinary Zig functions reachable through normal Zig
   name resolution — either a `pub const` on a context struct or a
   path-qualified tag (`<shadcn.Button>`) that resolves to a `@import`ed
   module.

Everything below is scored against those invariants.

## Shipped

### Parser and AST

- `src/parser.zig`: recursive-descent parser. Paired/self-closing tags,
  boolean/value/string attributes, text and `{expr}` children, fragments,
  path-qualified tag names (`.` in `isTagChar`). Runs at comptime only;
  every `test` block wraps its body in `comptime { }` so the AST is
  consumed at comptime (no runtime materialization of comptime-var
  pointers).
- `src/ast.zig`: `Element`, `Attribute`, `AttributeValue`, `Child` union.

### Emitter (`src/codegen.zig`)

- Extracted from `build.zig`; 13 unit tests assert generated shape, ID
  stride math, escaping, and control flow.
- Packed IDs: `file_index * FILE_STRIDE + sibling` at top level, plus
  `idx_0 * LOOP_STRIDE_0 + idx_1 * LOOP_STRIDE_1` inside loops. No
  collisions across siblings, iterations, or views.
- `escapeString` handles `"`, `\\`, `\n`, `\r`, `\t`, and control bytes as
  `\xNN`.
- Emits `preamble` (helper `render_X_N` functions for components with
  element children) separately from `code` so callers can hoist preambles
  to module scope.

### Preprocessor (`src/preprocess.zig`)

- Scans Zig source for `zsx!{ ... }` blocks. Skips strings, chars, line
  comments, block comments — a `zsx!{` inside `"..."` is not a block.
- Expands each block via `codegen.emitElement`, hoists the resulting
  preamble above the file, and shifts the body to match the block's
  source column.
- 14 tests: identity, single/multi block, ID distinctness across blocks,
  marker-not-in-string/comment/char, preamble hoisting, indentation
  shifting, trailing-semicolon consumption.

### Adapters

Two ship today, both implementing the same primitive surface
(`column`, `row`, `text`, `button`, `textEntry`, `textArea`, `checkbox`,
`progress`, `divider`, `slider`, `toggle`, `skeleton`):

- `src/adapters/dvui.zig`: DVUI on SDL3. Uses `@hasDecl` / `@hasField`
  for API-drift resilience (`TextEntryWidget` vs `textEntry`, `radius`
  vs `corners`, etc.).
- `src/adapters/nanoui.zig`: Nanoui on Metal (macOS only). Persists
  `TextBuffer` cache keyed by `id_extra` so input state survives frames.

Each adapter also ships a `StubX` that records primitive calls for fast
tests (~1s) without a window.

### Control flow

`{if cond}`, `{else if cond}`, `{else}`, `{endif}`, `{for items as item}`,
`{endfor}`, and `<>...</>` fragments. Lower to literal Zig `if`/`for`
statements in the generated file. Loop IDs are strided.

### Component library (`src/lib/shadcn.zig`)

15 components, all pure compositions of adapter primitives:
`Button`, `Badge`, `Card`, `Heading`, `Caption`, `Link`, `Section`,
`Input`, `Textarea`, `Checkbox`, `Progress`, `Divider`, `Slider`,
`Switch`, `Skeleton`.

Every component takes `self: anytype` as its first parameter so it is
callable both as `ctx.Button(ui, c, props)` (bare tag) and
`shadcn.Button(ctx, ui, c, props)` (path tag) without signature changes.

### Path-qualified component tags

`<shadcn.Button>` in markup becomes `shadcn.Button(ctx, ui, c, .{...})`
in generated Zig, where `shadcn` is whatever the `.zsx` file imported at
module scope. No `pub const Button` boilerplate on the context struct.

### Styling (`src/style.zig`)

Tailwind-named class subset (`bg-*`, `text-*`, `p-*`, `px-*`, `py-*`,
`gap-*`, `rounded-*`, `font-*`) resolved at comptime to `Style` struct
fields. Unknown class → compile error.

### Source-span errors

Every parser `@compileError` cites the `.zsx` file, line, and column:
`src/views/dashboard.zsx:14:8: mismatched closing tag: <column> closed by </row>`.
Line/col are computed from byte offsets by `formatSpan` in `src/parser.zig`;
the `.zsx` path is threaded from `build.zig` → `preprocess` → `parse`.
Compile errors now point at the user's source, not the generated `_gen.zig`.

### Tooling and distribution

- `scripts/new-project.sh`: fork workflow (rename package, regenerate
  fingerprint, init git).
- `scripts/screenshot-dvui.sh`: window-level screenshot via
  `CGWindowListCopyWindowInfo` + `screencapture -l`. No AppleScript, no
  window repositioning.
- `src/snapshot_test.zig`: nanoui snapshot harness (not in CI yet).
- `.github/workflows/ci.yml`: `zig build test` on ubuntu + macos, real
  binaries on macos.

## Explicitly rejected

### `Backend(comptime X)` trait

An earlier design had a `Backend(comptime X)` type exposing `Context`,
`Capabilities`, `emit(ast.Element, *Context)`. It never reached
production. Replaced by the simpler `Adapter(comptime X)` model: one
struct per backend, primitives callable from generated code, no dispatch
layer.

### `StyleRef` / `Feature` / `Capabilities` / `StyleResolver`

Never shipped. The style pipeline is comptime-only
(`parseClasses` → `Style` → emitter literals). Adding a pluggable
resolver would be a new adapter-adjacent concept, not a rewrite of the
existing path.

### Package distribution (`zig fetch zsx`)

Impossible by design. `@embedFile(path)` requires `path` to be a
comptime-known literal; a package cannot enumerate a consumer's `.zsx`
files, which live in the consumer's `build.zig`. The template-and-fork
model preserves comptime at the cost of git-mergeable updates.
`TEMPLATE.md` documents this.

### Runtime `parse(allocator, src)`

Rejected. Slower at build time, larger at runtime, contradicts the
"no parser in the release binary" pitch.

### Trait-based backend discovery

Rejected in favor of explicit module imports. A new backend is a new
`src/adapters/<name>.zig` implementing the primitive surface. No
registry, no plugin loader.

## Next

Prioritized, not committed to dates.

### A — Pluggable style resolver

Today `style.zig` is a fixed class-to-`Style` mapping. A resolver
interface (`resolve(class) → Style`, `lower(style, backend) → ...`) would
let consumers swap Tailwind for their own design system. This is the
concept the old `StyleRef` / `StyleResolver` was pointing at, but wired
through `style.zig` rather than a new backend trait.

### B — Backend expansion

Both current backends are Zig-native. Natural next targets, in order of
expected effort:

- **raylib-zig**: flattened layout → draw calls. Feasible; ~200 lines of
  adapter.
- **ImGui (cimgui-zig)**: immediate-mode, structurally similar to DVUI.
- **Web emitter**: serialize AST to HTML + class strings. Easy once
  `Style` is preserved as `raw_class`; needs a separate
  `Adapter(comptime HTMLWriter)` shape.
- **Capy / Zigui / Gooey**: uncertain API stability; treat as research.

Adding any one of these does not touch the parser, AST, preprocessor,
emitter, or component library. That is the point of the adapter model.

### D — ZLS / editor integration

`_gen.zig` files are gitignored. A fresh clone needs `zig build test`
before ZLS can resolve them. Options:

- Ship a `.zls.json` that runs `zig build test` on startup.
- Add `addUpdateSourceFiles` to every build step (already done), then
  document a `zig build zsx` hot-reload loop.
- Eventually: emit `_gen.zig` into `.zig-cache` and expose via
  `b.addModule` so consumers `@import("views/demo")` and never see a
  `_gen.zig` path.

The last option is the cleanest; it is a Zig build-system question, not a
ZSX question.

### E — `{switch}` and richer control flow

`{switch expr} ... {endswitch}` maps 1:1 to Zig's `switch`. No new
concepts, just grammar. Blocked on a real requirement.

### F — Slot children for components

Today `<Card>...</Card>` compiles to a `render_Card_N` helper passed as
`content`. A component that wants children placed in multiple named slots
(`<Card><Header>...</Header><Body>...</Body></Card>`) needs a richer ABI:
props struct with named content fields. Feasible; skip until a concrete
component demands it.

## Non-goals

ZSX will never be:

- A router, state manager, or component lifecycle system. That is your
  application's job.
- A template language with its own runtime. Output is plain Zig builder
  calls; a release build contains no interpreter.
- A React/Solid-style reactive layer. `{for}` and `{if}` are direct Zig
  control flow; nothing re-renders implicitly.
- A stylesheet language. Class strings resolve at comptime; no CSS, no
  cascade, no `.scss`.

## Timeline

None. Every shipped item is in the codebase today. Every "next" item is
a self-contained PR away and does not block anything else.
