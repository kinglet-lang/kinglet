# AGENT.md — Kinglet Project Context

> This file provides AI agents with the context needed to work effectively on the
> Kinglet compiler. Read it before making changes.

## What Kinglet Is

Kinglet is a **self-hosting compiler** for a statically-typed language called Kinglet
(extension `.kl`). The bootstrap compiler is C++; the self-host compiler is written in
Kinglet itself and compiles to bytecode that runs on a C++ VM. The self-host compiler
has achieved **round-trip verification** — compiling itself produces byte-identical
bytecode to the bootstrap compiler.

## Architecture Overview

```
Source (.kl)
  │
  ├── Lexer (scanner.kl + token.kl + keywords.kl)
  │     Produces Token stream with line/col positions
  │
  ├── Parser (parser.kl + ast.kl)
  │     Recursive-descent + Pratt parser → Program AST
  │     Every node carries (line, col)
  │
  ├── Checker (checker.kl)
  │     Type checking, declaration registration, diagnostics
  │
  ├── Compiler (compiler.kl + bytecode.kl + disasm.kl)
  │     AST → bytecode for the C++ VM
  │     Supports imports, enums, match, built-in methods
  │
  └── CLI (cli/main.kl)
        Entry point; wires scanner → parser → checker → compiler
```

### Key Properties

- **6,273 lines** of Kinglet source across 10 files (no external dependencies)
- **57 test files**: golden tests for lexer, parser, checker, and codegen
- **AST mirror pattern**: `checker.kl` and `cli/main.kl` maintain local copies of the
  AST enums from `ast.kl` instead of importing them, due to a bootstrap compiler bug
  where duplicate pub-function registration across transitive imports corrupts function
  indices. See the header comment in `parser/parser.kl` for details.
- **Bytecode compatibility**: self-host output must match the C++ bootstrap compiler
  byte-for-byte. OpCode order in `bytecode.kl` is frozen to match `chunk.h`.

## Language Quick Reference

Kinglet is a C-family language designed as "C++ after completing worthwhile standard committee proposals." See `decisions/0002-design-principles.md` for the three design pillars: full value semantics, deterministic destruction, and zero-cost abstraction without ownership.

```kl
// Types: int, float, double, bool, string, byte, void, auto
// Structs, Enums (with payload variants)
// match expressions, ?? (null coalesce), try (error propagation)
// Import system: import "../path/module.kl" { sym1, sym2 }
// Namespaces: io::out, io::err (built-in), user-defined via namespace
// Built-in methods: .len(), .push(), .pop(), .slice(), .split(), etc.

int example(int x) {
  if x > 0 { return "positive"; }
  return "non-positive";
}
```

## Project Status

| Phase | Description | Status |
|-------|-------------|--------|
| 0 | Compound assignment (`+= -= *= /=`) | Done |
| 1 | Enum variant construction | Done |
| 2 | Match expressions | Done |
| 3 | Built-in methods | Done |
| 4 | Imports & modules | Done |
| 5 | Self-hosting (round-trip verified) | Done |
| 6 | Stdlib + FFI cleanup | Future |
| 7 | Self-hosted VM | Future |

See `decisions/README.md` for the full decision index.

## Development Conventions

### Commit Messages

Use **Conventional Commits** in English:

```
type(scope): short description

# Types: feat, fix, refactor, docs, test, chore, perf
# Scope: module name (lexer, parser, checker, compiler, ast, cli)
# Multiple scopes: feat(ast,parser,checker): ...

# Examples:
feat(compiler): compile match expressions with enum and binding patterns
fix(parser): use left-operand position for postfix and assign AST nodes
refactor(lexer): migrate .code() to int(s[i]) after char type addition
docs: self-host compiler round-trip verified
chore: remove stale task files and backups
```

Rules:
- Lowercase description, no trailing period
- Keep under 72 characters total
- No internal project codes or tracking labels

### Code Style

- **No comments explaining WHAT the code does** — well-named identifiers suffice.
- **Comments are for WHY**: bootstrap compiler quirks, non-obvious encoding conventions,
  workarounds for known bugs. The existing codebase follows this pattern.
- **One comment per block max**, kept to a single short line.
- **No emojis** in code or commit messages.
- **No docstrings or multi-line comment blocks.**

### Testing

Tests are **golden tests** organized by pipeline stage:

```
tests/
  lexer/cases/*.kl + *.tokens    — scanner output checked against expected tokens
  parser/cases/*.kl + *.ast      — parser output checked against expected AST
  checker/cases/*.kl             — pass/fail type checking cases
  codegen/cases/*.kl             — bytecode compilation cases
```

Each stage has a `run_golden.sh` driver. The codegen suite uses a pre-compiled
`cli.kbc` to avoid recompiling the self-host compiler (~85s) on every test run.

When adding a feature:
1. Add a `.kl` test case in the appropriate `tests/*/cases/`
2. Add the expected golden output (`.tokens`, `.ast`, or compiler output)
3. Run the relevant `run_golden.sh` to verify

### File Organization

- **One module per file**, file name matches module purpose
- **Parser stays in one file** (`parser/parser.kl`) — splitting it triggers the
  bootstrap compiler's struct-meta registration bug
- AST enums are defined in `parser/ast.kl`; mirrors in `checker/checker.kl` and
  `cli/main.kl` must be kept in sync manually
- Design documents live in `decisions/` (see `decisions/README.md` for index)

### Bootstrap Compiler Quirks

When working on the self-host compiler, be aware of these constraints inherited from
the C++ bootstrap:

1. **Constant pool**: deduplication is implemented in both bs and sh `add_constant()` (see 0005 P1).
2. **Call sequence**: args pushed before function constant, then `Call argc`.
3. **Function preamble**: `Constant<main_fn>; Call 0; Return` at instruction offset 0-2.
4. **Function fallthrough**: every function body ends with `Null; Return`.
5. **VarDecl**: emits `StoreLocal + Pop` (StoreLocal copies, does not pop).
6. **Import dedup**: the bootstrap dedups imports by resolved path, but transitive
   re-imports of the same module can still corrupt function indices in edge cases.

### Design Decisions

All significant design decisions are recorded in `decisions/`, numbered by proposal date.
See `decisions/README.md` for the full index.
