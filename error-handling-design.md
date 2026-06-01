# Error Handling — Unified Design

> **NOTE:** This file is at the repo root because `docs/design/` is owned
> by `root` and I can't write there. After fixing ownership
> (`sudo chown -R sentomk:sentomk docs compiler cli.kbc*`), move it:
> `mv error-handling-design.md docs/design/error-handling.md`.

Status: design only. Targets RFC 0001 (`??` / `try`, retire cast `else`).
Applies to both the C++ bootstrap and the self-host compiler.

## Summary

Today three error-handling features evolved independently:

- **Cast**: `T(value) [else fallback]` — `else` is borrowed from `if/else`,
  which is confusing.
- **??**: only operates on Result-shaped enums (`Ok`/`Err`).
- **try**: only operates on Result-shaped enums; early-returns `Err`.

This design picks a single mental model:

> **Fallible operations produce a `Result`. `??` and `try` are the only
> ways to consume a `Result`.**

Cast is folded into that model: a *fallible* cast produces a Result
(`IntResult`, `FloatResult`); an *infallible* cast produces the target
type directly. The `else` clause on Cast is removed entirely. There is
no third operator.

Built-in enums (already pre-registered in the bootstrap) carry the design:

```
enum CastError  { Empty, NotANumber(string), Overflow(string) }
enum IntResult  { Ok(int),   Err(CastError) }
enum FloatResult{ Ok(float), Err(CastError) }
```

## Q1 — Cast syntax change

**Decision: Option A.** Replace `else` with `??`. Drop `else` for casts.

- The bootstrap is pre-1.0; there are no external users to keep
  backward-compatible for. Source files inside both repos are
  enumerable and can be migrated in the same commits that land the
  feature.
- Two operators for the same job (Option C) reintroduces exactly the
  conflict we are trying to remove. Option B (accepting both with
  deprecation) is dead weight in a one-developer codebase.
- `else` stays reserved for `if/else` and `guard ... else`. Cast no
  longer overloads it.

## Q2 — Cast result type

**Decision: Option B (with infallible bypass).** A cast's *expression
type* is determined by the source/target pair, using the existing
fallibility matrix:

| Source → Target              | Result type                 | Fallible? |
|------------------------------|-----------------------------|-----------|
| `int ↔ float`                | target type (`int`/`float`) | infallible |
| `int`/`float` → `string`     | `string`                    | infallible |
| `string` → `int`             | `IntResult`                 | fallible  |
| `string` → `float`           | `FloatResult`               | fallible  |
| same-type                    | (rejected: redundant)       | —         |
| anything else                | (rejected: no conversion)   | —         |

Rationale:

- Infallible casts have a single sensible value; wrapping them in a
  `Result` would force callers to unwrap something that cannot fail
  and adds churn.
- Fallible casts have *two* possible outcomes. The current "push null
  on failure, force the user to write `else`" works, but it lives
  outside the type system: the static type is `int` but the runtime
  value can silently be `null`. Lifting the failure into the type
  system means `??`, `try`, `match`, and pattern destructuring all
  work uniformly without special-casing Cast.
- Option A (keep null) overloads `??` to mean "unwrap Result *and*
  null-coalesce". That is exactly the kind of "this operator means
  several things" that we are removing from `else`.
- Option C (no Result wrap, mandate inline `??`) blocks `try` from
  working on casts and bakes the fallback into the expression form,
  preventing parse errors from being propagated.

This is a behavioural change to Cast. The compiled bytecode for
fallible casts is no longer `CastTo + Dup + IsNull + JmpFalse + Pop +
fallback`; it becomes a single `Result`-producing instruction (see Q8)
followed by the normal `??` or `try` lowering.

## Q3 — try and Cast interaction

**Decision: Yes. `try int("42")` works without new syntax.**

Because Q2 makes `int("42")` produce `IntResult`, `try` consumes it
the same way it consumes any other `Result`. No `int?(x)` /
question-mark cast form is needed.

```kinglet
fn parse_age(s: string) -> IntResult {
  let n = try int(s);     // Err short-circuits, propagates CastError
  return IntResult::Ok(n);
}
```

For an infallible cast, `try int(some_float)` is a type error: the
operand is `int`, not a Result. The existing `try`-on-non-Result
diagnostic covers this with no extra logic.

## Q4 — Unified syntax surface

```kinglet
// Infallible casts — produce the target type directly
let f: float  = float(42);     // int → float
let n: int    = int(3.7);      // float → int (truncates toward 0)
let s: string = string(42);    // int → string

// Fallible cast — produces IntResult / FloatResult
let r: IntResult = int("42");

// Cast + ?? to coalesce a fallible cast inline
let n: int = int(input) ?? 0;
let n: int = int(input) ?? |e| {
  io::err("bad number: " + e match {
    CastError::NotANumber(let txt) => txt,
    CastError::Empty               => "(empty)",
    CastError::Overflow(let txt)   => txt,
  });
  return -1;
};

// ?? on a Result returned from a function (unchanged)
let cfg = load_config(path) ?? default_config();

// try on a Result (unchanged)
fn run() -> IntResult {
  let n = try parse_count();   // propagates Err early
  return IntResult::Ok(n + 1);
}

// try on a fallible cast — no new syntax
fn parse_age(s: string) -> IntResult {
  let n = try int(s);
  return IntResult::Ok(n);
}
```

No new operators. No `int?(...)` form. The fallibility of a cast is a
property of the source/target pair, surfaced in its result type.

## Q5 — AST changes

| Node | Change |
|---|---|
| `CastExpr` (bootstrap `ast.h:242`, self-host `ast.kl` `Cast` variant) | **Drop the `fallback` field.** A Cast is now a pure conversion expression. Fallback handling moves into `NullCoalesceExpr` at the call site. |
| `NullCoalesceExpr` (bootstrap `ast.h:153`) | **Unchanged.** Still `(left, err_binding, right)`. Now naturally accepts a Cast on its LHS because Cast can be Result-typed. |
| `TryExpr` (bootstrap `ast.h:165`) | **Unchanged.** Still `(value)`. |

No new nodes. The Cast variant in the self-host `Expr` enum drops one
positional argument:

```
// before:  Cast(TypeExpr, Expr, Expr, int, int)         — target, value, fallback, line, col
// after:   Cast(TypeExpr, Expr, int, int)               — target, value, line, col
```

This is a breaking change to the AST shape; every match arm on
`Expr::Cast` in the self-host (parser/ast/checker/compiler) is touched.

## Q6 — Parser changes

| Function | Change |
|---|---|
| `Parser::primary()` (bootstrap `parser.cc:1101`) / `cast_expr` (self-host `parser.kl:489`) | **Stop matching `ELSE` after Cast.** The block that consumes `else` and parses a fallback expression/block is deleted. |
| `Parser::coalesce()` (bootstrap `parser.cc:847`) | **Unchanged.** Right-associative; sits between assignment and pipeline. Consumes anything `pipeline()` produces, including the new Cast. |
| `Parser::unary()` (bootstrap `parser.cc:1007`) | **Unchanged.** `try` is still a soft keyword at unary precedence. |

**Precedence: unchanged.** Cast already binds tighter than `??`, so
`int(x) ?? 0` parses as `(int(x)) ?? 0` without any precedence work.
`try int(x)` already parses as `try (int(x))` because `try` is unary.

The `??` token must lex; that is the existing TODO #8 (already in
flight on the bootstrap side per `HANDOFF.md:114`).

## Q7 — Checker changes

**CastExpr (bootstrap `type_checker.cc:960`).** Today the checker
classifies a cast as *infallible* or *fallible* and demands the
fallback be present-or-absent accordingly. After this change:

- The infallible/fallible classification is kept, but its only effect
  is choosing the *result type*: target type for infallible,
  `IntResult` / `FloatResult` for fallible.
- Same-type and unsupported pairs remain errors (unchanged).
- The two diagnostics tied to `cast->fallback`
  (`"'else' clause is not allowed: ..."` and
  `"... may fail; provide an 'else' clause."`) are deleted — the AST
  no longer has the field, and the rule they enforced is now a
  type-system rule. A bare `int(s)` for a string source is no longer
  rejected; its result type is `IntResult` and the caller must
  consume it.
- The fallibility matrix table itself is unchanged.

**NullCoalesceExpr.** Rules unchanged: LHS must be a Result-shaped
enum (has `Ok` and `Err` variants); RHS type must match `Ok`'s
payload; the `|e|` binding (when present) is the `Err` payload. The
*set of expressions* that can appear on the LHS is now larger because
Cast can be Result-typed, but no new rules are needed — Cast is just
another expression with a (sometimes) Result type.

**TryExpr.** Rules unchanged: operand must be Result-shaped; the
enclosing function's return type must be a Result whose `Err` payload
is compatible with the operand's. Same comment as `??` — Cast becomes
a valid operand without new logic.

**Built-in enums.** `CastError`, `IntResult`, `FloatResult` are
already pre-registered in the bootstrap (`type_checker.cc:175-198`).
The self-host checker must register the same three under the same
names so type comparisons by-name succeed and so generated bytecode
references identical type indices.

## Q8 — Compiler changes

The current Cast lowering pushes `null` on failure and uses a
`Dup + IsNull + JmpFalse + Pop + <fallback>` pattern. That pattern
disappears. Fallible casts now produce an enum value at runtime.

**New opcode: `CastFallible`** (operand: target kind 0=int, 1=float).
- Pops one string operand from the stack.
- On successful parse: pushes `IntResult::Ok(int)` or
  `FloatResult::Ok(float)`.
- On parse failure: pushes the matching `Err(CastError::...)` —
  `Empty` for empty input, `NotANumber(input)` for unparseable,
  `Overflow(input)` for out-of-range.

This is preferable to keeping `CastTo`'s null-failure semantics and
emitting a Dup/IsNull dance plus enum-construction at every cast
site:

- Smaller bytecode (one instruction vs ~10).
- Centralizes the error-classification logic in the VM, where it has
  access to the underlying parse error code.
- Removes the need for the compiler to know the variant indices of
  `CastError` / `IntResult` / `FloatResult` at every cast site.
- `CastTo` retains its existing semantics (used only for infallible
  casts: int↔float, num→string), so existing infallible-cast goldens
  do not change.

**`compile_cast_expr` / `emit_cast`** (bootstrap `compiler.cc:1368`,
self-host `compiler.kl:316`):

- For infallible source/target pairs: unchanged — emit `CastTo`.
- For fallible pairs: emit **`CastFallible`** with the same target
  kind. No `Dup`, no `IsNull`, no fallback handling. The Result lands
  on the stack; downstream `??` / `try` (if present) operates on it.
- Drop the `if (cast_expr->fallback) { ... }` block entirely — the AST
  field is gone.

**`compile_coalesce`** (bootstrap `compiler.cc:1583`): **unchanged.**
Already consumes any Result-shaped enum on the LHS.

**`compile_try`** (bootstrap `compiler.cc:1670`): **unchanged.**
Already early-returns the `Err` from the enclosing function.

**Bytecode equivalence note.** The self-host compiler's golden tests
compare its bytecode byte-for-byte against the bootstrap. As long as
both sides land the `CastFallible` opcode, drop the
`Dup/IsNull/JmpFalse/Pop` pattern, and emit `??` / `try` lowering
identically (which they already do for non-Cast inputs), goldens stay
in sync.

## Q9 — Implementation order

Each step is a self-contained commit. Bootstrap moves first; self-host
mirrors. Cross-repo PRs are paired in lockstep so goldens stay green.

**Bootstrap (C++)**

1. **Lex `??`.** Add `QUESTION_QUESTION` token and scanner rule.
   Standalone — no semantic change yet. *(TODO #8)*
2. **Parse + AST for `??` and `try`.** Add `NullCoalesceExpr` and
   `TryExpr` to `ast.h`; wire `Parser::coalesce()` and the `try`
   branch in `Parser::unary()`. No checker/compiler yet — purely
   syntactic. *(TODO #9)*
3. **Type-check `??` and `try`.** Implement the Result-shape rule for
   `??` LHS and `try` operand; implement enclosing-fn return-type
   rule for `try`. *(TODO #10)*
4. **Compile `??` and `try`.** Existing patterns from
   `compiler.cc:1583` / `1670`. After this commit, `??` and `try`
   work end-to-end on user-defined Result types.
5. **Add `CastFallible` opcode** in VM + disassembler. No compiler
   emits it yet. Standalone, easily revertable.
6. **Switch fallible Cast to `CastFallible` + retire `else`.** This is
   one commit because removing `else` while leaving the old
   null-failure path live would leave fallible casts unusable.
   - Parser: stop consuming `ELSE` after Cast.
   - AST: drop `CastExpr::fallback`.
   - Checker: type fallible casts as `IntResult`/`FloatResult`; delete
     the two `else`-related diagnostics.
   - Compiler: emit `CastFallible` for fallible pairs; delete
     `Dup/IsNull/Pop/fallback` block.
   - Migrate any in-tree `.kl` files (tests, fixtures) from
     `T(x) else fb` to `T(x) ?? fb`. *(TODO #11)*
7. **Golden refresh.** Re-bake any cast-related goldens whose
   bytecode shape changed. Verify via `bash tests/cli/run_golden.sh`.

**Self-host (Kinglet)**

8. **Lex `??`** in `scanner.kl` / `keywords.kl`.
9. **AST + parser for `??` and `try`.** Mirror bootstrap shape. The
   AST gains `Expr::NullCoalesce(Expr, string, Expr, int, int)` and
   `Expr::Try(Expr, int, int)`.
10. **Type-check `??` and `try`** in `checker.kl`, including
    pre-registering `CastError`/`IntResult`/`FloatResult`.
11. **Compile `??` and `try`** in `compiler.kl`. Emit byte-for-byte
    identical bytecode to the bootstrap.
12. **Switch self-host Cast to the new model.** One commit:
    - Drop `Else` parsing in `cast_expr`.
    - Drop the `fallback` slot from `Expr::Cast`; update every match
      arm in `parser/`, `checker/`, `compiler/`.
    - In `emit_cast`: for infallible pairs emit `CastTo`; for fallible
      emit `CastFallible`; delete the `Dup/IsNull/JmpFalse/Pop`
      block.
13. **Golden tests** for `??`, `try`, and Cast in
    `tests/codegen/cases/`, comparing self-host bytecode to bootstrap
    bytecode.

**Sequencing note.** Steps 1–4 (bootstrap `??` / `try` for user
Result types) can land independently of Cast; nothing about them
forces the Cast change. Step 6 is the breaking commit. Self-host
steps 8–11 can begin as soon as bootstrap step 4 is in. Self-host
step 12 needs bootstrap step 6 to be in first, otherwise self-host
emits bytecode the bootstrap VM rejects (no `CastFallible` opcode
yet).

The ~85s rebuild cycle for `cli.kbc` argues for batching steps 8–11
into a single self-host work session and steps 12–13 into another;
that minimizes intermediate rebuilds.
