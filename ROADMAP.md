# ZSX Roadmap

What shipped, what was rejected, what remains. Every "shipped" item is in the codebase today; every "rejected" item was tried and removed.

## Where ZSX is heading

TSX for Zig: TypeScript's `.tsx` proves that markup can live inside a programming language's source file without being a separate file format, a runtime parser, or a template language. ZSX targets the same shape for Zig.

Three invariants:

1. A `.zsx` file is a **superset of Zig**. It looks like a Zig file and compiles down to one, but `zsx!{ <markup> }` is not Zig syntax — the preprocessor expands each block into plain Zig before the compiler sees the file. Same mechanism as Svelte (`.svelte` → `.js`) or SCSS (`.scss` → `.css`), not TSX.
2. The preprocessor expands each block to plain Zig builder calls (`ui.column(c, .{...})`, `ctx.Button(ui, c, .{...})`, `shadcn.Button(ctx, ui, c, .{...})`) at build time. Release binaries contain no parser.
3. Components are ordinary Zig functions reachable through normal Zig name resolution — either a `pub const` on a context struct or a path-qualified tag (`<shadcn.Button>`) that resolves to a `@import`ed module.

## Shipped

### Parser and AST

- `src/rt/parser.zig`: recursive-descent parser.
- `Element`, `Attribute`, `AttributeValue`, `Child` live in `src/rt/parser.zig`.


### Emitter

- `src/rt/codegen.zig`: walks the AST, emits plain Zig.
- `src/gen.zig` (`zsx-gen`): CLI.


### Preprocessor

- `src/rt/preprocess.zig`: scans for `zsx!{ }` blocks.


### Build-time generator

- `src/gen.zig` (`zsx-gen`): standalone CLI. Takes `--input file.zsx --output file.zig --src-name path --file-index N`. Runs at build time, no comptime.
- `zsx.zig`: `addViews(b, opts)` helper. Consumers call it from their `build.zig`. Returns named modules that map to generated views.

### Adapters

Three adapters, each implementing the same primitive surface (`column`, `row`, `text`, `button`, `textEntry`, `textArea`, `checkbox`, `progress`, `divider`, `slider`, `toggle`, `skeleton`):

- `src/adapters/dvui.zig`: DVUI on SDL3.
- `src/adapters/nanoui.zig`: Nanoui on Metal (macOS).
- `src/adapters/html.zig`: plain HTML + inline styles, any `writeAll`-capable writer.

Each adapter also ships a `StubX` that records primitive calls for fast tests.

### Control flow

`{if cond}`, `{:else if cond}`, `{:else}`, `{/if}`, `{for items as item}`, `{/for}`, `{switch expr}`, `{:case "val"}`, `{/switch}`, and `<>...</>` fragments. Lower to literal Zig `if`/`for`/if-else-if chains. Old syntax (`{endif}`, `{endfor}`, etc.) still works as aliases during migration.

### Component library

20 components, all pure compositions of adapter primitives: `Button`, `Badge`, `Card`, `Heading`, `Caption`, `Link`, `Section`, `Input`, `Textarea`, `Checkbox`, `Progress`, `Divider`, `Slider`, `Switch`, `Skeleton`.

### Named slots

`<Slot name="header">...</Slot>` inside a component compiles to an `.header` fn field in the props struct. `Card` and `Section` iterate `content`, `header`, `body`, `footer` and call whichever are present.

### Path-qualified component tags

`<shadcn.Button>` becomes `shadcn.Button(ctx, ui, c, .{...})`. The module is imported at `.zsx` file top. No `pub const Button` boilerplate needed on the context struct.

### Pluggable style resolver

`style.styleFromWith(el, resolver)` accepts a comptime resolver struct with `parseClasses` and `parseNumeric`. `DefaultResolver()` wraps the built-in class map. Consumers swap for their own design system.

### Source-span errors

Every parser error cites `.zsx` file, line, column: `src/views/dashboard.zsx:14:8: zsx: mismatched closing tag`. Line/col computed from byte offset, `.zsx` path threaded from `build.zig` → `preprocess` → `parse`.

### Fetchable distribution

- **`.zsx` depends on `zsx` in `build.zig.zon`** — `.path` for local, `git+https://...` + hash for external.
- **`zsx.addViews(b, opts)` from consumer's `build.zig`** — builds `zsx-gen`, runs it, returns named modules.
- **Generated `.zig` files land in `.zig-cache`** — never in source tree.
- **Consumer imports by name** — `@import("home")`, not `@import("views/home_gen.zig")`.
- **Verified end-to-end** — [`examples/consumer/`](examples/consumer/) runs with zero fork, zero `_gen.zig` in source tree.


### Zig 0.17 documentation

`docs/zig-skill.md` contains 17 numbered gotchas discovered while porting the runtime pipeline to Zig 0.17. Each entry has the verbatim error and the fix.

## Explicitly rejected

### `Backend(comptime X)` trait

Earlier design: `Backend(comptime X)` exposing `Context`, `Capabilities`, `emit(ast.Element, *Context)`. Never reached production. Replaced by the simpler `Adapter(comptime X)` model: one struct per backend, primitives callable from generated code, no dispatch layer.

### `StyleRef` / `Feature` / `Capabilities` as separate modules

Never shipped as designed. `styleFromWith(el, resolver)` is the actual resolver interface. `StyleRef`, `Feature`, `Capabilities` were deleted.

### `@embedFile` + comptime parsing as the only pipeline

Was the only path until the runtime pipeline shipped. It required a fork to use as a dependency, because `@embedFile` cannot enumerate a consumer's `.zsx` files. Now comptime is one of two modes; the runtime mode works as a fetchable dependency.

### Runtime `parse(allocator, src)` for consumers

Rejected as the primary path — a runtime parser in release builds costs startup time and binary size. The runtime pipeline in `src/rt/` runs at **build** time, not runtime. The parser still never ships in the binary.

### Trait-based backend discovery

Rejected in favor of explicit module imports. A new backend is a new `src/adapters/<name>.zig` implementing the primitive surface. No registry, no plugin loader.

## Next

Prioritized, not committed to dates.

### A — Pluggable style resolver (SHIPPED)

See "Shipped — Pluggable style resolver."

### B — Backend expansion

- **raylib-zig**: flattened layout → draw calls. Feasible; ~200 lines of adapter. **Blocked**: recon showed no usable `pub fn` surface in the fetched raylib_zig package. Needs manual investigation.
- **ImGui (cimgui-zig)**: immediate-mode, structurally similar to DVUI.
- **Capy / Zigui / Gooey**: uncertain API stability; treat as research.

Adding any one of these does not touch the parser, AST, preprocessor, emitter, or component library.

### C — Source-span error reporting (SHIPPED)

See "Shipped — Source-span errors."

### D — Module wiring (SHIPPED)

See "Shipped — Fetchable distribution."

### E — `{switch}` control flow (SHIPPED)

See "Shipped — Control flow."

### F — Named slots (SHIPPED)

See "Shipped — Named slots."

### G — Editor tooling

- `.zsx` syntax highlighting via tree-sitter grammar
- LSP completion for component props
- `zsx fmt` for `.zsx` files

Lower priority than the core pipeline. Zig highlighting works today for the outer Zig; markup inside `zsx!{ }` gets no special treatment.

### H — More components

Current 15 cover the basics. Missing: `Select`, `Dialog`, `Table`, `Tabs`, `Toast`, `Tooltip`, `Popover`, `Radio Group`, `Checkbox Group`, `Form wrapper`.

## Non-goals

ZSX will never be:

- A router, state manager, or component lifecycle system. That is your application's job.
- A template language with its own runtime. Output is plain Zig builder calls.
- A React/Solid-style reactive layer. `{for}` and `{switch}` are direct Zig control flow; nothing re-renders implicitly.
- A stylesheet language. Class strings resolve at build time; no CSS, no cascade, no `.scss`.
- A package manager. It's a build-time code generator; your app manages its own dependencies.

## Timeline

None. Every shipped item is in the codebase today. Every "next" item is a self-contained PR away and does not block anything else.
