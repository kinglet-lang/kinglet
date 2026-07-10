# Build system

See [ADR 0014](https://github.com/kinglet-lang/ADRs/blob/main/0014-compilation-toolchain-architecture.md) (implemented).

## Layout

```
.kinglet/
├── cache/           # reserved for stamp indexes
├── objects/         # content-addressed blobs + <id>.meta (+ native/ obj cache)
├── out/             # default outputs (compiler native exe, or compiler.kbc with --backend vm)
└── stamps/          # last-success fingerprint per target (compiler, compiler-native, …)
```

## Commands

```bash
./kinglet init [name]        # new project dir (prompt; default kinglet-app/)
./kinglet build              # Ref compile [build].root → .kinglet/out/compiler (native default)
./klet build                 # same as kinglet build (short CLI alias)
./kinglet build --backend vm # → .kinglet/out/compiler.kbc (Shadow / prove path)
./kinglet build --quiet      # minimal stderr
./kinglet run                # run default build output (.kinglet/out/compiler or .kbc)
./kinglet file.kl            # compile + run one-off (same as bootstrap default)
./kinglet -v / --version     # bootstrap version
./kinglet prove              # Shadow vs Ref parity (bash script; stamp/Klos cache)
./kinglet debug emit-kbc out.kbc src.kl
./kinglet debug emit-kbc --shadow out.kbc src.kl
./kinglet native -o out prog.kl   # shorthand for bootstrap --backend native
KINGLET_BOOTSTRAP=... ./kinglet build
```

`init` / `build` / `run` / direct `.kl` execution are implemented in the bootstrap
binary. `prove` and `debug emit-kbc` are dev scripts under `scripts/build/`
(`prove.sh`, `debug-emit-kbc.sh`; `build.sh` is the internal stamp/Klos path used by prove/tests).

### `kinglet prune`

Prune `.kinglet/objects/` blobs no longer referenced by any stamp (reads
`.kinglet/stamps/*.object`). **Build-cache housekeeping only** — not language/runtime
GC ([ADR 0014](https://github.com/kinglet-lang/ADRs/blob/main/0014-compilation-toolchain-architecture.md) § Post-0014).

```bash
./kinglet prune              # remove unreferenced Klos objects
./kinglet prune --all        # remove entire .kinglet/ (stamps, out, objects, cache)
./kinglet prune -n           # dry-run
```

`objects/native/` (LLVM module cache) is kept by default; use `--all` to wipe it.

## Configuration (`kinglet.toml`)

| Key | Default | Meaning |
|-----|---------|---------|
| `[build].root` | `core/main.kl` | Toolchain entry source |
| `[build].cache_dir` | `.kinglet/cache` | Cache directory |
| `[build].out_dir` | `.kinglet/out` | Output directory |
| `[build.compiler].engine` | `ref` | `ref` only (`shadow` via `kinglet prove`) |
| `[build.compiler].default_backend` | `native` | `vm` or `native` (L1+) |
| `[build.prove].shadow_root` | `core/main.kl` | Entry for `kinglet prove` |

## Stamp

The compiler stamp hashes:

- All `.kl` files under `core/`, `parser/`, `compiler/`, `checker/`, `lexer/`
- `kinglet.toml` and `[build]` settings
- Bootstrap compiler identity (`--version` or binary hash)

On cache hit, `kinglet build` skips compilation.

## Tests

`ensure_build_stamp` in `tests/common.sh` wraps `scripts/build/build.sh --quiet` (internal stamp/Klos path; `./kinglet build` uses the bootstrap binary).

KIR goldens: `bash tests/ir/run_golden.sh` (requires bootstrap with `--ir`).

Native smoke: `bash tests/native/run_smoke.sh` (requires bootstrap with `enable_llvm=true`; see [native.md](native.md)).

Native build (L1): `./kinglet build --backend native` emits `.kinglet/out/compiler` when `[build].default_backend = "native"` or flag is passed.
