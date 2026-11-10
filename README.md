<div align="center">
  <img src="https://cdn.jsdelivr.net/gh/elcoosp/zsx@main/docs/logo.png" alt="Zsx Logo" width="300"/>
  <p>
    <strong>A JSX-like view syntax for Zig that compiles to native GUI code at build time</strong><br/>
    Zsx turns <code>.zsx</code> files into plain Zig at build time — no runtime parser, no dynamic dispatch,
    no interpreter in your release binary. It is for Zig developers building apps with dvui, nanoui,
    or HTML who want declarative views without giving up their toolkit. The 20-component playground in
    <code>src/views/playground.zsx</code> renders from one source through all three adapters.
  </p>
  <p>
    <a href="https://github.com/elcoosp/zsx/blob/main/.github/workflows/ci.yml"><img src="https://img.shields.io/github/actions/workflow/status/elcoosp/zsx/ci.yml?branch=main&style=flat-square" alt="CI status"/></a>
    <a href="https://github.com/elcoosp/zsx/blob/main/build.zig.zon"><img src="https://img.shields.io/badge/zig-0.17.0%2B-F7A41D?style=flat-square&logo=zig&logoColor=white" alt="Zig version"/></a>
    <a href="https://github.com/elcoosp/zsx/tree/main/src/adapters"><img src="https://img.shields.io/badge/backends-dvui%20%7C%20nanoui%20%7C%20html-lightgrey?style=flat-square" alt="Supported backends"/></a>
    <a href="https://github.com/elcoosp/zsx/blob/main/LICENSE"><img src="https://img.shields.io/badge/license-MIT-blue?style=flat-square" alt="MIT License"/></a>
    <a href="https://github.com/elcoosp/zsx/releases/tag/v0.3.0"><img src="https://img.shields.io/badge/distribution-fetchable-orange?style=flat-square" alt="Fetchable"/></a>
  </p>
</div>

<p align="center">
  <a href="#quickstart">Quickstart</a> • <a href="#not-quite-tsx">Not quite TSX</a> • <a href="#use-as-a-dependency">Use as a dependency</a> • <a href="#features">Features</a> • <a href="#how-it-works">How it works</a> • <a href="#usage">Usage</a> • <a href="#contributing">Contributing</a> • <a href="#status">Status</a>
</p>

## Quickstart

Prerequisites: Zig 0.17.0 or later (CI runs 0.17.1). SDL3 + freetype only if you want to run the DVUI binary.

**Try the demo (no fork required):**

```bash
git clone https://github.com/elcoosp/zsx
cd zsx
zig build test       # 130+ tests through the whole pipeline
zig build example    # headless stub demo — prints widget counts
```

**Open a real window:**

```bash
zig build build-app-dvui -Dreal=true      # needs SDL3 + freetype (brew install sdl3 freetype)
./zig-out/bin/zsx-hello-dvui

zig build build-app-nanoui -Dreal=true    # macOS only; renders through Metal
./zig-out/bin/zsx-hello-nanoui
```

Both binaries render the same 20-component playground defined once in `src/views/playground.zsx`.

**See the fetchable path end-to-end:**

```bash
cd examples/consumer
zig build run
```

That project declares `zsx` as a `.path` dependency in its `build.zig.zon`, calls `zsx.addViews(b, opts)` in its `build.zig`, imports generated views via `@import("home")` and `@import("about")`, and runs. Its `src/` contains only `.zsx` files — no generated `.zig` on disk.

## Not quite TSX

`zsx!{ <markup> }` is **not** Zig syntax. A `.zsx` file cannot be handed to `zig build-exe` directly. The pipeline is:

```
src/views/home.zsx        ← Zig outer, zsx!{ markup } blocks inside
        │
        │ zsx-gen (build-time host binary)
        │ reads via std.Io.Dir, preprocesses, emits
        ▼
.zig-cache/<hash>/home.zig  ← plain Zig, the only file Zig compiles
        │
        │ b.createModule({ .root_source_file = out_path })
        ▼
  @import("home") in your app
```

`zsx!{ }` blocks are scanned by the preprocessor, parsed as a markup AST, and rewritten into `ui.column(c, .{...})`, `ctx.Button(ui, c, .{...})`, or `shadcn.Button(ctx, ui, c, .{...})` calls. Zig never sees markup.

Closest mainstream analog: **Svelte** or **Vue SFC** (`.svelte` / `.vue` → `.js`), or **SCSS** (`.scss` → `.css`), not TSX. TSX works because TypeScript's own parser understands JSX. True TSX parity would require a Zig compiler change, out of scope for ZSX.

What this buys: release binaries contain zero parser, zero interpreter, zero markup — only the builder calls a hand-written view would produce.

## Use as a dependency

Add `zsx` to `build.zig.zon`:

```zig
.dependencies = .{
    .zsx = .{
        .url = "git+https://github.com/elcoosp/zsx#v0.3.0",
        .hash = "zsx-0.3.0-AAAA...",
    },
},
```

Call `zsx.addViews` from `build.zig`:

```zig
const zsx = @import("zsx");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const shadcn_mod = b.createModule(.{
        .root_source_file = b.path("src/lib/shadcn.zig"),
        .target = target, .optimize = optimize,
    });

    const views = zsx.addViews(b, .{
        .paths = &.{ "src/views/home.zsx", "src/views/about.zsx" },
        .target = target,
        .optimize = optimize,
        .imports = &.{.{ .name = "shadcn", .module = shadcn_mod }},
    });

    const app = b.createModule(.{
        .root_source_file = b.path("src/main.zig"),
        .target = target, .optimize = optimize,
    });
    app.addImport("shadcn", shadcn_mod);
    for (views) |v| app.addImport(v.name, v.module);

    b.installArtifact(b.addExecutable(.{ .name = "app", .root_module = app }));
}
```

Import the generated views by name in `main.zig`:

```zig
const home = @import("home");
const about = @import("about");
```

Write `.zsx` files with **named imports only**:

```zsx
// src/views/home.zsx
const shadcn = @import("shadcn");

pub fn view(ui: anytype, c: anytype, ctx: anytype) void {
    zsx!{
        <column padding={8}>
          <shadcn.Button variant="primary">Get Started</shadcn.Button>
        </column>
    }
}
```

**One rule that changes from in-repo usage:** relative imports (`@import("../lib/shadcn.zig")`) do not work in external `.zsx` files. Generated `.zig` lives in `.zig-cache`, and `../` from there doesn't reach your source tree. Use named imports (`@import("shadcn")`), wired via `zsx.addViews(b, .{ .imports = ... })`.

See [`examples/consumer/`](examples/consumer/) for a working end-to-end project.

## Features

- **One pipeline.** `zsx.addViews` (external) or `zsx.addViewsLocal` (in-repo) builds `zsx-gen` — a small host executable from `src/gen.zig` — and runs it once per `.zsx`. `zsx-gen` reads the source, preprocesses `zsx!{ }` blocks into plain Zig, and writes `.zig` into `.zig-cache`. The compiler never sees markup. Release binaries carry no parser.

- **One source, three toolkits.** The same view renders through `src/adapters/dvui.zig` (dvui on SDL3), `src/adapters/nanoui.zig` (nanoui on Metal), and `src/adapters/html.zig` (plain HTML for the web). Each adapter implements the same primitive surface — `column`, `row`, `text`, `button`, `textEntry`, `textArea`, `checkbox`, `progress`, `divider`, `slider`, `toggle`, `skeleton` — and generated code only speaks that surface.

- **Control flow in markup, native code out.** `{if}`, `{:else if}`, `{:else}`, `{/if}`, `{for items as item}`, `{/for}`, `{switch expr}`, `{:case "val"}`, `{/switch}`, and `<>...</>` fragments lower to literal Zig `if`/`for`/if-else-if chains. Widget IDs in loops get stable strided arithmetic, so identity survives dynamic item counts. Old `{endif}`/`{endfor}`/`{endswitch}` forms still work as aliases.

- **Styling resolved at build time.** A Tailwind-named class subset (`bg-blue-500`, `p-4`, `gap-2`, `font-bold`, `rounded-lg`, ...) maps to concrete colors, spacing, and font values during code generation. An unrecognized class is a build error (`error.ZsxUnknownClass`), not a silently unstyled widget.

- **20 shadcn-inspired components.** `src/lib/shadcn.zig` defines `Button`, `Input`, `Textarea`, `Checkbox`, `Card`, `Section`, `Badge`, `Heading`, `Caption`, `Link`, `Progress`, `Divider`, `Slider`, `Switch`, and `Skeleton` as pure compositions of adapter primitives.

- **Named slots.** `<Card><Slot name="header">...</Slot><Slot name="body">...</Slot></Card>` compiles to an `.header` / `.body` fn field in the props struct. `Card` and `Section` iterate slots and call whichever are present.

- **Path-qualified tags.** `<shadcn.Button>` compiles to `shadcn.Button(ctx, ui, c, .{...})`. No `pub const Button` boilerplate on the context struct — the import at the top of the `.zsx` file is enough.

- **Pluggable style resolver.** `styleFromWith(el, resolver)` accepts any comptime resolver struct with `parseClasses` and `parseNumeric`. `DefaultResolver()` wraps the built-in class map; swap for your design system.

- **Source-span errors.** Parser errors cite `.zsx` file, line, column. Example: `src/views/dashboard.zsx:14:8: zsx: mismatched closing tag`.

## How it works

```
src/views/home.zsx
    │
    ├─ build.zig calls zsx.addViews / addViewsLocal
    │       │
    │       ├─ builds zsx-gen (host binary, from src/gen.zig)
    │       ├─ runs zsx-gen once per .zsx
    │       │       │
    │       │       ├─ src/rt/preprocess.zig — scan for zsx!{ } blocks
    │       │       ├─ src/rt/parser.zig    — parse markup into AST
    │       │       ├─ src/rt/codegen.zig   — walk AST, emit plain Zig
    │       │       └─ writes .zig-cache/<hash>/home.zig
    │       │
    │       └─ b.createModule({ .root_source_file = out_path })
    │
    ▼
@import("home") in your app
    │
    ▼
ui.column(c, .{...}) / ctx.Button(ui, c, .{...}) at runtime
    │
    ▼
adapter (dvui / nanoui / html) → widget calls
```

The runtime pipeline in `src/rt/` is the only pipeline. It runs at build time, not at runtime — the release binary contains only the builder calls a hand-written view would produce.

## Usage

A `.zsx` file is a Zig file with `zsx!{ <markup> }` blocks:

```zsx
const shadcn = @import("shadcn");

pub fn view(ui: anytype, c: anytype, ctx: anytype) void {
    zsx!{
        <column padding={16} class="gap-2">
          {if ctx.show_save}
            <button class="bg-blue-500 text-white px-4 py-2" on_click={ctx.save()}>Save</button>
          {:else}
            <label class="text-gray-500">No actions</label>
          {/if}
          {for ctx.items as item}
            <shadcn.Badge color="green">{item}</shadcn.Badge>
          {/for}
        </column>
    }
}
```

The generator produces plain Zig (in `.zig-cache`, not source tree):

```zig
pub fn view(ui: anytype, c: anytype, ctx: anytype) void {
    {
        var b_0 = ui.column(c, .{.id_extra = 0, .padding = .{ .x = 16, .y = 16, .w = 16, .h = 16 }, .gap = 8});
        defer b_0.end();
        if (ctx.show_save) {
            if (ui.button(c, "Save", .{.id_extra = 1, .color_fill = .{ .r = 59, .g = 130, .b = 246, .a = 255 }, .color_text = .{ .r = 255, .g = 255, .b = 255, .a = 255 }, .padding = .{ .x = 16, .y = 8, .w = 16, .h = 8 }})) ctx.save();
        } else {
            ui.text(c, "No actions", .{.id_extra = 2, .color_text = .{ .r = 107, .g = 114, .b = 128, .a = 255 }});
        }
        for (ctx.items, 0..) |item, idx_0| {
            ctx.Badge(ui, c, .{.id_extra = 3 + idx_0 * 1000000, .color = "green", .text = item});
        }
    }
}
```

The grammar is a strict subset of HTML with Zig in braces:

| Construct | Example |
|---|---|
| Layout primitive | `<column>`, `<row>`, `<label>`, `<button>` |
| Self-closing component | `<Input buffer={&ctx.name} placeholder="Your name" />` |
| Path-qualified component | `<shadcn.Button variant="primary">Save</shadcn.Button>` |
| Bare component (via Ctx) | `<Button variant="primary">Save</Button>` |
| Named slot | `<Card><Slot name="header"><Heading>Title</Heading></Slot></Card>` |
| Boolean attribute | `<column flex />` |
| Value attribute | `<column padding={16} />` |
| String attribute | `<label class="text-lg font-bold">` |
| Text expression | `<label>{item}</label>` |
| Conditional | `{if ctx.flag}...{:else if other}...{:else}...{/if}` |
| Loop | `{for ctx.items as item}...{/for}` |
| Switch | `{switch ctx.status}{:case "ok"}...{:else}...{/switch}` |
| Fragment | `<>...</>` |

Click handlers must be `on_click={ctx.method()}`; the emitter rewrites them to `@field(@TypeOf(ctx.*), "method")` for dispatch through the context pointer. Bare text inside `<column>` or `<row>` is rejected — wrap in `<label>`. Components accept text children, lowered to `text` calls.

**Bare tags** (`<Button>`) resolve through the context struct: `ctx.Button(ui, c, .{...})`. For these, declare `pub const Button = @import("shadcn").Button;` on your `Ctx` struct. **Path tags** (`<shadcn.Button>`) resolve through a file-level import: `shadcn.Button(ctx, ui, c, .{...})`. No `Ctx` boilerplate needed.

Wire your app with a context struct, an adapter, and the generated view. Excerpt from `src/hello_dvui.zig`:

```zig
const dvui = @import("dvui");
const playground = @import("playground");
const adapter = @import("adapters/dvui.zig");

const Ctx = struct {
    pub const Button = @import("shadcn").Button;
    pub const Input = @import("shadcn").Input;
    // one decl per bare component the view uses

    name: [64]u8 = @splat(0),
    remember: bool = false,
    completion: f32 = 0.42,
};

var g_ctx: Ctx = .{};
const A = adapter.Adapter(dvui);

fn frame() !dvui.App.Result {
    // ... window setup ...
    playground.view(A, win, &g_ctx);
    return .ok;
}
```

To add a view: create `src/views/your_view.zsx`, add its path to `zsx_files` in `build.zig`, run `zig build test`. `_gen.zig` never appears in source tree — the module is available as `@import("your_view")`. See [docs/components.md](docs/components.md) for component details and per-backend limitations.

## Formatting

`zsx fmt` reformats the markup inside `zsx!{ }` blocks. Zig code outside blocks is preserved byte-for-byte. Idempotent.

```bash
zig build cli                         # installs zig-out/bin/zsx
zsx fmt                               # dry-run: list files that need formatting
zsx fmt --write                       # apply
zsx fmt --check                       # exit 1 if anything needs formatting (CI-friendly)
```

From this repo without installing: `zig build zsx -Dcmd=fmt -Dcmd-args=--check`.
M0 wraps `scripts/zsx-fmt.py`; the native implementation lands in M1.

What it normalizes:
- 4-space indentation per nesting level inside `zsx!{ }` blocks
- Bodies of `{if}`, `{for}`, `{switch}` get +1 indent
- `{/if}`, `{/for}`, `{/switch}`, `{:else}`, `{:case}`, `</>` adjust accordingly
- Trailing whitespace stripped
- Leading/trailing blank lines in blocks removed

## Validation

`zsx check` validates `.zsx` structure (balanced tags, control-flow nesting) in **<100ms**, without compiling. Catches errors `zig build test` takes ~30s to surface.

```bash
zsx check                # validate all .zsx in repo
zsx check file.zsx       # validate one file
```

From this repo: `zig build zsx -Dcmd=check`. M0 wraps `scripts/zsx-check.py`.

Detects:
- `<column>...</row>` — mismatched close
- `<column>` never closed
- `{if}` without `{/if}`
- `{:case}` outside `{switch}`
- `{:else}` outside `{if}` / `{switch}`
- Unknown CSS classes (warning)

Exit codes: 0 clean, 1 structural errors found.

Both scripts run on every push via CI.

## Contributing

Working on ZSX itself — the emitter, adapters, or components — follows the same flow as any Zig project:

```bash
zig build test                        # run full test suite
zig build example                     # headless stub demo, prints widget counts
zig build example-nanoui              # nanoui stub demo, prints widget counts
zig build build-app-dvui -Dreal=true              # build real DVUI binary
zig build build-app-nanoui -Dreal=true            # build real Nanoui binary
zig build snapshot                    # generate playground screenshot (macOS)
```

**Structure:**

| Path | Purpose |
|---|---|
| `src/rt/parser.zig` | recursive-descent parser for `.zsx` markup |
| `src/rt/preprocess.zig` | scan Zig source for `zsx!{ }` blocks |
| `src/rt/codegen.zig` | walk AST, emit plain Zig |
| `src/rt/style.zig` | class name → Style struct |
| `src/gen.zig` | `zsx-gen` CLI entry point |
| `zsx.zig` | `addViews` / `addViewsLocal` build helpers |
| `src/lib/shadcn.zig` | 20 components |
| `src/lib/style.zig` | strict class parser (`!Style`) |
| `src/adapters/dvui.zig` | DVUI on SDL3 |
| `src/adapters/nanoui.zig` | Nanoui on Metal |
| `src/adapters/html.zig` | plain HTML + inline styles |
| `src/views/*.zsx` | demo views |
| `examples/consumer/` | fetchable-path example |

**Adding a component** goes in `src/lib/shadcn.zig` as an `inline fn`. Public functions with a `self: anytype` first parameter work as both bare tags (`<Button>` via `ctx.Button`) and path tags (`<shadcn.Button>` via `shadcn.Button`).

**Adding an adapter** goes in `src/adapters/<name>.zig`, implementing the same primitive surface as the existing three. No registry, no plugin loader — import at the callsite.

## Status

> [!NOTE]
> Version **0.3.0**, tagged and released. The single runtime pipeline is the only pipeline; the earlier comptime pipeline was removed in `v0.2.0`; M0 ground-truth tooling landed in `v0.3.0`. The `.zsx` grammar and the adapter primitive surface may still change between 0.x releases.
>
> Targets Zig **0.17.0+**, tested on 0.17.1 across ubuntu-latest and macos-latest. Both real binaries build on macOS every push; Nanoui is macOS-only (Metal), DVUI needs SDL3 and freetype.
>
> **Production-ready:** the fetchable path (`zsx.addViews` in a consumer's `build.zig`) — see `examples/consumer/`.
>
> **Tooling:** `zsx fmt` (reformat `.zsx` markup, idempotent) and `zsx check` (validate structure in <100ms) via `zig build zsx -Dcmd=fmt` / `zig build zsx -Dcmd=check`; the underlying Python scripts are deprecated and will be replaced in M1. `scripts/init.sh` is the one-command project scaffold.
>
> **M0 gates:** `zig build check-meta`, `zig build check-docs`, `zig build golden`, and `zig build bench-smoke` run in CI. Memory files live in [AGENTS.md](AGENTS.md) and [docs/STATE.md](docs/STATE.md).
>
> **Not yet:** `examples/todo/` on a real DVUI window (currently stub-only); tree-sitter grammar for `.zsx` syntax highlighting; routing between screens (deliberately out of scope — use `{switch}` on a `ctx.screen` enum).
>
> Known limitations, all listed in [docs/components.md](docs/components.md): class strings must be build-time constants, `m-*` margin classes are rejected, DVUI headings fall back to the theme font weight, and Nanoui ignores `id_extra` on checkboxes.

## Learn more

- [docs/components.md](docs/components.md) — API reference for all 20 components, with examples and per-backend notes.
- [TEMPLATE.md](TEMPLATE.md) — fetchable-vs-fork decision tree.
- [ROADMAP.md](ROADMAP.md) — shipped items, rejected designs, remaining work.
- [CHANGELOG.md](CHANGELOG.md) — what shipped in each release.
- [docs/zig-skill.md](docs/zig-skill.md) — Zig 0.17 compiler errors and fixes discovered while building this.
- [`examples/consumer/`](examples/consumer/) — minimal fetchable project.
