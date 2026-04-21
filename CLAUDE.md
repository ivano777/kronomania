# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Engine and tooling

- **Godot 4.6.2** — Forward Plus renderer, D3D12 on Windows, Jolt Physics.
- The Godot console executable is at `$GODOT` (set in `.claude/settings.local.json`).
- Run headless validation: `"$GODOT" --headless --path "C:/Users/ivano/Documents/ivano/svago/godot/kronomania" --quit-after 5`
- No build step, no test runner, no linter — Godot parses scripts on load. Headless run is the check.

## Committing and pushing

Use `/ship` — stages everything, writes a Conventional Commit message from the diff, pulls `--rebase`, pushes. Never skip hooks, never force-push unless explicitly asked.

## Autonomous Feature Loop

Follow this workflow for every requested feature, without exception.

### 1. Plan
- Identify the smallest safe implementation slice that proves the feature.
- Present a clear plan: which files change, what logic is added, what is explicitly deferred.
- **Wait for explicit approval before writing any code.**

### 2. Implement
- Edit only the files identified in the approved plan.
- No unnecessary rewrites, refactors, or scope creep.
- Where files are independent (no shared state, no load order dependency),
  implement them in parallel using subagents.
- Never parallelize writes to files that share state or that must be
  applied in a specific order (e.g. autoloads before scenes that depend on them).

### 2b. Debug & Testability
Every feature that introduces a new mechanic or runtime value must ship with a way to exercise it interactively.

Debug widgets live exclusively in `scenes/debug/`. Reference via null-safe `@onready` delegate: `@onready var _dbg = $Widget if has_node("Widget") else null`. Remove at release: delete `scenes/debug/`, remove the child from the parent `.tscn`, remove the `@onready` and its delegation method — nothing else changes. If a mechanic has no tunable parameters, a log-only approach is acceptable; document the decision in the feature report.

### 3. Validate (deploy a sub-agent)
Deploy a sub-agent: run headless (see Engine section), check for SCRIPT ERRORs and ERRORs (UID WARNINGs are safe), verify `@onready` paths, signal connections, and `class_name` registrations in `.godot/global_script_class_cache.cfg`.

### 4. Fix Loop
If validation fails:
- Fix the specific error reported.
- Re-run validation.
- Repeat until the headless run is clean.

### 5. Update Documentation
Only after a clean validation pass:
- Update relevant files under `docs/game-rules/` if mechanics changed.
- Update `CLAUDE.md` if architecture or rules changed.
- If the feature added or renamed a `.gd` file, added a signal, added an `@export` field,
  or added a `.tres` file — run `/refresh-index` as the final action in this step, before
  asking the user to run `/ship`. Content-only changes (bug fixes, logic edits) skip this.

### 6. Report
Return a concise summary covering:
- What was implemented and where.
- What the validation found and confirmed.
- What documentation was updated.

### 7. Commit and push
Ask the user to run `/ship`.

---

**Rules**
- Docs updated only after successful validation, never before.
- The final report must be short enough to scan in under a minute.
- Never edit files under `docs/game-rules/` without explicit user approval — it is the single source of truth for all game design. If a rule is ambiguous, ask; never decide unilaterally.

## Project structure

```
autoloads/          # RollEngine (dice), CombatManager (combat SM), PlayerProgression (constellation)
resources/          # Resource class definitions (.gd) + data/ (.tres files) — see project-index.md
scenes/battle/      # BattleScene (root), CombatantHUD, RoundHUD, Combatant
scenes/constellation/  # ConstellationScene (skill tree)
scenes/debug/       # Debug widgets — removable at release; never imported by production code directly
scripts/            # gen_project_index.py — regenerates docs/project-index.md
docs/game-rules/    # Design source of truth — navigation TOC at index.md; load files on demand
docs/               # project-status.md (roadmap), project-index.md (generated code map)
.claude/            # agents/docs-alignment-auditor.md, commands/audit-docs.md + refresh-index.md
```

## Architecture

### One-way data flow

`CombatantData` (`.tres` resource) → `CombatManager` → signals → `BattleScene` → HUD nodes.

`CombatantData` is **immutable config** only. All runtime state lives inside `CombatManager.CombatantState`, an inner class instantiated per combat. Scene nodes hold no game state.

`CombatantState` fields: `data` (CombatantData), `current_wounds`, `max_wounds`, `is_defeated`, `unlocked_nodes`, `tier_override`, `weapon_override`, plus per-pool guard state (`stance_guard`, `resolve_guard`, `stamina_guard`, and matching `_rolled` booleans), plus magic state (`fervor_size`, `is_burned_out`, `has_minor_studies`, `has_spellcasting`, `known_spells: Array`, `known_cantrips: Array`). Methods: `init()`, `reset_guard()`, `get_guard(pool)`, `set_guard_val(pool, value)`, `is_pool_rolled(pool)`, `set_pool_rolled(pool, value)`.

### Autoload singletons

Signatures and signals are in `docs/project-index.md`. Architectural gotchas:
- **`RollEngine`** — stateless. Returns `Dictionary`; always cast values with `as int` / `as Array` — the type inferencer cannot infer through `Dictionary`. `resolve()` accepts optional `fervor_size` (additive post-keep Fervor die), `aspect_stat_size` and `aspect_count` (for mixed-pool spells). Returns `ingenuity_maxed_count` — count of Ingenuity-tagged pool dice that rolled their maximum (used for Fervor escalation).
- **`CombatManager`** — all output via signals; nothing returned. Disconnect all signals before `reload_current_scene()`. Signals: `fervor_changed(is_player, fervor_size, fervor_cap, is_burned_out)`, `player_magic_available(can_cantrip, can_cast_spell)`. Public methods: `player_chose_cantrip(spell: SpellData)`, `player_chose_spell(spell: SpellData)`, `debug_set_fervor(size, burned_out)`.
- **`PlayerProgression`** — constellation state; read by `CombatManager` at `start_combat()`. `ALL_NODES` catalog. `get_known_spells()` and `get_known_cantrips()` iterate all unlocked nodes and collect from `node.spells` (is_cantrip=false / true).

### Round loop (CombatManager)

```
_begin_round()
  → resets both guards to 0
  → emits player_magic_available(can_cantrip, can_cast_spell)
  → emits player_action_required
  → (player presses Strike / Cantrip / Spell → BattleScene calls player_chose_strike / _cantrip / _spell)
  → _resolve_round / _resolve_round_cantrip / _resolve_round_spell
  → rolls both attacks, VT check, _resolve_attack() × 2
  → [spell only] _escalate_fervor() if Fervor die maxed
  → await 0.8s timer
  → _begin_round()  ← loops until defeat
```

`_resolve_round*` are GDScript coroutines (use `await`). Calling them without `await` from the `player_chose_*` methods is intentional — they run cooperatively on the main thread, yielding at the timer.

### Magic system

Group 4 implements Fervor / Burnout / Cantrips / True Spells with per-spell `SpellData`:

- **Fervor** — player-only runtime state on `CombatantState`. Track: d4 → d6 → d8 → d10 (`FERVOR_TRACK` const). Cap = `data.ingenuity_size`. Resets to d4 each combat (Long Rest / Recovery persistence deferred to Group 5).
- **Escalation** — after a true spell resolves, `_escalate_fervor(_player, steps)` where `steps = ingenuity_maxed_count + (1 if fervor_maxed)`. Multiple steps possible in a single cast.
- **Burnout** — blocks `player_chose_spell()`; cantrips remain available. Cleared at combat start (Group 5 will add cross-scene persistence).
- **Cantrip** — uses `SpellData` (is_cantrip=true). Ingenuity pool, no Fervor die, no escalation. Available during Burnout. Granted via `node.spells` (Minor Studies carries cantrip_spark + arcane_touch; Fire Magic I carries Sparks).
- **True spell** — uses `SpellData`. Ingenuity pool + optional aspect dice + real Fervor die. Granted by spell school nodes (Fire Magic II–IV, Arcane I–III).

### SpellData (implemented)

`resources/SpellData.gd` (`class_name SpellData`):
- `spell_name: String`, `description: String`
- `aspect_stat: String` (`"dominion"` | `"negation"` | `""`) — non-Ingenuity stat for anchor dice; `""` = pure Ingenuity.
- `aspect_dice: int` — how many pool dice use `aspect_stat`; the rest are Ingenuity-tagged (count toward escalation even if discarded).
- `target_pool: String` — defense pool the spell pressures.
- `flat_bonus: int` — post-keep flat addition.
- `is_cantrip: bool` — no Fervor die, available during Burnout.
- `tags: PackedStringArray` — matched against `SpellBonusEffect.tag` at spell resolution.

### Spell school system (implemented — Groups 4.5 A + B)

**Phase A — Core stat nodes (implemented):**
- `NodeData.prerequisites: Array[NodeData]` — compound prereqs; all `.tres` migrated.
- Core nodes (`core_dominion_1/2`, `core_negation_1/2`, `core_ingenuity_1/2`) grant stat size upgrades via `effect_type="stat_size_<stat>"` and `effect_value` (8 or 10).
- `CombatManager._stat_size(state, stat)` — reads base from `CombatantData`, returns highest `effect_value` across matching unlocked Core nodes. All `state.data.*_size` reads replaced with this helper.

**Phase B — Spell schools (implemented):**
- `SpellBonusEffect` resource (`resources/SpellBonusEffect.gd`): `tag: String`, `bonus_type: "pool"|"keep"`, `value: int`, `stat: String`.
- `NodeData.spell: SpellData` → `NodeData.spells: Array[SpellData]` + `NodeData.bonus_effects: Array[SpellBonusEffect]`.
- School nodes Fire Magic I–IV and Arcane I–III in `resources/data/nodes/`. Each grants spells via `spells` array; Fire Magic II adds fire pool +1, Fire Magic IV adds fire keep +1.
- Minor Studies carries `spells = [cantrip_spark, arcane_touch]`; the 4 old flat spell stub nodes removed from `ALL_NODES`.
- `PlayerProgression.get_known_spells/cantrips()` scans `node.spells` on all unlocked nodes.
- `CombatManager._resolve_round_spell()` sums matching `bonus_effects` from all unlocked nodes before calling `RollEngine`: effective tier += pool bonus, keep_grade += keep bonus.

### GDScript typing rules

- All scene scripts that are referenced as types in other scripts **must** have a `class_name` declaration. Missing `class_name` causes "Could not find type" parse errors at load time.
- After adding a new `class_name`, update `.godot/global_script_class_cache.cfg` manually if the Godot editor has not been opened — the headless runner uses the cached index and will not rescan.
- Dictionary values from `RollEngine.resolve()` are `Variant`. Always annotate locals explicitly or cast with `as int` / `as Array`.

## Design references

- **Game rules** — entry point with reading order, section list, and current canonical design decisions:
  [docs/game-rules/index.md](docs/game-rules/index.md)
  _(Load specific rule files on demand; the rules summary table below covers 90% of coding needs.)_
- **Game style** — 2D turn-based dark fantasy duel RPG. Hand-drawn or dark-fantasy pixel art.
  UI should feel like a tangible RPG document. Tone: tense, strategic, rewarding.
  Full vision: [docs/game-style/style-concept.md](docs/game-style/style-concept.md)
- **Project status** — what is implemented, what is next, ordered roadmap:
  consult this before proposing any new implementation to ensure suggestions
  align with the current development phase and do not skip planned dependencies.
  [docs/project-status.md](docs/project-status.md)
  @./docs/project-status.md
- **Project index** — auto-generated code map: all GDScript files, resource schemas, data files,
  scenes, and their dependencies. Read this before scanning source files.
  @./docs/project-index.md

## Fragile areas — do not accidentally "fix" these

| Area | What looks wrong | Why it's correct |
|------|-----------------|-----------------|
| `_resolve_round*` in CombatManager | Called without `await` from `player_chose_*` | Intentional coroutine pattern — runs cooperatively on main thread, yields at the timer |
| `global_script_class_cache.cfg` | May be stale after adding a new `class_name` | Must be updated manually when Godot editor hasn't been opened — headless runner uses the cached index |
| `EquipmentData` flat bonuses | Applied unconditionally regardless of training | Inefficiency rule (Potency → 1 without training) is deferred to Group 3 |
| Per-pool guard state in `CombatantState` | Three separate guard/rolled pairs | Will become richer (cumulative Disadvantage) in Group 4; current structure is intentional |
| `debug_set_player_weapon` on `CombatManager` | Public method with "debug" in name on a production autoload | Used by `DebugWeaponSelector`; safe because it's null-guarded at the call site |
| `fervor_size` resets to d4 each `start_combat()` | Fervor doesn't persist across combats | Intentional — Long Rest / Recovery Scene cross-scene persistence is deferred to Group 5 |

## Game rules summary

The rules live in `docs/game-rules/`. The implementation must match them exactly. Key rules for the current prototype:

| Concept | Rule |
|---|---|
| Roll resolution | Build Pool → Roll → Keep → Flat → Outcome |
| Pool size | = Tier (T1=1 die, T2=2, T3=3, T4=4) |
| Die size | from stat field (`dominion_size`, `negation_size`, `ingenuity_size`) — face value int (4/6/8/10) |
| Keep | grade 0 → keep 1, grade 1 → keep 2, grade 2 → keep 3 |
| VT (Fast/Slow) | VT is a **static enemy property**. Only the **player's** action roll is compared to the enemy's VT. Player >= VT → Fast (acts first); Player < VT → Slow (enemy acts first). Enemy timing is implicit in VT — no roll. |
| Guard | rolled **once per round** when first pressured; subsequent same-round pressure reuses existing Guard without re-rolling; resets to 0 at round start |
| Breach | `attack_total >= guard` (reaching exactly 0 is a breach) |
| Wounds | 1 on breach; 2 if Massive: `(attack - guard) > defensive_size` |
| Defeat | `wounds >= max_wounds` |
| Cantrip | Ingenuity die, Tier pool, no Fervor die, no escalation, available during Burnout; spell granted by Minor Studies or school nodes (`SpellData.is_cantrip=true`) |
| True spell | Ingenuity + optional aspect dice + real Fervor die; spell granted by school node; escalation = `ingenuity_maxed_count + (1 if fervor_maxed)` |
| Fervor cap | = `ingenuity_size` die face; caster may act at cap; escalating **beyond** cap triggers Burnout |
| Burnout | Blocks true spells; cantrips unaffected; clears at next combat start (Group 5 adds persistence) |
| Stat sizes | Base from `CombatantData`; upgraded by Core nodes (mechanic wired in Phase A of spell school feature) |
| Spell schools | Fire Magic I–IV + Arcane I–III; `SpellBonusEffect` pool/keep bonuses applied at spell resolution (implemented) |

Next unimplemented feature: Group 5 — full game loop (hub scene, rest/recovery, reward loop, enemy roster).
