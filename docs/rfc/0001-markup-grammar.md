# RFC 0001 — ZSX markup grammar v1

- **Status:** draft (normative working reference; acceptance tracked by WP 1.1)
- **Author(s):** ZSX maintainers
- **Created:** 2026-11-16
- **Target milestone:** M1
- **Related ADR(s):** [ADR 0002](../adr/0002-zig-version-policy.md),
  [ADR 0003](../adr/0003-scope-aware-codegen.md)

## Summary

This RFC fixes the syntax and semantics of the markup inside `zsx!{ … }`
blocks. The normative grammar is [docs/spec/grammar.ebnf](../spec/grammar.ebnf);
this document explains it, records the semantics codegen attaches to each
construct, and defines the error model the future CST parser and LSP must
share. The RFC describes what the compiler implements **today** rather than a
greenfield language, so passing its corpus is a compatibility requirement, not
a redesign.

## Motivation

Three front-ends currently read markup: the fail-fast `parser.zig`, the
tolerant `scan.zig`, and the formatting/checking logic built on both. They
agree by accident. That caused the findings in
[the master plan](../ZSX_MASTER_PLAN.md) counted as F5 (brace matching),
F11 (three parsers), and the legacy-alias drift the checker warns about.
A single written grammar lets M1 replace those front-ends with one CST parser
without renegotiating the language in code review, and gives the LSP, the
formatter, the codemod and the fuzzer one source of truth.

Without it, every new construct (`{let}`, snippets, attribute spread,
comments, expression-position blocks) is designed ad hoc, and syntax errors
surface as Zig compile errors or silent no-ops — both forbidden by
`AGENTS.md`.

## Guide-level explanation

A view is ordinary Zig with one or more `zsx!{ … }` blocks. Each block
contains exactly one markup root:

```zig
pub fn view(ui: anytype, c: anytype, ctx: anytype) void {
    zsx!{
        <column class="gap-2 p-4">
            <label>Hello</label>
            <Button variant="primary" on:click={ctx.save()}>Save</Button>
            {if ctx.show}
                {for ctx.items as item}
                    <Button on:click={ctx.pick(item)}>{item}</Button>
                {/for}
            {:else}
                <label>Empty</label>
            {/if}
        </column>
    }
}
```

Core rules:

- One root element per block; `<>…</>` makes a fragment root.
- Tags: lowercase names are intrinsics (`column`, `row`, `label`, `button`),
  PascalCase or dotted paths are components (`Button`, `shadcn.Button`).
- Attributes: bare (`disabled`), double-quoted (`class="p-4"`), or Zig
  expression (`on:click={ctx.save()}`). No single quotes, no escapes in
  strings.
- Events are `on:<event>` (preferred) or `on_<event>` (legacy spelling,
  also accepted; `zsx migrate` rewrites it).
- Control flow is written inside braces as markup children:
  `{if}`, `{:else if}`, `{:else}`, `{for … as x}`, `{switch}`,
  `{:case}`, and the closers `{/if}`, `{/for}`, `{/switch}`.
- Text is literal. Entities are not decoded. To emit a literal `{`, use an
  expression that produces it.
- `{let …}` and `{#snippet}` are **not** in v1; they are future RFCs.

## Reference-level explanation

### Block boundary

`zsx!{` is recognised as the exact byte sequence, outside Zig string, char
and comment literals. The block ends at the `}` that balances the opener,
with the same string/char-aware matcher used for expressions. An optional
`;` directly after the closing `}` is consumed and not re-emitted. Leading
and trailing whitespace around the root is allowed; the leading indentation
before `zsx!{` is stripped from emitted Zig.

### Grammar

The normative EBNF is [docs/spec/grammar.ebnf](../spec/grammar.ebnf). Notes:

- Whitespace is permitted between attributes, before `>`/`/>`, and inside
  control-flow braces (`{ if x }`), but **not** around `=` in an attribute.
- `tag_name` and `attr_name` accept `A-Z a-z 0-9 _ - .`; attribute names also
  accept `:`. The lexer does not restrict the first byte; dispatch does.
- `string` is delimited by `"` only and has no escape syntax. A value that
  needs a quote must use an expression.
- `{expression}` uses a nesting counter; `"…"` and `'…'` literals (with
  backslash escapes) are skipped. `//`/`/* */` comments inside the expression
  are currently **not** skipped by the matcher.
- A fragment is exactly `<>` … `</>` with no attributes.
- Text runs until `<` or `{`. A bare `}` is text. UTF-8 is passed through.

### Semantics (normative)

**S1 — Block root.** The root is a single element or fragment. Top-level
text, expressions and control-flow tokens are invalid. `zsx check` enforces
this on whole blocks (`require_single_root`); the fragment-level API leaves it
off so detached markup (slot bodies, formatter previews) can be validated.

**S2 — Tag dispatch.**
1. Empty name: fragment, transparent grouping.
2. `column` / `row`: container builder with `defer …end()`.
3. `label`: single text child becomes `ui.text`; other children are invalid.
4. `button`: single text child plus an optional `click` handler becomes the
   intrinsic `ui.button` path.
5. Name containing `.`: component call through the context namespace
   (`ctx.scope.Name(...)`), with the final segment potentially resolved by
   `@import`. Only `shadcn`/`ui` dotted names are prop-checked.
6. Name starting with an uppercase ASCII letter: component call through the
   context (`ctx.Name(...)`).
7. Anything else is invalid markup (`error.ZsxParseError` today; a
   `ZSX0xxx` diagnostic once WP 1.5 lands).

**S3 — Attributes.** Boolean attributes pass `true`. String attributes pass
the bytes between the quotes. Expression attributes pass the Zig source
unchanged. Attribute names map to Zig field names by replacing `:` with `_`
(`on:click` → `on_click`), so dotted and namespaced attributes cannot collide
with reserved Zig syntax. Duplicate attribute names are invalid; today they
surface as a Zig duplicate-field error.

**S4 — Events.** Any attribute whose field name starts with `on_` is an
event. Its value must be an expression. Codegen emits either a hoisted
`inline fn render_handler_…(ctx)` when the expression captures no loop
locals, or a `ZsxHandler_…(comptime T…) type` carrying captured loop values.
The intrinsic `<button>` only consumes the `click` event.

**S5 — Styles.** On intrinsics and containers, `class="…"` is resolved at
compile time through the shared class table (`src/rt/style.zig`); unknown
classes are build errors. On components, `class` is passed through as a field.
Space-separated tokens may not contain classes outside the table.

**S6 — Control flow.** `{if …}` … `{/if}` with optional `{:else if …}` and
`{:else}`; `{for <iterable> as <binding>}` … `{/for}`; `{switch <expr>}` with
one or more `{:case <pattern>}` and optional `{:else}` … `{/switch}`.
Nesting is arbitrary. Closers must match the innermost opener; `{:else}` is
valid only in `if`/`switch`, `{:case}` only in `switch`. A `for` binding and
its implicit `idx_N` are in scope only inside the loop body, and IDs include
the loop index so instances are stable.

**S7 — Slot children.** Inside a component, a direct child `<Slot name="…">`
names a content field. Slot children may contain markup and control flow but
no non-whitespace text directly. `Slot` is invalid elsewhere.

**S8 — Text.** Text is emitted verbatim through `ui.text` when the parent
accepts text bodies (components, fragments) and is invalid where the parent
requires structural children only (containers and intrinsic `label`/`button`
beyond their single text child).

### Error model

The fail-fast parser returns `error.ZsxParseError` (build failure). Tooling
uses the tolerant scanner and reports stable codes:

| Code | Meaning |
|---|---|
| ZSX0001 | stray closing tag |
| ZSX0002 | mismatched closing tag |
| ZSX0003 | unclosed tag |
| ZSX0004 | stray control-flow closer |
| ZSX0005 | mismatched control-flow closer |
| ZSX0006 | unclosed control flow |
| ZSX0007 | misplaced `{:else}` |
| ZSX0008 | misplaced `{:case}` |
| ZSX0009 | unknown class (warning) |
| ZSX0010 | legacy closer alias (warning) |
| ZSX0011 | unterminated `zsx!{` block |
| ZSX0012 | junk syntax (stray `<`, bad tag/attribute) |
| ZSX0013 | unknown built-in component prop |
| ZSX0014 | more than one root element in a block |
| ZSX0015 | text/expression/control flow at block top level |
| ZSX0016 | block has no root element |
| ZSX0020 | unused `{for … as name}` binding (warning) |
| ZSX0021 | empty `{for}` body (warning) |
| ZSX0022 | text directly inside `<column>` (warning) |

Warnings can be suppressed per block with `// zsx-ignore ZSX0020` on the line
directly above `zsx!{` (space- or comma-separated codes/names).

Recovery rules: the scanner never fails; a bad tag or expression becomes a
`junk` token and scanning resumes at the next plausible byte. The checker
collects all diagnostics and only `severity == .err` affects the exit code.

### Normalization

`zsx migrate` rewrites `on_<event>` to `on:<event>` for the known events
(`click`, `change`, `input`, `submit`, `key`, `focus`, `blur`, `hover`,
`drag`) and legacy closers to `{/if}`, `{/for}`, `{/switch}`. The formatter
normalises indentation only; it preserves token spelling. The grammar does
not define whitespace or quote style beyond what the lexer requires.

## Drawbacks

- Codifying today's grammar also codifies its quirks: colon-less
  `{else}`/`{case}`, expression attributes without trimming, and no string
  escapes. The RFC marks legacy spellings as non-grammar and migrates them,
  but the tolerant scanner is deliberately more permissive than the grammar.
- The single-root rule makes fragments necessary for multi-root blocks; some
  authors expect Vue-style multiple roots.
- A normative corpus adds maintenance cost and must be updated with every
  grammar change.

## Alternatives

- **Document only the parser AST** (no EBNF): cheaper, but leaves formatter,
  checker and LSP free to disagree again.
- **Design a new language now** (`{let}`, snippets, attribute spread,
  comments, multiple roots): would invalidate every existing view and all 23
  goldens; better as additive RFCs after the CST parser exists.
- **Adopt an existing template grammar** (JSX/HTML): loses Zig-native
  expression semantics (brace balancing, `for … as`, `switch`) and the
  component/intrinsic split that codegen relies on.

## Unresolved questions

- **U1 — Multiple roots.** Keep one root per block, or allow fragments as an
  implicit wrapper?
- **U2 — Comments.** Add `{/* … */}` markup comments (and skip Zig comments
  in the brace matcher) in v1 or a follow-up?
- **U3 — Text escapes and entities.** Support `\{`, `&amp;`, and whitespace
  control (`{ }`), or require expressions for literal braces?
- **U4 — Comment-aware brace matching.** `matchBrace` does not skip `//` or
  `/* */`; a `}` in a comment ends the expression early. Fix in the CST
  parser?
- **U5 — `<label>` → `<text>`.** `zsx migrate` defers this rename because
  `<text>` is not an intrinsic. Decide the alias/removal schedule.
- **U6 — Duplicate attributes.** Add `ZSX0xxx` for duplicates (today a Zig
  compile error), and decide whether the last or first wins.
- **U7 — Expression attributes.** Should string-valued attributes also accept
  single quotes or `${}` interpolation, or stay Zig-only?

## Acceptance / test plan

- [ ] This RFC reviewed and marked accepted; `docs/spec/grammar.ebnf` is
      treated as normative.
- [x] Corpus of **150** files under `spec/grammar/` (102 valid, 48 invalid).
      Invalid files name their expected code in a `// expect: ZSXnnnn` first
      line. Deferred: committed golden generated bodies for every valid file.
- [x] `src/tests/grammar.zig` runs the corpus through `checker`, `fmt` and
      `preprocess`, asserting clean checks, deterministic preprocessing and
      idempotent formatting on the valid corpus, and the expected code on
      every invalid file. Scanner/parser byte-level agreement is implicit:
      `preprocess` parses and `checker` tokenizes the same files.
- [ ] Fuzz: random bytes and random valid-token permutations never crash the
      scanner/checker; invalid inputs always yield a diagnostic, never a hang.
- [x] `zsx migrate` handles every legacy form named here and is idempotent.
- [ ] Goldens regenerated only for deliberate output changes; zero-diff for a
      grammar-only PR.
- [ ] LSP/M1 CST parser consumes the same corpus with no new divergences;
      any intentional difference is recorded in this RFC's normalization
      section.
