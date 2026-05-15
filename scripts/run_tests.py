#!/usr/bin/env python3
"""
GUT headless test runner for Kronomania.

Usage:
    python scripts/run_tests.py

Exits 0 when all tests pass; non-zero otherwise.

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

cmd = [
    GODOT, "--headless",
    "--path", str(PROJECT),
    "-s", "addons/gut/gut_cmdln.gd",
    "-gdir=res://tests",
    "-ginclude_subdirs",
    "-gprefix=test_",
    "-gexit",
    "-glog=1",
]

print("Running GUT tests headless...")
print("Command:", " ".join(cmd))
print("-" * 60)

try:
    result = subprocess.run(
        cmd,
        capture_output=True,
        text=True,
        timeout=120,
        encoding="utf-8",
        errors="replace",
    )
except subprocess.TimeoutExpired:
    print("ERROR: test run timed out after 120 s", file=sys.stderr)
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

# GUT 9.x summary format (printed to stdout/stderr):
#   Tests                70
#   Passing Tests        70
#   Failing Tests         0
#   (plus "---- All tests passed! ----" or "---- N tests failed. ----")
ran     = 0
passed  = 0
failed  = 0
pending = 0
errors  = 0

m_ran    = re.search(r"^Tests\s+(\d+)", output, re.MULTILINE)
m_pass   = re.search(r"^Passing Tests\s+(\d+)", output, re.MULTILINE)
m_fail   = re.search(r"^Failing Tests\s+(\d+)", output, re.MULTILINE)
m_pend   = re.search(r"^Pending\s+(\d+)", output, re.MULTILINE)

if m_ran:
    ran = int(m_ran.group(1))
if m_pass:
    passed = int(m_pass.group(1))
if m_fail:
    failed = int(m_fail.group(1))
if m_pend:
    pending = int(m_pend.group(1))

# SCRIPT ERROR lines in Godot output indicate parse/load failures.
if re.search(r"SCRIPT ERROR", output):
    errors += 1

# If we couldn't parse GUT's summary at all, fall back to the process exit code.
parsed_summary = bool(m_ran or m_pass or m_fail)

print()
print("=" * 60)
print("  GUT Test Summary")
print("=" * 60)
print(f"  Ran:     {ran}")
print(f"  Passed:  {passed}")
print(f"  Failed:  {failed}")
print(f"  Pending: {pending}")
print(f"  Errors:  {errors}")
print("=" * 60)

if failed > 0 or errors > 0:
    print("RESULT: FAILED", file=sys.stderr)
    sys.exit(1)

if not parsed_summary:
    # Couldn't parse GUT output — fall back to process exit code.
    if result.returncode != 0:
        print("WARNING: no GUT summary found and process exited non-zero.", file=sys.stderr)
        sys.exit(1)
    print("WARNING: no GUT summary found but process exited 0 — treating as passed.")

if ran == 0 and passed == 0 and parsed_summary:
    print("WARNING: no tests were discovered — check GUT setup.", file=sys.stderr)
    sys.exit(1)

print("RESULT: PASSED")
sys.exit(0)
