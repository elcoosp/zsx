# lossless_demo — the lossless front-end as a library

`examples/consumer` shows the codegen path (`zsx.addViews` in your
`build.zig`) and `examples/checker` shows the validation seam
(`zsx.checker.checkSource`). This example shows the lossless seam (master-plan
spikes S1 + S2): the `zsx` package partitions a `.zsx` source into typed,
byte-exact segments and re-emits the file byte-for-byte.

```zig
const zsx = @import("zsx");

const doc = try zsx.lossless.Document.init(arena, source);
for (doc.blocks) |blk| {
    // markup body between `zsx!{` and the closing `}`
    std.debug.print("{s}\n", .{doc.markup(blk)});
}
// S2: byte-for-byte reconstruction
const same = try doc.render(arena);
```

Every segment carries its kind (`zig_text`, `string`, `char_literal`,
`line_comment`, `block_comment`, `zsx_block`) and absolute byte offsets, so
`zsx.diag.LineIndex` built on the same source points at the same bytes. A
`zsx!{` inside a string, char literal or comment is never mistaken for a
block — one scanner decides, shared by the preprocessor, checker and
formatter.

## Run

```bash
zig build run     # segment outline + markup of the sample view + round-trip proof
zig build test    # two smoke tests pinning the round-trip and block detection
```

The sample in `src/main.zig` deliberately contains a `zsx!{` inside a
comment, a `'}'` char literal and `{if}` control flow inside the block: the
outline shows how each lands in a different segment and the round-trip shows
that none of them moved a byte.
