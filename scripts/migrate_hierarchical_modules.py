#!/usr/bin/env python3
"""Migrate kinglet self-host tree to hierarchical module ids."""

from __future__ import annotations

import re
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]

MODULE_MAP = {
    "token": "lexer.token",
    "keywords": "lexer.keywords",
    "scanner": "lexer.scanner",
    "ast": "parser.ast",
    "helpers": "parser.helpers",
    "expressions": "parser.expressions",
    "parser": "parser",
    "bytecode": "compiler.bytecode",
    "compiler_state": "compiler.compiler_state",
    "codegen": "compiler.codegen",
    "project_config": "compiler.project_config",
    "compiler": "compiler",
    "disasm": "compiler.disasm",
    "checker": "checker",
    "ast_printer": "core.ast_printer",
    "checker_driver": "core.checker_driver",
    "main": "core.main",
    "manifest": "stdlib.manifest",
    "math": "stdlib.math",
    "map": "stdlib.map",
    "algorithms": "stdlib.algorithms",
    "ir": "ir.ir",
    "ir_print": "ir.ir_print",
    "ir_emit": "ir.ir_emit",
}

QUALIFIER_MAP = {old: mod.replace(".", "::") for old, mod in MODULE_MAP.items()}

USING_BLOCK_RE = re.compile(
    r"using\s+(\w+)\s*\{[^}]*\}\s*;",
    re.MULTILINE,
)


def migrate_nest(path: Path) -> str:
    text = path.read_text(encoding="utf-8")
    lines = []
    for line in text.splitlines():
        stripped = line.strip()
        if "=" in stripped and not stripped.startswith("project") and not stripped.startswith("build"):
            key, _, rhs = stripped.partition("=")
            key = key.strip()
            if key in MODULE_MAP:
                line = line.replace(key, MODULE_MAP[key], 1)
        lines.append(line)
    return "\n".join(lines) + ("\n" if text.endswith("\n") else "")


def migrate_kl(path: Path) -> str:
    text = path.read_text(encoding="utf-8")
    for old, new in MODULE_MAP.items():
        text = re.sub(
            rf"^export module {re.escape(old)};",
            f"export module {new};",
            text,
            flags=re.MULTILINE,
        )
        text = re.sub(
            rf"^import {re.escape(old)};",
            f"import {new};",
            text,
            flags=re.MULTILINE,
        )

    def using_repl(match: re.Match[str]) -> str:
        old = match.group(1)
        new = MODULE_MAP.get(old, old)
        return f"using namespace {new};"

    text = USING_BLOCK_RE.sub(using_repl, text)

  # Longest keys first to avoid partial prefix replacement.
    for old in sorted(QUALIFIER_MAP, key=len, reverse=True):
        qual = QUALIFIER_MAP[old]
        text = re.sub(rf"\b{re.escape(old)}::", f"{qual}::", text)
    return text


def main() -> None:
    nest = ROOT / "kinglet.nest"
    nest.write_text(migrate_nest(nest), encoding="utf-8")
    print(f"updated {nest}")

    dirs = [
        ROOT / "compiler",
        ROOT / "parser",
        ROOT / "checker",
        ROOT / "lexer",
        ROOT / "core",
        ROOT / "ir",
        ROOT / "stdlib",
    ]
    count = 0
    for d in dirs:
        if not d.is_dir():
            continue
        for path in sorted(d.rglob("*.kl")):
            new = migrate_kl(path)
            if new != path.read_text(encoding="utf-8"):
                path.write_text(new, encoding="utf-8")
                count += 1
                print(f"  {path.relative_to(ROOT)}")
    print(f"migrated {count} .kl files")


if __name__ == "__main__":
    main()
