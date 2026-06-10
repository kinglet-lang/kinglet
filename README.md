# Kinglet (self-host)

[![CI](https://github.com/kinglet-lang/kinglet/actions/workflows/ci.yml/badge.svg)](https://github.com/kinglet-lang/kinglet/actions/workflows/ci.yml)

Self-hosted Kinglet compiler: the `.kl` sources in this repo compile to bytecode
(`.kbc`) that runs on the C++ VM from the
[bootstrap compiler](https://github.com/kinglet-lang/bootstrap). Round-trip against the
bootstrap compiler is verified.

Kinglet is a statically typed, value-semantics language (see
[decisions/0002](decisions/0002-design-principles.md)). This tree is the
compiler implementation — lexer, parser, checker, and VM bytecode backend — not
the language spec alone.

## Prerequisites

- **Bootstrap VM** — a built `kinglet` binary (default:
  `../kinglet/out/Default/kinglet`). Override with `KINGLET=/path/to/kinglet`.
- No other runtime dependencies; sources are plain `.kl` files.

## Quick start

```bash
# Bootstrap compiler (C++ reference implementation)
export KINGLET_BOOTSTRAP=../kinglet/out/Default/kinglet   # adjust if needed

# Build toolchain artefact (Ref compile → .kinglet/out/compiler.kbc; cached by stamp)
./kinglet build

# Run the self-host CLI on a source file (VM host = backend/vm/out/kinglet)
export KINGLET=backend/vm/out/kinglet
$KINGLET --run .kinglet/out/compiler.kbc --ast path/to/file.kl
$KINGLET --run .kinglet/out/compiler.kbc --save-bytecode out.kbc path/to/file.kl

# Run the full test suite (rebuilds only on stamp miss)
bash tests/run_all.sh
```

Build output lives under `.kinglet/` (see [decisions/0014](decisions/0014-compilation-toolchain-architecture.md)).
Test helpers call `ensure_build_stamp` in `tests/common.sh`.

## Repository layout

```
kinglet-self/
  core/           CLI entry (main.kl), AST printer, checker driver
  lexer/          Scanner, tokens, keywords
  parser/         AST, recursive-descent + Pratt parser
  checker/        Type checker
  compiler/       AST → bytecode (imports, match, builtins, …)
  backend/        C++ VM experiments (embedded self-host; see decisions/0010)
  decisions/      Design RFCs (English)
  tests/          Harness-driven suites (see tests/README.md)
  kinglet         Project build driver (`./kinglet build`)
  .kinglet/       Klos cache and build output (gitignored)
  kinglet.toml    Project manifest (`//` import paths, `[build]` section)
  SYNTAX.md       Syntax notes and self-host / bootstrap boundaries
  AGENT.md        Context for AI-assisted development
```

Module system: `import { "//parser/ast.kl" }` with file-stem namespaces;
`using ast { Expr };` for selective imports. See
[decisions/0011](decisions/0011-module-system-redesign.md).

## Testing

See **[tests/README.md](tests/README.md)** for the full layout (decision 0012).

| Suite | Command | What it checks |
|-------|---------|----------------|
| All | `bash tests/run_all.sh` | Gating suites + probe/builtin/differential snapshots |
| Harness (ad-hoc) | `bash tests/harness/run.sh <cases/>` | Directive-driven pipelines |
| Selfhost E2E | `bash tests/exec/run.sh` | `compiler.kbc` compile + run |
| Sema | `bash tests/sema/run.sh` | `--check` pass and fail cases |
| Differential | `bash tests/differential/run.sh` | bootstrap vs selfhost must match |
| Property | `bash tests/property/run.sh` | AST/token stability + fuzz-lite |
| Capability matrix | `bash tests/probe/run_matrix.sh` | 28 language-feature probes (snapshot) |
| Builtin methods | `bash tests/builtin_methods/run_matrix.sh` | 26 builtin methods (snapshot) |

**Authoritative self-host semantics** — `exec/`, `sema/`, probe, and builtin
matrices run through `compiler.kbc`. Bootstrap `kinglet` is the VM host; differential
and regression also exercise the C++ compiler path.

Detailed write-ups:

- [tests/README.md](tests/README.md) — suite index and harness guide
- [tests/harness/directives.md](tests/harness/directives.md) — directive language
- [tests/probe/README.md](tests/probe/README.md) — feature capability matrix
- [tests/builtin_methods/README.md](tests/builtin_methods/README.md) — builtin
  method coverage, opcode reference, checker gaps

### Current snapshot (2026-06-08)

| Matrix | run✓ | Notes |
|--------|-----:|-------|
| Feature probes (`tests/probe`) | 28/28 | Bootstrap aligned on same corpus (see differential) |
| Builtin methods | 26/26 runtime | Checker 24/26; see builtin README for fix list |

## V0 verification

Before archiving the bootstrap repo, run the three CI tiers locally — see
[docs/v0.md](docs/v0.md).

## Documentation

| Document | Purpose |
|----------|---------|
| [SYNTAX.md](SYNTAX.md) | Syntax, operators, sh/bs differences |
| [decisions/README.md](decisions/README.md) | Architecture RFC index |
| [decisions/0003-stdlib-roadmap.md](decisions/0003-stdlib-roadmap.md) | Planned `stdlib/` layout |
| [AGENT.md](AGENT.md) | Conventions, commit style, bootstrap quirks |
| [docs/ci.md](docs/ci.md) | GitHub Actions CI/CD and local reproduction |

## Related repositories

| Repository | Role |
|------------|------|
| [github.com/kinglet-lang/bootstrap](https://github.com/kinglet-lang/bootstrap) | C++ bootstrap compiler + VM (reference implementation) |
| [github.com/kinglet-lang/kinglet](https://github.com/kinglet-lang/kinglet) | Self-host compiler sources + tests (this repo) |

## License

See repository metadata; no separate LICENSE file at this time.
