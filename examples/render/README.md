# render-demo — the code-frame renderer as a library

Consumes the M1 presentation seam: `zsx.render.Renderer` turns structured
`ZSX0xxx` diagnostics (from `zsx.checker.checkSource`) into annotated code
frames — header, optional help line, source lines, caret span. This is the
same API that backs `zsx check` output (`src/cli.zig`); an editor plugin or
CI annotator would embed exactly this.

The demo checks one broken view and prints every diagnostic framed against
its source:

```console
$ zig build run
views/bad.zsx:3:17: warning[ZSX0009]: unknown class 'made-up-class' (will error at build)
2 |     zsx!{
3 |         <column class="gap-2 made-up-class">
  |                 ^^^^^^^^^^^^^^^^^^^^^^^^^^^
4 |             {if ctx.show}
views/bad.zsx:3:9: error[ZSX0003]: <column> never closed
2 |     zsx!{
3 |         <column class="gap-2 made-up-class">
  |         ^^^^^^^
4 |             {if ctx.show}
views/bad.zsx:5:17: error[ZSX0003]: <row> never closed
4 |             {if ctx.show}
5 |                 <row>
  |                 ^^^^
6 |                     <label>x</label>
views/bad.zsx: 2 error(s), 1 warning(s) — each one framed against the source
```

Run:

```bash
zig build run     # print the framed diagnostics
zig build test    # smoke tests over the library API
```

Sibling examples: `examples/consumer` (codegen path, `zsx.addViews`) and
`examples/checker` (validation path, `zsx.checker.checkSource`).
