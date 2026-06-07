# Kinglet Syntax Reference

A complete listing of Kinglet (`.kl`) syntax, derived from the self-hosting
compiler in `lexer/`, `parser/`, and `compiler/`. Items marked *(planned)* are
reserved or tracked in `decisions/` but not yet wired into the parser.

## Comments

```kl
// line comment
/* block comment, may span lines */
```

## Primitive Types

| Type | Meaning |
|------|---------|
| `int` | integer |
| `float` | single-precision float |
| `double` | double-precision float |
| `bool` | boolean |
| `string` | string |
| `byte` | byte |
| `void` | no return value |
| `auto` | inferred type |

Compound types:

```kl
int[]              // array (sugar for Array<int>)
int[][]            // nested array
Map<string, int>   // generic with angle brackets
Box<T>             // user-defined generic
int?               // nullable suffix (desugars to Nullable<int>)
```

## Literals

```kl
42  0xFF  0b1010  1_000_000     // int: decimal / hex / binary / underscore groups
3.14  1e10  1.5e-3  2.0E+8       // float: fraction / exponent
"hello\n\t\"q\""                 // string, escapes: \n \r \t \\ \" \' \0
'a'  '\n'  '\0'                  // char literal (value is int)
true  false                      // bool
null                             // null
[1, 2, 3]                        // array literal
{ "k": 1, "k2": 2 }              // map literal
Point { 1, 2 }                   // struct literal
```

## Variable Declarations

```kl
int x = 10;            // with initializer
int y;                 // uninitialized
const int MAX = 100;   // constant
auto z = x + y;        // inferred
Point p { 1, 2 };      // struct-literal shorthand (type followed by {})
int[] arr = [1, 2, 3];
```

## Functions

```kl
int add(int a, int b) {        // block body
  return a + b;
}

int square(int n) => n * n;    // expression body

int compute(int n) => {        // => with block body
  return n * 2;
}

void greet() { io::out("hi"); }   // void return

pub int helper(int x) { ... }     // public (importable)

T identity<T>(T value) => value;  // generic function
```

## Structs

```kl
struct Point {
  int x;
  int y;
}

pub struct Node<T> {     // public + generic
  T value;
  int next;
}
```

## Enums (with payload variants)

```kl
enum Color { Red, Green, Blue }            // no payload

enum Shape {
  Circle(float),                           // single param
  Rect(int, int),                          // multiple params
  Empty,                                   // no params
}

pub enum Option { Some(int), None }        // public

// construction:
Shape s = Shape::Rect(3, 4);
Color c = Color::Red;
```

## Concepts (require at least one type parameter)

```kl
concept Printable<T> {
  string to_string(T value);   // method signature, ends with ;
}

pub concept Comparable<T> {
  int compare(T a, T b);
}
```

## Operators and Precedence

Lowest to highest (actual parser levels):

| Level | Operators | Assoc |
|-------|-----------|-------|
| assignment | `=` `+=` `-=` `*=` `/=` | right |
| ternary | `? :` | right |
| null coalesce | `?:`, `?: let e =>` | right |
| pipeline | `\|>` | left |
| logical or | `\|\|` | left |
| logical and | `&&` | left |
| bitwise or | `\|` | left |
| bitwise xor | `^` | left |
| bitwise and | `&` | left |
| equality | `==` `!=` | left |
| comparison | `<` `<=` `>` `>=` | left |
| shift | `<<` `>>` | left |
| additive | `+` `-` | left |
| multiplicative | `*` `/` `%` | left |
| unary (prefix) | `!` `-` `~`, `try` | right |
| postfix chain | call `()`, field `.x`, index `[]`, `match {}`, propagate `?` | left |

```kl
int r = (a + b) * 2 - a / b;
bool ok = n > 0 && n < 100 || n == -1;
int m = flags & MASK | bit;
int sh = x << 2 >> 1;
int neg = -x;  bool no = !flag;  int inv = ~bits;
x |> double |> print;          // pipeline: x becomes the first argument
int v = cond ? a : b;          // ternary
```

## Control Flow

```kl
// if / else (condition parens optional)
if x > 0 { return 1; } else { return -1; }
if (x > 0) { ... }

// while
while n < 10 { n = n + 1; }

// for (C-style three-clause; any clause may be empty)
for (int i = 0; i < 3; i = i + 1) { ... }

// guard (run else block when condition fails; typically early return)
guard x > 0 else { return; }

// jumps
break;
continue;
return value;
return;            // no value

// bare block
{ int tmp = 1; ... }
```

## Match Expressions

```kl
int result = o match {
  Option::Some(let x) => x,             // enum payload binding
  Option::None        => 0,             // no-payload variant
  _                   => -1,            // wildcard
};

int y = n match {
  0                 => 100,             // literal pattern
  let v if (v > 10) => v * 2,           // binding + guard if (cond)
  [let a, let b]    => a + b,           // array pattern
};
```

Pattern kinds: `let x` (binding), literal/expression, `[a, b]` (array),
`Enum::Variant(let x, ...)` (enum), `_` (wildcard). Guard: `pattern if (cond) => body`.

## Error Handling

```kl
// prefix try: unwrap Ok / early-return on Err
auto v = try parse(s);

// postfix ?: error propagation
auto v = parse(s)?;

// ?: null coalesce (Elvis)
auto x = maybe() ?: fallback;

// ?: let e => coalesce with error binding
auto x = risky() ?: let e => handle(e);

// try / catch statement (one or more catch arms)
try {
  do_work();
} catch (let e: IoError) {
  io::err(e);
} catch (let e: ParseError) {
  recover();
}
```

## Module System

```kl
// import block (the only form). "//" prefix resolves from project root.
import {
  "ast.kl"                 // relative to current file
  "../lib/math.kl" as m    // aliased
  "//lexer/token.kl"       // project root
}

// using: bring symbols / namespaces into scope
using io;                       // namespace
using namespace io;             // equivalent namespace form
using ast { Expr, Stmt, Decl }; // selective symbol import
```

Namespace access uses `::` — `io::out`, `scanner::scan`, `Enum::Variant`.
A user module's namespace is its file stem (e.g. `ast::`, `parser::`).

## Built-in Methods

Array:

```kl
arr.len()  arr.push(x)  arr.pop()  arr.remove(i)  arr.contains(x)
arr.clear()  arr.insert(i, x)  arr.index_of(x)  arr.slice(a, b)
arr.reverse()  arr.resize(n, v)
```

String:

```kl
s.len()  s.slice(a, b)  s.starts_with(p)  s.ends_with(p)
s.replace(a, b)  s.split(sep)  s.trim()  s.to_upper()  s.to_lower()
s[i]      // index a single character
```

Map:

```kl
m.has(k)  m.keys()  m[k]   // index read/write
```

## Casts and Type-Qualified Methods

```kl
int n    = int("42");      // cast: int / float / double / bool / string / byte
float f  = float(n);
int bits = int::bits(3.14);   // type-qualified method (Type::method)
```

## Native Namespaces

```kl
io::out(x)   io::outln(x)   io::err(x)   io::errln(x)   io::in()
io::out.line(x)   io::err.line(x)   io::in.secret()
fs::__read(path)   fs::__write(path, data)
sys::args()
```

## Keywords (33)

```
auto int float double bool string void byte const
return if else for while break continue guard
match let when try catch
pub import export namespace using
struct enum concept where
true false null
```

`when`, `export`, and `char` are tokenized but not yet given dedicated parser
syntax (char *literals* `'a'` work; the `char` *type* keyword is unregistered —
`byte` is the corresponding 8-bit type).

## Planned (not yet implemented)

From `decisions/0001-pending-syntax-and-perf.md`: `once` lazy blocks,
`retry N { }`, `test "name" { }`, `scope` resource management, struct patterns
in match, `[[nodiscard]]`, and `spawn`/`channel`/`select` concurrency.

Selfhost-only syntax not in bootstrap: `?:` / `?: let e =>` (bootstrap uses
`??`), and call-site generic type args `f<T>(args)`.
