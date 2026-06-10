# CI/CD

GitHub Actions workflows live under [`.github/workflows/`](../.github/workflows/).

## Workflows

| Workflow | Trigger | What it does |
|----------|---------|--------------|
| **CI — test-fast** | push / PR to `main` | macOS: bootstrap + VM, runs `tests/run_all.sh` (Ref path, no Shadow parity) |
| **CI — test-prove** | push / PR to `main` | macOS: bootstrap + VM, runs `./kinglet prove` (round-trip + differential) |
| **CI — test-native** | push / PR to `main` | macOS: bootstrap with LLVM, runs `tests/native/run_smoke.sh` (11 cases) |
| **Release** | tag `v*` | Builds `compiler.kbc` and attaches it to the GitHub Release |

## Local reproduction

```bash
# 1. Clone bootstrap next to this repo (or into ./bootstrap)
git clone https://github.com/kinglet-lang/bootstrap.git bootstrap

# 2. Install gn + ninja (macOS/Linux: see scripts/ci/install-gn-ninja.sh)

# 3. Fast CI tier (same as test-fast job)
bash scripts/ci/build-bootstrap.sh
bash scripts/ci/run-tests-fast.sh

# 4. Prove tier (Shadow parity)
bash scripts/ci/run-tests-prove.sh
# or: ./kinglet prove

# 5. Native smoke (requires LLVM; same as test-native job)
bash scripts/ci/run-tests-native.sh
```

V0 release checklist: [v0.md](v0.md).

`tests/common.sh` resolves bootstrap at `bootstrap/out/Default/kinglet` when
`KINGLET_BOOTSTRAP` is unset.

## Environment variables

| Variable | Default | Purpose |
|----------|---------|---------|
| `BOOTSTRAP_REPO` | `kinglet-lang/bootstrap` | Bootstrap checkout (CI only) |
| `BOOTSTRAP_REF` | `main` | Git ref for bootstrap |
| `BOOTSTRAP_ROOT` | `$REPO/bootstrap` | Bootstrap source tree |
| `KINGLET_BOOTSTRAP` | auto | C++ compiler binary |
| `KINGLET` | `backend/vm/out/kinglet` | VM host for `--run` |
| `KINGLET_COMPILE_TIMEOUT` | `600` | Self-host compile timeout (seconds) |

## Platform notes

- **macOS** is the CI gate and reference platform for `pass2b_ns_rank` /
  bootstrap byte parity.
- **Linux** (`ubuntu-latest`) is used in **Release** to build `compiler.kbc`.
  Full `run_all.sh` on Linux may hit runner limits during the ~3× self-host
  compile in round-trip, or fail bootstrap parity until `pass2b_ns_rank` is
  platform-neutral (see [decisions/0013](../decisions/0013-bootstrap-bytecode-delta.md)).

## Fixtures

`scripts/ci/setup-fixtures.sh` creates `/tmp/_kl_probe_fs.txt` for probe `28_fs_read`.
