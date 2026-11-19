# ADR 0004 — Event handlers v1: arbitrary expressions + loop capture

- Status: accepted
- Date: 2026-11-14
- Work package: M2 WP 2.6 (event system, first slice)

## Context

Markup event props were limited to `on_click={ctx.method()}`. The codegen
rewrote that exact shape into `@field(@TypeOf(ctx.*), "method")` and rejected
everything else (`normalizeClickHandler`). This blocks the common cases the
master plan calls out: arguments (`ctx.remove(item.id)`) and handlers emitted
inside `{for … as item}` (the handler must capture `item`). Attribute names
were only accepted in the `on_click` form, not `on:click`.

## Decision

1. **Namespaced event attributes.** `on:<event>` is accepted wherever
   `on_<event>` is. Colons in attribute names are normalized to `_` when
   emitted as struct fields, so `on:change` becomes `.on_change`.
2. **Handlers are callables, not rewritten method values.** For component
   props the generator emits either
   - a hoisted `inline fn render_handler_<base>_<slot>(ctx) void` when the
     expression captures no loop locals, or
   - a container-level generic capture factory
     `ZsxHandler_<base>_<slot>(comptime T…) type` returning a struct with the
     captured fields and `pub inline fn call(self, ctx) void`, constructed at
     the call site (same technique as content/slot bodies, ADR 0003).
   The expression body is kept verbatim; no AST rewriting of the Zig code.
3. **Consumers invoke through a helper.** `shadcn.invokeHandler(f, self)` calls
   `f.call(self)` for structs and `f(self)` for functions. `shadcn.Button` and
   the test-local Button use it. Intrinsic `<button on:click={expr}>` continues
   to emit `if (ui.button(...)) expr;`, which already supports arguments and
   in-scope loop locals.
4. **Captures are chosen by identifier-token scan** over the expression
   (`mentionsIdentifier`), never by substring search.

## Consequences

- `on:click={ctx.remove(item)}`, `on:click={std.debug.print(...)}` and
  handler-in-loop compile and run on the stub backend (`event_args_demo`).
- Custom components must use `invokeHandler` (or replicate the struct check)
  to accept capture-struct handlers; plain function handlers keep working
  unchanged, so existing `props.on_click(self)` call sites are source
  compatible only if they use the helper.
- Deferred to a later slice of WP 2.6: bare method references
  (`on:change={ctx.setName}`), a zero-allocation `Callback(T)` type, and
  adapter wiring for `change`/`input`/`submit`/`key`/`focus`/`hover`/`drag`.
  Those allow reading the field but the adapters do not emit the events yet.

## Alternatives considered

- **Closures in Zig:** not part of the language; capture structs are the
  idiomatic zero-allocation substitute.
- **Struct/function union type:** Zig has no anonymous sum type for callables;
  a `call`-method probe at comptime is cheaper and keeps generated types
  monomorphic.
