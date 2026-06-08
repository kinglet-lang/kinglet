# Kinglet (self-host)

Self-hosted Kinglet compiler: the `.kl` sources in this repo compile to bytecode
(`.kbc`) that runs on the C++ VM from the
[bootstrap compiler](https://github.com/sentomk/kinglet). Round-trip against the
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
# Build the self-host compiler artifact (~85s first time; cached as compiler.kbc)
export KINGLET=../kinglet/out/Default/kinglet   # adjust if needed
$KINGLET --save-bytecode compiler.kbc core/main.kl

# Run the self-host CLI on a source file
$KINGLET --run compiler.kbc --ast path/to/file.kl    # parse → AST
$KINGLET --run compiler.kbc path/to/file.kl --check  # type check
$KINGLET --run compiler.kbc --save-bytecode out.kbc path/to/file.kl

# Run the full test suite (rebuilds compiler.kbc when sources are stale)
bash tests/run_all.sh
```

`compiler.kbc` is checked in or regenerated automatically by test helpers via
`tests/common.sh` (`ensure_cli_kbc`).

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
  compiler.kbc    Prebuilt self-host compiler bytecode
  kinglet.toml    Project manifest (`//` import paths)
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
| Feature probes (`tests/probe`) | 24/28 | Gaps: top-level `const`, `?:` runtime, concept calls, UFCS |
| Builtin methods | 26/26 runtime | Checker 24/26; see builtin README for fix list |

## Documentation

| Document | Purpose |
|----------|---------|
| [SYNTAX.md](SYNTAX.md) | Syntax, operators, sh/bs differences |
| [decisions/README.md](decisions/README.md) | Architecture RFC index |
| [decisions/0003-stdlib-roadmap.md](decisions/0003-stdlib-roadmap.md) | Planned `stdlib/` layout |
| [AGENT.md](AGENT.md) | Conventions, commit style, bootstrap quirks |

## Related repositories

| Repository | Role |
|------------|------|
| [github.com/sentomk/kinglet](https://github.com/sentomk/kinglet) | C++ bootstrap compiler + VM (reference implementation) |
| [github.com/kinglet-lang/kinglet](https://github.com/kinglet-lang/kinglet) | Self-host compiler sources + tests (this repo) |

## License

See repository metadata; no separate LICENSE file at this time.
