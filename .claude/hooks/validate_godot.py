import sys
import json
import os
import subprocess
import re
from pathlib import Path

data = json.load(sys.stdin)
# PostToolUse nests the tool arguments under "tool_input"; keep the flat
# lookup as a fallback for older payload shapes.
fp = data.get("tool_input", {}).get("file_path", "") or data.get("file_path", "")

PROJECT = Path(__file__).parent.parent.parent

# Sprite frames/clips: validate with the sprite compiler (fast, no Godot).
_norm = fp.replace("\\", "/")
if _norm.endswith(".xpm") or _norm.endswith("tools/sprites/clips.json"):
    result = subprocess.run(
        [sys.executable, str(PROJECT / "tools" / "sprites" / "compile.py"),
         "--check", str(PROJECT / "tools" / "sprites")],
        capture_output=True, text=True, timeout=30,
        encoding="utf-8", errors="replace",
    )
    if result.returncode != 0:
        print("=== Sprite validation failed ===")
        print(result.stdout + result.stderr)
        sys.exit(2)
    sys.exit(0)

if not (fp.endswith(".gd") or fp.endswith(".tres")):
    sys.exit(0)


def find_godot() -> str:
    if os.environ.get("GODOT"):
        return os.environ["GODOT"]

    env_file = PROJECT / ".env.local"
    if env_file.exists():
        for line in env_file.read_text().splitlines():
            line = line.strip()
            if line.startswith("GODOT=") and not line.startswith("#"):
                value = line.split("=", 1)[1].strip()
                if value:
                    return value

    try:
        subprocess.run(["godot", "--version"], capture_output=True, check=True)
        return "godot"
    except (FileNotFoundError, subprocess.CalledProcessError):
        pass

    common_paths = [
        Path(os.environ.get("LOCALAPPDATA", "")) / "Programs" / "Godot" / "Godot.exe",
        Path("C:/Program Files/Godot/Godot.exe"),
    ]
    for p in common_paths:
        if p.exists():
            return str(p)

    print("Godot executable not found — skipping hook validation.")
    sys.exit(0)


GODOT = find_godot()

try:
    result = subprocess.run(
        [GODOT, "--headless", "--path", str(PROJECT), "--quit-after", "5"],
        capture_output=True, text=True, timeout=30
    )
except subprocess.TimeoutExpired:
    print("Godot headless validation timed out after 30s")
    sys.exit(2)

output = result.stdout + result.stderr
errors = [
    line for line in output.splitlines()
    if re.search(r"SCRIPT ERROR|ERROR:", line) and "WARNING" not in line
]

if errors:
    print("=== Godot validation failed ===")
    for e in errors:
        print(e)
    sys.exit(2)
