"""
gen_project_index.py — generates docs/project-index.md from the codebase.

Run from project root:
    python scripts/gen_project_index.py

Regenerate when: adding/renaming a .gd file, adding a signal, adding an @export
field, or adding a .tres file. Not needed for content-only changes.
"""

import os
import re
from pathlib import Path

ROOT = Path(__file__).parent.parent
OUT = ROOT / "docs" / "project-index.md"

# ── helpers ───────────────────────────────────────────────────────────────────

def read(path: Path) -> list[str]:
    return path.read_text(encoding="utf-8").splitlines()


def short(path: Path) -> str:
    return str(path.relative_to(ROOT)).replace("\\", "/")


# ── GDScript parser ───────────────────────────────────────────────────────────

def parse_gd(path: Path) -> dict:
    lines = read(path)
    info = {
        "path": short(path),
        "class_name": None,
        "extends": None,
        "signals": [],
        "public_funcs": [],
        "export_fields": [],   # list of (name, type_str)
        "preloads": [],        # list of res:// paths (from const := preload())
    }

    for line in lines:
        s = line.strip()

        m = re.match(r'^class_name\s+(\w+)', s)
        if m:
            info["class_name"] = m.group(1)

        m = re.match(r'^extends\s+(\S+)', s)
        if m:
            info["extends"] = m.group(1)

        m = re.match(r'^signal\s+(\w+)\s*(\(.*\))?', s)
        if m:
            args = m.group(2) or "()"
            info["signals"].append(f"{m.group(1)}{args}")

        # Top-level public funcs only: 'func' must start at column 0 (not indented
        # inside an inner class). Use unstripped `line`, not `s`.
        m = re.match(r'^func\s+([^_]\w*\s*\(.*?\)(?:\s*->\s*\S+)?)', line)
        if m:
            info["public_funcs"].append(m.group(1).strip())

        # @export variants: @export, @export_range(a, b), @export_enum("x"), etc.
        # Drop \b after 'export' — @export_range has _ (word char) immediately after,
        # so a word boundary would fail. Use .*? to skip annotation args (incl. spaces).
        m = re.match(r'^@export.*?\bvar\s+(\w+)(?::\s*([^\s=]+))?', s)
        if m:
            field_name = m.group(1)
            field_type = m.group(2) or "Variant"
            info["export_fields"].append((field_name, field_type))

        # preload: const X := preload("res://...")
        m = re.match(r'^const\s+\w+\s*:?=\s*preload\("(res://[^"]+)"\)', s)
        if m:
            info["preloads"].append(m.group(1).replace("res://", ""))

    return info


# ── .tres parser ──────────────────────────────────────────────────────────────

def parse_tres(path: Path) -> dict:
    lines = read(path)
    info = {
        "path": short(path),
        "script_class": None,
        "ext_resources": [],   # list of res:// paths this file depends on
        "fields": {},          # key: value (strings)
    }

    in_resource = False
    id_to_path: dict[str, str] = {}

    for line in lines:
        s = line.strip()

        # header: [gd_resource ... script_class="Foo" ...]
        m = re.search(r'script_class="([^"]+)"', s)
        if m:
            info["script_class"] = m.group(1)

        # ext_resource declarations
        m = re.match(r'\[ext_resource[^\]]*path="(res://[^"]+)"[^\]]*id="([^"]+)"\]', s)
        if m:
            rpath = m.group(1).replace("res://", "")
            rid = m.group(2)
            id_to_path[rid] = rpath
            info["ext_resources"].append(rpath)

        if s == "[resource]":
            in_resource = True
            continue

        if in_resource and "=" in s and not s.startswith("["):
            key, _, val = s.partition("=")
            key = key.strip()
            val = val.strip()
            # skip script assignment and complex values
            if key == "script":
                continue
            # resolve ExtResource references to readable paths
            m = re.match(r'ExtResource\("([^"]+)"\)', val)
            if m:
                val = id_to_path.get(m.group(1), val)
            # resolve array of ExtResource
            m = re.match(r'\[ExtResource\("([^"]+)"\)(.*)\]', val)
            if m:
                items = re.findall(r'ExtResource\("([^"]+)"\)', val)
                val = "[" + ", ".join(id_to_path.get(i, i) for i in items) + "]"
            info["fields"][key] = val

    return info


# ── categorise files ──────────────────────────────────────────────────────────

def collect():
    autoloads, resources, scenes, debug_scenes, data_files = [], [], [], [], []

    for gd in sorted(ROOT.rglob("*.gd")):
        rel = short(gd)
        if ".godot" in rel or ".git" in rel:
            continue
        info = parse_gd(gd)
        if rel.startswith("autoloads/"):
            autoloads.append(info)
        elif rel.startswith("resources/") and not rel.startswith("resources/data/"):
            resources.append(info)
        elif rel.startswith("scenes/debug/"):
            debug_scenes.append(info)
        elif rel.startswith("scenes/"):
            scenes.append(info)

    for tres in sorted(ROOT.rglob("*.tres")):
        rel = short(tres)
        if ".godot" in rel or ".git" in rel:
            continue
        data_files.append(parse_tres(tres))

    return autoloads, resources, scenes, debug_scenes, data_files


# ── render ────────────────────────────────────────────────────────────────────

def sig_cell(signals: list[str]) -> str:
    if not signals:
        return "—"
    return "<br>".join(f"`{s}`" for s in signals)


def func_cell(funcs: list[str]) -> str:
    if not funcs:
        return "—"
    return "<br>".join(f"`{f}`" for f in funcs)


def export_cell(fields: list[tuple]) -> str:
    if not fields:
        return "—"
    return ", ".join(f"`{n}: {t}`" for n, t in fields)


def refs_from_exports(fields: list[tuple]) -> str:
    """Resource types referenced via @export typed fields (non-primitive types)."""
    primitives = {"String", "int", "float", "bool", "Array", "PackedStringArray",
                  "Variant", "Color", "Vector2", "Vector3", "NodePath"}
    refs = []
    for _, t in fields:
        base = re.sub(r'\[.*\]', '', t)  # strip Array[X] → X
        arr_m = re.match(r'Array\[(\w+)\]', t)
        if arr_m:
            base = arr_m.group(1)
            if base not in primitives:
                refs.append(f"`{base}[]`")
        elif base not in primitives and base:
            refs.append(f"`{base}`")
    return ", ".join(refs) if refs else "—"


def render(autoloads, resources, scenes, debug_scenes, data_files) -> str:
    lines = []
    a = lines.append

    a("# Project Index")
    a("")
    a("_Auto-generated by `scripts/gen_project_index.py`. Do not edit manually._")
    a("_Regenerate (`/refresh-index`) when: adding/renaming a `.gd` file, adding a signal,_")
    a("_adding an `@export` field, or adding a `.tres` file._")
    a("")

    # ── Autoloads ──
    a("## Autoloads")
    a("")
    a("| File | Signals | Public entry points |")
    a("|------|---------|-------------------|")
    for info in autoloads:
        file_cell = f"`{info['path']}`"
        a(f"| {file_cell} | {sig_cell(info['signals'])} | {func_cell(info['public_funcs'])} |")
    a("")

    # ── Resource schemas ──
    a("## Resource schemas")
    a("")
    a("| File | Class | @export fields | References |")
    a("|------|-------|---------------|-----------|")
    for info in resources:
        cn = f"`{info['class_name']}`" if info["class_name"] else "—"
        a(f"| `{info['path']}` | {cn} | {export_cell(info['export_fields'])} | {refs_from_exports(info['export_fields'])} |")
    a("")

    # ── Data files ──
    a("## Data files (.tres)")
    a("")
    a("| File | Type | Key values | References |")
    a("|------|------|-----------|-----------|")
    for info in data_files:
        sc = info["script_class"] or "—"
        # show a selection of meaningful fields (skip script, uid-like values)
        skip = {"script"}
        kv_parts = []
        for k, v in info["fields"].items():
            if k in skip:
                continue
            # shorten long paths
            v_short = os.path.basename(v) if ("/" in v and not v.startswith("[")) else v
            kv_parts.append(f"{k}={v_short}")
        kv = ", ".join(kv_parts[:6])  # cap at 6 pairs for readability
        # references: other .tres files this one depends on
        refs_list = [r for r in info["ext_resources"] if r.endswith(".tres")]
        refs = ", ".join(f"`{os.path.basename(r)}`" for r in refs_list) if refs_list else "—"
        a(f"| `{info['path']}` | `{sc}` | {kv} | {refs} |")
    a("")

    # ── Scenes ──
    a("## Scenes")
    a("")
    a("| File | Class | Preloads |")
    a("|------|-------|---------|")
    for info in scenes:
        cn = info["class_name"] or "—"
        preloads = ", ".join(f"`{os.path.basename(p)}`" for p in info["preloads"]) if info["preloads"] else "—"
        a(f"| `{info['path']}` | `{cn}` | {preloads} |")
    a("")

    # ── Debug scenes ──
    a("## Debug scenes _(removable at release)_")
    a("")
    a("| File | Signals | Public entry points |")
    a("|------|---------|-------------------|")
    for info in debug_scenes:
        a(f"| `{info['path']}` | {sig_cell(info['signals'])} | {func_cell(info['public_funcs'])} |")
    a("")

    return "\n".join(lines)


# ── main ──────────────────────────────────────────────────────────────────────

def main():
    autoloads, resources, scenes, debug_scenes, data_files = collect()
    content = render(autoloads, resources, scenes, debug_scenes, data_files)
    OUT.write_text(content, encoding="utf-8")
    print(f"Written: {short(OUT)}")
    print(f"  autoloads:    {len(autoloads)}")
    print(f"  resources:    {len(resources)}")
    print(f"  scenes:       {len(scenes)}")
    print(f"  debug scenes: {len(debug_scenes)}")
    print(f"  data files:   {len(data_files)}")


if __name__ == "__main__":
    main()
