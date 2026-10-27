"""Mechanical code rules for Deepdraft (doc 258 step 5).

Scans game GDScript (scripts/, without scripts/tests) and data JSON for the
problems the 2026-10-22 review found by hand. Today's violations are recorded in
tools/lint_baseline.json; the run fails only when something is new or grows.

    py tools/lint_project.py                   check; exit 1 on new violations
    py tools/lint_project.py --update-baseline record fixes (counts only go down)
    py tools/lint_project.py --reset-baseline  rewrite from scratch (owner's call only)

Rules
  private-access  one script using another object's _private member
  json-owner      res://data paths outside registries/ and systems/, or read by two scripts
  dev-gate        DEV buttons in a script that never checks UIRegistry.dev_tools_enabled,
                  and DEV dock entries outside a "dev" menu
  garbled-text    UTF-8 text decoded as cp1252 and saved again
  unused-data     data JSON files or keys that no script or tool mentions
  legacy-code     the words legacy, compat or migrat in game code or data
  world-literal   1024, 1023 or 127 typed out instead of the WorldData constants
  file-length     game scripts over MAX_LINES may not grow
  type-size       a text size typed as a number instead of a step of UITheme's type scale
                  (doc 23, "Type"); 3D labels and sizes in proportion to art are not checked
"""
import argparse
import json
import re
import sys
from collections import defaultdict
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
BASELINE = ROOT / "tools" / "lint_baseline.json"
MAX_LINES = 1500
OWNER_DIRS = ("scripts/registries/", "scripts/systems/")
# Scripts outside the owner folders that read files, and why that is allowed.
USER_FILE_READERS = {"scripts/components/SaveFileStore.gd": "user:// save files",
                     "scripts/ui/UIWindowManager.gd": "user:// window layout"}
# Scripts whose DEV buttons only exist inside an already gated DEV window.
DEV_INSIDE_GATED_WINDOW = {"scripts/ui/JobInspectorPanel.gd": "built only by DwarfDirector's gated Job inspector"}
# Signatures of UTF-8 decoded as cp1252, written as escapes so this file stays clean.
GARBLED = [chr(0xC2), chr(0xC3), chr(0xE2) + chr(0x20AC), chr(0xE2) + chr(0x2020), chr(0xE2) + chr(0x2030), chr(0xE2) + chr(0x2C6)]
# Files that quote garbled text on purpose.
GARBLED_EXAMPLES = {"scripts/tests/DataEncodingTest.gd", "tools/lint_project.py",
                    "docs/00_dev_roadmap/258_code_review_2026_10_22.md"}
DOC_KEYS = {"description", "comment", "comments", "note", "notes", "_comment", "$schema"}
TEXT_SUFFIXES = {".gd", ".json", ".md", ".py", ".ps1", ".mjs", ".tscn", ".txt", ".gdshader", ".gdshaderinc"}
SKIP_DIRS = {".git", ".godot", "tmp", "node_modules", "__pycache__"}


def rel(path):
    return path.relative_to(ROOT).as_posix()


def walk(top, suffixes):
    for path in sorted((ROOT / top).rglob("*")):
        if path.is_file() and path.suffix in suffixes and not SKIP_DIRS.intersection(path.relative_to(ROOT).parts):
            yield path


def read(path):
    return path.read_text(encoding="utf-8", errors="replace")


def split_code(text):
    """Per line: (code with string contents blanked and comments dropped, string literals)."""
    lines, literals = [], []
    in_triple = None
    for raw in text.split("\n"):
        code, found, i = [], [], 0
        while i < len(raw):
            if in_triple:
                end = raw.find(in_triple, i)
                if end < 0:
                    i = len(raw)
                    break
                i = end + 3
                code.append('""')
                in_triple = None
                continue
            ch = raw[i]
            if ch == "#":
                break
            if raw.startswith('"""', i) or raw.startswith("'''", i):
                in_triple = raw[i:i + 3]
                i += 3
                continue
            if ch in "\"'":
                j = i + 1
                while j < len(raw) and raw[j] != ch:
                    j += 2 if raw[j] == "\\" else 1
                found.append(raw[i + 1:j])
                code.append(ch + ch)
                i = j + 1
                continue
            code.append(ch)
            i += 1
        lines.append("".join(code))
        literals.append(found)
    return lines, literals


class Findings:
    def __init__(self):
        self.counts = defaultdict(lambda: defaultdict(lambda: defaultdict(int)))
        self.where = defaultdict(list)

    def add(self, rule, file, key, line=0, text="", amount=1):
        self.counts[rule][file][key] += amount
        self.where[(rule, file, key)].append((line, text.strip()[:110]))

    def as_baseline(self):
        return {rule: {file: dict(sorted(keys.items())) for file, keys in sorted(files.items())}
                for rule, files in sorted(self.counts.items())}


PRIVATE = re.compile(r"(?<![\w.])([A-Za-z_]\w*|\))\s*\.\s*(_[a-z0-9]\w*)")
PRIVATE_BY_NAME = re.compile(r"\.(?:call|call_deferred|get|set)\(\s*\"(_[a-z0-9]\w*)\"")
DEV_BUTTON = re.compile(r"(?:make_button|apply_button_variant)\(.*\"dev\"\s*\)")
WORLD = re.compile(r"(?<![\w.])(1024|1023|127)(?![\w.])")
FILE_READ = re.compile(r"FileAccess\.open\(|JSON\.parse_string\(|JSON\.new\(")
# "compatible" and animal migration are ordinary words; old-save support is not.
LEGACY = re.compile(r"legacy|backwards?[- ]compat\w*|\bcompat\b|\bmigrat(?:e|es|ed|ing)\b", re.IGNORECASE)
# Calls that set a text size, and the argument that holds it. A script's own helpers join
# when their definition names a font_size or size parameter.
SIZE_CALLS = {"add_theme_font_size_override": 1, "format_label": 2, "apply_title": 1, "apply_heading": 1,
              "add_keycaps": 2, "set_font_size": 2}
SIZE_HELPER = re.compile(r"^func (_\w+)\(([^)]*)\)")
HAND_SIZE = re.compile(r"\d+|\d+\s+if\s+.+\s+else\s+\d+")


def call_arguments(line, open_at):
    """The arguments of the call whose '(' is at open_at, or None when it runs past the line."""
    depth, args, start = 0, [], open_at + 1
    for i in range(open_at, len(line)):
        if line[i] in "([{":
            depth += 1
        elif line[i] in ")]}":
            depth -= 1
            if depth == 0:
                return args + [line[start:i].strip()]
        elif line[i] == "," and depth == 1:
            args.append(line[start:i].strip())
            start = i + 1
    return None


def game_scripts():
    return [p for p in walk("scripts", {".gd"}) if not rel(p).startswith("scripts/tests/")]


def check_scripts(findings):
    data_refs = defaultdict(set)
    for path in game_scripts():
        name = rel(path)
        text = read(path)
        code, literals = split_code(text)
        raw_lines = text.split("\n")
        if len(raw_lines) > MAX_LINES:
            findings.add("file-length", name, "lines", 0, "%d lines" % len(raw_lines), amount=len(raw_lines))
        gated = "dev_tools_enabled" in text or name in DEV_INSIDE_GATED_WINDOW
        size_calls = dict(SIZE_CALLS)
        for line in code:
            helper = SIZE_HELPER.match(line)
            if helper:
                params = [p.split(":")[0].split("=")[0].strip() for p in helper.group(2).split(",")]
                for index, param in enumerate(params):
                    if param in ("font_size", "size"):
                        size_calls[helper.group(1)] = index
        size_call = re.compile(r"\b(%s)\(" % "|".join(size_calls))
        for n, (line, found) in enumerate(zip(code, literals), 1):
            raw = raw_lines[n - 1]
            if not line.lstrip().startswith("func "):
                for call in size_call.finditer(line):
                    args = call_arguments(line, call.end() - 1)
                    index = size_calls[call.group(1)]
                    if args is not None and index < len(args) and HAND_SIZE.fullmatch(args[index]):
                        findings.add("type-size", name, "text size %s" % args[index], n, raw)
            for receiver, member in PRIVATE.findall(line):
                if receiver not in ("self", "super"):
                    findings.add("private-access", name, "%s.%s" % ("()" if receiver == ")" else receiver, member), n, raw)
            for member in PRIVATE_BY_NAME.findall(raw):
                findings.add("private-access", name, 'call("%s")' % member, n, raw)
            for literal in found:
                if literal.startswith("res://data/"):
                    data_refs[literal].add(name)
                    if not name.startswith(OWNER_DIRS):
                        findings.add("json-owner", name, literal, n, raw)
            if FILE_READ.search(line) and not name.startswith(OWNER_DIRS) and name not in USER_FILE_READERS:
                findings.add("json-owner", name, "file read outside registries/ and systems/", n, raw)
            if DEV_BUTTON.search(raw) and not gated:
                findings.add("dev-gate", name, "DEV button without the switch", n, raw)
            for literal in WORLD.findall(line):
                if not re.search(r"const WORLD_SIZE_[XYZ]", line):
                    findings.add("world-literal", name, literal, n, raw)
            for word in LEGACY.findall(raw):
                findings.add("legacy-code", name, word.lower(), n, raw)
    for path_literal, readers in data_refs.items():
        if len(readers) > 1:
            for reader in sorted(readers):
                findings.add("json-owner", reader, "shared: " + path_literal, 0, "also read by " + ", ".join(sorted(readers - {reader})))


def check_garbled(findings):
    for top in ("scripts", "data", "docs", "tools", "scenes"):
        for path in walk(top, TEXT_SUFFIXES):
            if rel(path) in GARBLED_EXAMPLES:
                continue
            for n, line in enumerate(read(path).split("\n"), 1):
                if any(sig in line for sig in GARBLED):
                    findings.add("garbled-text", rel(path), "garbled", n, line)


def json_keys(value, out):
    if isinstance(value, dict):
        # A map from ids to records: its keys are data, not field names.
        id_map = len(value) >= 2 and all(isinstance(v, (dict, list)) for v in value.values())
        for key, child in value.items():
            if not id_map:
                out.add(key)
            json_keys(child, out)
    elif isinstance(value, list):
        for child in value:
            json_keys(child, out)


def check_data(findings):
    corpus_files = list(walk("scripts", {".gd"})) + list(walk("tools", {".gd", ".py", ".mjs", ".ps1"})) \
        + list(walk("scenes", {".tscn"})) + list(walk("data", {".json"}))
    corpus = {rel(p): read(p) for p in corpus_files}
    readers = "\n".join(text for name, text in corpus.items() if not name.startswith("data/") and name != "tools/lint_project.py")
    reader_words = set(re.findall(r"[a-z][a-z0-9_]*", readers))
    everything = "\n".join(corpus.values())
    for path in walk("data", {".json"}):
        name = rel(path)
        res = "res://" + name
        folder = res.rsplit("/", 1)[0] + "/"
        own = corpus[name]
        named = any(everything.count(token) > own.count(token) for token in (res, name, path.name))
        if not named and folder not in readers:
            findings.add("unused-data", name, "file", 0, "nothing names this file or scans its folder")
            continue
        text = read(path)
        for n, line in enumerate(text.split("\n"), 1):
            for word in LEGACY.findall(line):
                findings.add("legacy-code", name, word.lower(), n, line)
        try:
            data = json.loads(text)
        except ValueError as error:
            findings.add("unused-data", name, "invalid JSON", 0, str(error))
            continue
        keys = set()
        json_keys(data, keys)
        for key in sorted(keys):
            if key in DOC_KEYS or key.startswith("_") or not re.fullmatch(r"[a-z][a-z0-9_]*", key):
                continue
            if key not in reader_words:
                findings.add("unused-data", name, "key: " + key, 0, key)


def check_dock(findings):
    dock = json.loads(read(ROOT / "data/ui/dock.json"))
    for menu_id, menu in dock.get("menus", {}).items():
        for entry in menu.get("items", []):
            label = str(entry.get("label", "")) + " " + str(entry.get("tooltip", ""))
            if label.lstrip().startswith("DEV") and not menu.get("dev") and not entry.get("dev"):
                findings.add("dev-gate", "data/ui/dock.json", "DEV entry outside a dev menu: " + menu_id, 0, entry.get("id", ""))


def scan():
    findings = Findings()
    check_scripts(findings)
    check_garbled(findings)
    check_data(findings)
    check_dock(findings)
    return findings


def main():
    sys.stdout.reconfigure(encoding="utf-8", errors="replace")
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--update-baseline", action="store_true")
    parser.add_argument("--reset-baseline", action="store_true")
    args = parser.parse_args()
    findings = scan()
    current = findings.as_baseline()
    if args.reset_baseline:
        BASELINE.write_text(json.dumps(current, indent=1, ensure_ascii=False) + "\n", encoding="utf-8")
        print("LINT baseline rewritten: %d known violations." % total(current))
        return 0
    baseline = json.loads(BASELINE.read_text(encoding="utf-8")) if BASELINE.exists() else {}
    new, fixed = [], 0
    for rule, files in current.items():
        for file, keys in files.items():
            for key, count in keys.items():
                allowed = baseline.get(rule, {}).get(file, {}).get(key, 0)
                if count > allowed:
                    new.append((rule, file, key, count, allowed))
    for rule, files in baseline.items():
        for file, keys in files.items():
            for key, count in keys.items():
                fixed += max(0, count - current.get(rule, {}).get(file, {}).get(key, 0))
    if args.update_baseline:
        shrunk = {}
        for rule, files in baseline.items():
            for file, keys in files.items():
                for key, count in keys.items():
                    now = min(count, current.get(rule, {}).get(file, {}).get(key, 0))
                    if now > 0:
                        shrunk.setdefault(rule, {}).setdefault(file, {})[key] = now
        BASELINE.write_text(json.dumps(shrunk, indent=1, ensure_ascii=False) + "\n", encoding="utf-8")
        print("LINT baseline updated: %d known violations (%d fixed)." % (total(shrunk), fixed))
        return 0
    for rule, file, key, count, allowed in new:
        if rule == "file-length":
            print("LINT file-length  %s: %d lines (limit %d, recorded %d). Split it or shrink it." % (file, count, MAX_LINES, allowed))
            continue
        print("LINT %-14s %s: %s (%d, recorded %d)" % (rule, file, key, count, allowed))
        for line, text in findings.where[(rule, file, key)][:5]:
            print("      %s:%d  %s" % (file, line, text) if line else "      " + text)
    known = total(baseline)
    tail = " %d fixed; run with --update-baseline to record them." % fixed if fixed else ""
    if new:
        print("LINT FAIL: %d new violation group(s); %d known.%s" % (len(new), known, tail))
        return 1
    print("LINT OK: no new violations; %d known.%s" % (known, tail))
    return 0


def total(table):
    return sum(count for rule, files in table.items() if rule != "file-length"
               for keys in files.values() for count in keys.values())


if __name__ == "__main__":
    sys.exit(main())
