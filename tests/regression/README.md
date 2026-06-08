# Regression suite

Selfhost oracle tests: each case is compiled with `compiler.kbc`, run on the
VM, and compared to hand-verified sidecars. When stdout is checked, bootstrap
is also run (with the same program args) and drift is reported non-gating.

```bash
bash tests/regression/run_golden.sh
```

## Case sidecars

| File | Purpose |
|------|---------|
| `<name>.kl` | Source (required) |
| `<name>.expected` | Exact stdout oracle (optional; skip stdout check if absent) |
| `<name>.exit` | Expected process exit code (default `0`) |
| `<name>.args` | Program arguments forwarded to `sys::args()` (optional) |

### `.args` format

One argument per non-empty line. Lines starting with `#` are comments. Relative
paths resolve against `cases/` (so `cat_fixture.txt` → `cases/cat_fixture.txt`).

Example `cat.args`:

```
cat_fixture.txt
```

The harness runs:

```bash
kinglet --run cat.kbc "$(pwd)/cases/cat_fixture.txt"
```

## Lists in `run_golden.sh`

- **MUST_PASS** — failure fails the suite (currently 15 cases, including `cat`
  and `arrays_bytecode`).
- **KNOWN_FAIL** — tracked gaps; empty when there are no open regressions.

Type-check-only failures use `<name>.exit` with value `65` and skip compile/run.

## Related

- [tests/README.md](../README.md) — full suite index
- Bootstrap CLI equivalent: `tests/cli/run_golden.sh` `run_args_case` (C++
  compiler runs `.kl` directly)
