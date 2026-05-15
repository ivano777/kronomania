#!/usr/bin/env python3
"""
Headless engine validation for Kronomania.

Usage:
    python scripts/run_headless.py

Runs the Godot engine headless for 5 seconds and checks for SCRIPT ERRORs.
Exits 0 if clean; non-zero if any errors are found.

Godot binary is resolved from (in order):
  1. GODOT environment variable
  2. .env.local file in the project root
  3. 'godot' on the system PATH
  4. Common Windows install locations
"""

import os
import re
import subprocess
import sys
from pathlib import Path


PROJECT = Path(__file__).parent.parent


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

    print("ERROR: Godot executable not found.")
    print("Fix: copy .env.local.example to .env.local and set your GODOT path.")
    sys.exit(1)


GODOT = find_godot()

cmd = [GODOT, "--headless", "--path", str(PROJECT), "--quit-after", "5"]

print("Running headless engine validation...")
print("Command:", " ".join(cmd))
print("-" * 60)

try:
    result = subprocess.run(
        cmd,
        capture_output=True,
        text=True,
        timeout=30,
        encoding="utf-8",
        errors="replace",
    )
except subprocess.TimeoutExpired:
    print("ERROR: headless run timed out after 30 s", file=sys.stderr)
    sys.exit(2)
except FileNotFoundError:
    print(
        f"ERROR: Godot executable not found: '{GODOT}'\n"
        "Set the GODOT environment variable or configure .env.local.",
        file=sys.stderr,
    )
    sys.exit(2)

output = result.stdout + result.stderr
print(output)

# UID WARNINGs are safe (expected on fresh clone); ignore them.
# Only flag SCRIPT ERROR and ERROR lines.
error_lines = [
    line for line in output.splitlines()
    if re.search(r"SCRIPT ERROR|^ERROR", line) and "UID" not in line
]

print()
print("=" * 60)
print("  Headless Validation Summary")
print("=" * 60)

if error_lines:
    print(f"  Errors found: {len(error_lines)}")
    for line in error_lines:
        print(f"    {line}")
    print("=" * 60)
    print("RESULT: FAILED", file=sys.stderr)
    sys.exit(1)

print("  No SCRIPT ERRORs or ERRORs found.")
print("=" * 60)
print("RESULT: PASSED")
sys.exit(0)
