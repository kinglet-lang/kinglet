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
| `chk✗` (checker only) | **2** |

| Receiver | run✓ | chk✗ |
|----------|-----:|-----:|
| `int[]` / array | 11/11 | 0 |
| `{K: V}` map | 4/4 | 1 (`map_len`) |
| `string` | 11/11 | 1 (`string_split` chain) |

**Runtime: all builtin methods work end-to-end in selfhost today.**

**Checker: incomplete** — see [Checker gaps](#checker-gaps) (fix planned).

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
| map_len | map | len | **✗** | run✓ | `len` not typed on map |
| map_remove | map | remove | ✓ | run✓ | |
| string_contains | string | contains | ✓ | run✓ | |
| string_ends_with | string | ends_with | ✓ | run✓ | |
| string_index_of | string | index_of | ✓ | run✓ | |
| string_len | string | len | ✓ | run✓ | |
| string_replace | string | replace | ✓ | run✓ | see assignment gap below |
| string_slice | string | slice | ✓ | run✓ | |
| string_split | string | split | **✗** | run✓ | split inferred as `bool` → `.len()` fails |
| string_starts_with | string | starts_with | ✓ | run✓ | |
| string_to_lower | string | to_lower | ✓ | run✓ | see assignment gap below |
| string_to_upper | string | to_upper | ✓ | run✓ | see assignment gap below |
| string_trim | string | trim | ✓ | run✓ | see assignment gap below |

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

## Checker gaps

`checker/checker.kl` `check_method_call` is a partial table. Known issues
(**runtime OK**, checker wrong or missing):

| Issue | Affected methods | Symptom |
|-------|------------------|---------|
| `len` only on array/string | `map.len()` | chk✗ in `map_len` case |
| String mutators return `bool` in checker | `replace`, `trim`, `to_upper`, `to_lower` | `string t = s.trim()` → assign bool to string (not caught when result goes straight to `io::out.line`) |
| `split` return type | `split` | inferred `bool`; `s.split(d).len()` → chk✗ in `string_split` case |
| Array helpers return `unknown` | `contains`, `index_of`, `insert`, `remove`, `slice`, `resize`, … | no arity/return typing; usually no error unless assigned to a narrow type |
| No receiver kind check | e.g. `string.push(1)` | chk✓ incorrectly |
| Map helpers return `unknown` | `has`, `keys` | passes when fed to `io::out.line`; assignment would be unchecked |

### Suggested fix (next session)

Replace the ad-hoc `check_method_call` branches with a single dispatch table
matching the [Method reference](#method-reference) above (receiver kind × method
→ arg types + return type). Re-run this matrix; target **26/26 chk✓**.

## Adding a case

1. Add `cases/<receiver>_<method>.kl` with `// EXPECT_OUT:` as line 1.
2. Keep one method per file; print a single line to stdout for the oracle.
3. Run `bash tests/builtin_methods/run_matrix.sh` and update the matrix section.

## Related

- Feature-level probes: [tests/probe/](../probe/README.md) (`13_array`, `14_string_method`)
- Stdlib roadmap (moving natives to `stdlib/`): [decisions/0003](../../decisions/0003-stdlib-roadmap.md)
