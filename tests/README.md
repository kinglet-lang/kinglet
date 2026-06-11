# Test suite

Unified layout per [decision 0012](../decisions/0012-test-suite-redesign.md). All
selfhost-driven suites share `common.sh` (`resolve_kinglet`, `ensure_build_stamp`) and
the bootstrap C++ binary is only the **VM host** unless a suite explicitly compares
pipelines.

## CI

Push/PR to `main` runs [`.github/workflows/ci.yml`](../.github/workflows/ci.yml):
**test-fast** (Ref + selfhost suites) and **test-prove** (Shadow parity). See
[docs/ci.md](../docs/ci.md).

## Quick commands

```bash
bash tests/run_all.sh              # fast orchestrator (no Shadow parity)
./kinglet prove                    # round-trip + differential (Shadow vs Ref)
bash tests/harness/run.sh <path>   # ad-hoc harness on a file or directory
bash tests/exec/run.sh             # selfhost end-to-end (gate)
bash tests/sema/run.sh             # type checker pass + fail (gate)
bash tests/property/run.sh         # AST/token stability + fuzz-lite (gate)
bash tests/ir/run_golden.sh        # bootstrap --ir vs .kir goldens (M1)
bash tests/native/run_smoke.sh     # bootstrap --native smoke (L0; needs LLVM build)
```

Regenerate codegen goldens after bytecode changes:

```bash
bash tests/codegen/refresh_goldens.sh
```

## Layout

```
tests/
  harness/          run.sh, directives.md — shared directive runner
  lexer/            token goldens
  parser/           AST goldens
  sema/
    pass/           RUN: check (must pass)
    fail/           RUN: check + COMPILE-FAIL + CHECK-ERR
  codegen/          --bytecode goldens + smoke compile+run
  exec/             RUN: selfhost end-to-end
  differential/
    cases/          RUN: diff (gating)
    run_matrix.sh   broad snapshot (non-gating)
  regression/       selfhost oracle + bootstrap drift report (see regression/README.md)
  property/         parse/print stability + fuzz-lite
  probe/            28-feature capability matrix (snapshot)
  builtin_methods/  builtin method matrix (snapshot)
  diagnostics/      error message goldens
  kbc/              bytecode serialize round-trip
  selfhost/         fixed-point (S3==S4) + bootstrap parity gate (compiler.kbc==S3)
  run_selfhost/     additional selfhost behavioral cases
  common.sh
  run_all.sh
```

Deprecated wrappers (forward to new locations):

- `tests/run/run_golden.sh` → `tests/exec/run.sh`
- `tests/checker/run_golden.sh` → `tests/sema/run.sh`
- `tests/differential/run_diff.sh` → `tests/differential/run_matrix.sh`

## Harness pipelines

See [harness/directives.md](harness/directives.md).

| `RUN:` | Purpose |
|--------|---------|
| `selfhost` | `compiler.kbc` compile + run |
| `check` | `compiler.kbc --check` |
| `diff` | bootstrap `kinglet file.kl` vs selfhost |
| `bytecode` | `--bytecode` golden or `CHECK` |
| `ast` | `--ast` + `CHECK` substrings |

Environment:

| Variable | Default | Effect |
|----------|---------|--------|
| `KINGLET` | `$KINGLET_BOOTSTRAP` (bootstrap Ref) | selfhost VM host |
| `KINGLET_BOOTSTRAP` | `../kinglet/out/Default/kinglet` | C++ compiler + differential bootstrap |
| `FUZZ_ROUNDS` | `32` | property fuzz iterations |
| `PER_CASE_TIMEOUT` | `15`–`30` | parser/property wall-clock cap |

## `run_all.sh` tiers

**Gating** (failure fails the run):

lexer, parser, sema, codegen, run_selfhost, selfhost round-trip, exec,
differential (gate), diagnostics, kbc, regression, property.

**Non-gating snapshots** (always counted pass; print matrices):

`probe/run_matrix.sh`, `builtin_methods/run_matrix.sh`,
`differential/run_matrix.sh`.

## Adding cases

| Kind | Where | Directives / files |
|------|-------|-------------------|
| Must run on selfhost | `exec/cases/` | `RUN: selfhost`, `.expected`, `.exit` |
| Must type-check | `sema/pass/` or `sema/fail/` | `RUN: check`, optional `CHECK-ERR` |
| Must match bootstrap | `differential/cases/` | `RUN: diff` |
| Bytecode shape | `codegen/cases/` | `.bytecode` golden + optional `.exit` |
| Fixed bug | `regression/cases/` | `.expected` / `.exit` oracle; optional `.args` (one `sys::args` value per line) |
| Language feature probe | `probe/cases/` | `// EXPECT_OUT:` header |

## Related docs

- [regression/README.md](regression/README.md) — oracle sidecars (`.expected`, `.exit`, `.args`)
- [probe/README.md](probe/README.md) — feature capability matrix
- [builtin_methods/README.md](builtin_methods/README.md) — builtin method coverage
