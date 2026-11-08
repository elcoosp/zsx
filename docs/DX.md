# Developer Experience

## On disk vs. what you see

| Path | Committed | Visible in editor | Created by |
|---|---|---|---|
| `src/views/*.zsx` | yes | yes | you write it |
| `src/views/*_gen.zig` | no (gitignored) | no (editor config hides it) | `zig build` regenerates from `.zsx` |
| `.zig-cache/` | no | no | Zig build cache |
| `zig-out/` | no | no | Zig build output |

The `.zsx` → `.zig` compilation happens at build time. `_gen.zig` files are intermediate artifacts — same role as `.js` files from `tsc` before they get gitignored, or `.css` from `.scss`.

## Why `_gen.zig` files are hidden

Opening `src/views/demo_gen.zig` shows the compiled output. That's useful when debugging the emitter itself, but 99% of the time it's noise. The editor configs shipped in this repo hide them from:

- File explorer
- Quick-open (Ctrl+P / Cmd+P)
- Global search
- File watchers

They're still on disk. `zig build test` finds them, ZLS resolves imports to them, `cat src/views/demo_gen.zig` from a terminal works. You just don't see them in the editor.

**Editors configured out of the box:**

| Editor | Config file |
|---|---|
| VS Code, Cursor, VSCodium, Windsurf | `.vscode/settings.json` |
| Zed | `.zed/settings.json` |
| IntelliJ, WebStorm, RustRover, GoLand | `.idea/.gitignore` |

For any other editor, add `**/*_gen.zig` to its file-exclude pattern. Full list of editors that support this: almost all modern ones.

## Fresh clone behavior

`_gen.zig` files don't exist after `git clone`. Before ZLS or the first build runs, `@import("views/demo_gen.zig")` will report "file not found" in the editor.

Resolution (automatic):

- `.zls.json` has `enable_build_on_save: true` — the first save of any file in the project triggers `zig build zsx` and every `_gen.zig` appears.
- Every `zig build <target>` depends on the `zsx` step — any build regenerates missing files.

Manual trigger (no editor):
```bash
zig build zsx
```

## Regeneration is automatic

Every build step depends on `zsx`:

| Command | Regenerates `_gen.zig` |
|---|---|
| `zig build test` | yes (regenerates first, then runs tests) |
| `zig build example` | yes |
| `zig build example-nanoui` | yes |
| `zig build build-app-dvui` | yes |
| `zig build build-app-nanoui` | yes |
| Editor save | yes (via `.zls.json`) |

You never need to remember to regenerate manually. Editing a `.zsx` file and running any target does the right thing.

## GitHub PRs

`.gitattributes` marks `*_gen.zig` as:
- `linguist-generated=true` — GitHub doesn't count them toward language stats
- `-diff` — GitHub collapses them in PR diffs

Since they're gitignored, they never appear in PRs anyway. The marker is defense-in-depth if someone force-adds one.

## Opting out

Two common cases:

### 1. Commit generated files

Some teams do this for easier review of the emitter's output. To opt in:

1. Delete `src/views/*_gen.zig` from `.gitignore`
2. `git add src/views/*_gen.zig`
3. (Optional) Delete `**/*_gen.zig` from `.vscode/settings.json` `files.exclude` so they show up in the editor

Everything else keeps working — nothing in the build system assumes the files are gitignored.

### 2. See generated files in the editor

Remove the `**/*_gen.zig` key from `.vscode/settings.json` `files.exclude` (or `.zed/settings.json` `file_scan_exclusions`). The files were always there — they just stop being hidden.

## Editor support summary

The `.zsx` file type is registered as Zig syntax highlight in both VS Code (`.vscode/settings.json`) and Zed (`.zed/settings.json`). Markup inside `zsx!{ ... }` won't get special highlighting — it's Zig highlight applied to Zig-shaped content — but the surrounding Zig gets correct colors.

For full `.zsx` highlighting (markup-aware), a proper tree-sitter grammar would need to ship. That's a separate, larger project (`ROADMAP.md` "Next C" territory, if anyone wants it).

## For external consumers (fetchable path)

When zsx is used as a dependency in another project, the comptime pipeline above doesn't apply. `zsx.addViews` runs `zsx-gen` at build time, and generated `.zig` files land in `.zig-cache`, not `src/views/`.

**What the consumer's `src/` contains:**

```
consumer/src/
├── main.zig         ← @import("home"), @import("about")
├── views/
│   ├── home.zsx     ← you write this
│   └── about.zsx    ← you write this
├── shadcn.zig       ← your component library
└── stub.zig         ← your adapter
```

No `_gen.zig`. No generated files in source tree. `.zig-cache/` regenerates on every build.

**One rule that changes from in-repo usage:**

Relative imports (`@import("../lib/shadcn.zig")`) break — generated files are in `.zig-cache/<hash>/<name>.zig`, and `../` from there doesn't reach your source tree.

Use named imports:

```zsx
const shadcn = @import("shadcn");   // ✓
```

Wire them via `zsx.addViews(b, .{ .imports = &.{ .{ .name = "shadcn", .module = shadcn_mod } } })`.

**Fresh clone of a consumer project:**

1. `git clone my-app`
2. First `zig build` triggers `zsx-gen` — every `.zig` in `.zig-cache` appears
3. Subsequent builds are cached

No manual regeneration step. The build step IS the editor's data source.

**See also:** [`examples/consumer/`](../examples/consumer/) for a working demo.
