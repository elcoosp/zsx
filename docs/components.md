# ZSX Components

Ten components ship with ZSX. Each is a Zig inline function callable from
generated code as `<Component>...</Component>` in `.zsx` markup.

All components are pure compositions of framework primitives — no
framework-specific code in the component definitions themselves. Each
framework adapter (`src/adapters/dvui.zig`, `src/adapters/nanoui.zig`)
implements the underlying primitives (`text`, `button`, `textEntry`, etc.).

## Layout

### `Column`

Vertical stack. Children compose normally.

```zsx
<column padding={16} class="gap-2">
  <Heading>Title</Heading>
  <Caption>Subtitle</Caption>
</column>
```

Accepts `padding={n}`, `class` (Tailwind subset), `flex` (expand).

### `Row`

Horizontal stack. Same attributes as `Column`.

```zsx
<row class="gap-2">
  <Button variant="primary">OK</Button>
  <Button variant="secondary">Cancel</Button>
</row>
```

## Typography

### `Heading`

Bold heading text. Sizes 1-6 map to font sizes 24/20/18/16/14/12.

```zsx
<Heading size={1}>Page Title</Heading>
<Heading size={2}>Section</Heading>
```

Attributes: `size={n}` (1-6), `class`, `color`.

Renders correctly on Nanoui. On DVUI, font size is mapped through
`Style.font_size` → `dvui.Font.size` but weight falls back to the theme
default (documented limitation of the DVUI adapter).

### `Caption`

Small muted text. Renders gray (#6b7280) at 12pt.

```zsx
<Caption>Helper text</Caption>
```

### `Link`

Blue inline text, semantically a link. No URL — just styling.

```zsx
<Link>Read the docs</Link>
```

Use `on_click` on a wrapping button if navigation is needed.

## Data display

### `Badge`

Colored text label. Color names: `red`, `green`, `blue`, default.

```zsx
<Badge color="green">stable</Badge>
<Badge color="red">error</Badge>
```

Colored text only — no pill background. Wrap in a styled `<row>` if a pill
shape is needed.

## Forms

### `Input`

Single-line text field. Binds a `[]u8` buffer on the context.

```zsx
<Input buffer={&ctx.name} placeholder="Your name" />
```

The buffer must be `[N]u8 = @splat(0)`. The adapter manages edit state:
on Nanoui, a `TextBuffer` cache keyed by widget ID persists across frames;
on DVUI, `TextEntryWidget` handles its own state.

### `Textarea`

Multi-line text field. Same buffer semantics as `Input`.

```zsx
<Textarea buffer={&ctx.notes} placeholder="Notes..." />
```

DVUI's `TextEntryWidget` handles multiline natively. Nanoui uses `textArea`
with the same `TextBuffer` cache as `Input`.

### `Checkbox`

Boolean toggle with label. Binds a `*bool`.

```zsx
<Checkbox checked={&ctx.remember} text="Remember me" />
```

On DVUI: `dvui.checkbox(src, *bool, title, opts)`. On Nanoui:
`ui.checkbox(c, title, *bool)`. `id_extra` is accepted by the adapter but
silently ignored on Nanoui (its checkbox widget takes no options struct).

## Actions

### `Button`

Clickable button with optional click handler. Variants control color.

```zsx
<Button variant="primary" on_click={ctx.save()}>Save</Button>
<Button variant="secondary">Cancel</Button>
<Button variant="danger">Remove</Button>
```

Attributes: `variant` (primary/secondary/ghost/danger), `on_click` (method
reference `ctx.method()`), `class`.

On Nanoui, variant maps to `ui.ButtonOptions.variant` directly. On DVUI,
the adapter maps `color_fill` values to variants (blue→primary,
red→danger) since dvui has no variant enum.

### `Card`

Container with padding, rounded corners, and a content function.

```zsx
<Card>
  <Caption>Card content goes here.</Caption>
  <Link>Learn more</Link>
</Card>
```

Passes an `id_extra` to the inner box, so multiple Cards stack correctly.

### `Section`

Card variant with a heading title. Uses an inline heading, not the
`Heading` component, to avoid type-unification issues with `**Ctx`.

```zsx
<Section title="Forms">
  <Input buffer={&ctx.name} placeholder="Name" />
</Section>
```

## Path-qualified tags

Besides bare `<Button>` / `<Badge>` (which resolve via `ctx.Button` /
`ctx.Badge`), the emitter also accepts dotted tag names that reference a
Zig module directly:

```zsx
const shadcn = @import("../lib/shadcn.zig");

pub fn view(ui: anytype, c: anytype, ctx: anytype) void {
    zsx!{
        <column padding={8}>
          <shadcn.Button variant="primary">Save</shadcn.Button>
          <shadcn.Badge color="green">ok</shadcn.Badge>
        </column>
    }
}
```

The emitter lowers `<shadcn.Button ...>` to `shadcn.Button(ctx, ui, c, .{...})`
— the module's function receives `ctx` as its first argument (`self`),
matching every shadcn component's signature. The rest follows the bare-tag
rules: text children become `.text = "..."`, `on_click` becomes
`@field(@TypeOf(ctx.*), "method")`, and element children cause a
`render_<sanitized_tag>_<id>` helper to be hoisted above `view`.

Advantages over bare tags:

- **No `Ctx` boilerplate.** You do not need `pub const Button = @import("lib/shadcn.zig").Button;` on every context struct. The import lives at the top of the `.zsx` file.
- **Real Zig resolution.** `@import("../lib/shadcn.zig")` is the same mechanism any `.zig` file uses. Typos surface as ordinary compile errors.
- **Mix libraries.** Different `.zsx` files can import different component libraries.

Both forms are supported simultaneously; migration is incremental.

## Path-qualified tags

Besides bare `<Button>` / `<Badge>` (which resolve via `ctx.Button` /
`ctx.Badge`), the emitter also accepts dotted tag names that reference a
Zig module directly:

```zsx
const shadcn = @import("../lib/shadcn.zig");

pub fn view(ui: anytype, c: anytype, ctx: anytype) void {
    zsx!{
        <column padding={8}>
          <shadcn.Button variant="primary">Save</shadcn.Button>
          <shadcn.Badge color="green">ok</shadcn.Badge>
        </column>
    }
}
```

The emitter lowers `<shadcn.Button ...>` to `shadcn.Button(ctx, ui, c, .{...})`
— the module's function receives `ctx` as its first argument (`self`),
matching every shadcn component's signature. The rest follows the bare-tag
rules: text children become `.text = "..."`, `on_click` becomes
`@field(@TypeOf(ctx.*), "method")`, and element children cause a
`render_<sanitized_tag>_<id>` helper to be hoisted above `view`.

Advantages over bare tags:

- **No `Ctx` boilerplate.** You do not need `pub const Button = @import("lib/shadcn.zig").Button;` on every context struct. The import lives at the top of the `.zsx` file.
- **Real Zig resolution.** `@import("../lib/shadcn.zig")` is the same mechanism any `.zig` file uses. Typos surface as ordinary compile errors.
- **Mix libraries.** Different `.zsx` files can import different component libraries.

Both forms are supported simultaneously; migration is incremental.

## Component authoring

To add a component, define an inline function in `src/lib/shadcn.zig`:

```zig
pub inline fn MyComponent(self: anytype, ui: anytype, c: anytype, props: anytype) void {
    _ = self;
    // props has all attributes + .text from children
    // call ui.* primitives
    ui.text(c, props.text, .{});
}
```

Then add re-export to every consumer `Ctx`:

```zig
const Ctx = struct {
    // ...
    pub const MyComponent = @import("lib/shadcn.zig").MyComponent;
};
```

No codegen changes needed. The codegen already treats uppercase tags as
component calls: `<MyComponent prop={x}>text</MyComponent>` becomes
`ctx.MyComponent(ui, c, .{ .prop = x, .text = "text" })`.

## Known limitations

- **DVUI font weight**: `Heading` renders at correct size but theme-default
  weight. Adapter maps size, not weight.
- **Nanoui checkbox id_extra**: silently ignored. No options struct on the
  nanoui widget.
- **Margins**: `m-*` classes raise `@compileError`. `Style` has no `margin`
  field; use a wrapping row with padding instead.
- **Dynamic classes**: class strings must be comptime-known. Runtime class
  expressions compile-error.
