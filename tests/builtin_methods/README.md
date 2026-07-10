# Builtin method matrix

Exercises every `obj.method(...)` binding lowered in `compiler/codegen.kl`
`emit_method_call` (aligned with bootstrap `compiler.cc`). One minimal program
per method under `cases/`; oracle on line 1: `// EXPECT_OUT: ...`.

```bash
bash tests/builtin_methods/run_matrix.sh
```

Pipeline matches [probe matrix](../probe/README.md): **selfhost only**
(`compiler.kbc`; bootstrap `kinglet` is the VM host). The `check` column is
informational and does not gate `stage`.

## Summary (2026-06-08)

| Metric | Count |
|--------|------:|
| Cases | 26 |
| `run✓` (parse → compile → run) | **26** |
| `chk✗` (checker only) | **0** |

| Receiver | run✓ | chk✗ |
|----------|-----:|-----:|
| `int[]` / array | 11/11 | 0 |
| `{K: V}` map | 4/4 | 0 |
| `string` | 11/11 | 0 |

**Runtime and checker: all 26 builtin methods pass end-to-end in selfhost.**

## Matrix

| case | receiver | method | check | stage | note |
|------|----------|--------|:-----:|:-----:|------|
| array_clear | array | clear | ✓ | run✓ | |
| array_contains | array | contains | ✓ | run✓ | |
| array_index_of | array | index_of | ✓ | run✓ | |
| array_insert | array | insert | ✓ | run✓ | |
| array_len | array | len | ✓ | run✓ | |
| array_pop | array | pop | ✓ | run✓ | |
| array_push | array | push | ✓ | run✓ | |
| array_remove | array | remove | ✓ | run✓ | |
| array_resize | array | resize | ✓ | run✓ | |
| array_reverse | array | reverse | ✓ | run✓ | |
| array_slice | array | slice | ✓ | run✓ | |
| map_has | map | has | ✓ | run✓ | |
| map_keys | map | keys | ✓ | run✓ | |
| map_len | map | len | ✓ | run✓ | |
| map_remove | map | remove | ✓ | run✓ | |
| string_contains | string | contains | ✓ | run✓ | |
| string_ends_with | string | ends_with | ✓ | run✓ | |
| string_index_of | string | index_of | ✓ | run✓ | |
| string_len | string | len | ✓ | run✓ | |
| string_replace | string | replace | ✓ | run✓ | |
| string_slice | string | slice | ✓ | run✓ | |
| string_split | string | split | ✓ | run✓ | |
| string_starts_with | string | starts_with | ✓ | run✓ | |
| string_to_lower | string | to_lower | ✓ | run✓ | |
| string_to_upper | string | to_upper | ✓ | run✓ | |
| string_trim | string | trim | ✓ | run✓ | |

Regenerate this table: `bash tests/builtin_methods/run_matrix.sh`

## Method reference

Opcodes and semantics follow bootstrap VM (`kinglet-bootstrap/src/vm/vm.cc`).
`len` is a shared opcode (`ArrayLen`) with receiver dispatch in the VM.

### Array (`int[]`, …)

| Method | Args | Returns | Opcode |
|--------|------|---------|--------|
| `len()` | — | `int` | `ArrayLen` |
| `push(v)` | 1 | `void` | `ArrayPush` |
| `pop()` | — | element | `ArrayPop` |
| `remove(i)` | index `int` | removed element | `ArrayRemove` |
| `contains(v)` | 1 | `bool` | `ArrayContains` |
| `clear()` | — | `void` | `ArrayClear` |
| `insert(i, v)` | index, value | `void` | `ArrayInsert` |
| `index_of(v)` | 1 | `int` (-1 if missing) | `ArrayIndexOf` |
| `slice(a, b)` | start, end `int` | `T[]` | `ArraySlice` |
| `reverse()` | — | `void` | `ArrayReverse` |
| `resize(n, fill)` | count, default | `void` | `ArrayResize` |

### Map (`{K: V}`)

| Method | Args | Returns | Opcode |
|--------|------|---------|--------|
| `len()` | — | `int` | `ArrayLen` (map branch) |
| `has(k)` | key | `bool` | `MapHas` |
| `keys()` | — | `K[]` | `MapKeys` |
| `remove(k)` | key | `void` | `ArrayRemove` (map branch) |

### String

| Method | Args | Returns | Opcode |
|--------|------|---------|--------|
| `len()` | — | `int` | `ArrayLen` (string branch) |
| `contains(sub)` | substring | `bool` | `ArrayContains` (string branch) |
| `index_of(sub)` | substring | `int` | `ArrayIndexOf` (string branch) |
| `slice(a, b)` | start, end | `string` | `ArraySlice` (string branch) |
| `starts_with(p)` | prefix | `bool` | `StringStartsWith` |
| `ends_with(s)` | suffix | `bool` | `StringEndsWith` |
| `replace(old, new)` | 2 × `string` | `string` | `StringReplace` |
| `split(delim)` | delimiter | `string[]` | `StringSplit` |
| `trim()` | — | `string` | `StringTrim` |
| `to_upper()` | — | `string` | `StringToUpper` |
| `to_lower()` | — | `string` | `StringToLower` |

## Checker dispatch

Builtin method typing lives in `checker/checker.kl`:
`check_array_builtin_method`, `check_map_builtin_method`,
`check_string_builtin_method`, plus `check_native_member_call` for
`io::out.line` / `io::err.line` / `io::in.secret`.

## Adding a case

1. Add `cases/<receiver>_<method>.kl` with `// EXPECT_OUT:` as line 1.
2. Keep one method per file; print a single line to stdout for the oracle.
3. Run `bash tests/builtin_methods/run_matrix.sh` and update the matrix section.

## Related

- Feature-level probes: [tests/probe/](../probe/README.md) (`13_array`, `14_string_method`)
- Stdlib roadmap (moving natives to `stdlib/`): [ADR 0003](https://github.com/kinglet-lang/ADRs/blob/main/0003-stdlib-roadmap.md)
