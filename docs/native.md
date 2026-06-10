# Native backend (LLVM)

KIR → LLVM IR → per-module objects → link → executable
([ADR 0015](../decisions/0015-llvm-backend-roadmap.md)). Phases **L0–L5** are
complete: the toolchain root (`core/main.kl`) builds and runs natively, which
closes [ADR 0014](../decisions/0014-compilation-toolchain-architecture.md) **M3**.

## Prerequisites

- **LLVM 15+** with `llvm-config` on `PATH` or under Homebrew
  (`/opt/homebrew/opt/llvm/bin/llvm-config`).
- Bootstrap **kinglet** rebuilt with LLVM enabled.

## Build bootstrap with LLVM

From `kinglet-bootstrap/`:

```bash
gn gen out/Default --args='enable_llvm=true llvm_config="/opt/homebrew/opt/llvm/bin/llvm-config"'
ninja -C out/Default kinglet kinglet_rt
```

Without `enable_llvm=true`, `kinglet --native` reports that the native backend
was not built. CI uses `scripts/ci/build-bootstrap-llvm.sh`.

## Developer workflow

```bash
export KINGLET_BOOTSTRAP=/path/to/kinglet-bootstrap/out/Default/kinglet

# Toolchain: [build].default_backend = "native" → .kinglet/out/compiler
./kinglet build
.kinglet/out/compiler --check path/to/file.kl

# One-off program
$KINGLET_BOOTSTRAP --native /tmp/just42 tests/native/cases/just42.kl
/tmp/just42; echo $?   # 42

# With DWARF debug info (L5-1): line tables from KIR locations.
# On macOS a <out>.dSYM bundle is produced; lldb resolves .kl file:line.
$KINGLET_BOOTSTRAP --native /tmp/km -g core/main.kl
```

`--native` lowers every reachable function from KIR into one object per source
module, links them with `libkinglet_rt` (process `main` shim), and writes an
executable. Test suites still build `compiler.kbc` on the VM backend
(`ensure_build_stamp` passes `--backend vm`), so they do not require LLVM.

## Embedded self-host compiler (L5-2)

The bootstrap binary can embed a natively built toolchain compiler for
single-binary distribution:

```bash
# kinglet-bootstrap/
gn gen out/Embed --args='enable_llvm=true llvm_config="..." embed_compiler_path="/abs/path/kinglet-self/.kinglet/out/compiler"'
ninja -C out/Embed kinglet

out/Embed/kinglet selfhost --check file.kl   # runs the embedded compiler
```

`selfhost` materialises the embedded compiler in a content-addressed temp path
and execs it; no `compiler.kbc` or external compiler binary is involved.

## Tests

```bash
export KINGLET_BOOTSTRAP=/path/to/kinglet-bootstrap/out/Default/kinglet
bash tests/native/run_smoke.sh          # manifest cases, native vs VM exit codes
bash tests/native/run_driver_smoke.sh   # kinglet build --backend native + --check
```

Cases are listed in `tests/native/manifest.txt`; expected exit codes live beside
sources as `<name>.exit` when not zero. Both scripts skip cleanly when the
bootstrap was built without LLVM.

## Manifest coverage

| Group | Cases | What they exercise |
|-------|-------|-------------------|
| Core | `just42`, `addmain`, `while_count`, `if_pos` | Literals, locals, integer ops, calls, loops, branches |
| Aggregates | `struct_sum`, `array_index`, `str_len` | Struct fields, array index, string length via `libkinglet_rt` |
| Numeric and enum | `big_int`, `neg_add`, `enum_no_payload`, `match_enum_simple` | Full `int64` range, unary negation, inline enum wire, simple `match` |
| Errors | `elvis_null`, `try_ok`, `try_propagate`, `cast_catch` | `?:`, `try`/`catch`, error propagation, cast errors |
| Match and modules | `match_option_payload`, `enum_guard`, `match_int_lit`, `import_add` | Payload destructuring, guards, literal arms, cross-module calls |
| Natives | `io_line`, `fs_roundtrip`, `sys_args_len` | `io::out`, `fs::__read`/`__write`, `sys::args` |
| Floats and concat | `float_arith`, `float_cmp`, `str_concat` | Boxed-float math, relational dispatch, string `+` |
| Methods and maps | `map_ops`, `array_methods`, `str_methods`, `bit_ops` | Map literal/index/has/keys/remove, array and string methods, bitwise ops |

## Runtime (`libkinglet_rt`)

Linked into every native binary. Bootstrap sources under `runtime/`:

- Entry shim (`kinglet_rt_main.cc`) captures `argc`/`argv` for `sys::args` and
  maps user `main`'s return through `kl_exit_code` (0–255 clamp, same as VM).
- **Wire format**: plain `int64` integers; heap refs tagged `0xFFFE<<48`;
  no-payload enums inline as `0xFFFD<<48 | type | variant`; floats are boxed
  heap values (`KlFloat`), so arithmetic dispatches through the runtime.
- **Implemented**: strings (slice, index, len, methods), arrays (new/get/set/
  len/slice/methods), maps (literal/index/has/keys/remove), structs (new/field
  get/set), enums (payload, equality, casts), float math, string concat,
  bitwise ops, io/fs/sys natives.

## Known gaps

- No bool/null tags in the wire format: bools print as `1`/`0` and null prints
  as `0` (both share the integer wire encoding).
- No GC — heap objects in RT use manual `new`/`delete`; deterministic
  destruction per ADR 0002 needs KIR drop insertion (future work).
- Single host triple; cross-target builds are not wired into `kinglet build`.
