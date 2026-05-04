# ATK Auto Mode — Execution Flow and Heuristic

## Overview

ATK Auto Mode lets the player skip the cascading menu each round. When enabled, the combat
manager resolves the attack automatically using saved preferences or a scored heuristic.

## Execution Paths

### 1. Default path

Fires when `CombatPreferences.defaults` contains both `attack_weapon` and `attack_action`,
and the currently equipped weapon name matches `attack_weapon`.

- Executes that saved action immediately.
- Applies `brutal_trade` from defaults if `dom_brutal >= 1`.
- Log: `[Auto] {action_name} → {Pool} (default)`

### 2. Auto-Best fallback

Fires when no complete default exists (weapon changed, or no pin saved yet).

Calls `_auto_best_action()` in `CombatManager`, which scores the player's strike action
and executes it with `brutal_trade=false`.

- Log: `[Auto-Best] Strike → {Pool} (score: {value})`

## Auto-Best Heuristic Formula

```
score = effective_tier × (1 + dominion_size) / 2 + flat_bonus
```

| Variable | Source |
|---|---|
| `effective_tier` | `_effective_tier(_player, mod)` — respects `ActionModifier.tier_cap` |
| `dominion_size` | `_stat_size(_player, "dominion")` — die face integer (4 / 6 / 8 / 10) |
| `flat_bonus` | `_attack_flat(_player)` — weapon flat + node flat bonuses |

The formula approximates expected attack output: `(1 + die_face) / 2` is the average roll
on a single die, multiplied by pool size (tier), plus flat. Higher score = better expected
total before guard.

Target pool is taken from `ActionModifier.target_pool`; falls back to `"stance"` if unset.

## Scope Limits

- **Magic is never auto-selected by heuristic.** Magic Auto only fires when a default spell
  is pinned in `CombatPreferences.defaults["magic"]`. If no spell is pinned, the magic
  intent button remains active and waits for player input.
- **Brutal Trade** is applied only on the default path (saved preference). The auto-best
  fallback always passes `brutal_trade=false`.
- **DEF Mode** (`def_mode`) is independent — this document covers ATK Mode only.
