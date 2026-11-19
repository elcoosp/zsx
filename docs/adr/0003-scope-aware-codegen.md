# ADR 0003 — Scope-aware codegen: stable IDs, one control-flow lowering, capture structs

- **Status:** accepted (M2 work packages 2.2, 2.3, 2.4)
- **Date:** 2026-11-14
- **Supersedes/closes:** master-plan findings F1, F2, F3

## Context

The v0.2 generator carried three latent defects that blocked every later
codegen milestone:

- **F1 — widget-ID arithmetic overflow.** IDs were
  `(file_index * BLOCK_STRIDE + block) * FILE_STRIDE + base`, which overflows
  `usize` at roughly 184 `.zsx` files and makes identity depend on the order of
  `.paths` in `build.zig`.
- **F2 — duplicated control-flow lowering.** `emitChildren` and
  `emitContentChildren` were near-copies; the latter hard-coded `idx_0` and loop
  depth 0, so nested loops inside a slot collided on widget identity.
- **F3 — slot/content bodies could not capture locals.** Hoisted
  `inline fn render_*(ui, c, ctx)` helpers only received those three
  parameters, so a child inside `{for … as item}` that referenced `item` could
  not compile.

## Decision

### 1. Stable, hash-based node IDs (F1)

`id = @truncate(hash64(src_key, block_index, structural_path))`, where
`src_key` is the source path as written in the build list — never its index.
Loop indices are mixed in with wrapping (`+%`, `*%`) arithmetic and the result
is truncated to `usize`, so deep loops cannot overflow and 32-bit (wasm)
targets still compile. Reordering `.paths` no longer renames widgets.

`codegen.stableNodeId(src_key, block_index, path_index)` is the exported
primitive; `FILE_STRIDE`/`BLOCK_STRIDE`/`LOOP_STRIDE_*` are gone.

### 2. One control-flow lowering (F2)

`emitChildren` is the only lowering. It takes a `TextMode` (element bodies
reject raw text; slot/content bodies render it) and maintains a dynamic stack
of `Loop { value, index }` scopes. Loop depth is unbounded; each nested loop gets
its own `idx_N` name. `emitContentChildren` is deleted.

### 3. Capture structs for slot/content bodies (F3)

When a component body is emitted while loop locals are in scope, the body is no
longer hoisted. Instead the generator emits a container-level generic factory:

```zig
fn ZsxBody_7(comptime T0: type, T1: type) type {
    return struct {
        item: T0,
        idx_0: T1,
        pub inline fn call(self: @This(), ui: anytype, c: anytype, ctx: anytype) void {
            const item = self.item;
            const idx_0 = self.idx_0;
            // body, using item / idx_0 normally
        }
    };
}
```

and constructs the value at the call site:

```zig
ctx.Card(ui, c, .{ .body = ZsxBody_7(@TypeOf(item), @TypeOf(idx_0)){
    .item = item, .idx_0 = idx_0,
} });
```

Only captures the body actually mentions are stored (identifier-token scan —
the one analysis WP 2.3 permits). Bodies with no surrounding loop locals remain
plain hoisted `inline fn render_*`, so existing components and generated
goldens are unchanged in that case.

The factory lives at container scope on purpose: its `call` method may alias
`const item = self.item;` without shadowing the view's parameters (Zig rejects
shadowing across nested scopes). A *local* struct would have triggered
`parameter 'ui' shadows function parameter from outer scope`.

### 4. Slot protocol accepts both callables

`shadcn.invokeSlot(f, ui, c, self)` calls `f(ui, c, self)` for a plain function
and `f.call(ui, c, self)` for a capture struct. `Card`, `Section`, and `Tabs`
use it. Existing user components keep working because the no-capture path is
still a function; only the new capture path yields a struct value.

## Consequences

- F1/F2/F3 reproducers in `src/tests/reproducers.zig` now assert the fixed
  behaviour; `src/tests/views.zig` covers both cases end-to-end via
  `slot_capture_demo.zsx` (capture) and `slot_loop_demo.zsx` (nested loops).
- Goldens change: IDs are now hashes and loop IDs use wrapping arithmetic.
- `preprocess.preprocess` keeps its `file_index` parameter for API stability but
  ignores it.
- Future work (WP 2.3 full scope) extends captures to `{let}` bindings and Zig
  locals from the S1 scanner; the factory shape already accommodates them.
