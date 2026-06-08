# Capability matrix (self-host)

Snapshot of language features the **self-hosted compiler** (`compiler.kbc`) can parse, check, compile, and run. The bootstrap `kinglet` binary is only the VM host.

```bash
bash tests/probe/run_matrix.sh
# or via full suite:
bash tests/run_all.sh
```

## Pipeline

| Step | Command | Gates `stage`? |
|------|---------|----------------|
| Parse | `kinglet --run compiler.kbc --ast <probe>` | yes (`parse✗`) |
| Check | `kinglet --run compiler.kbc --check <probe>` | **no** — reported in `check` column only |
| Compile | `kinglet --run compiler.kbc --save-bytecode <tmp> <probe>` | yes (`cg✗`) |
| Run | `kinglet --run <tmp>` vs `// EXPECT_OUT:` on line 1 | yes (`run✗`, `run≠out`, `run✓`) |

The checker is still shallow on enum `match` result types, array method calls, and some builtins. A probe can be `chk✗` while `stage` is `run✓`.

## Summary (2026-06-08)

| Metric | Count |
|--------|------:|
| Probes | 28 |
| `run✓` (end-to-end) | **28** |
| `cg✗` (compile) | 0 |
| `run≠out` (wrong output) | 0 |
| `chk✗` (checker only) | 3 |

## Matrix by category

### Core — expressions & control flow

| Probe | Feature | check | stage | Notes |
|-------|---------|:-----:|:-----:|-------|
| `01_arith` | `+ - *` precedence | ✓ | ✓ | |
| `02_comparison` | `> < ==` | ✓ | ✓ | |
| `03_bool_logic` | `&& \|\| !` | ✓ | ✓ | |
| `04_var_auto` | `auto` local inference | ✓ | ✓ | |
| `05_const` | top-level `const` | ✓ | ✓ | |
| `06_if_else` | `if` / `else` | ✓ | ✓ | |
| `07_while` | `while` loop | ✓ | ✓ | |
| `08_for` | C-style `for` | ✓ | ✓ | |
| `09_break_continue` | `break` / `continue` | ✓ | ✓ | |
| `10_recursion` | recursive calls | ✓ | ✓ | |

### Types — struct, enum, array, generics

| Probe | Feature | check | stage | Notes |
|-------|---------|:-----:|:-----:|-------|
| `11_struct` | struct literal + fields | ✓ | ✓ | |
| `12_enum_match` | enum variant `match` | ✓ | ✓ | |
| `13_array` | `[]`, `.push()`, `.len()` | ✓ | ✓ | |
| `25_generic_struct` | `struct Box<T>` | ✓ | ✓ | |

### Syntax sugar & control extensions

| Probe | Feature | check | stage | Notes |
|-------|---------|:-----:|:-----:|-------|
| `14_string_method` | `string.len()` | ✓ | ✓ | |
| `15_cast` | `int("42")` | ✓ | ✓ | |
| `16_ternary` | `cond ? a : b` | ✓ | ✓ | |
| `17_match_literal` | `int` literal `match` | ✓ | ✓ | |
| `18_guard` | `guard … else` | ✓ | ✓ | |
| `19_try_catch` | `try` / `catch` | ✓ | ✓ | |
| `20_null_coalesce` | `null ?: "default"` | ✓ | ✓ | Elvis `?:` (selfhost syntax; not bootstrap `??`) |
| `21_pipe` | `\|>` pipe | ✓ | ✓ | |

### Generics & concepts

| Probe | Feature | check | stage | Notes |
|-------|---------|:-----:|:-----:|-------|
| `23_generic_fn_explicit` | `id<int>(42)` | ✓ | ✓ | |
| `24_generic_fn_infer` | `id(42)` type inference | ✓ | ✓ | |
| `26_concept_qualified` | `Printable::to_string(42)` | ✓ | ✓ | |
| `27_ufcs` | `p.getv()` UFCS | ✓ | ✓ | |

### Platform & modules

| Probe | Feature | check | stage | Notes |
|-------|---------|:-----:|:-----:|-------|
| `28_fs_read` | `fs::__read` native | ✓ | ✓ | needs `/tmp/_kl_probe_fs.txt` with `hello` |
| `29_using_namespace` | `using namespace io` | ✓ | ✓ | unqualified `out.line` |

> Probe `22` is intentionally unused (numbering gap).

## Known gaps (action items)

| Priority | Probe | Layer | Issue |
|:--------:|-------|-------|-------|
## Self-host vs bootstrap

Both trees share most probes under `tests/probe/cases/`. Divergences:

| Probe | Self-host (`compiler.kbc`) | Bootstrap (`kinglet` CLI) |
|-------|---------------------------|---------------------------|
| `20_null_coalesce` | `?:` run✓ | `?:` run✓ (bootstrap also supports `??`) |
| `29_using_namespace` | run✓ | run✓ |

Use **self-host matrix** as the authoritative gap list for compiler development. Bootstrap matrix tracks the C++ reference implementation.

## Adding a probe

1. Add `tests/probe/cases/NN_name.kl` with `// EXPECT_OUT: <exact stdout line>` as the first line.
2. Pick the next free number (currently `30`).
3. Add a category entry in this README.
4. Run `bash tests/probe/run_matrix.sh` and paste the new row into the table above.

## Related

- Per-method builtin coverage (26 methods): [tests/builtin_methods/](../builtin_methods/README.md)
