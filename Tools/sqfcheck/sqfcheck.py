#!/usr/bin/env python3
"""Static syntax checker for Arma 3 SQF files - Python engine.

Rule-for-rule identical to Check-Sqf.ps1 (same codes, same messages, same
suppression behaviour); it exists because it scans the whole repository in
seconds instead of minutes. Tools/sqfcheck/Test-Checker.ps1 runs the fixture
suite through both engines and fails if they ever disagree.

Codes:
  E001  Mismatched bracket: closer does not match the open bracket
  E002  Unclosed bracket at end of file
  E003  Stray closing bracket with nothing open
  E004  Unterminated string or block comment / unexpected character
  E005  Unbalanced preprocessor conditional (#if/#ifdef/#ifndef vs #endif)
  E006  ';' before 'else' - terminates the if-statement early
  E007  ';' used as a separator inside an array literal '[ ]'
  W001  Probable missing ';' after a '}' code block
  W002  ',' used at code-block scope inside '{ }'
  W003  Single '=' inside an if/while condition (assignment, not comparison)
  W004  Assignment to an undeclared local variable (--strict only)
  E008  File starts with a UTF-8 BOM (hides a leading #include from the preprocessor)

Fixtures under tests/ are deliberately broken and are skipped by directory and git-based
discovery; naming one explicitly still checks it, which is how the self-test drives them.

Exit codes: 0 = clean (or warnings only), 1 = errors found, 2 = bad invocation.
"""

from __future__ import annotations

import argparse
import bisect
import json
import os
import re
import subprocess
import sys

REPO_ROOT = os.path.abspath(os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", ".."))

TOKEN_RE = re.compile(
    r"""
      (?P<lc>//[^\r\n]*)
    | (?P<bc>/\*.*?(?:\*/|\Z))
    | (?P<dq>"(?:[^"]|"")*")
    | (?P<sq>'(?:[^']|'')*')
    | (?P<pp>(?<=\n)[ \t]*\#[A-Za-z_]+(?:[^\r\n\\]|\\\r?\n|\\[^\r\n])*)
    | (?P<ppstart>\A[ \t]*\#[A-Za-z_]+(?:[^\r\n\\]|\\\r?\n|\\[^\r\n])*)
    | (?P<num>0[xX][0-9a-fA-F]+|(?:[0-9]+\.?[0-9]*|\.[0-9]+)(?:[eE][+-]?[0-9]+)?)
    | (?P<id>[A-Za-z_][A-Za-z0-9_]*)
    | (?P<br>[()\[\]{}])
    | (?P<op>==|!=|>=|<=|>>|&&|\|\||[-+*/%^=<>!\#:,;?.\\])
    | (?P<ws>\s+)
    """,
    re.VERBOSE | re.DOTALL,
)

# Tokens that may legally follow a '}' without an intervening ';'.
AFTER_BLOCK_OK = {
    s.lower()
    for s in (
        "and or not then else do count each forEach forEachReversed exitWith in call "
        "callExtension spawn execVM execFSM catch try param params select apply findIf "
        "sort sortBy from to step isEqualTo isEqualToAny isEqualType isNil configClasses "
        "remoteExec remoteExecCall pushBack append joinString arrayIntersect inAreaArray "
        "while switch case default for if with private waitUntil canSuspend deleteAt "
        "deleteRange set splitString regexFind regexMatch"
    ).split()
}

CONDITION_KEYWORDS = {"if", "while", "waituntil"}
DECL_KEYWORDS = {"private", "params", "param"}
MAGIC_LOCALS = {
    "_this", "_x", "_y", "_forEachIndex", "_exception", "_thisScript", "_thisArgs",
    "_thisEventHandler", "_fnc_scriptName", "_thisType",
}
PAIRS = {"(": ")", "[": "]", "{": "}"}
CASCADE_SUPPRESSED = {"E007", "W001", "W002", "W003", "W004"}
FATAL = {"E001", "E002", "E003", "E004"}


class Token:
    __slots__ = ("kind", "text", "index")

    def __init__(self, kind: str, text: str, index: int) -> None:
        self.kind = kind
        self.text = text
        self.index = index


def rel_path(path: str) -> str:
    full = os.path.abspath(path)
    if full.lower().startswith(REPO_ROOT.lower()):
        full = full[len(REPO_ROOT):].lstrip("\\/")
    return full.replace("\\", "/")


def check_file(path: str, strict: bool) -> list[dict]:
    rel = rel_path(path)
    with open(path, "r", encoding="utf-8", errors="replace", newline="") as handle:
        text = handle.read()

    bom = text.startswith("﻿")
    if bom:
        text = text[1:]

    line_starts = [0] + [m.end() for m in re.finditer("\n", text)]
    lines = text.split("\n")
    findings: list[dict] = []

    def add(index: int, level: str, code: str, message: str) -> None:
        line_no = bisect.bisect_right(line_starts, index) - 1
        col = index - line_starts[line_no] + 1
        source = lines[line_no].strip() if line_no < len(lines) else ""
        findings.append({
            "File": rel, "Line": line_no + 1, "Col": col,
            "Level": level, "Code": code, "Message": message, "Source": source,
        })

    if bom:
        add(0, "ERROR", "E008",
            "File starts with a UTF-8 BOM - Arma's preprocessor may not see a leading #include")

    # --- tokenize -----------------------------------------------------------
    tokens: list[Token] = []
    cursor = 0
    for m in TOKEN_RE.finditer(text):
        if m.start() > cursor:
            gap = text[cursor:m.start()].strip()
            if gap:
                add(cursor, "ERROR", "E004",
                    "Unexpected character sequence '%s' (unterminated string?)" % gap[:20])
        cursor = m.end()

        kind = m.lastgroup
        value = m.group()
        if kind == "ws":
            continue
        if kind in ("lc", "bc"):
            if kind == "bc" and not value.endswith("*/"):
                add(m.start(), "ERROR", "E004", "Unterminated block comment /* ... */")
            continue
        if kind == "ppstart":
            kind = "pp"
        if kind == "pp":
            # the match may include the leading indentation; keep the index on the '#'
            offset = value.index("#")
            tokens.append(Token("pp", value[offset:], m.start() + offset))
            continue
        tokens.append(Token(kind, value, m.start()))

    if cursor < len(text) and text[cursor:].strip():
        add(cursor, "ERROR", "E004", "Unterminated string literal at end of file")

    # --- structural walk ----------------------------------------------------
    stack: list[Token] = []
    pp_stack: list[Token] = []
    prev: Token | None = None
    cond_depth = -1

    for i, t in enumerate(tokens):
        if t.kind == "pp":
            directive = re.match(r"\#([A-Za-z_]+)", t.text).group(1).lower()
            if directive in ("if", "ifdef", "ifndef"):
                pp_stack.append(t)
            elif directive == "endif":
                if not pp_stack:
                    add(t.index, "ERROR", "E005", "#endif without a matching #if/#ifdef/#ifndef")
                else:
                    pp_stack.pop()
            prev = None
            continue

        if t.kind == "br":
            if t.text in PAIRS:
                # Only a parenthesised condition - `waitUntil { _i = _i - 1; ... }` and
                # `while {...}` bodies legitimately assign.
                if (prev is not None and prev.kind == "id"
                        and prev.text.lower() in CONDITION_KEYWORDS and t.text == "("):
                    cond_depth = len(stack)
                stack.append(t)
            else:
                if not stack:
                    add(t.index, "ERROR", "E003", "Closing '%s' with nothing open" % t.text)
                else:
                    opener = stack[-1]
                    expected = PAIRS[opener.text]
                    if t.text != expected:
                        open_line = bisect.bisect_right(line_starts, opener.index)
                        add(t.index, "ERROR", "E001",
                            "Found '%s' but '%s' was expected (opened by '%s' on line %d)"
                            % (t.text, expected, opener.text, open_line))
                    stack.pop()
                    if len(stack) <= cond_depth:
                        cond_depth = -1
            prev = t
            continue

        scope = stack[-1].text if stack else ""

        if t.kind == "op":
            if t.text == ";" and scope == "[":
                add(t.index, "ERROR", "E007",
                    "';' inside an array literal - array elements are separated by ','")
            elif t.text == "," and scope == "{":
                add(t.index, "WARN", "W002",
                    "',' at code-block scope inside '{ }' - statements are separated by ';'")
            elif t.text == "=":
                in_nested_block = False
                if cond_depth >= 0:
                    in_nested_block = any(s.text == "{" for s in stack[cond_depth:])
                if not in_nested_block and cond_depth >= 0 and len(stack) > cond_depth:
                    add(t.index, "WARN", "W003",
                        "Single '=' inside a condition - did you mean '=='  or 'isEqualTo'?")

        if (t.kind == "id" and t.text.lower() == "else"
                and prev is not None and prev.kind == "op" and prev.text == ";"):
            add(t.index, "ERROR", "E006", "';' before 'else' ends the if-statement - remove it")

        if prev is not None and prev.kind == "br" and prev.text == "}":
            starter = t.kind in ("id", "num", "dq", "sq") or (t.kind == "br" and t.text in "([{")
            # A binary command continuing the same line is normal SQF; a genuine
            # missing ';' virtually always starts a new line.
            if starter and "\n" not in text[prev.index:t.index]:
                starter = False
            if starter:
                ok = t.kind == "id" and t.text.lower() in AFTER_BLOCK_OK
                if (not ok and t.kind == "id" and re.match(r"^[A-Z][A-Za-z0-9_]*$", t.text)
                        and i + 1 < len(tokens) and tokens[i + 1].kind == "br"
                        and tokens[i + 1].text == "("):
                    ok = True   # macro invocation: expansion is opaque
                if not ok:
                    add(t.index, "WARN", "W001",
                        "Probable missing ';' after '}' before '%s'" % t.text)

        prev = t

    for opener in stack:
        add(opener.index, "ERROR", "E002",
            "Unclosed '%s' - no matching '%s' before end of file" % (opener.text, PAIRS[opener.text]))
    for opener in pp_stack:
        add(opener.index, "ERROR", "E005", "Preprocessor conditional never closed with #endif")

    # --- optional strict pass ----------------------------------------------
    if strict:
        declared = {v.lower() for v in MAGIC_LOCALS}
        for i, t in enumerate(tokens):
            if t.kind != "id":
                continue
            low = t.text.lower()
            if low in DECL_KEYWORDS:
                for j in range(i + 1, min(i + 60, len(tokens))):
                    n = tokens[j]
                    if n.kind in ("dq", "sq"):
                        declared.add(n.text[1:-1].lower())
                    elif n.kind == "id" and n.text.startswith("_"):
                        declared.add(low if False else n.text.lower())
                        if tokens[i + 1].kind == "id":
                            break
                    elif n.kind == "br" and n.text == "]":
                        break
                    elif n.kind == "op" and n.text == ";":
                        break
                continue
            if low in ("for", "foreach"):
                for j in range(i + 1, min(i + 6, len(tokens))):
                    if tokens[j].kind in ("dq", "sq"):
                        declared.add(tokens[j].text[1:-1].lower())
                continue
            if t.text.startswith("_") and i + 1 < len(tokens):
                n = tokens[i + 1]
                if n.kind == "op" and n.text == "=" and low not in declared:
                    add(t.index, "WARN", "W004",
                        "Local '%s' assigned without 'private' - it leaks into the caller's scope"
                        % t.text)
                    declared.add(low)

    # Once the bracket stack is broken, every scope-sensitive finding after it is noise.
    if any(f["Code"] in FATAL for f in findings):
        findings = [f for f in findings if f["Code"] not in CASCADE_SUPPRESSED]

    return findings


# ------------------------------------------------------------------ driver --

# tests/*.sqf are deliberately broken fixtures for the self-test, so they must never turn up in a
# discovered file set - otherwise every push touching Tools/sqfcheck fails CI. Naming one
# explicitly still checks it, which is exactly what Test-Checker.ps1 relies on.
FIXTURE_DIR = os.path.join(os.path.dirname(os.path.abspath(__file__)), "tests")


def is_fixture(path: str) -> bool:
    return os.path.abspath(path).lower().startswith(FIXTURE_DIR.lower() + os.sep)


def git_files(args: argparse.Namespace) -> list[str]:
    out: list[str] = []

    def run(cmd: list[str]) -> list[str]:
        try:
            res = subprocess.run(cmd, cwd=REPO_ROOT, capture_output=True, text=True, check=False)
            return [line for line in res.stdout.splitlines() if line.strip()]
        except OSError:
            return []

    if args.staged:
        out = run(["git", "diff", "--name-only", "--diff-filter=ACMR", "--cached"])
    else:
        ref = args.changed or "HEAD"
        out = run(["git", "diff", "--name-only", "--diff-filter=ACMR", ref])
        out += run(["git", "ls-files", "--others", "--exclude-standard"])

    files = []
    for name in out:
        if name.lower().endswith(".sqf"):
            full = os.path.join(REPO_ROOT, name)
            if os.path.isfile(full) and not is_fixture(full):
                files.append(full)
    return files


def collect(paths: list[str]) -> list[str]:
    files: list[str] = []
    for p in paths:
        if not os.path.exists(p):
            sys.stderr.write("sqfcheck: no such path: %s\n" % p)
            sys.exit(2)
        if os.path.isdir(p):
            for root, dirs, names in os.walk(p):
                dirs[:] = [d for d in dirs if d not in (".git", "build", ".idea")]
                for n in sorted(names):
                    if n.lower().endswith(".sqf"):
                        full = os.path.join(root, n)
                        if not is_fixture(full):
                            files.append(full)
        elif p.lower().endswith(".sqf"):
            files.append(p)
    return files


def finding_key(f: dict) -> str:
    return "%s|%s|%s" % (f["File"], f["Code"], f["Source"])


def main(argv: list[str]) -> int:
    ap = argparse.ArgumentParser(description="Static syntax checker for Arma 3 SQF files.")
    ap.add_argument("paths", nargs="*", help="files or directories (default: repository root)")
    ap.add_argument("--changed", nargs="?", const="HEAD", metavar="REF",
                    help="check only files changed against REF (default HEAD) plus untracked files")
    ap.add_argument("--staged", action="store_true", help="check only files staged in git")
    ap.add_argument("--baseline", metavar="PATH", help="baseline file of accepted findings")
    ap.add_argument("--update-baseline", action="store_true", help="rewrite the baseline instead of reporting")
    ap.add_argument("--strict", action="store_true", help="enable extra scope-safety checks (W004)")
    ap.add_argument("--warnings-as-errors", action="store_true")
    ap.add_argument("--quiet", action="store_true")
    ap.add_argument("--json", action="store_true", help="emit findings as JSON")
    args = ap.parse_args(argv)

    if args.staged or args.changed:
        files = git_files(args)
    else:
        files = collect(args.paths or [REPO_ROOT])

    if not files:
        # --json must always emit valid JSON, so machine consumers do not have to parse prose.
        if args.json:
            print("[]")
        elif not args.quiet:
            print("sqfcheck: no .sqf files to check.")
        return 0

    findings: list[dict] = []
    for f in files:
        findings.extend(check_file(f, args.strict))

    baseline_path = args.baseline or os.path.join(os.path.dirname(os.path.abspath(__file__)), "baseline.txt")
    if args.update_baseline:
        keys = sorted({finding_key(f) for f in findings})
        with open(baseline_path, "w", encoding="utf-8") as handle:
            handle.write("\n".join(keys) + ("\n" if keys else ""))
        print("sqfcheck: baseline written with %d entries -> %s" % (len(keys), baseline_path))
        return 0

    suppressed = 0
    if os.path.isfile(baseline_path):
        with open(baseline_path, "r", encoding="utf-8") as handle:
            known = {line.strip() for line in handle if line.strip() and not line.startswith("#")}
        kept = []
        for f in findings:
            if finding_key(f) in known:
                suppressed += 1
            else:
                kept.append(f)
        findings = kept

    errors = [f for f in findings if f["Level"] == "ERROR"]
    warns = [f for f in findings if f["Level"] == "WARN"]

    if args.json:
        print(json.dumps(findings, indent=2))
    else:
        for f in sorted(findings, key=lambda x: (x["File"], x["Line"], x["Col"])):
            print("%s:%d:%d: %s %s: %s"
                  % (f["File"], f["Line"], f["Col"], f["Level"].lower(), f["Code"], f["Message"]))
            if f["Source"]:
                print("    | %s" % f["Source"])
        if not args.quiet or findings:
            extra = ", %d baselined" % suppressed if suppressed else ""
            print("sqfcheck: %d file(s), %d error(s), %d warning(s)%s"
                  % (len(files), len(errors), len(warns), extra))

    if errors:
        return 1
    if args.warnings_as_errors and warns:
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
