# Build system (M0)

See [decisions/0014](../decisions/0014-compilation-toolchain-architecture.md).

## Layout

```
.kinglet/
├── cache/           # reserved for stamp indexes (M0+)
├── objects/         # content-addressed blobs + <id>.meta
├── out/             # default outputs (e.g. compiler.kbc)
└── stamps/          # last-success stamp per target
```

## Commands

```bash
./kinglet build              # compile [build].root via bootstrap (Ref)
./kinglet build --quiet      # cache hit/miss only on stderr
./kinglet prove              # Shadow vs Ref parity (round-trip + differential)
./kinglet debug emit-kbc out.kbc src.kl
./kinglet debug emit-kbc --shadow out.kbc src.kl
KINGLET_BOOTSTRAP=... ./kinglet build
```

`build` uses the Ref compiler only. `prove` runs Shadow parity suites. Non-build
subcommands other than `prove` / `debug` / `native` forward to bootstrap `kinglet`.

## Configuration (`kinglet.toml`)

| Key | Default | Meaning |
|-----|---------|---------|
| `[build].root` | `core/main.kl` | Toolchain entry source |
| `[build].cache_dir` | `.kinglet/cache` | Cache directory |
| `[build].out_dir` | `.kinglet/out` | Output directory |
| `[build.compiler].engine` | `ref` | `ref` only in M0 |
| `[build.compiler].default_backend` | `vm` | Reserved for native (M3) |

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
