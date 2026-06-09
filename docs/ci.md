# CI/CD

GitHub Actions workflows live under [`.github/workflows/`](../.github/workflows/).

## Workflows

| Workflow | Trigger | What it does |
|----------|---------|--------------|
| **CI** | push / PR to `main` | Builds [sentomk/kinglet](https://github.com/sentomk/kinglet) bootstrap + VM, runs `tests/run_all.sh` (includes bootstrap parity gate) |
| **Release** | tag `v*` | Builds `compiler.kbc` and attaches it to the GitHub Release |

## Local reproduction

```bash
# 1. Clone bootstrap next to this repo (or into ./bootstrap)
git clone https://github.com/sentomk/kinglet.git bootstrap

# 2. Install gn + ninja (macOS/Linux: see scripts/ci/install-gn-ninja.sh)

# 3. Full CI-equivalent run
bash scripts/ci/build-bootstrap.sh
bash scripts/ci/run-tests.sh
```

`tests/common.sh` resolves bootstrap at `bootstrap/out/Default/kinglet` when
`KINGLET_BOOTSTRAP` is unset.

## Environment variables

| Variable | Default | Purpose |
|----------|---------|---------|
| `BOOTSTRAP_REPO` | `sentomk/kinglet` | Bootstrap checkout (CI only) |
| `BOOTSTRAP_REF` | `main` | Git ref for bootstrap |
| `BOOTSTRAP_ROOT` | `$REPO/bootstrap` | Bootstrap source tree |
| `KINGLET_BOOTSTRAP` | auto | C++ compiler binary |
| `KINGLET` | `backend/vm/out/kinglet` | VM host for `--run` |
| `KINGLET_COMPILE_TIMEOUT` | `600` | Self-host compile timeout (seconds) |

## Platform notes

- **macOS** is the reference platform for `pass2b_ns_rank` / bootstrap byte parity.
- **Linux** CI may fail bootstrap parity until namespace compile order is
  platform-neutral (see [decisions/0013](../decisions/0013-bootstrap-bytecode-delta.md)).
  Behavior suites (exec, regression, differential gating) should still pass.

## Fixtures

`scripts/ci/setup-fixtures.sh` creates `/tmp/_kl_probe_fs.txt` for probe `28_fs_read`.
