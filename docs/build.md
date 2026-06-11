# Build system

See [decisions/0014](../decisions/0014-compilation-toolchain-architecture.md) (implemented).

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
./kinglet build              # Ref compile [build].root → .kinglet/out/compiler (native default)
./kinglet build --backend vm # → .kinglet/out/compiler.kbc (Shadow / prove path)
./kinglet build --quiet      # cache hit/miss only on stderr
./kinglet prove              # Shadow vs Ref parity (round-trip + differential)
./kinglet debug emit-kbc out.kbc src.kl
./kinglet debug emit-kbc --shadow out.kbc src.kl
./kinglet native -o out prog.kl   # shorthand for bootstrap --backend native
KINGLET_BOOTSTRAP=... ./kinglet build
```

`build` uses the Ref compiler only. `prove` runs Shadow parity suites. Non-build
subcommands forward to bootstrap `kinglet` except `build` / `prove` / `debug`.

### `kinglet clean` (planned — V0 CLI)

Prune `.kinglet/objects/` blobs no longer referenced by any stamp. **Build-cache
housekeeping only** — not language/runtime GC ([0014](../decisions/0014-compilation-toolchain-architecture.md)
§ Post-0014). Not implemented in the Bash driver yet; until then remove
`.kinglet/objects` manually if needed.

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

`ensure_build_stamp` in `tests/common.sh` wraps `scripts/build/kinglet-build.sh --quiet`.

KIR goldens: `bash tests/ir/run_golden.sh` (requires bootstrap with `--ir`).

Native smoke: `bash tests/native/run_smoke.sh` (requires bootstrap with `enable_llvm=true`; see [native.md](native.md)).

Native build (L1): `./kinglet build --backend native` emits `.kinglet/out/compiler` when `[build].default_backend = "native"` or flag is passed.
