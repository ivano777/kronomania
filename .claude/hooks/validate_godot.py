import sys
import json
import subprocess
import re

data = json.load(sys.stdin)
fp = data.get("file_path", "")

if not (fp.endswith(".gd") or fp.endswith(".tres")):
    sys.exit(0)

GODOT = "C:/Program Files/Godot/Godot_v4.6.2-stable_win64_console.exe"
PROJECT = "C:/Users/ivano/Documents/ivano/svago/godot/kronomania"

try:
    result = subprocess.run(
        [GODOT, "--headless", "--path", PROJECT, "--quit-after", "5"],
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
