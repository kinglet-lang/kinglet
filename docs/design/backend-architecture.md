# Backend architecture — VM + LLVM, fronted by a shared IR

> Design note. Status: **draft, awaiting review**. Updated 2026-05-31.
> Lives in `docs/design/` because it's about how *the self-host compiler*
> is structured, not what the language looks like. Move to an RFC if any
> of this needs to be controversial.

## Goal

Land on a layered pipeline so that:

- **One frontend** (lexer/parser/checker/IR-emit) is shared by everything
- **Two backends** plug in below the IR:
  - A **VM backend** that emits bytecode for the existing C++ VM. Fast
    iteration, the hot path for `kinglet run`, REPL, LSP, golden tests.
  - An **LLVM backend** that lowers IR to LLVM IR for native release
    builds. Slow to compile, fast to run, optional.
- LSP and ad-hoc dev never touch LLVM and stay snappy.
- Adding a third backend later (WASM, C source, native via Cranelift, …)
  is "write another lowering", not "rewrite the compiler".

```
              ┌─────────┐  ┌────────┐  ┌─────────┐  ┌───────────┐
source ─────► │  lexer  │─►│ parser │─►│ checker │─►│  IR-emit  │
              └─────────┘  └────────┘  └─────────┘  └─────┬─────┘
                                                          │ KIR
                                          ┌───────────────┼───────────────┐
                                          ▼                               ▼
                                   ┌─────────────┐                ┌──────────────┐
                                   │ VM backend  │                │ LLVM backend │
                                   │ KIR → bcode │                │ KIR → llvm   │
                                   └──────┬──────┘                └───────┬──────┘
                                          ▼                               ▼
                                   C++ VM (today)                    native binary
```

## What "frontend done" means under this layering

We currently have **lexer, parser, checker** in the self-host repo.
Calling that "frontend done" depends on where we draw the line:

- If frontend = "everything up to AST + types": already done modulo
  polish. Codegen is next.
- If frontend = "everything up to a backend-agnostic IR": **not done.**
  IR-emit is the missing module, and it's the natural seam between
  frontend and the two backends.

This note argues for the second definition. Reason: if codegen v1 emits
bytecode directly from AST, the LLVM backend later has to either reuse
that AST→bytecode logic and lift bytecode (lossy), or re-walk the AST
and re-do everything the bytecode path did (duplication). An IR makes
both backends consume the same thing.

## What KIR (Kinglet IR) should look like

Concrete proposal — round-1, open to push-back on every line:

- **Form:** typed CFG with basic blocks, SSA values. Each basic block is
  a list of instructions ending in a terminator (`Br`, `CondBr`, `Ret`,
  `Switch`, `Unreachable`).
- **Types:** every value carries the same `Type` the checker assigns.
  Means there's no separate "untyped IR pass"; the checker's output is
  effectively half of IR-emit's input.
- **Lowering level:** mid-level. After IR-emit:
  - `match` is desugared to `Switch` + bind instructions
  - `for`/`while` are desugared to `Br`/`CondBr`
  - generic functions are **monomorphized** at this layer (same as the
    C++ side does today, just made explicit)
  - method calls are resolved to function references (no dynamic
    dispatch yet — traits are static-dispatch only for now)
  - cast / pipeline / chained-comparison sugar already gone (parser
    desugars some, checker desugars the rest)
  - `using io;` / native intrinsics show up as calls to a known set of
    extern declarations — they stay as calls, not opcodes, until each
    backend lowers them
- **Memory model in IR:** stack slots represented as `Alloca` +
  `Load`/`Store`. SSA only for register-like temporaries. The VM backend
  collapses this back to its stack model; LLVM consumes as-is.
- **Serialization:** in-memory only at first. Add a textual dump
  (`--ir`) modeled on `--ast` for golden tests and debugging. Skip
  binary on-disk format until there's a reason.

A toy `add(int, int) -> int` in KIR text form, illustrative:

```
fn add(a: int, b: int) -> int {
  bb0:
    %0 = iadd a, b
    ret %0
}
```

A `match` example to show the desugar:

```
// Source
int describe(Color c) {
  return c match { Red => 1, Green => 2, Blue => 3 };
}

// KIR
fn describe(c: Color) -> int {
  bb0:
    %tag = enum_tag c
    switch %tag, default bb_unreachable, [
      0 -> bb_red, 1 -> bb_green, 2 -> bb_blue
    ]
  bb_red:    ret 1
  bb_green:  ret 2
  bb_blue:   ret 3
  bb_unreachable: unreachable
}
```

## Where the backends sit

### VM backend

Existing C++ VM is the consumer. The backend's job:

- Allocate VM stack slots for KIR `Alloca`s
- Linearize basic blocks (greedy, place-fall-throughs-after-branches)
- Resolve `Br`/`CondBr` targets to bytecode offsets in a second pass
- Translate KIR ops 1:1 to existing opcodes where possible
  (`iadd` → `OP_ADD`, `enum_tag` → `OP_ENUM_TAG`, …)
- Emit `OP_NATIVE_*` for resolved intrinsics

**Output is identical to what C++ `compiler.cc` emits today** — same
opcodes, same constant pool layout. That's the contract: the VM backend
should pass bytecode through golden tests byte-for-byte against the C++
output for at least the simple cases.

### LLVM backend

Out of scope for v1. Sketch:

- KIR types map to LLVM types: `int → i64`, `float → float`, `string →
  { i64, ptr }`, structs → named LLVM struct types, enums with payloads
  → tagged unions (`{ i32, [N x i8] }` with bitcasts for variants).
- Each KIR function → one `define`. Basic blocks 1:1.
- Native intrinsics declared as `extern` functions resolved by a small
  C runtime (`kinglet_runtime.c`) that wraps the same `io`/`fs`/`sys`
  primitives the VM exposes. This is how we keep parity.
- Driver: `--emit=llvm` dumps `.ll`, `--emit=native` invokes `clang` /
  `lld` to link.

Hard parts deferred: GC (today the C++ VM is reference-tracing-ish,
mostly through value semantics; LLVM path needs an actual story),
debug info, exceptions/panic. None of these are blockers for a v1 LLVM
target that just runs the simple cases.

## C++ side: refactor or leave alone?

Two paths, pick one:

**Path A — leave C++ alone.** Self-host introduces KIR, C++ stays
AST→bytecode. Faster to start. Risk: no reference implementation to
diff against; KIR design happens in a vacuum.

**Path B — refactor C++ to KIR-shaped layers too.** Split
`compiler.cc` into `ir_builder.cc` (AST→KIR) + `bytecode_emitter.cc`
(KIR→bytecode). Same KIR shape on both sides. Lets us diff KIR text
output between the two implementations. Pays for itself if KIR design
takes more than one iteration.

Recommendation: **Path B** if we're committing to KIR seriously, **Path
A** if KIR might be retracted. Worth deciding before either implementation starts.

## Build-up order — what to do first

If we're going to do this, the order that wastes the least work:

1. **This note becomes RFC 0003** (or stays a design note — TBD with
   how heavyweight RFCs are around here). Lock down: KIR form, lowering
   level, monomorphization timing, intrinsic protocol, Path A vs B.
2. Stand up `docs/` properly (`docs/README.md`, `docs/design/`,
   `docs/rfcs/`). Move this file into the right slot.
3. Decide Path A vs B. If B, refactor `compiler.cc` first; the result
   is the reference implementation.
4. Self-host `ir/` module: `ir.kl` (data definitions, mirrors
   `ast.kl`'s shape), `ir_emit.kl` (AST + types → KIR), `ir_print.kl`
   for `--ir` dump.
5. Self-host VM backend: `codegen/vm.kl`. Goldens diff bytecode against
   the C++ VM backend.
6. **Bootstrap fixpoint test**: bootstrap-built self-host compiler vs
   self-built self-host compiler should produce byte-identical
   bytecode for the test suite.
7. LLVM backend (`codegen/llvm.kl`): only after everything above is
   green.

Step 6 is where "self-host" stops being a science project. It also
gates anything risky in KIR — once fixpoint is green, KIR changes can
be made and re-verified mechanically.

## Open questions

Questions this note doesn't answer; flag them in review:

- **Generics: mono before or after IR?** Current draft says before
  (so KIR sees no `<T>`). Alternative: KIR is generic too, mono is
  per-backend. Probably the former; mono is finicky and we want it
  centralized.
- **Closures.** Don't exist today. When they land, do they show up as
  KIR `Closure` instructions or get lowered to env-struct + function
  pointer at IR-emit time? Lean toward the latter — keeps backends
  dumb.
- **Panics / aborts.** No story. LLVM backend will need one. KIR could
  have an `Unreachable` and a `Panic(string)` instruction; both
  backends just emit a runtime call.
- **Source locations in KIR.** Probably yes, every instruction tags
  the source span. Cheap, makes diagnostics work post-IR.
- **Diff format.** What exactly is "byte-identical bytecode" comparing
  — opcodes? Constant pool order? Debug tables? Need a precise spec
  before fixpoint test is meaningful.

## What this note *isn't* deciding

To keep scope tight, these are explicitly **out of scope** here, even
though they touch backends:

- Standard library layout (RFC 0002 territory)
- `??` / `try` syntax (RFC 0001)
- Concurrency model
- GC strategy beyond "the LLVM path will need one eventually"
