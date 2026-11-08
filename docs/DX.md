# Developer experience

## Editor setup

`.zsx` files are Zig files with `zsx!{ <markup> }` blocks. Editors give them Zig syntax highlighting if you set the association:

- **VS Code / Cursor**: shipped in `.vscode/settings.json`
- **Zed**: shipped in `.zed/settings.json`
- **Other editors**: associate `*.zsx` with Zig

`.zls.json` disables build-on-save. The full pipeline (`parse → emit → compile → link → test`) is too slow to run on every keystroke. Run `zig build test` manually when you want validation.

## In-repo development

```bash
zig build test                # full pipeline (~130 integration tests)
zig build example             # headless stub demo, prints widget counts
zig build example-nanoui      # nanoui stub demo
zig build build-app-dvui      # needs SDL3 + freetype
zig build build-app-nanoui    # macOS only, Metal
zig build snapshot            # playground screenshot via nanoui tester
```

No `_gen.zig` files appear on disk. Generated views live in `.zig-cache` and are exposed as named modules — `@import("playground")`, `@import("demo")`, etc. `.gitignore` has no generated-file entries because nothing generated lands in source tree.

## External consumer development

A consumer project depends on `zsx` in `build.zig.zon`, calls `zsx.addViews(b, opts)` from `build.zig`, and imports views by name in `main.zig`. See `examples/consumer/` for a working example.

**One rule that changes from in-repo usage:** `.zsx` files use named imports (`@import("shadcn")`), not relative paths. Generated `.zig` lives in `.zig-cache`, and `../` from there doesn't reach your source tree.

## What's on disk

| Path | Committed | In editor | Created by |
|---|---|---|---|
| `src/views/*.zsx` | yes | yes | you |
| `.zig-cache/` | no | hidden by editor configs | `zig build` |
| `zig-out/` | no | hidden by editor configs | `zig build` |
| `zig-pkg/` | no | hidden by editor configs | `zig fetch` |

No generated `.zig` files. Ever. Neither for in-repo work nor external consumption.
