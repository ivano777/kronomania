# Kronomania

A 2D turn-based dark fantasy duel RPG built with Godot 4.

## Getting started

1. Clone the repo
2. Copy `.env.local.example` to `.env.local` and set your Godot path
3. Run all checks:
   ```
   python scripts/run_tests.py
   ```

Requirements: Godot 4.6.2+, Python 3.8+, GUT addon already included in `addons/gut/`.

## Running checks individually

```bash
# Unit + integration tests only
python scripts/run_tests.py

# Headless engine validation only (checks for SCRIPT ERRORs)
python scripts/run_headless.py

# Full check (tests first, then headless)
python scripts/run_tests.py && python scripts/run_headless.py
```

## Godot binary resolution

Both scripts find the Godot executable in this order:

1. `GODOT` environment variable
2. `.env.local` file in the project root
3. `godot` on the system PATH
4. Common Windows install locations
