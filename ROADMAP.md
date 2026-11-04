# ZSX Roadmap

A phased plan with concrete deliverables and exit criteria. Time estimates assume an AI agent with the `vercel-labs/native` Zig skill installed, plus daily review. Calendar time is roughly 2× active time.

---

## Phase 0 — Architectural Anchors (1–2 days)

**Goal:** Lock the decisions that everything else depends on.

- **Backend contract:** Define the `comptime` interface every backend implements—`Node` associated type, `Capabilities` struct, `emit(el, ctx)`, `supports(feature)`.
- **`Feature` enum:** The canonical set of style/layout capabilities (background, hover_background, padding, margin, border, radius, gap, flex_direction, font, shadow, etc.).
- **`StyleRef`:** The opaque handle attached to AST elements. Carries `raw_class` (for web) and `resolved` pointer (for native).
- **`StyleResolver` interface:** `resolve(class, ctx) → StyleRef` and `lower(style, BackendType, ctx) → void`. Aeolus plugs in here later; a hand-rolled stub resolver ships first.
- **Error semantics:** Permissive (`zsx!`) vs strict (`zsx_strict!`) modes, mirroring `gpui-rsx`.

**Exit:** A `zsx/contract.zig` file with the types above, reviewed and frozen.

---

## Phase 1 — Parser + Neutral AST (2–3 days)

**Goal:** Validate the core thesis—comptime JSX-like parsing in Zig.

- Recursive-descent parser at `comptime` for a subset: paired tags, self-closing tags, boolean attributes, value attributes (`gap={8}`), text children, `{expr}` interpolation.
- Neutral AST: `Element`, `Attribute`, `Child` union (element/text/expression).
- Span-aware `@compileError` for malformed markup.

**Exit:** A test file that parses 5–6 markup strings at comptime and prints the AST via `@compileLog`. No backend yet.

---

## Phase 2 — DVUI Backend Vertical Slice (2–3 days)

**Goal:** Prove end-to-end lowering to a real framework.

- Emitter: AST → `dvui.Options` field assignments (`color_fill`, `padding`, `margin`, `border`, `corners`, `font`, `style`).
- Map subset of `Feature` values to DVUI capabilities; emit compile errors for unsupported features in strict mode.
- Hand-write a minimal resolver mapping ~10 utilities (`bg-blue-500`, `p-4`, `rounded-lg`, `text-white`) to `StyleRef` slots.
- Example app: a single `<column><button>{"Save"}</button></column>` rendered in DVUI.

**Exit:** Working DVUI window showing the example. **This is the thesis-validating milestone.**

---

## Phase 3 — Nanoui Backend (2–3 days)

**Goal:** Prove the generic emitter holds across a second, structurally different backend.

- Emitter: AST → Nanoui builder chains (`.gap()`, `.p()`, `.bg()`, `.hover()`, `.rounded()`, `.row()`).
- Capability table: Nanoui supports `hover` natively; DVUI does too but via a different field. The emitter must dispatch per backend.
- Same example app, Nanoui target.

**Exit:** Same markup, two backends, no changes to the parser or AST. If this works, the architecture is validated.

---

## Phase 4 — Control Flow + Fragments (2–3 days)

**Goal:** The authoring experience becomes usable for real views.

- `{if cond}`, `{for (items) |item|}`, `{switch}`, fragments `<>...</>`.
- Comptime generation of native Zig `if`/`for`/`switch` around backend emissions.
- Nested components: `<Profile name={user.name} />` resolved at comptime.

**Exit:** A list-rendering example in both DVUI and Nanoui, driven by runtime data.

---

## Phase 5 — Style Resolver Integration (2–4 days)

**Goal:** Replace the hand-rolled stub resolver with a pluggable interface; wire Aeolus as the default.

- `StyleResolver` interface finalized.
- `zsx-aeolus` adapter crate: bridges `StyleRef` ↔ Aeolus `StylePlan`.
- Backend `lower()` functions consume `StylePlan` slots.
- `class` attributes accept static strings and runtime `[]const u8` expressions.

**Exit:** Example app using real Tailwind classes via Aeolus, rendering in DVUI and Nanoui.

---

## Phase 6 — Additional Backends (3–5 days each)

Prioritized by lowering fidelity:

- **zigui:** Modifier-chain emission (`.padding()`, `.background()`, `.cornerRadius()`). High fidelity.
- **Capy:** Wrapper widgets (`StyledButton`, `StyledColumn`) because Capy primitives have no style fields. Medium fidelity.
- **Gooey:** Theme generation from resolved tokens + wrappers for inline overrides. Medium fidelity.
- **zig-webui / web emitter:** Serialize AST to HTML with `class` strings. Trivial once `raw_class` is preserved.

**Exit:** At least three native backends + one web backend passing the same example suite.

---

## Phase 7 — DX Polish (3–5 days)

**Goal:** Make it feel like a real tool, not a demo.

- Strict-mode diagnostics: unsupported features reported at exact source spans.
- Capability report: `zsx.describeBackend(DvuiBackend)` prints what a backend supports.
- `zig build` step: `.zsx` files transpiled to `.zig` for ZLS compatibility (if inline comptime proves too opaque for tooling).
- Documentation: backend authoring guide, capability matrix, examples per backend.

**Exit:** A new backend can be added by following the doc alone.

---

## Phase 8 — Ecosystem (ongoing)

- **Zylix web backend:** Serialize resolved style to CSS strings.
- **raylib-zig / ImGui backends:** Flattened layout → draw calls.
- **Aeolus Shadcn layer:** Reuse `aeolus-shadcn` class tables for `zsx-shadcn` components.
- **LSP extension:** Syntax highlighting and completion for ZSX markup inside Zig files.
- **Community backend template:** Starter repo for third-party backends.

---

## Timeline Summary

| Phase | Active days | Cumulative calendar (with review) |
|---|---|---|
| 0 — Anchors | 1–2 | ~3–4 days |
| 1 — Parser + AST | 2–3 | ~1 week |
| 2 — DVUI slice | 2–3 | ~2 weeks |
| 3 — Nanoui | 2–3 | ~2.5 weeks |
| 4 — Control flow | 2–3 | ~3.5 weeks |
| 5 — Aeolus resolver | 2–4 | ~4.5 weeks |
| 6 — Extra backends | 9–15 | ~7 weeks |
| 7 — DX polish | 3–5 | ~9 weeks |

**Thesis-validating prototype (through Phase 3): ~2.5 weeks calendar.** **Usable multi-backend tool (through Phase 5): ~4.5 weeks.** **Polished with three-plus backends (through Phase 7): ~9 weeks.**

---

## Critical Risks

1. **Comptime parser fragility.** Zig's comptime error messages are opaque; the skill mitigates this but does not eliminate it. Mitigation: build the parser incrementally, one grammar feature at a time, with a test file per feature.
2. **Backend API drift.** DVUI and Nanoui are pre-1.0; their APIs will change. Mitigation: keep each backend in its own module with a thin adapter surface, so breakage is localized.
3. **Aeolus coupling creep.** Resist pulling Aeolus into Phase 1–3. The stub resolver must prove ZSX works *without* Aeolus. Mitigation: Phase 5 is explicitly gated behind a working two-backend demo.
4. **Scope creep toward a full framework.** ZSX is a syntax + lowering layer, not a router, state manager, or component lifecycle system. Mitigation: the backend contract has no hooks for those; if someone wants them, they build them on top.

---

## First Three Actions

1. Write `zsx/contract.zig` by hand (Phase 0). Do not let the agent infer it.
2. Write one test markup string and a `@compileLog` AST dump (Phase 1 start).
3. Read `dvui/src/Options.zig` and write the field-mapping table for the DVUI emitter before writing any emitter code (Phase 2 start).

If you want, I can draft `contract.zig` with the `Feature` enum and backend interface as the concrete starting point.
