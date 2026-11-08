# Todo — real app example

A working todo app: form input, validation, list rendering, disk persistence. Built on the fetchable zsx pipeline — no fork, no `_gen.zig` in source tree.

## Run it

```bash
cd examples/todo
zig build run
```

**Expected output:**

```
loaded: 0 items

=== Step 1: render empty ===
labels=4 buttons=3 dividers=2

=== Step 2: add empty (error) ===
error: empty text
labels=5 (error badge adds 1)

=== Step 3: add items ===
store.len=3, next_id=4
rendered: labels=7 buttons=3

=== Step 4: UI click on Add ===
after click: store.len=4 buttons=3

=== Step 5: save ===
saved to todos.json

=== Step 6: reload from disk ===
reloaded: 4 items
  [1] Buy milk done=false
  [2] Walk dog done=false
  [3] Write tests done=false
  [4] Read book done=false

=== All steps complete ===
```

**Second run** loads the previous state — persistence works.

## Structure

```
examples/todo/
├── build.zig.zon          ← zsx as .path dependency
├── build.zig              ← zsx.addViews(b, opts)
└── src/
    ├── main.zig           ← 6-step verification + 6 unit tests
    ├── store.zig          ← persistence (load/save JSON)
    ├── stub.zig           ← adapter with queued clicks
    ├── shadcn.zig         ← 6 components (Heading, Caption, Badge, Button, Input, Divider)
    └── views/
        └── todo.zsx       ← form + list + actions
```

`todos.json` is created in the CWD on save. `.gitignore` excludes it.

## What this proves

- **Form input** — `<Input buffer={&ctx.new_text} />` two-way binding works
- **Validation** — `ctx.add()` catches empty/too-long/full, sets an error badge
- **Conditional rendering** — `{if ctx.last_error.len > 0}`, `{if ctx.store.len == 0}`
- **List rendering** — `{for ctx.store.items[0..ctx.store.len] as item}` over a runtime slice
- **Expression children** — `{ctx.itemText(item)}`, `{ctx.itemColor(item)}` (function calls, not just field reads)
- **Component dispatch** — `<shadcn.Badge>` calls `shadcn.Badge(ctx, ui, c, ...)` correctly
- **Event handling** — `on_click={ctx.add()}` fires when adapter returns `true`
- **Persistence** — `store.saveJson` / `store.loadJson` with real `std.Io.Dir` I/O
- **Fetchable** — `build.zig.zon` uses `.path = "../.."`, `@import("todo")` for the generated view

## Known limitations

- **Per-item actions** — the current `on_click` grammar only supports `ctx.method()` (no arguments). Deleting one specific item via a row button isn't expressible in markup. Workaround: a "Clear done" button that operates on all done items, plus programmatic calls from `ctx` for per-item actions.

Adding `<Button on_click={ctx.remove(item.id)}>` requires either:
- Emitter change: pass `item.id` through as a closure
- Context change: a `pending_action_id` field set by a row-click handler

Neither is in v0.1.0. Documented as a limitation.

## Swap the stub for a real adapter

`stub.zig` records calls to stdout. To render on a real DVUI window:

1. Add the DVUI adapter import to `build.zig` (see `../../build.zig`)
2. Replace `stub.Adapter` with `dvui_adapter.Adapter(dvui)` in `main.zig`
3. Open a window (see `../../src/hello_dvui.zig` for the frame loop)

The view (`views/todo.zsx`) requires no changes.
