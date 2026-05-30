# Kinglet — Project Handoff

> Snapshot for picking the project up on a different machine. Written
> 2026-05-31. Update or delete sections as state moves on; this file is
> meant to be a short-lived bridge, not a permanent spec.

## Two repositories

The project lives in two separate working directories. They are independent
git repos. Keep them side-by-side with the same parent so relative paths in
notes work.

| Path | Role | Language |
|---|---|---|
| https://github.com/sentomk/kinglet | C++ bootstrap compiler. Source of truth for the language **today**. | C++20 |
| https://github.com/kinglet-programming-language/kinglet | Self-host compiler. The future Kinglet implementation, written in Kinglet itself. | Kinglet |

The C++ binary built from the bootstrap repo is what runs the self-host
code. Until the self-host compiler can compile itself, the C++ side is
the authoritative implementation; the self-host side is a parallel
re-implementation that consumes its output.

To build the bootstrap binary, clone https://github.com/sentomk/kinglet,
ensure `gn` and `ninja` are available, then:

```bash
gn gen out/Debug
ninja -C out/Debug
```

The resulting `out/Debug/kinglet` (or `kinglet.exe` on Windows) is what
the self-host scripts invoke.

## What works right now

### C++ side (bootstrap — https://github.com/sentomk/kinglet)
- Full pipeline: Scanner → Parser → TypeChecker → Compiler → Bytecode VM
- Modules: `using io/fs/sys;`, selective `import "path.kl" { Sym }`, transitive imports, paths resolved relative to the importing file
- Types: int / float / double / bool / string / byte / arrays / structs / enums (with payloads) / generics (monomorphized) / traits + impls
- Pattern matching: `x match { Variant(let v) => ... }` with exhaustiveness warnings
- Built-in pre-registered enums: `CastError`, `IntResult`, `FloatResult`
- Cast expressions: `T(value) [else { ... }]` with a fallibility matrix
- Recursive / forward-referenced struct/enum types (committed today as `5da1975`)
- LSP server: diagnostics, completion, go-to-def, hover, document symbols, signature help
- Test harness: `tests/cli/run_golden.sh` — full CLI golden suite, currently green

### Self-host side (https://github.com/kinglet-programming-language/kinglet)
Layout:
```
<self-host repo>/
├── lexer/
│   ├── token.kl     (TokenType enum, Token struct with line/col/lexeme/int/float/string values)
│   └── scanner.kl   (scan(string) -> Token[])
├── cli/
│   └── main.kl      (entry: reads sys::args(), runs scan, prints tokens)
├── tests/lexer/
│   ├── cases/       (paired *.kl + *.tokens golden fixtures)
│   └── run_golden.sh
└── (no parser, ast, checker, codegen, std/, docs/ yet)
```
The self-host **lexer** is feature-complete enough to tokenize itself.
With `KINGLET` pointing at the bootstrap binary and run from the
self-host repo root:
```bash
"$KINGLET" cli/main.kl <some.kl>
bash tests/lexer/run_golden.sh
```

## Conversation context — what was just done

Last session's work, in order:
1. Built `cli/main.kl` self-host entry, added five lexer golden cases, and added a `string_value` field to `Token` so escape sequences are unescaped at scan time. Committed on self-host side as `fdb8645`.
2. On the C++ side, fixed module loader to resolve nested imports relative to their importing file (not the entry file), and reordered enum/struct registration in three import paths so imported struct fields with imported enum types type-check. Committed as `931cf98`.
3. On the C++ side, added forward-decl support for recursive and forward-referenced user-defined types: a pre-pass in `TypeChecker::check()` registers every struct/enum name with an empty stub before any fields are resolved, plus a registry re-lookup at field-access time so forward-ref snapshots can't go stale. Regression test `tests/cli/cases/recursive_types.kl` covers recursive enums, self-ref structs through arrays, and forward sibling references. Committed as `5da1975`.

This unblocks self-host work: AST nodes are themselves recursive ADTs
(`Expr::Binary(Expr, Expr)` and friends) and could not be expressed in
Kinglet without that fix.

## Roadmap — next steps in order

### Immediate (next session)
1. **Stand up `docs/` on the self-host side.** No code yet, just structure:
   - `docs/README.md` — index
   - `docs/roadmap.md` — bootstrap stages
   - `docs/rfcs/0000-template.md` — RFC template (Summary / Motivation / Design / Alternatives / Migration / Status)
   - `docs/language/` — language spec placeholders (grammar, types, modules, stdlib)
   - `docs/design/` — self-host compiler ADRs (e.g. ast-representation, error-reporting)
2. **Refactor the lexer keyword/token registry** so adding a token only touches `token.kl` plus one data table:
   - New `lexer/keywords.kl` exporting `Keyword[] all_keywords()` (`spelling`, `type`, `display`)
   - `scanner.kl` keyword check becomes a table lookup
   - `cli/main.kl:tt_name` rewritten as a table lookup (extend the table to cover non-keyword tokens too — the long if-chain there is the biggest cleanup win)
   - Linear scan is fine; total token count is small. Map-cache only if profiling says so.

### Short term (next 1–2 sessions)
3. **RFC 0001 — `??` and `try` operators, retire cast `else`.** TODO list items #8–#11 on the C++ side. RFC drives the design; implementation lands in C++ first, then mirrored in self-host.
4. **RFC 0002 — Standard library layout.** Two layers: native primitives (Layer 1, host-provided) and Kinglet-implemented stdlib (Layer 2, in `std/`). Decisions to record:
   - How does `using io;` find `std/io/mod.kl`? (search root + env var)
   - File-as-module vs explicit `namespace` blocks
   - FFI syntax for native primitives
   - Initial module list: io, fs, sys, string, collections, result, math
5. **AST design note** in `docs/design/`. Decide enum-of-variants vs tagged-struct, error node strategy, source-location storage.

### Bootstrap path (medium term)
6. `parser/` — recursive descent, `Token[] -> Decl[]`. Mirror C++ parser shape.
7. `ast/` — AST node definitions. Now writable thanks to the recursive-types fix.
8. `checker/` — type checker.
9. `codegen/` — initially target the same bytecode the C++ VM consumes, so the self-host frontend can be validated against the C++ VM before writing a self-host VM.
10. `std/` — populate per RFC 0002.

## C++ TODO carryover (still pending)

From the bootstrap repo's `TODO.md`, the items active in our task list:
- #8 lex `??` operator
- #9 parser + AST for `??` and `try`
- #10 type-check `??` and `try`
- #11 compile `??/try`, retire cast `else`

These are gated behind RFC 0001 above.

## Conventions / things easy to forget

- **Shell:** Bash (Git Bash on Windows, native bash elsewhere). Use Unix syntax — forward slashes, `/dev/null`, no `NUL`.
- **Binary path:** point `KINGLET` at the bootstrap binary built from https://github.com/sentomk/kinglet. The self-host golden runner defaults to `$ROOT/../../kinglet/out/Debug/kinglet` assuming the two repos sit side-by-side; override `KINGLET` for any other layout.
- **Build C++ side:** `ninja -C out/Debug` from the bootstrap repo. `gn gen out/Debug` only when `BUILD.gn` changes.
- **Run golden suites:**
  - C++: `bash tests/cli/run_golden.sh` from the bootstrap repo
  - Self-host lexer: `bash tests/lexer/run_golden.sh` from the self-host repo
- **CRLF:** golden runners normalize with `sed -i 's/\r$//'`. Don't strip that.
- **Native intrinsics on C++ side** (`io`/`fs`/`sys`) are hard-coded across `compiler.cc`, `type_checker.cc`, etc. There is no registry. Don't try to "tidy this up" without a plan — the self-host stdlib (RFC 0002) is the place to do it right.
- **Self-host module imports** use `import "../lexer/token.kl" { Token, TokenType }` form. Paths are relative to the importing file (this was fixed today on the C++ loader).
- **Token formatting for goldens:** strings get re-escaped via `display_string` in `cli/main.kl` so newlines don't break diff output.

## Things explicitly **not** decided yet

Don't assume answers; revisit in RFCs:
- Whether modules are file-as-module or explicit `namespace { }` blocks
- Whether the self-host compiler emits the C++ VM's bytecode, a new IR, or native code
- Error-handling story end-state (`Result<T, E>` ubiquity vs `?`/`try` vs panics)
- Whether generics stay monomorphization-only
- Concurrency model (currently nothing; spawn/select/channels are on the C++ TODO P4)

## Active task list (across both repos)

- [pending] cpp: lex `??` operator (#8)
- [pending] cpp: parser + AST for `??` and `try` (#9)
- [pending] cpp: type-check `??` and `try` (#10)
- [pending] cpp: compile `??/try`, retire cast `else` (#11)
- [completed] selfhost: cli/main.kl entry (#12)
- [completed] selfhost: lexer golden tests (#13)
- [completed] selfhost: unescape strings + Token.string_value (#14)
- [completed] cpp: forward-decl pass for recursive struct/enum (#15)
- [completed] cpp: add built-in `Result<T, E>` and `CastError` enums (#7)

## Where to look for more

- C++ side has `AGENTS.md` (build instructions, conventions) and `TODO.md` (longer wishlist organized P1–P5).
- C++ side `docs/changelog/v0.0.*.md` records past releases.
- Self-host side has nothing yet — that's what step 1 of the roadmap fixes.
