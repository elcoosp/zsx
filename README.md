

## Not quite TSX

`zsx!{ <markup> }` is **not** Zig syntax. The Zig compiler has never heard of `zsx!{` — a `.zsx` file cannot be handed to `zig build-exe` directly.

```
src/views/demo.zsx      input to the preprocessor
        v
src/views/demo_gen.zig  expanded to plain Zig at build time
        v               (this is the only file Zig compiles)
   test / binary
```

`src/preprocess.zig` scans for `zsx!{ ... }` blocks, parses the markup at comptime, and emits plain `ui.column(c, .{...})` / `ctx.Button(ui, c, .{...})` calls. Zig never sees markup.

Closest mainstream analog: **Svelte** or **Vue SFC** (`.svelte` / `.vue` → `.js`), or **SCSS** (`.scss` → `.css`), not TSX. TSX works because TypeScript's own parser understands JSX. True TSX parity would need a Zig compiler change, out of scope.

## Not quite TSX

`zsx!{ <markup> }` is **not** Zig syntax. The Zig compiler has never heard of `zsx!{` — a `.zsx` file cannot be handed to `zig build-exe` directly.

```
src/views/demo.zsx      input to the preprocessor
        v
src/views/demo_gen.zig  expanded to plain Zig at build time
        v               (this is the only file Zig compiles)
   test / binary
```

`src/preprocess.zig` scans for `zsx!{ ... }` blocks, parses the markup at comptime, and emits plain `ui.column(c, .{...})` / `ctx.Button(ui, c, .{...})` calls. Zig never sees markup.

Closest mainstream analog: **Svelte** or **Vue SFC** (`.svelte` / `.vue` → `.js`), or **SCSS** (`.scss` → `.css`), not TSX. TSX works because TypeScript's own parser understands JSX. True TSX parity would need a Zig compiler change, out of scope.

