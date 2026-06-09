# Native backend (LLVM)

Spike path for KIR → LLVM → executable ([ADR 0015](../decisions/0015-llvm-backend-roadmap.md) L0).

## Prerequisites

- **LLVM 15+** with `llvm-config` on `PATH` or under Homebrew (`/opt/homebrew/opt/llvm/bin/llvm-config`).
- Bootstrap **kinglet** rebuilt with LLVM enabled.

## Build bootstrap with LLVM

From `kinglet-bootstrap/`:

```bash
gn gen out/Default --args='enable_llvm=true llvm_config="/opt/homebrew/opt/llvm/bin/llvm-config"'
ninja -C out/Default kinglet
```

Without `enable_llvm=true`, `kinglet --native` reports that the native backend was not built.

## Compile and run

```bash
kinglet --native /tmp/just42 tests/native/cases/just42.kl
/tmp/just42
echo $?   # 42
```

`--native` lowers the user `main` function from KIR, links with `libkinglet_rt` (process `main` shim), and writes an executable.

## Tests

```bash
export KINGLET_BOOTSTRAP=/path/to/kinglet-bootstrap/out/Default/kinglet
bash tests/native/run_smoke.sh
```

Cases are listed in `tests/native/manifest.txt`. Expected exit codes live beside sources as `<name>.exit` when not zero.

## Limitations (L0)

- Only `const_int` + `ret` in a single-block `main`.
- No `io`, calls, or control flow yet (L1+).
- Runtime is a thin exit-code wrapper only (`runtime/kinglet_rt_main.cc` in bootstrap).
