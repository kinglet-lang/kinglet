#!/usr/bin/env python3
"""Structured diff of two .kbc files (Kinglet bytecode v1/v2)."""

from __future__ import annotations

import struct
import sys
from dataclasses import dataclass, field
from typing import Dict, List, Optional, Tuple


def sleb_at(b: bytes, off: int) -> Tuple[int, int]:
    result = 0
    shift = 0
    while True:
        byte = b[off]
        off += 1
        result |= (byte & 0x7F) << shift
        shift += 7
        if not (byte & 0x80):
            break
    if shift < 32 and (byte & 0x40):
        result -= 1 << shift
    return result, off


VALUE_TYPE = {
    0: "int",
    1: "double",
    2: "bool",
    3: "char",
    4: "null",
    5: "string",
    6: "function",
    8: "enum",
}

OP_NAMES = {
    0: "Constant",
    1: "Null",
    2: "True",
    3: "False",
    4: "Add",
    5: "Subtract",
    6: "Multiply",
    7: "Divide",
    8: "Modulo",
    9: "Negate",
    10: "Not",
    11: "BitNot",
    12: "BitAnd",
    13: "BitOr",
    14: "BitXor",
    15: "Shl",
    16: "Shr",
    17: "LoadLocal",
    18: "StoreLocal",
    19: "Pop",
    20: "Dup",
    21: "CastTo",
    22: "FloatToBits",
    23: "Call",
    24: "Return",
    25: "Jmp",
    26: "JmpFalse",
    27: "JmpIfErr",
    28: "Eq",
    29: "Neq",
    30: "Lt",
    31: "Gt",
    32: "Le",
    33: "Ge",
    34: "NativeOut",
    35: "NativeOutLn",
    36: "NativeErr",
    37: "NativeErrLn",
    38: "NativeIn",
    39: "NativeInSecret",
    40: "NativeFsRead",
    41: "NativeFsWrite",
    42: "NativeSysArgs",
    43: "StructNew",
    44: "FieldGet",
    45: "FieldSet",
    46: "EnumVariant",
    47: "ArrayNew",
    48: "IndexGet",
    49: "IndexSet",
    50: "ArrayLen",
    51: "ArrayPush",
    52: "ArrayResize",
    53: "ArrayPop",
    54: "ArrayRemove",
    55: "ArrayContains",
    56: "ArrayClear",
    57: "ArrayInsert",
    58: "ArrayIndexOf",
    59: "ArraySlice",
    60: "ArrayReverse",
    61: "StringStartsWith",
    62: "StringEndsWith",
    63: "StringReplace",
    64: "StringSplit",
    65: "StringTrim",
    66: "StringToUpper",
    67: "StringToLower",
    68: "EnumVariantPayload",
    69: "EnumPayloadGet",
    70: "MapNew",
    71: "MapGet",
    72: "MapSet",
    73: "MapHas",
    74: "MapRemove",
    75: "MapKeys",
    76: "MapLen",
    77: "PushHandler",
    78: "PopHandler",
    79: "PropagateErr",
    80: "IsNull",
    81: "StringToInt",
    82: "StringToFloat",
    83: "StringCode",
    84: "StringCodeAt",
    85: "AddI32",
    86: "SubtractI32",
    87: "MultiplyI32",
    88: "DivideI32",
    89: "ModuloI32",
    90: "DenseArrayNew",
}


@dataclass
class Constant:
    tag: int
    label: str
    raw_size: int


@dataclass
class Instruction:
    op: int
    operand: int
    line: int
    col: int
    raw_size: int


@dataclass
class Function:
    name: str
    entry: int
    param_count: int


@dataclass
class StructMeta:
    name: str
    field_names: List[str]


@dataclass
class EnumMeta:
    name: str
    variants: List[str]
    variant_param_counts: List[int]


@dataclass
class Chunk:
    version: int
    flags: int
    constants: List[Constant] = field(default_factory=list)
    instructions: List[Instruction] = field(default_factory=list)
    functions: List[Function] = field(default_factory=list)
    struct_metas: List[StructMeta] = field(default_factory=list)
    enum_metas: List[EnumMeta] = field(default_factory=list)
    raw_len: int = 0


def read_str(b: bytes, off: int) -> Tuple[str, int]:
    ln, = struct.unpack_from("<I", b, off)
    off += 4
    s = b[off : off + ln].decode()
    return s, off + ln


def parse_constant(b: bytes, off: int) -> Tuple[Constant, int]:
    start = off
    tag = b[off]
    off += 1
    vt = VALUE_TYPE.get(tag, f"tag{tag}")
    if tag == 0:
        off += 8
        label = "int"
    elif tag == 1:
        off += 8
        label = "double"
    elif tag == 2:
        off += 1
        label = "bool"
    elif tag == 3:
        off += 1
        label = "char"
    elif tag == 4:
        label = "null"
    elif tag == 5:
        ln, = struct.unpack_from("<I", b, off)
        off += 4 + ln
        label = "string"
    elif tag == 6:
        off += 4
        label = "function"
    elif tag == 8:
        off += 8
        pc, = struct.unpack_from("<I", b, off)
        off += 4
        for _ in range(pc):
            pt = b[off]
            off += 1
            if pt == 0:
                off += 8
            elif pt == 5:
                ln, = struct.unpack_from("<I", b, off)
                off += 4 + ln
            elif pt == 2:
                off += 1
        label = "enum"
    else:
        label = vt
    return Constant(tag, label, off - start), off


def parse(path: str) -> Chunk:
    b = open(path, "rb").read()
    magic, version, flags, _ = struct.unpack_from("<4I", b, 0)
    if magic != 0x01424B43:
        raise SystemExit(f"{path}: bad magic")
    off = 16
    nconst, = struct.unpack_from("<I", b, off)
    off += 4
    chunk = Chunk(version=version, flags=flags, raw_len=len(b))
    for _ in range(nconst):
        c, off = parse_constant(b, off)
        chunk.constants.append(c)
    ninsn, = struct.unpack_from("<I", b, off)
    off += 4
    use_sleb = version >= 2
    has_dbg = bool(flags & 1)
    for _ in range(ninsn):
        start = off
        op = b[off]
        off += 1
        if use_sleb:
            operand, off = sleb_at(b, off)
        else:
            operand, = struct.unpack_from("<i", b, off)
            off += 4
        line = col = 0
        if has_dbg:
            if use_sleb:
                line, off = sleb_at(b, off)
                col, off = sleb_at(b, off)
            else:
                line, col = struct.unpack_from("<2i", b, off)
                off += 8
        chunk.instructions.append(
            Instruction(op, operand, line, col, off - start)
        )
    nfn, = struct.unpack_from("<I", b, off)
    off += 4
    for _ in range(nfn):
        name, off = read_str(b, off)
        entry, = struct.unpack_from("<Q", b, off)
        off += 8
        pc, = struct.unpack_from("<i", b, off)
        off += 4
        chunk.functions.append(Function(name, entry, pc))
    nsm, = struct.unpack_from("<I", b, off)
    off += 4
    for _ in range(nsm):
        name, off = read_str(b, off)
        fc, = struct.unpack_from("<I", b, off)
        off += 4
        fields: List[str] = []
        for _ in range(fc):
            fn, off = read_str(b, off)
            fields.append(fn)
        chunk.struct_metas.append(StructMeta(name, fields))
    nem, = struct.unpack_from("<I", b, off)
    off += 4
    for _ in range(nem):
        name, off = read_str(b, off)
        vc, = struct.unpack_from("<I", b, off)
        off += 4
        variants: List[str] = []
        param_counts: List[int] = []
        for _ in range(vc):
            vn, off = read_str(b, off)
            pc, = struct.unpack_from("<i", b, off)
            off += 4
            variants.append(vn)
            param_counts.append(pc)
        chunk.enum_metas.append(EnumMeta(name, variants, param_counts))
    return chunk


def op_name(op: int) -> str:
    return OP_NAMES.get(op, f"op{op}")


def fmt_insn(i: int, ins: Instruction) -> str:
    op = op_name(ins.op)
    extra = ""
    if ins.op == 46:  # EnumVariant
        type_idx = ins.operand >> 16
        var_idx = ins.operand & 0xFFFF
        extra = f" type_idx={type_idx} var={var_idx}"
    return f"{i:5d} {op:18s} op={ins.operand:6d}{extra} @{ins.line}:{ins.col}"


def fn_at_index(chunk: Chunk, insn_idx: int) -> Optional[str]:
    best: Optional[Function] = None
    for fn in chunk.functions:
        if fn.entry <= insn_idx and (best is None or fn.entry > best.entry):
            best = fn
    return best.name if best else None


def insn_span(chunk: Chunk) -> Dict[str, int]:
    """Map function name -> instruction count (by entry ordering)."""
    fns = sorted(chunk.functions, key=lambda f: f.entry)
    spans: Dict[str, int] = {}
    for i, fn in enumerate(fns):
        end = len(chunk.instructions)
        if i + 1 < len(fns):
            end = fns[i + 1].entry
        spans[fn.name] = end - fn.entry
    return spans


def count_const_tags(chunk: Chunk) -> Dict[str, int]:
    counts: Dict[str, int] = {}
    for c in chunk.constants:
        counts[c.label] = counts.get(c.label, 0) + 1
    return counts


def main() -> None:
    if len(sys.argv) != 3:
        print(f"usage: {sys.argv[0]} <a.kbc> <b.kbc>", file=sys.stderr)
        sys.exit(2)
    a_path, b_path = sys.argv[1], sys.argv[2]
    a, b = parse(a_path), parse(b_path)

    print(f"A: {a_path} ({a.raw_len} bytes, v{a.version})")
    print(f"B: {b_path} ({b.raw_len} bytes, v{b.version})")
    print()
    print("Section counts:")
    print(
        f"  constants:    {len(a.constants):6d}  {len(b.constants):6d}"
        f"  delta {len(b.constants) - len(a.constants):+d}"
    )
    print(
        f"  instructions: {len(a.instructions):6d}  {len(b.instructions):6d}"
        f"  delta {len(b.instructions) - len(a.instructions):+d}"
    )
    print(
        f"  functions:    {len(a.functions):6d}  {len(b.functions):6d}"
        f"  delta {len(b.functions) - len(a.functions):+d}"
    )
    print(
        f"  structs:      {len(a.struct_metas):6d}  {len(b.struct_metas):6d}"
        f"  delta {len(b.struct_metas) - len(a.struct_metas):+d}"
    )
    print(
        f"  enums:        {len(a.enum_metas):6d}  {len(b.enum_metas):6d}"
        f"  delta {len(b.enum_metas) - len(a.enum_metas):+d}"
    )

    ca, cb = count_const_tags(a), count_const_tags(b)
    all_tags = sorted(set(ca) | set(cb))
    if any(ca.get(t, 0) != cb.get(t, 0) for t in all_tags):
        print("\nConstant tag counts:")
        for t in all_tags:
            da, db = ca.get(t, 0), cb.get(t, 0)
            if da != db:
                print(f"  {t:10s}: {da:5d}  {db:5d}  delta {db - da:+d}")

    if a.enum_metas != b.enum_metas:
        print("\nEnum metadata drift:")
        max_n = max(len(a.enum_metas), len(b.enum_metas))
        shown = 0
        for i in range(max_n):
            ea = a.enum_metas[i] if i < len(a.enum_metas) else None
            eb = b.enum_metas[i] if i < len(b.enum_metas) else None
            if ea == eb:
                continue
            print(f"  [{i}] A: {ea.name if ea else '<missing>'}  B: {eb.name if eb else '<missing>'}")
            shown += 1
            if shown >= 12:
                rest = sum(
                    1
                    for j in range(max_n)
                    if (a.enum_metas[j] if j < len(a.enum_metas) else None)
                    != (b.enum_metas[j] if j < len(b.enum_metas) else None)
                )
                if rest > 12:
                    print(f"  ... {rest - 12} more enum rows differ")
                break
    else:
        print("\nEnum metadata: identical order and names")

    # Identical instruction prefix
    prefix = 0
    for i in range(min(len(a.instructions), len(b.instructions))):
        if a.instructions[i] != b.instructions[i]:
            break
        prefix += 1
    print(f"\nIdentical instruction prefix: {prefix} insns")

    fn_a = {f.name: f for f in a.functions}
    fn_b = {f.name: f for f in b.functions}
    entry_diffs = []
    for name in sorted(set(fn_a) | set(fn_b)):
        fa, fb = fn_a.get(name), fn_b.get(name)
        if fa and fb and (fa.entry != fb.entry or fa.param_count != fb.param_count):
            entry_diffs.append((name, fa.entry, fb.entry, fa.param_count, fb.param_count))
    if entry_diffs:
        print("\nFunction entry drift (first 15):")
        for row in entry_diffs[:15]:
            print(f"  {row[0]}: entry {row[1]}->{row[2]}  params {row[3]}->{row[4]}")
        if len(entry_diffs) > 15:
            print(f"  ... {len(entry_diffs) - 15} more")

    span_a, span_b = insn_span(a), insn_span(b)
    insn_deltas = []
    for name in sorted(set(span_a) | set(span_b)):
        da, db = span_a.get(name, 0), span_b.get(name, 0)
        if da != db:
            insn_deltas.append((db - da, name, da, db))
    insn_deltas.sort(reverse=True)
    if insn_deltas:
        print("\nPer-function instruction count delta (B - A, top 20):")
        for delta, name, da, db in insn_deltas[:20]:
            print(f"  {delta:+4d}  {name}  ({da} -> {db})")
        if len(insn_deltas) > 20:
            print(f"  ... {len(insn_deltas) - 20} more functions differ")

    print("\nFirst instruction mismatches:")
    limit = 20
    shown = 0
    max_i = max(len(a.instructions), len(b.instructions))
    for i in range(max_i):
        ia: Optional[Instruction] = a.instructions[i] if i < len(a.instructions) else None
        ib: Optional[Instruction] = b.instructions[i] if i < len(b.instructions) else None
        if ia == ib:
            continue
        fn_a_name = fn_at_index(a, i)
        fn_b_name = fn_at_index(b, i)
        print(f"--- index {i} (A fn={fn_a_name}, B fn={fn_b_name}) ---")
        if ia:
            print(f"  A {fmt_insn(i, ia)}")
        else:
            print("  A <missing>")
        if ib:
            print(f"  B {fmt_insn(i, ib)}")
        else:
            print("  B <missing>")
        shown += 1
        if shown >= limit:
            rest = sum(
                1
                for j in range(max_i)
                if (a.instructions[j] if j < len(a.instructions) else None)
                != (b.instructions[j] if j < len(b.instructions) else None)
            )
            if rest > limit:
                print(f"  ... {rest - limit} more mismatches")
            break

    ba, bb = open(a_path, "rb").read(), open(b_path, "rb").read()
    for i, (x, y) in enumerate(zip(ba, bb)):
        if x != y:
            print(f"\nFirst raw byte diff at offset {i}: A=0x{x:02x} B=0x{y:02x}")
            lo = max(0, i - 8)
            print(f"  A[{lo}:{lo+24}]: {ba[lo:lo+24].hex()}")
            print(f"  B[{lo}:{lo+24}]: {bb[lo:lo+24].hex()}")
            break
    if len(ba) != len(bb):
        print(f"\nRaw size delta: {len(bb) - len(ba):+d} bytes")


if __name__ == "__main__":
    main()
