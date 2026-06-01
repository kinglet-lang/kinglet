# Error Handling Design — ??, try, and Cast Unification

| Date       | 2026-06-01 |
|------------|-----------|
| Status     | Draft     |
| Author     | Hermes    |

## 1. Motivation

Current Cast uses `else` for fallback (`int(x) else 0`), which conflicts visually with
conditional `if/else`. `??` and `try` were added in the bootstrap (commits `cc4da02`,
`4e5a5e7`, `e52d804`) as operators on Result types. The plan has always been to retire
Cast `else` and unify the error-handling surface (HANDOFF.md §3, items #8–#11).

## 2. Current State (Bootstrap HEAD `e52d804`)

### What exists

| Feature     | Syntax                    | AST Node            | Semantics                                      |
|-------------|---------------------------|--------------------|-----------------------------------------------|
| Cast        | `T(value) else fallback`  | `CastExpr`          | CastTo opcode; null on failure; else handles it |
| Coalesce    | `lhs ?? rhs` / `?? \|e\| rhs` | `NullCoalesceExpr` | Requires LHS be Result-shaped; unwraps Ok, else rhs |
| try         | `try expr`                | `TryExpr`           | Requires operand be Result-shaped; Ok→unwrap, Err→early return |

Scaffolding: `CastError` (enum with Empty/NotANumber/Overflow), `IntResult`,
`FloatResult` — pre-registered Result-shaped enums but NOT yet connected to Cast's
runtime behavior. Currently Cast produces untyped `null` on failure.

### What's missing

- **Cast** produces `null`, not a `Result<Int, CastError>`. Therefore Cast results
  cannot be operated on by `??`/`try`.
- `else` is still the Cast fallback syntax.
- No integration between the error-handling operators and Cast.

## 3. Design Decisions

### Q1: Cast syntax — retire `else`, adopt `??`

**Decision: Option A — `else` is removed entirely.**

```kl
// Before
int(s) else 0

// After
int(s) ?? 0
```

Rationale: `else` conflicts with `if/else`. `??` is the established "or-else" operator
in the language (null-coalescing). Retiring `else` simplifies the parser and teaches one
fewer keyword.

Migration: `else` keyword remains in the language for `if/else` conditionals only.
Cast fallback syntax changes from `else` to `??`.

### Q2: Cast result type — wrap fallible casts in Result

**Decision: Option B — fallible casts produce `Result<T, CastError>`.**

```kl
int(s)        // produces Result<Int, CastError>   —— fallible, needs ?? or try
float(42)     // produces Float                     —— infallible, no wrapper
```

Rationale:
- Unifies error handling: `??` and `try` already work on Result types. Making Cast
  produce a Result means zero new operator semantics — just connect the Cast codegen to
  emit `Ok(v)`/`Err(CastError::X)` wrapped in a Result enum variant.
- The scaffolding (`IntResult`, `FloatResult`, `CastError` enums) is already registered
  in the bootstrap checker (commits `893dacb`, `5da1975`). The missing piece is
  connecting Cast's compiler to emit these enum variants instead of `null`.
- Infailable casts (int↔float, num→string) stay unwrapped — they never fail, so
  wrapping them in Result would be pure overhead with no benefit.

### Q3: try and Cast interaction

**Decision: Yes — `try int("42")` works.**

```kl
fn parse_or_zero(string s) -> int {
  return int(s) ?? 0;        // fallible cast + fallback → int
}

fn parse_or_err(string s) -> int {
  return try int(s);         // Ok(v) → v, Err(e) → early return Err from fn
}
```

The `try` keyword operates on any Result-shaped value. Since fallible Cast produces
Result, `try` works transparently. The enclosing function must return a compatible
Result type (e.g., `fn parse(...) -> IntResult` where `IntResult = Result<Int, CastError>`).

### Q4: Unified syntax surface

```kl
// === Infallible casts (no wrapping, no ?? needed) ===
float(42)              // → 42.0 (int→float, always succeeds)
int(3.14)              // → 3   (float→int, truncates)
string(42)             // → "42" (int→string)
string(3.14)           // → "3.14" (float→string)

// === Fallible casts WITH fallback ===
int(s) ?? 0            // → Ok(v) unwraps to v, Err → 0
int(s) ?? |e| {        // → Err binds payload to e
  io::err("parse failed: ")
  io::err(e.string())
  0
}
float(s) ?? 0.0        // → same pattern for float

// === Fallible casts WITH propagation ===
try int(s)             // → Ok(v) → v, Err → return Err from enclosing fn
try float(s) ?? 0.0    // → try + fallback: propagate Err, but ?? catches the rest...

// === ?? on any Result type (not just Cast) ===
maybe_ok_result ?? default_value
fn_result() ?? |e| handle_error(e)
```

**NOT allowed** (compile error):

```kl
let result = int(s);   // Error: fallible cast must be consumed by ?? or try
```

Rationale: a bare fallible cast producing `Result<T, E>` is meaningless in expression
position without handling the error case. Requiring immediate consumption via `??` or
`try` prevents silent error swallowing.

### Q5: AST changes

| Node          | Change                                                                    |
|---------------|--------------------------------------------------------------------------|
| `CastExpr`    | Remove `fallback: Stmt` field. Only stores `target, value`.               |
| `NullCoalesceExpr` | **Unchanged** — already supports `left ?? right` and `left ?? \|e\| right`. |
| `TryExpr`      | **Unchanged** — `try expr`.                                               |

No new AST nodes needed. The `??` and `try` nodes are already generic over any
Result-producing expression, including Cast.

### Q6: Parser changes

| Function           | Change                                                                                     |
|--------------------|-------------------------------------------------------------------------------------------|
| `Parser::primary()` | Cast: remove `else` branch. CastExpr no longer accepts fallback.                           |
| `Parser::coalesce()` | **No change** — `??` already parses after pipeline, right-associative.                     |
| `Parser::unary()`   | **No change** — `try` already a soft keyword at unary precedence.                          |
| Precedence          | Cast > unary > coalesce(??) > assignment. Cast binds tightest, `??` is between pipeline and assignment. |

Atom: `CastExpr` wraps its value expression as usual.

### Q7: Checker changes

**Cast fallibility matrix** (unchanged):

| From     | To      | Category      |
|----------|---------|---------------|
| int      | float   | infallible    |
| float    | int     | infallible    |
| int/float| string  | infallible    |
| string   | int     | fallible      |
| string   | float   | fallible      |

**New rules:**

1. **Infallible Cast** → expression type is target type T. No Result wrapping.
   - `int(3.14)` → type `int`
   - `float(42)` → type `float`

2. **Fallible Cast** → expression type is `Result<T, CastError>`.
   - `int(s)` → type `IntResult` (== `Result<Int, CastError>`)
   - Must be consumed by `??` or `try` in the same expression context.
   - Bare `int(s)` without `??` or `try` is a compile error.

3. **`??` on Cast** → LHS is `Result<T, E>`, RHS must produce `T`. Expression type is `T`.
   - Already checked by existing `??` checker logic.

4. **`try` on Cast** → LHS is `Result<T, E>`. Expression type is `T`.
   - Enclosing function must return compatible `Result<_, E>`.
   - Already checked by existing `try` checker logic.

### Q8: Compiler changes

**Cast compiler** (`emit_cast`):

```
For infallible casts:
  compile_expr(value)        # push source value
  CastTo(target_kind)         # in-place conversion, no Result
  → stack: T

For fallible casts:
  compile_expr(value)         # push source string
  Call string.parse_int/parse_float (or CastTo fallible variant)
  → stack: Result<T, CastError>  (as enum variant)

  Fallback handling moved to ?? / try compiler (below).
```

Wait — the bootstrap VM's `CastTo` opcode pushes `null` on failure, not a Result.
We need an opcode change:

**Option 1**: Extend `CastTo` to produce Result enum variants.
**Option 2**: Add `CastToResult` opcode that produces Result wrapping.

Leaning toward Option 1 (extend CastTo semantics): when target is a fallible cast
destination, `CastTo` pushes:
- `Ok(value)` (variant index 0, payload = parsed value) on success
- `Err(CastError::X)` (variant index 1, payload = variant index of CastError) on failure

This reuses the existing enum variant encoding (opcode EnumVariant already handles this).

**`??` compiler** (`compile_coalesce`):

No semantic change — already handles Result types. The emitted bytecode:
```
Dup
EnumVariant(err_variant_idx)
Eq
JmpFalse → ok_path
  # Err path
  (optional: EnumPayloadGet + StoreLocal for |e| binding)
  compile_expr(rhs)
  Jmp → end
ok_path:
  EnumPayloadGet(0)    # extract Ok payload
end:
```

**`try` compiler** (`compile_try`):

No semantic change — already handles Result types. The emitted bytecode:
```
StoreLocal(temp_slot)
Pop
LoadLocal(temp_slot)
EnumVariant(err_variant_idx)
Eq
JmpFalse → err_path
  # Ok path
  LoadLocal(temp_slot)
  EnumPayloadGet(0)
  Jmp → end
err_path:
  LoadLocal(temp_slot)
  Return
end:
```

### Q9: Implementation order (self-hosted)

The self-hosted compiler already has Cast (`42a4953`). The implementation order:

| Step | Description                                          | Files              |
|------|------------------------------------------------------|--------------------|
| 1    | **Add Result enum types** to bytecode.kl + pre-register in compiler.kl. IntResult, FloatResult, CastError as built-in enum metas. | `bytecode.kl`, `compiler.kl` |
| 2    | **Modify Cast AST**: remove fallback field from CastExpr. Update ast.kl. | `ast.kl` |
| 3    | **Modify parser**: remove `else` parsing from Cast. Cast now always a primary expr without fallback. | `parser.kl` |
| 4    | **Modify compiler**: CastTo emits Result enum variant (Ok/Err) for fallible casts instead of null. | `compiler.kl` |
| 5    | **Already done: `??` parser** — coalesce() already parses `??` between assignment and pipeline. Add NullCoalesceExpr to ast.kl, parser.kl. | `ast.kl`, `parser.kl` |
| 6    | **Already done: `try` parser** — unary() already parses `try` as soft keyword. Add TryExpr to ast.kl, parser.kl. | `ast.kl`, `parser.kl` |
| 7    | **`??` compiler**: compile_coalesce() — Dup + EnumVariant + JmpFalse + fallback/Ok paths. | `compiler.kl` |
| 8    | **`try` compiler**: compile_try() — StoreLocal + EnumVariant + JmpFalse + early Return/Ok paths. | `compiler.kl` |
| 9    | **Checker**: fallibility rules for Cast, Result-type resolution for `??`/`try`. | `checker.kl` |
| 10   | **Golden tests**: cast with `??`, `try` on cast, `try` on Result, `??` on Result. | `tests/codegen/cases/` |

Note: Steps 5–6 (?? and try parser) don't exist in the self-hosted parser yet. The
bootstrap has them. The self-hosted parser needs to add:
- `null_coalesce()` at precedence between assignment and pipeline
- `try` soft keyword in unary()

## 4. Syntax Summary (end state)

```kl
// Infallible casts
float(42)             // 42.0
int(3.14)             // 3
string(42)            // "42"

// Fallible casts with fallback
int(s) ?? 0
float(s) ?? 0.0
int(s) ?? |e| handle_err(e)

// Error propagation
try int(s)            // Ok → v, Err → early return

// Result types (general)
some_result ?? default
some_result ?? |e| { log(e); default }
try some_result
```

`else` is no longer used for Cast fallback. It remains only for `if/else`.
