# Self-hosting roadmap

> Goal: `kinglet cli/main.kl --run self-host.kl` compiles and runs itself.
> Each phase delivers a committable, testable slice.

## Phase 0 — compound assignment ✅ (d69c7a7)

Done. `+= -= *= /=` in compiler + checker + golden test.

## Phase 1 — Enum variants ✅

Done. Enum registration, variant construction (with and without payload), 22 golden tests passing.

## Phase 2 — Match expressions ✅

Done. EnumPat, BindingPat, ArrayPat, wildcard, literal, and guard patterns all compiled.

## Phase 3 — Built-in methods ✅

Done. Array/string/map method calls dispatched to opcodes. io::out.line() supported.

## Phase 4 — Imports & modules ✅

The self-host compiler now handles `ImportDecl` end-to-end:
- Loads imported files from disk via `fs::__read`
- Scans and parses them using the compiled-in scanner/parser
- Registers imported functions (qualified + bare names), structs, and enums
- Handles transitive imports with circular-import detection
- Compiles imported function bodies in Pass 2b
- Supports selective imports (`{ sym1, sym2 }`) and aliased imports

Key changes: `compiler/compiler.kl` gained path helpers, `ImportState`/`ImportedFunc`
structs, `load_module` recursive loader, namespace-aware `emit_ns_call`/`emit_ns_access`,
and Pass 0a + Pass 2b in `compile_program`. `cli/main.kl` passes `source_path` to the
compiler so imports resolve relative to the source file.

## Phase 5 — Self-hosting milestone ✅

The self-host compiler can compile itself. Verified by round-trip:
1. Bootstrap compiles `cli/main.kl` → `cli_v1.kbc` (342KB, zero errors)
2. `cli_v1.kbc` compiles `cli/main.kl` → disassembly output (22,184 lines)
3. Bootstrap's disassembly of the same source is **byte-identical** (`diff` reports no differences)

**Why first.** Every source file constructs enum variants — `Expr::Binary(...)`,
`Stmt::Block(...)`, `TypeKind::Int`, `BinaryOp::Add`. The compiler can't emit any
of these today (falls into `NsAccess` → `handle_ns_call` → unrecognised).

### 1a. Register enum declarations in the compiler

In `compile_program`, add a pass over `EnumDecl` (currently ignored):

- Build a local `EnumType` table inside `Compiler`:
  ```
  struct EnumType { string name; string[] variants; int[] param_counts; int type_idx; }
  ```
- Call `add_enum_meta(chunk, EnumMeta { name, variants, param_counts })` for each
  user-declared enum, *after* the built-in enums (CastError=0, IntResult=1,
  FloatResult=2). User enum type_idx starts at 3.
- Resolve forward references — an enum variant's param types may reference
  another enum declared later. Two-pass: register names first, then resolve.

Files: `compiler/compiler.kl` (Compiler struct + compile_program)

### 1b. Compile enum variant construction

In `emit_call`, when callee is `NsAccess(EnumName, VariantName)`:

1. Look up `EnumName` in the compiler's enum table → get `type_idx`
2. Look up `VariantName` in `enum_metas[type_idx].variants[]` → get `variant_idx`
3. Compile each arg (the payload fields) onto the stack
4. Emit `EnumVariantPayload` with operand = `(type_idx << 16) | variant_idx`

For zero-param variants (`BinaryOp::Add`):

- Emit `EnumVariant_` with same operand encoding (no args on stack)

Files: `compiler/compiler.kl` (emit_call / new emit_enum_variant helper)

### 1c. Golden tests

Two tests:
- `enum_no_payload.kl` — `enum Color { Red, Green, Blue }` + construct + return
- `enum_with_payload.kl` — `enum Option { Some(int), None }` + construct + return

Bytecode must match C++ bootstrap compiler.

## Phase 2 — Match expressions

**Why second.** 71 uses across the 4 core source files. Without match the
compiler can't process a single `.kl` file that does anything interesting.

### 2a. Variant tag introspection

The VM needs a way to check "which variant is this enum value?" at runtime.
The `EnumVariant_` / `EnumVariantPayload` opcodes already encode this info
in the value. Need an opcode or encoding convention to extract it.

*Decision needed: new `GetVariantTag` opcode, or a convention using IsNull +
constant comparison? Check C++ bootstrap for the existing mechanism.*

### 2b. Compile match

For `value match { Pattern1 => body1, Pattern2 => body2, ... }`:

1. Compile `value`, store in a hidden local
2. For each arm:
   - **EnumPat(enum, variant, fields)**: Load hidden local, check variant tag.
     Mismatch → JmpFalse to next arm. Match → bind `fields` to payload slots
     via `EnumPayloadGet`, execute body, Jmp to end.
   - **BindingPat(name)**: Wildcard — always matches. Bind hidden local to
     `name`. Execute body, Jmp to end.
   - **ArrayPat**: Deferred to Phase 5.
3. After all arms, emit a runtime panic for "no match" (or Null).
4. Patch all jumps.

Files: `compiler/compiler.kl` (new compile_match / emit_match)

### 2c. Golden tests

- `match_enum_simple.kl` — match on a 2-variant enum
- `match_enum_payload.kl` — match with payload destructuring
- `match_wildcard.kl` — BindingPat catch-all

## Phase 3 — Built-in methods

**Why third.** `.len()` has 176 call sites, `.push()` / `.pop()` 12 more.
The opcodes already exist in `bytecode.kl`; they just aren't plumbed through
the compiler.

### 3a. Array methods via FieldAccess

When `emit_field_get` sees an array-typed object with method name, emit the
corresponding array opcode instead of `FieldGet`:

| Method | OpCode |
|---|---|
| `.len()` | `ArrayLen` |
| `.push()` | `ArrayPush` (needs value on stack first) |
| `.pop()` | `ArrayPop` |
| `.slice()` | `ArraySlice` |
| etc. | … |

For mutating methods (`.push()`, `.pop()`) in call position, need to plumb
through `emit_call` → `FieldAccess` callee path.

### 3b. String methods

Same pattern for string built-ins: `.len()` → `str.byte_count()` (or add
`StringLen` opcode if the C++ VM has it). Check what the bootstrap VM provides.

Files: `compiler/compiler.kl` (emit_field_get + emit_call)

### 3c. Golden tests

- `array_methods.kl` — new/literal + push + pop + len
- `string_methods.kl` — slice + len + to_upper

## Phase 4 — Imports & modules

**Why fourth.** `cli/main.kl` has 6 imports, `compiler/compiler.kl` has 2. Without
import compilation the compiler can't load anything beyond a single file.

### 4a. Compile ImportDecl

In `compile_program`, add a pass for `ImportDecl`:
1. Resolve the import path relative to the current file
2. Read + lex + parse + compile the imported file
3. Merge the imported chunk's constants/functions/enum_metas into the current
   chunk (deduplicating where needed)
4. Expose the imported symbols as locals/globals in the current scope

*Decision needed: merge at IR level (bytecode chunks) or at AST level? AST
merge is simpler but duplicates work; IR merge needs symbol re-indexing.*

### 4b. Multi-file golden test

- `import_a.kl` + `import_b.kl` — A imports B and calls a function from B

## Phase 5 — Self-hosting milestone

At this point the compiler should have enough coverage to attempt compiling
itself. The process:

1. Compile `cli/main.kl` with the bootstrap compiler → `cli_v1.kbc`
2. Run `cli_v1.kbc` on `cli/main.kl` (self-compile) → `cli_v2.kbc`
3. Diff `cli_v1.kbc` bytecode vs `cli_v2.kbc` bytecode — should match
4. If not: fix bugs, iterate until bit-identical

### Known gaps before self-hosting works

- **Pattern match guard expressions** (`Variant(let x) when x > 0 => ...`)
- **Match exhaustiveness** (runtime "no match" fallback)
- **Import path resolution** relative to importing file
- **StructDecl compilation** (struct constructors are already registered, but
  struct type metadata may need to be in the chunk)
- **ArrayPat** in match patterns
- **Nested match** (match inside match inside match — the compiler source does this heavily)
- **Recursive functions** (functions calling themselves — should already work
  with the forward-decl pass)
- **Break/continue across match inside loop**

## Phase 6 — Cleanup & FFI migration

After self-hosting is solid:

### 6a. Move native bindings to stdlib

- Delete `handle_ns_call` hardcoding of `io/fs/sys`
- Create `std/native/io.kl`, `std/native/fs.kl`, `std/native/sys.kl` — thin
  wrappers that expose native opcodes as plain functions
- Create `std/io/mod.kl` — user-facing API (`println`, `readln`, etc.)

### 6b. Standard library

- `std/collections/array_list.kl` — generic dynamic array (wraps built-in array)
- `std/collections/hash_map.kl` — key-value store
- `std/result.kl` — `Result<T, E>` enum + combinators
- `std/option.kl` — `Option<T>` enum
- `std/string/mod.kl` — string builder, split, join, etc.
- `std/math/mod.kl` — min, max, abs, pow, etc.
- `std/iter/mod.kl` — Iterator trait + map/filter/reduce adaptors

## Phase 7 — Self-hosted VM

Today the self-host compiler emits bytecode that runs on the C++ VM. The final
bootstrap step is writing the VM in Kinglet itself:

- `vm/value.kl` — tagged value representation
- `vm/chunk.kl` — bytecode loader
- `vm/vm.kl` — stack machine interpreter
- `vm/native.kl` — native function bindings

Once the VM runs on itself, the C++ bootstrap compiler is fully retired.

---

## Summary

| Phase | What | Status |
|---|---|---|
| 0 | Compound assignment | ✅ |
| 1 | Enum variant construction | ✅ |
| 2 | Match expressions | ✅ |
| 3 | Built-in methods (.len/.push/.pop) | ✅ |
| 4 | Imports & modules | ✅ |
| 5 | **Self-hosting** | ✅ round-trip verified |
| 6 | Stdlib + FFI cleanup | Future |
| 7 | Self-hosted VM | Future |

Phase 1 is unblocked and ready to start: bytecode opcodes are defined, AST
representation is settled, the only gap is the ~60 lines of compiler logic to
register enums and emit `EnumVariant_`/`EnumVariantPayload`.
