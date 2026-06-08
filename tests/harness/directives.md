# Harness directive language

Test cases are Kinglet source files (`.kl`) with **directives** in leading `//`
comments. `tests/harness/run.sh` parses them and runs the declared pipeline.

Directives must appear in a contiguous block at the top of the file. The block
ends at the first line that is neither a directive nor a blank line.

## Pipelines (`RUN`)

| Value | Behavior |
|-------|----------|
| `selfhost` | `compiler.kbc --save-bytecode` then `kinglet --run` the `.kbc` |
| `check` | `compiler.kbc <file> --check` (type checker) |
| `diff` | bootstrap `kinglet <file>` vs selfhost compile+run; stdout and exit must match |
| `bytecode` | `compiler.kbc --bytecode <file>`; compare to sidecar `.bytecode` or `CHECK` |
| `ast` | `compiler.kbc --ast <file>`; assert `CHECK` substrings on stdout |

## Assertions

| Directive | Applies to |
|-----------|------------|
| `EXPECT-STDOUT: <text>` | exact stdout (after CRLF strip) |
| `EXPECT-STDERR: <text>` | exact stderr |
| `EXPECT-EXIT: <n>` | process exit code (default `0`) |
| `CHECK: <substr>` | stdout must contain substring |
| `CHECK-NOT: <substr>` | stdout must not contain substring |
| `CHECK-ERR: <substr>` | stderr must contain substring |
| `CHECK-ERR-AT: <line>:<col>` | stderr must contain `line:col:` |
| `COMPILE-FAIL` | compile/check step must fail (non-zero or type errors) |

## Sidecar files (migration helpers)

If a directive is omitted, the harness falls back to sibling files:

| File | Maps to |
|------|---------|
| `<case>.expected` | `EXPECT-STDOUT` |
| `<case>.exit` | `EXPECT-EXIT` |
| `<case>.stderr_contains` | `CHECK-ERR` |
| `<case>.bytecode` | golden for `bytecode` pipeline |

## Examples

### End-to-end (selfhost)

```kl
// RUN: selfhost
// EXPECT-STDOUT: 7
// EXPECT-EXIT: 0
using io;
int main() { io::out.line(3 + 4); return 0; }
```

### Type check must fail

```kl
// RUN: check
// COMPILE-FAIL
// CHECK-ERR: Cannot assign
int main() { int x = "hello"; return 0; }
```

Sema suites live in `tests/sema/pass/` and `tests/sema/fail/`; run via
`tests/sema/run.sh`.

### Bootstrap vs selfhost

```kl
// RUN: diff
using io;
int main() { io::out.line(42); return 0; }
```

Compares bootstrap (`kinglet file.kl`) with selfhost (`compiler.kbc` compile +
run). Exit code and stdout must match. Override bootstrap binary with
`KINGLET_BOOTSTRAP`.

Gating cases live in `tests/differential/cases/`; the broad snapshot matrix is
`tests/differential/run_matrix.sh` (non-gating).

When bootstrap and selfhost legitimately differ, use `RUN: selfhost` with an
oracle `EXPECT-STDOUT` instead of `diff`.

## Usage

```bash
bash tests/harness/run.sh tests/exec/cases
bash tests/harness/run.sh tests/exec/cases/hello.kl
```

Exit code is the number of failed cases (0 = all passed).
