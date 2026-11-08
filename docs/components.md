# ZSX Components

Fifteen components ship with ZSX. Each is a Zig inline function callable from
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

## Feedback and loading

### Progress

Horizontal progress bar. Takes a `value` in `[0.0, 1.0]`.

```zsx
<Progress value={ctx.completion} />
```

Calls `ui.progress(c, value, .{})`. Adapters clamp out-of-range values.

### Divider

Thin horizontal rule, useful between `Section`s.

```zsx
<Divider />
```

Calls `ui.divider(c, .{})`. Takes no attributes.

### Skeleton

Loading placeholder rectangle. Accepts `width`, `height`, `radius` (numeric).

```zsx
<Skeleton width={320} height={24} />
<Skeleton width={220} height={16} radius={4} />
```

Backed by `ui.skeleton(c, opts)`; each adapter decides the visual (flat grey or shimmer).

### Switch

Boolean toggle with label, visually distinct from `Checkbox`. Binds a `*bool`.

```zsx
<Switch checked={&ctx.notifications} text="Notifications" />
```

Maps to `ui.toggle(c, label, value, opts)`. On DVUI this is a checkbox with a toggle appearance; on Nanoui a native toggle widget.

### Slider

Continuous numeric input. Binds a `*f32` in `[0.0, 1.0]`.

```zsx
<Slider value={&ctx.volume} />
```

Calls `ui.slider(c, value, .{})`. The pointed-to `f32` is the current fraction; the backend updates it in place as the user drags.

## Path-qualified tags

Besides bare `<Button>` / `<Badge>` (which resolve via `ctx.Button` /
`ctx.Badge`), the emitter also accepts dotted tag names that reference a
Zig module directly:

```zsx
const shadcn = @import("shadcn");

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

- **No `Ctx` boilerplate.** You do not need `pub const Button = @import("shadcn").Button;` on every context struct. The import lives at the top of the `.zsx` file.
- **Real Zig resolution.** `@import("shadcn")` is the same mechanism any `.zig` file uses. Typos surface as ordinary compile errors.
- **Mix libraries.** Different `.zsx` files can import different component libraries.

Both forms are supported simultaneously; migration is incremental.

## Path-qualified tags

Besides bare `<Button>` / `<Badge>` (which resolve via `ctx.Button` /
`ctx.Badge`), the emitter also accepts dotted tag names that reference a
Zig module directly:

```zsx
const shadcn = @import("shadcn");

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

- **No `Ctx` boilerplate.** You do not need `pub const Button = @import("shadcn").Button;` on every context struct. The import lives at the top of the `.zsx` file.
- **Real Zig resolution.** `@import("shadcn")` is the same mechanism any `.zig` file uses. Typos surface as ordinary compile errors.
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
    pub const MyComponent = @import("shadcn").MyComponent;
};
```

No codegen changes needed. The codegen already treats uppercase tags as
component calls: `<MyComponent prop={x}>text</MyComponent>` becomes
`ctx.MyComponent(ui, c, .{ .prop = x, .text = "text" })`.

## HTML adapter

`src/adapters/html.zig` implements the same primitive surface as DVUI and Nanoui, but writes semantic HTML with inline styles. Useful for server-rendered views, static site generation, and testing.

**Usage:**

```zig
const html = @import("adapters/html.zig");
const A = html.Adapter(MyWriter);
// MyWriter needs: pub fn writeAll(self: *MyWriter, bytes: []const u8) !void
demo.view(A, &writer, &ctx);
// writer now holds HTML output
```

**Component behavior on HTML:**

| Component | Emits | Notes |
|---|---|---|
| `Button` | `<button>` | Always returns `false` (no click handling) |
| `Badge`, `Heading`, `Caption`, `Link` | `<span>` with inline styles | Text content escaped |
| `Input`, `Textarea` | `<input type="text">`, `<textarea>` | Value from buffer, escaped |
| `Checkbox`, `Switch` | `<input type="checkbox">` in `<label>` | Checked state rendered |
| `Progress` | `<progress>` | Clamped to 0-100 |
| `Slider` | `<input type="range">` | Step 0.01, range 0-1 |
| `Divider` | `<hr>` | None |
| `Skeleton` | `<div class="skeleton">` | Width/height as inline style |
| `Column`, `Row` | `<div class="flex flex-col/row">` | Classes for CSS frameworks |

**What's not supported:**

- **State.** Inputs render their current buffer value; there's no round-trip back. Server-rendered forms need their own submission handling.
- **Interactivity.** Buttons always return `false`. Click handlers are not attached.
- **Hover states.** `hover_background` is dropped.

**CSS.** The adapter emits `class="flex flex-col"` for columns, `class="flex flex-row"` for rows, `class="skeleton"` for skeletons. You provide the CSS. Inline styles fill in colors, padding, font-size.

**Testing.** `html.TestWriter` captures output as `[]const u8`:

```zig
test "demo view" {
    const A = html.Adapter(html.TestWriter);
    var w: html.TestWriter = .{};
    var ctx = Ctx{};
    demo.view(A, &w, &ctx);
    try std.testing.expect(std.mem.indexOf(u8, w.output(), ">Save</button>") != null);
}
```

## Known limitations

- **DVUI font weight**: `Heading` renders at correct size but theme-default
  weight. Adapter maps size, not weight.
- **Nanoui checkbox id_extra**: silently ignored. No options struct on the
  nanoui widget.
- **Margins**: `m-*` classes raise `@compileError`. `Style` has no `margin`
  field; use a wrapping row with padding instead.
- **Dynamic classes**: class strings must be comptime-known. Runtime class
  expressions compile-error.
