# Native backend (LLVM)

KIR → LLVM IR → object → link → executable ([ADR 0015](../decisions/0015-llvm-backend-roadmap.md)).
Bootstrap native lowering covers integers, control flow, strings, arrays, structs, and
simple enum `match`. Error propagation, multi-module link, and I/O are not implemented yet.

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

Cases are listed in `tests/native/manifest.txt`. Expected exit codes live beside sources as `<name>.exit` when not zero. The smoke gate is **11 cases** (all must match VM exit codes; stderr must be empty).

## Manifest coverage

| Group | Cases | What they exercise |
|-------|-------|-------------------|
| Core | `just42`, `addmain`, `while_count`, `if_pos` | Literals, locals, integer ops, calls, loops, branches |
| Aggregates | `struct_sum`, `array_index`, `str_len` | Struct fields, array index, string length via `libkinglet_rt` |
| Numeric and enum | `big_int`, `neg_add`, `enum_no_payload`, `match_enum_simple` | Full `int64` range, unary negation, inline enum wire, simple `match` |

## Runtime (`libkinglet_rt`)

Linked into every native binary. Bootstrap sources under `runtime/`:

- Entry shim (`kinglet_rt_main.cc`) calls user `main` and maps the return value through `kl_exit_code` (0–255 clamp, same rules as the VM).
- **Wire format**: plain `int64` integers; heap refs tagged `0xFFFE<<48`; no-payload enums inline as `0xFFFD<<48 | type | variant`.
- **Implemented**: strings, arrays, structs, enum equality (`kl_value_eq`), heap enum allocation (`kl_enum_new`).

## Not yet on native

- `try` / `catch`, `?:` error propagation (`JmpIfErr`, `PropagateErr`)
- Enum payload destructuring, guarded match arms
- `float` / `double` arithmetic
- `io`, `fs`, `sys` natives
- Multi-module link (import graph → multiple `.o` files)

## Limitations

- `kinglet build --backend native` compiles `[build].root` to a native executable in `.kinglet/out/`; toolchain-sized programs may fail until error handling, linking, and I/O land.
- Single host triple first; no DWARF debug info yet.
- No GC — heap objects in RT use manual `new`/`delete` (RC may trail VM).
