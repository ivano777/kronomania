# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Engine and tooling

- **Godot 4.6.2** — Forward Plus renderer, D3D12 on Windows, Jolt Physics.
- Godot binary resolved automatically (see "Running all checks" for priority order).
- Headless validation: `python scripts/run_headless.py` · Unit + integration tests: `python scripts/run_tests.py`
- **GUT 9.6.0** at `addons/gut/`; tests in `tests/`.
- After adding a new addon or asset (PNG etc.), run `"$GODOT" --headless --import --path .` once to import resources / register class names before testing. (`run_headless.py` has no `--import` flag.)
- No build step, no linter — Godot parses scripts on load.

## Committing and pushing

Use `/ship` — stages everything, writes a Conventional Commit from the diff, pulls `--rebase`, pushes. Never skip hooks; never force-push unless explicitly asked.

## Autonomous Feature Loop

Follow this for every requested feature, without exception.

### 1. Plan
Identify the smallest safe slice that proves the feature. Present which files change, what logic is added, what is deferred. **Wait for explicit approval before writing code.**

### 2. Implement
- Edit only the files in the approved plan. No unnecessary rewrites or scope creep.
- Parallelize independent files via subagents; never parallelize writes to files that share state or have load-order dependencies (e.g. autoloads before scenes that depend on them).
- Match subagent model to task: `haiku` — validation/headless/single-file fixes/searches; `sonnet` — single-file features, most implementation; `opus` — multi-file architecture, cross-system reasoning, design decisions.

### 2b. Debug & Testability
Every new mechanic/runtime value ships with a way to exercise it interactively. Debug widgets live in `scenes/debug/`, referenced via null-safe `@onready var _dbg = $Widget if has_node("Widget") else null`. Removal at release: delete `scenes/debug/`, remove the child from the `.tscn`, remove the `@onready` + its delegation method. If a mechanic has no tunable parameters, log-only is acceptable — document it in the report.

### 2c. Inter-phase context compaction
For multi-phase features, `/compact` between phases (after a phase validates, before the next) is encouraged when context grows large. The phase boundary is a natural checkpoint; the plan file preserves intent.

### 3. Validate (deploy a sub-agent)
Run **both**, in order:
1. **Tests first**: `python scripts/run_tests.py` — a failure blocks the loop; do not proceed until green.
2. **Headless**: `"$GODOT" --headless --path "..." --quit-after 5` — check SCRIPT ERRORs and ERRORs (UID WARNINGs are safe), verify `@onready` paths, signal connections, `class_name` registrations in `.godot/global_script_class_cache.cfg`.

### 4. Fix Loop
On failure: if a **test** fails, fix logic → re-run tests → re-run headless. If the **headless run** fails, fix the SCRIPT ERROR → re-run headless only. Repeat until both clean.

### 5. Update Documentation
Only after a clean validation pass: update `docs/game-rules/` if mechanics changed; update `CLAUDE.md` if architecture/rules changed. If the feature added/renamed a `.gd`, added a signal or `@export`, or added a `.tres` — run `/refresh-index` as the final action before `/ship`. Content-only changes skip this.

### 6. Report
Short enough to scan in under a minute: what was implemented + where, what validation confirmed, what docs were updated.

### 7. Commit and push
Ask the user to run `/ship`.

---

**Rules**
- Docs updated only after successful validation, never before.
- Never edit `docs/game-rules/` without explicit user approval — it is the single source of truth for design. If a rule is ambiguous, ask; never decide unilaterally.

## Running all checks

Canonical command (tests first, then headless):
```
python scripts/run_tests.py && python scripts/run_headless.py
```
Exits 0 only if all tests pass **and** the headless check is clean.

Godot binary resolved from (in order): 1) `GODOT` env var; 2) `.env.local` in project root (copy `.env.local.example`); 3) `godot` on PATH; 4) common Windows locations (`%LOCALAPPDATA%\Programs\Godot\Godot.exe`, `C:\Program Files\Godot\Godot.exe`). New contributors: copy `.env.local.example` → `.env.local` and set your path.

## Testing rules

- Every new mechanic ships with ≥1 unit test in `tests/unit/<system>/test_<system>.gd`. Scene/autoload-dependent flows go in `tests/integration/`.
- Tests must be deterministic: `seed(N)` before `RollEngine` calls.
- No `class_name` on test files (avoids polluting the global class cache). Test-only helpers (e.g. `combat_rules_helper.gd`) live beside the test, extend `RefCounted`, no `class_name`.
- Debug widgets (`scenes/debug/`) are never tested directly.

## Art pipeline (pixel-sprites skill)

- **Global pixel grid 640x360** — project viewport is 640x360, integer-scaled 2x into a 1280x720 window (`window_width_override`); do not "fix" the small viewport numbers in project.godot. Standard characters ≈64px tall (player 64x72, grunt 56x48, soldier 64x72, knight 64x80). UI text = **monogram pixel font** (`assets/fonts/monogram-extended.ttf`, CC0) as theme `default_font` @16 (titles 32); font import has AA/hinting/subpixel disabled. monogram is on-grid at 16 (its native em) — sizes must be multiples of 16. VT323 (the old font) was replaced because at 16px it rendered off-grid (uneven 1–3px strokes = "glitchy" text). monogram lacks some symbol glyphs (◆⚔★✦⊕═○●⚠🧘…); UI strings use only covered glyphs (♦ × • · ▶ ▼ * + − —) — do not reintroduce uncovered symbols or `allow_system_fallback` pulls AA'd system glyphs.
- Sprites are authored as XPM text frames in `tools/sprites/frames/` at native grid size (install at **scale 1** — the old `--scale 15` convention is dead), compiled by `python tools/sprites/compile.py [--check] tools/sprites` (Pillow — `tools/sprites/requirements.txt`). Full workflow lives in the **pixel-sprites skill** — invoke it for any sprite/art-asset work; never hand-draw PNGs.
- `.xpm` / `clips.json` writes are auto-validated by the PostToolUse hook (same `.claude/hooks/validate_godot.py`; sprite branch skips the Godot launch). `tools/sprites/out/` is generated and gitignored; visual previews at `out/preview/*@8x.png`.
- Install conventions (convention-loaded, **no `.tres` edits**): icons → `assets/sprites/icons/{weapons|spells|nodes}/<key>.png` (key = name lowercased, spaces→underscores; node icons use `node_id`); animated effects → `assets/sprites/effects/<Clip>_sheet.png` + `.json`, loaded via `SpriteRegistry.get_effect_frames(clip)` (animation `"default"`, fps/loop from JSON).
- Combatant battle sprites are **NOT pipeline art** — converted from CC0 packs (LuizMelo; license + links in `assets/sprites/combatants/LICENSE.md`) by `tools/sprites/import_pack.py` + manifest `tools/sprites/packs.json` (strip slicing, union-bbox crop for feet alignment, `flip` to face right, per-anim fps/loop). Output = `<anim>_sheet.{png,json}` per combatant, loaded by `SpriteRegistry.get_combatant_frames`. All 5 anims populated for the player, 4 for enemies (no cast). `die` has `loop=false` (freeze = corpse); `Combatant.gd` returns to idle via `animation_finished`, no timers. Enemy attacks animate via the `combatant_attacking` signal → `BattleScene._on_combatant_attacking`. Pack ZIPs in `tools/sprites/packs/` (gitignored). The XPM pipeline's scope = icons, spell/skill VFX, particles, effects, UI.
- Scene **backgrounds** are **NOT pipeline art** — composited from CC0 packs (ansimuz Gothicvania; license + links in `assets/sprites/backgrounds/LICENSE.md`) by `tools/sprites/import_env.py` + manifest `tools/sprites/env.json` (layers listed back→front, integer NEAREST upscale to cover 640x360, center-crop, optional `darken`). Output = `assets/sprites/backgrounds/<key>.png`, loaded by `SpriteRegistry.get_background(key)` (silent null on miss → scenes keep their flat-color fallback). Wired null-safe into `battle`/`campfire`/`menu` (`_ready` adds a `TextureRect` with `expand_mode=EXPAND_IGNORE_SIZE` — required, else the texture's native size blows out container layout; the `test_ui_bounds.gd` regression test guards this).
- **UI skin** is **NOT pipeline art** — 9-slice frames baked from the CC0 Kenney Fantasy UI Borders pack (license in `assets/sprites/ui/LICENSE.md`) by `tools/sprites/bake_ui.py` (composites a two-tone frame: dark fill + parchment/gold ring, colours mirror `theme/dark_fantasy.tres`). Output = `assets/sprites/ui/{panel,button_*}.png`, referenced as `StyleBoxTexture` (texture_margin 6) in the theme. Re-run `bake_ui.py` if the theme palette changes.
- After installing a new PNG run `"$GODOT" --headless --import --path .`, commit PNG + `.png.import`. The Fireball clip is the loader's test fixture (`tests/integration/test_sprite_registry.gd`) — keep it.

## Project structure

```
autoloads/          # RollEngine (dice), CombatManager (combat SM), PlayerProgression (constellation), DungeonManager (run state), SaveManager, DebugManager, SpriteRegistry, TooltipManager
combat/             # CombatManager refactor layers: CombatantState.gd (per-combat state), CombatMath.gd (pure static math), StatusOps.gd + InterruptOps.gd (status/interrupt bookkeeping), Disciplines.gd (magic-discipline casts)
combat/effects/     # Discipline effect-handler layer: CombatEffect base + EffectRegistry + Hex/TimeLock/Echo/MindBomb handlers; typed status-payload views (CastSnapshot, *Payload) + AttackContext
resources/          # Resource class defs (.gd) + data/ (.tres) — see project-index.md
scenes/main_menu/   # MainMenuScene (title, New Game, 3-slot save/load, Quit)
scenes/battle/      # BattleScene (1v1), CombatantHUD, RoundHUD, Combatant
scenes/campfire/    # CampfireScene (rest, weapon selector, Constellation nav, Give Up)
scenes/constellation/  # ConstellationScene (skill tree)
scenes/debug/       # Debug widgets — removable at release; never imported by production code
scripts/            # gen_project_index.py — regenerates docs/project-index.md
tools/sprites/      # XPM→PNG pipeline (compile.py, frames/, clips.json; out/ gitignored) + CC0 pack converters (import_pack.py combatants, import_env.py backgrounds, bake_ui.py UI skin; packs.json/env.json; packs/ gitignored)
assets/sprites/     # icons/{weapons,spells,nodes}/, effects/, combatants/, backgrounds/, ui/ — convention-loaded by SpriteRegistry
assets/fonts/       # monogram pixel font (CC0) — theme default_font
docs/game-rules/    # Design source of truth — TOC at index.md; load on demand
docs/impl/          # per-group implementation specs
docs/               # project-status.md (roadmap), project-index.md (generated map)
.claude/            # agents/docs-alignment-auditor.md, commands/, hooks/validate_godot.py (PostToolUse), skills/pixel-sprites
```

## Architecture

### One-way data flow

`CombatantData` (`.tres`) → `CombatManager` → signals → `BattleScene` → HUD nodes.

`CombatantData` is **immutable config** only. All runtime state lives in `CombatantState` (`combat/CombatantState.gd`, global `class_name`, instantiated per combat). Scene nodes hold no game state.

**CombatManager refactor (in progress — incremental strangler):** pure combat math (stat/tier/keep/modifier/format helpers) lives in `combat/CombatMath.gd` as stateless `static` funcs. CombatManager keeps same-signature private wrappers (`_stat_size`, `_effective_tier`, `_get_action_modifier`, `_add_status`, `_find_interrupts`, …) that delegate to `CombatMath.*` / `StatusOps.*` / `InterruptOps.*`. Do NOT re-inline the logic into CombatManager. `StatusOps.tick()` RETURNS log lines (the `_tick_statuses` wrapper emits them). Orchestrators that read `PlayerProgression`/round-scoped state stay in CombatManager: `_apply_spell_outcome_effects` (delegates per-effect predicates + dispatch to `StatusOps`), `_process_statuses_hook` (awaits the echo). Awaited interrupt resolvers (`_resolve_interrupt`, `_resolve_meat_for_the_grinder`, `_try_prevent_burnout`) stay in CombatManager. Magic-discipline logic (Mind Detonation, Mind Rend, Time Lock cast, echo resolution + the shared `roll_enemy_guard` dedup) lives in `combat/Disciplines.gd` as statics over the `CombatManager` autoload global; CM keeps `_check_mind_detonation`/`_cast_mind_rend`/`_cast_time_lock`/`_resolve_spell_echo` wrappers. The async spine (`_resolve_attack`, `_resolve_round*`, `_end_of_round`) stays in CombatManager. **Refactor COMPLETE — all 5 phases done** (0 characterization tests, 1 CombatState, 2 CombatMath, 3 StatusOps+InterruptOps, 4 Disciplines). CombatManager 2052 → 1466 lines.

**Discipline effect-handler layer (`combat/effects/`, COMPLETE):** the async spine now names NO discipline — the inline hex/Time-Lock/echo/frozen special-cases were dissolved into per-`status_id` handlers. `CombatEffect` (base, `RefCounted`) has 5 optional no-op hooks: `on_wound_calc(status, ctx)` (Hex +1), `on_player_attack_resolved(status, ctx)` (Time Lock armed→frozen), `on_end_of_round(status, state)` (Echo, async), `on_guard_reset(status, state, i)` (Time Lock frozen restore), `on_expire(status, state)` (expiry log). `EffectRegistry.get_handler(status_id)` maps to `HexEffect`/`TimeLockEffect`/`EchoEffect`/`MindBombEffect`. `_resolve_attack`, `_end_of_round`, `_process_statuses_hook`, and `StatusOps.tick` iterate `active_statuses.duplicate()` and dispatch to the registry — do NOT re-inline discipline logic into the spine. Status payload is de-smuggled via typed VIEWS over `stat_overrides` (`CastSnapshot`, `MindBombPayload`, `EchoPayload`, `TimeLockPayload` — the `cast_*`/phase/kept-dice key schema lives ONLY in those classes; storage stays a dict). `AttackContext` carries the per-attack facts (`did_breach`, `wounds_pending`, …) to the hooks. Cast dispatch is data-driven: `SpellData.cast_handler`/`placement_scratch`/`primes_status` replace the old `spell.spell_name` match. The three round coroutines share one `_run_enemy_attacks(slow_phase, p_total, target_pool, target_index, brutal_trade)` for their Phase 1/3 enemy loops. Handlers reach singletons via the `CombatManager`/`PlayerProgression` globals (like Disciplines/StatusOps). `Disciplines.gd` still holds the discipline CAST logic (`cast_mind_rend`, `cast_time_lock`, `detonate_mind_bomb`, `resolve_spell_echo`); the handlers hold the SPINE-integrated lifecycle. Adding a discipline = new handler + registry entry + spell fields, no spine edit. Plan: `~/.claude/plans/i-think-we-have-twinkly-steele.md`.

`CombatantState` fields, grouped:
- *Identity/HP:* `data`, `current_wounds`, `max_wounds`, `is_defeated`
- *Progression:* `node_levels: Dictionary` (NodeData→int), `tier_override`, `weapon_override`, `off_hand_override`
- *Per-combat charges:* `item_action_charges` (action_key→uses; from `rest_type="combat"` ActionModifiers at `start_combat()`), `space_domination_active`
- *Effects:* `active_statuses: Array[CombatStatus]` (always iterated as `.duplicate()`), `interrupt_handlers: Array[InterruptHandler]` (combat-scoped, registered at `start_combat()`, charges reset each combat), `pending_guard_debuffs` (`{pool: {flat, keep}}`; single-use, queued by SpellOutcomeEffect, consumed on next guard roll)
- *Guard:* `stance_guard`/`resolve_guard`/`stamina_guard` + matching `_rolled` bools
- *Magic:* `fervor_size`, `is_burned_out`, `has_minor_studies`, `has_spellcasting`, `known_spells`, `known_cantrips`
- *Methods:* `init()`, `reset_guard()`, `get_guard(pool)`, `set_guard_val(pool, v)`, `is_pool_rolled(pool)`, `set_pool_rolled(pool, v)`

### Autoload singletons

Signatures/signals are in `docs/project-index.md`. Gotchas:

**`RollEngine`** — stateless. Returns `Dictionary`; always cast with `as int` / `as Array` (the inferencer can't infer through `Dictionary`). `resolve()` optional args: `fervor_size` (additive post-Keep Fervor die), `aspect_stat_size` + `aspect_count` (mixed-pool spells), `post_keep_bonus_size` (post-Keep bonus die, e.g. Earthshatter). Returns `primary_dice_maxed_count` (escalation) and `post_keep_bonus_roll`.

**`CombatManager`** — all output via signals; nothing returned. Disconnect all signals before `reload_current_scene()`.
- *Signals:* `player_intents_available`, `fervor_changed`, `player_magic_available`, `player_massive_incoming`, `player_burnout_imminent` (L2, before `_burnout_decision_gate`), `player_defense_incoming`, `player_defense_item_choice`, `combatant_attacking(is_player, enemy_index)` (pre-resolve, drives enemy attack anims). Coroutine gates: `_massive_decision_gate(use_charge)`, `_burnout_decision_gate(use_charge)`.
- *Public:* lifecycle `start_combat(player, enemies)`, `reset_item_charges(rest_type)`; actions `player_chose_strike(net_adv, pool, brutal, idx, weapon)`, `player_chose_cantrip(spell, idx, source_weapon)`, `player_chose_spell(spell, idx, source_weapon)`, `player_chose_lucidity()` (L1); interrupts `player_chose_degrade_wound(use)` (MftG), `player_chose_prevent_burnout(use)` (L2); UI `player_acknowledged_defense()`, `player_chose_defense_item(mod)`, `player_auto_execute_attack(idx, net_adv)`; debug `debug_set_fervor`, `debug_refill_hp`, `debug_set_immortal`, `debug_set_lethal`, `debug_set_player_off_hand`; reads `get_player_bare_hands_modifier(key)`, `get_player_attack_preview()`.
- *Key helpers:* `_get_action_modifier(state, key)` (weapon→bare_hands→zero stub), `_effective_tier(state, mod)` (mod.tier_cap=0 = uncapped), `_attack_flat`/`_guard_flat`/`_pool_bonus` (delegate to `_get_action_modifier`). `_get_cast_modifier(state)` resolves the player's chosen `_player_cast_weapon`'s `"cast"` modifier; bare-hands fallback (tier_cap=0 = full Tier). Cantrip and true-spell pools route through `_get_cast_modifier`, never `_get_action_modifier(_, "strike")`. `_collect_spell_bonuses(spell)` sums pool/keep/flat across purchased nodes (shared by `_resolve_round_spell`, `_detonate_mind_bomb`, `_resolve_spell_echo`). Discipline entry points: `_check_mind_detonation`, `_detonate_mind_bomb`, `_cast_mind_rend`, `_resolve_spell_echo`, `_cast_time_lock` — behavior in Game rules summary. The Time Lock armed→frozen transition + frozen-guard restore + hex amplification + echo dispatch are NO LONGER inline in the spine — they live in `combat/effects/` handlers fired by the generic registry loops (see the Discipline effect-handler layer above).

**`PlayerProgression`** — constellation state; read by `CombatManager` at `start_combat()`.
- `ALL_NODES`: 11 Dominion + neg_core/ing_core L1-3 + ability nodes. `get_known_spells()`/`get_known_cantrips()` collect from `levels_data[0..level-1].spells`. `get_node_level_by_id(id)` returns level (0 if absent).
- **Fervor persistence:** `saved_fervor_size`/`saved_is_burned_out`/`saved_wounds` written by `_end_combat()`, read at `start_combat()` (`saved_wounds` carries across chained encounters).
- `combat_prefs: CombatPreferences` — persisted action defaults + mode flags; fresh in `reset()`, serialized with saves.
- **Default keep baseline:** `_grant_default_keep_nodes()` (in `reset()`) auto-grants L1 of `dom_martial_arts`, `dom_stamina`, `neg_stance`, `ing_resolve`. Post-C2.6 their effect_values are 1/2/3 (keep N dice); L1 is the free baseline (1 die), L2/L3 the upgrades.
- Methods: `reset()`, `apply_long_rest()` (reset Fervor + clear Burnout), `apply_short_rest()` (−1 wound, −1 Fervor step, clear Burnout), `apply_recovery()` (clear Burnout only), `grant_points(n)`, `equip_main_hand(w)`, `equip_off_hand(w)`, `debug_set_points(n)`, `debug_set_tier(t)`.

**`DungeonManager`** — run state: `start_run()`, `current_enemies()`, `on_victory()` (+1 point, advance), `on_defeat()`, `has_next_enemy()`, `is_run_complete()`, `was_last_fight_chained()`, `enemies_cleared()`, `enemies_total()`. Hard-coded 8-encounter sequence: [1] Grunt, [2] Grunt→Grunt, [3] Grunt+Grunt, [4] Soldier, [5] Grunt→Grunt+Soldier, [6] Grunt×3, [7] Grunt+Soldier→Soldier+Soldier, [8] Knight.

### Round loop (CombatManager)

```
_begin_round()
  → _process_statuses_hook("start_of_round", player/enemy×N)
  → _tick_statuses(...)                            ← decrements/removes expired
  → emits player_intents_available / player_magic_available / player_action_required
  → player presses Strike/Cantrip/Spell → BattleScene → player_chose_*
  → _resolve_round / _resolve_round_cantrip / _resolve_round_spell
  → rolls attacks, VT check, _resolve_attack() × N (Slow enemies → Player → Fast enemies)
	  → on breach: _process_statuses_hook("on_breach", defender, {pool, attacker})
	  → interrupt check: _find_interrupts(defender, trigger) → await _resolve_interrupt() each
  → [Phase 2.1, post player-attack] await _check_mind_detonation(target, idx) — all 3 round types
  → [spell only] _escalate_fervor(steps), steps = primary_dice_maxed_count + (1 if fervor_maxed)

await _end_of_round()
  → await _process_statuses_hook("end_of_round", player/enemy×N)
	  → [Echoing Mind] "echoing_spell": await _resolve_spell_echo → _resolve_attack (frozen Fervor,
		no escalation) → if target alive, await _check_mind_detonation → decrement current_kept_dice
  → if _all_enemies_defeated(): _end_combat(); return   ← echo may have killed last enemy
  → _tick_statuses(...)
  → guard reset for all combatants (+ guard_changed signals)
  → await 0.8s timer → _begin_round()  ← loops until defeat
```

`_resolve_round*`, `_resolve_attack`, `_end_of_round`, `_process_statuses_hook` are all coroutines. `player_chose_*` call `_resolve_round*` without `await` intentionally (cooperative, yields at timer). `_process_statuses_hook` calls at `_begin_round`/`_resolve_attack` are NOT awaited (no async work on `start_of_round`/`on_breach`); the `_end_of_round` call IS awaited (echo). Guards reset in `_end_of_round`, so they're 0 when `start_of_round` hooks fire.

### Status system

`CombatStatus` is data-only (`resources/CombatStatus.gd`); all logic lives in `CombatManager._process_statuses_hook()`, never in the resource.

Helpers: `_add_status(state, status)` (removes same `status_id` then appends — re-applying refreshes, no stacking), `_remove_status(state, id)`, `_has_status(state, id)`, `_get_status(state, id)`, `_tick_statuses(state)` (decrements `duration_rounds`, removes at 0; runs once after `start_of_round` hooks and once after `end_of_round` hooks → twice per full round).

`_process_statuses_hook(hook, state, context)` matches on `status_id`, always over `active_statuses.duplicate()`. Active cases: `mind_detonation_primed`, `hex_marked`, `echoing_spell` (only `echoing_spell` does async work on `end_of_round`; the others are no-ops — breach-driven, not hook-driven).

Stat overrides: `_stat_size()` reads `status.stat_overrides[stat]` before node levels — overrides win. `stat_overrides` also carries non-stat payload (e.g. `mind_detonation_primed`'s `fervor_at_prime`/`md_level`, `echoing_spell`'s echo state); non-stat keys are never read by `_stat_size`.

### Interrupt system

`InterruptHandler` is a reactive hook registered per `CombatantState` at `start_combat()`. Two fire points, **separate dispatch paths**:
1. **`_resolve_attack()`** — trigger `"on_massive_wound"`, wounds-shaped. `_find_interrupts` → `await _resolve_interrupt(handler, state, ctx)` (returns `{wounds_modified, resolved}`). Active: **Meat for the Grinder**. Add: case in `_resolve_interrupt()` + `_resolve_<name>()` + register in `start_combat()` + priority table.
2. **`_escalate_fervor()`** — trigger `"on_burnout"`, bool-shaped. `await _try_prevent_burnout(state)` directly (emits `player_burnout_imminent`, awaits `_burnout_decision_gate`, returns `true` if prevented). Does NOT use `_resolve_interrupt`. Active: **Lucidity L2**.

Priority (lower first): Lucidity L2 (`on_burnout`) = 10, Meat for the Grinder (`on_massive_wound`) = 20. Never contend — different fire points.

### Data-only resource fields

Three data-only resources (zero methods; logic in `CombatManager`):
- **CombatStatus** (`resources/CombatStatus.gd`): `status_id`, `duration_rounds` (-1 = permanent), `stat_overrides: Dictionary`, `escalation_threshold: int`, `source_node_id`. (Behaviour: Status system.)
- **InterruptHandler** (`resources/InterruptHandler.gd`): `handler_id`, `trigger` ("on_massive_wound"|"on_burnout"), `target` ("self"|"enemy"), `charges`, `priority`. (Behaviour: Interrupt system.)
- **SpellOutcomeEffect** (`resources/SpellOutcomeEffect.gd`): `spell_id`, `trigger` ("on_hit"|"on_breach"|"on_cast"|"on_detonate"), `target`, `target_pool`, `effect_type` ("debuff_flat"|"debuff_keep"|"bonus_keep"|"bonus_flat"|"apply_status"), `value`, `condition`, `status_to_apply: CombatStatus`. (Behaviour: Spell outcome effects.)

**Boundary — SpellOutcomeEffect vs CombatStatus:** SpellOutcomeEffect is instantaneous (same spell resolution). For cross-round persistence use `effect_type="apply_status"`. NEVER add a duration field to SpellOutcomeEffect.

### Magic system

- **Fervor** — player-only state. Track d4→d6→d8→d10 (`FERVOR_TRACK`). Cap = `data.ingenuity_size`. Persists across combats (`saved_fervor_size`); Long Rest resets to d4, Recovery only clears Burnout.
- **Escalation** — after a true spell, `await _escalate_fervor(_player, steps)`, `steps = primary_dice_maxed_count + (1 if fervor_maxed)`. Coroutine: a positive step that would set Burnout awaits `_try_prevent_burnout` (Lucidity L2) before committing.
- **Burnout** — blocks `player_chose_spell()`; cantrips remain. Persists; cleared by Long Rest or Recovery.
- **Cantrip** — `is_cantrip=true`. Ingenuity pool, no Fervor die, no escalation, available during Burnout. Via `node.spells` (Minor Studies: `arcane_bolt`, `arcane_touch`).
- **True spell** — Ingenuity + optional aspect dice + real Fervor die. Granted by Spellcasting L1+ (Arcane Missile + Arcane Mark).

**SpellData** (`resources/SpellData.gd`): `spell_name`, `description`, `aspect_stat` (`"dominion"`|`"negation"`|`""`=pure Ingenuity), `aspect_dice` (non-Ingenuity pool dice; the rest are Ingenuity-tagged and count toward escalation), `target_pool`, `flat_bonus`, `is_cantrip`, `tags: PackedStringArray` (matched vs `SpellBonusEffect.tag`).

### Node-driven spell bonuses

**Core stat nodes:** `dom_core`/`neg_core`/`ing_core` L1–L3 via `effect_type="stat_size_<stat>"` + `effect_value`. `_stat_size(state, stat)` returns the highest `effect_value` across purchased entries (base from `CombatantData`).

**SpellBonusEffect** (`resources/SpellBonusEffect.gd`): `tag`, `bonus_type` ("pool"|"keep"|"flat"), `value`, `stat`, `spell_id`. Applies if `spell_id` matches the spell name (non-empty) OR `tag` matches a spell tag (empty `spell_id`). `_resolve_round_spell()` sums matches into `spell_pool_bonus`/`spell_keep_bonus`/`spell_flat_bonus`. E.g. Spellcasting L2: `tag="arcane" keep+1` + `spell_id="Arcane Missile" flat+1`; L3 adds another `keep+1` and `flat+1`.

**Node schema:** `NodeData`: `node_id`, `display_name`, `category`, `base_description`, `icon`, `max_levels`, `levels_data: Array[NodeLevelData]`. `NodeLevelData`: `level_index`, `cost`, `required_tier`, `prerequisites` (untyped `[{node_id, required_level}]`), `level_effect_description`, `effect_type`, `effect_value`, `stat`, `weapon_tags`, `uses_per_combat`, `spells`, `bonus_effects`, `outcome_effects`. CombatManager node helpers: `_node_effect_max`, `_node_effect_sum`, `_node_weapon_bonus_sum`, `_has_effect_type`, `_physical_keep_grade`, `_defense_keep_grade`, `_wounds_node_bonus`, `_meat_grinder_charges`. Both `_physical_keep_grade` and `_defense_keep_grade` use `maxi(_training_keep_grade(state), _node_effect_max(state, key))` — training is the floor. All `*_keep` effect_values follow the post-C2.5/C2.6 convention: **N = keep N dice** (1/2/3 for L1/L2/L3).

### Spell outcome effects

`SpellOutcomeEffect` (on `NodeLevelData.outcome_effects`) describes effects applied AFTER resolution — contrast `SpellBonusEffect` (modifies the roll). Flow in `_resolve_round_spell`/`_cantrip`:
1. Roll built with `SpellBonusEffect` applied (incl. `spell_id` filter)
2. `_resolve_attack` runs → breach/hit outcome, updates `_current_round_player_breaches`
3. `_apply_spell_outcome_effects` collects matching entries from purchased nodes
4. Each filtered by `trigger` then `condition`, then dispatched
5. Effects queue a single-use `pending_guard_debuffs` entry (consumed on next guard roll), apply a `CombatStatus`, or are no-ops with `push_warning`

**Round-scoped tracking:** `_current_round_player_breaches` lives on `CombatManager` (not `CombatantState`), reset every `_begin_round()`. `"hit"/"breach"` in the outcome dict = "this spell caused the round's FIRST breach on its target_pool" (false if the pool was already breached).

### GDScript typing rules

- Scene scripts referenced as types elsewhere **must** declare `class_name` (missing it → "Could not find type" at load).
- After adding a `class_name`, update `.godot/global_script_class_cache.cfg` manually if the editor hasn't been opened — the headless runner uses the cached index.
- `RollEngine.resolve()` Dictionary values are `Variant` — annotate locals or cast (`as int`/`as Array`).

## Design references

- **Game rules** (reading order, canonical decisions): [docs/game-rules/index.md](docs/game-rules/index.md). _Load specific files on demand; the summary below covers ~90% of coding needs._
- **Game style** — 2D turn-based dark-fantasy duel RPG; hand-drawn/dark-fantasy pixel art; UI feels like a tangible RPG document; tense, strategic. [docs/game-style/style-concept.md](docs/game-style/style-concept.md)
- **Project status** (roadmap; consult before proposing new work): [docs/project-status.md](docs/project-status.md) @./docs/project-status.md
- **Project index** (auto-generated code map; read before scanning source): @./docs/project-index.md

## Fragile areas — do not accidentally "fix" these

| Area | Why it's correct |
|---|---|
| `_resolve_round*` / `_end_of_round()` called without visible `await` | Coroutine pattern — run cooperatively on the main thread, yield at the timer; callers do use `await` where needed |
| Guard reset in `_end_of_round()` not `_begin_round()` | Guards must be 0 when `start_of_round` hooks fire |
| `global_script_class_cache.cfg` stale after new `class_name` | Update manually when the editor hasn't been opened — headless uses the cached index |
| `EquipmentData` flat fields (`potency`, `flat_attack_bonus`, …) still present | Deprecated shims, superseded by `action_modifiers`; ignored at runtime when `action_modifiers` is non-empty |
| Three separate per-pool guard/rolled pairs | Cumulative Disadvantage on 2nd+ pool pressure is deferred (project-status Future) |
| `debug_set_player_weapon` public on a production autoload | Used by `DebugWeaponSelector`; null-guarded at the call site |
| `CombatStatus` has no methods | Logic lives in the dispatcher, not the data |
| `_process_statuses_hook` iterates `.duplicate()` | Prevents array mutation during iteration if a case adds/removes mid-loop |
| `_stat_size()` checks active_statuses before node_levels | Temporary overrides (e.g. Purple Hollow d12) must win over permanent progression |
| `_add_status` silently replaces duplicates | Re-applying refreshes, not stacks |
| `pending_guard_debuffs` consumed/erased before the roll | Single-use; consuming first guarantees apply-once |
| `_current_round_player_breaches` on `CombatManager` not `CombatantState` | Round-scoped, resets every `_begin_round()` |
| `status_to_apply` is `.duplicate()`'d before adding | Each application independent; otherwise duration ticks share state across enemies |
| `bonus_keep`/`bonus_flat` in `SpellOutcomeEffect` `push_warning` at dispatch | Reserved for Group D outcome-driven bonuses; warning prevents silent misuse |
| `SpellBonusEffect` with `spell_id` set matches OR-style with tag | `spell_id` non-empty = name filter; empty = tag match; both true is harmless (summed once) |
| `"hit"/"breach"` false even when `attack_total >= guard` | They mean "round's FIRST breach on the target_pool"; an already-breached pool yields false |
| InterruptHandler priority 10/20 | Lucidity L2 (10, `_escalate_fervor`) before MftG (20) — deliberate order |
| `_resolve_interrupt` awaited inside `_resolve_attack` | Interrupts may need player input — the await is the point |
| InterruptHandler charges on the handler, not `CombatantState` | Each handler manages its own resource; same-trigger handlers have independent charges |
| Interrupt registration in `start_combat`, not on purchase | Handlers are combat-scoped; charges reset every combat |
| `wounds_pending` reassigned inside the interrupt loop | Loop modifies wounds only on the player-defender/massive path; final `wounds := wounds_pending` is the applied count |
| `_escalate_fervor` accepts negative steps | Lucidity L1 cools Fervor; `clampi` floors at 0; Burnout check + cap clamp gated to `steps > 0` |
| `_escalate_fervor` is a coroutine | Awaits `_try_prevent_burnout` on the positive-step Burnout path; both call sites use `await`; the cooling path never hits an await |
| `_try_prevent_burnout` separate from `_resolve_interrupt` | `_resolve_interrupt` is wounds-shaped (`_resolve_attack`); `_try_prevent_burnout` is bool-shaped (`_escalate_fervor`) — different fire point + return contract |
| Discipline spine logic lives in `combat/effects/` handlers, not the spine | `_resolve_attack`/`_end_of_round`/`_process_statuses_hook`/`StatusOps.tick` iterate `active_statuses.duplicate()` and dispatch to `EffectRegistry.get_handler(status_id)`. Do NOT re-inline hex/Time-Lock/echo/frozen into the spine. Breach-driven MD detonation stays in the round coroutines (`_check_mind_detonation` at Phase 2.1) — it is dispatch, not a lifecycle hook |
| Cast routing is data-driven via `SpellData.cast_handler`/`placement_scratch`/`primes_status` | `_resolve_round_spell` matches `cast_handler` ("mind_rend"/"time_lock"/""), not `spell.spell_name`; do not reintroduce name string-matches. Echo arming stays tag-driven (`"echo" in spell.tags`) |
| Three round coroutines share `_run_enemy_attacks(slow_phase, …)` | Phase 1/3 Slow/Fast enemy loops extracted; `brutal_trade` VT offset is a param (strike passes it, cantrip/spell pass false) |
| Mind Detonation placement roll uses pool=1, not tier | Driven by `SpellData.placement_scratch=true`; deliberate weak gear-independent scratch (literal `1`, `net_advantage=0`, no `_pool_bonus`) |
| Status removed BEFORE `_resolve_attack` in `_detonate_mind_bomb` | Prevents re-trigger: MD fires on Stance breach, explosion hits Resolve; removing first is the clean guarantee |
| Mind Detonation explosion does not escalate Fervor | Delayed payoff using frozen `fervor_at_prime`, not a fresh cast |
| `_cast_mind_rend` bypasses `_resolve_attack` | Mind Rend suppresses the breach wound and applies a mark instead; the standard path always deals the wound |
| Hex amplification is `HexEffect.on_wound_calc` (+1), not inline | The spine's generic wound loop calls handlers only for player-on-enemy breaches; `HexEffect` returns +1 and logs "hex flares" |
| Mind Rend's own breach does not self-amplify | Mark applied AFTER the on_breach hook; wound suppressed regardless |
| Hex + Mind Detonation: both Stance breach and explosion breach amplified | Both route through `_resolve_attack` with the same mark; each amplification independent — designed combo |
| `echoing_spell` lives on the PLAYER, not the target | The caster echoes; one echo train at a time; new cast overwrites old; moves with the caster regardless of which enemy is alive |
| `current_kept_dice` self-terminates the echo, not `duration_rounds` | Kept-dice decay is the design; `duration_rounds=20` is a safety bound that should never trip (`_tick_statuses` logs `[debug]` if it does) |
| Echo routes through `_resolve_attack` but does NOT escalate Fervor | `_escalate_fervor` is in `_resolve_round_spell` after Phase 3, not in `_resolve_attack`; echo bypasses the cast path (frozen Fervor, delayed payoff) |
| New cast of an echoing spell overwrites the existing `echoing_spell` | Stacking echo trains rejected as too complex; latest wins (known simplification) |
| `_process_statuses_hook` has `await` but not all callers `await` it | Only `end_of_round` fires async (echo); `start_of_round`/`on_breach` run synchronously — fire-and-forget is safe there |
| `_end_of_round` checks `_all_enemies_defeated()` mid-function and returns early | An echo can kill the last enemy; `_end_combat()` before the timer; callers guard with `if _all_enemies_defeated(): return` before `_begin_round()` |
| `_cast_time_lock` bypasses `_resolve_attack` | Intentional — Time Lock suppresses the breach wound, mirrors `_cast_mind_rend`; the Resolve attack never routes through the standard pipeline |
| `time_locked` is a two-phase status (armed→frozen) | Intentional — armed waits for the next player attack; frozen locks that pool. `TimeLockEffect.on_player_attack_resolved` transitions it (via `ctx.did_breach`); `on_guard_reset` restores the frozen pool each `_end_of_round`. Payload via `TimeLockPayload` (typed view over `stat_overrides`) |
| Frozen pools survive `reset_guard()` across `_end_of_round` | `TimeLockEffect.on_guard_reset` runs AFTER the reset: restores `frozen_value` (from `TimeLockPayload`), marks the pool rolled, decrements `skip_resets`, removes the status at 0 |
| The armed→frozen transition fires for echoes and MD explosions too | Intentional — any player attack through `_resolve_attack` hits the generic post-attack handler loop (`attacker_is_player=true`); echoes and explosions included |
| Cantrip/true-spell pool uses `_get_cast_modifier`, never strike mod | Do not revert to `_get_action_modifier(_, "strike")`; that was the Phase 1 bug. Cast pool = `_effective_tier(player, cast_mod) + cast_mod.pool_bonus` (+ school bonuses for spells) |
| Explosion uses frozen cast values from `MindBombPayload`/`CastSnapshot` | Frozen at prime time via `CastSnapshot.from_mod`; read back with `MindBombPayload.from_status`. Legacy statuses without keys fall back to `_effective_tier(_player, null)`. Do not read live `_player_cast_weapon` in `_detonate_mind_bomb` |
| Echo uses frozen cast values from `EchoPayload`; keep NOT present | `EchoPayload` omits `cast_keep_bonus` (`CastSnapshot.write(include_keep=false)`) — focus keep is baked into `current_kept_dice` at arming and decays with the train |
| Cast tool list mirrors strike list in `_build_tool_entries("magic")` | Bare Hands entry appears only when no equipped item has `"cast"` key — same logic as attack Bare Hands |
| Player strike flat/pool/weapon-tag bonuses sourced from `chosen_weapon` | `_attack_flat`, `_pool_bonus`, and `_node_weapon_bonus_sum` accept optional `strike_mod`/`weapon` params; the player-strike call site in `_resolve_round` passes `_strike_mod` + `chosen_weapon`. Do NOT revert to calling without those args there — that was the off-hand bug. Enemy/auto/preview callers use defaults and are unaffected. When `chosen_weapon == null` (auto-fallback/disarmed), helpers fall back to state's main-hand/equipped weapon. |
| `get_player_attack_preview()` is dead code | Has zero callers in the repo; intentionally untouched. Do not rely on it to test strike bonuses. |

## Game rules summary

Rules live in `docs/game-rules/`; the implementation must match exactly.

| Concept | Rule |
|---|---|
| Roll resolution | Build Pool → Roll → Keep → Flat → Outcome |
| Pool size | = Tier (T1=1 die … T4=4) |
| Die size | from stat field (`dominion_size`/`negation_size`/`ingenuity_size`), face int 4/6/8/10 |
| Keep | **N = keep N dice** (keep_grade=1→1 die, 2→2, 3→3) |
| VT (Fast/Slow) | VT is a static enemy property; only the **player's** action roll is compared. Player ≥ VT → Fast (acts first); < VT → Slow. Enemy timing implicit, no roll. |
| Guard | rolled **once per round** when first pressured; same-round pressure reuses it; resets to 0 at round start |
| Breach | `attack_total >= guard` (exactly 0 is a breach) |
| Wounds | 1 on breach; 2 if Massive: `(attack − guard) > defensive_size` |
| Defeat | `wounds >= max_wounds` |
| Cantrip | Ingenuity die, pool = effective Tier via chosen cast tool (`_get_cast_modifier`; mundane weapon caps at 1, bare hands = full Tier), no Fervor die, no escalation, no school bonuses, usable during Burnout; via `node.spells` (Minor Studies: Arcane Bolt, Arcane Touch), `is_cantrip=true` |
| True spell | Ingenuity + optional aspect dice + real Fervor die; pool = effective Tier via chosen cast tool (same cap/bonus mechanics as cantrip) + school pool bonus; Spellcasting L1+ (Arcane Missile vs Stance, Arcane Mark vs Resolve); escalation = `primary_dice_maxed_count + (1 if fervor_maxed)` |
| Fervor cap | = `ingenuity_size` face; may act at cap; escalating **beyond** cap → Burnout |
| Burnout | Blocks true spells; cantrips unaffected; persists across combats; cleared by Long Rest (also resets Fervor) or Recovery (Burnout only) |
| Stat sizes | Base from `CombatantData`; upgraded by Core nodes via `_stat_size()` |
| Spellcasting L1–L3 | L1: Arcane Missile + Arcane Mark, unlocks Fervor. L2: all arcane keep 2, Arcane Missile +1 flat, Arcane Mark breach → enemy Stance flat −2. L3: all arcane keep 3, Arcane Missile +2 flat total, Arcane Mark breach also → enemy Stance keep −1 (Frattura Totale). |
| Tier advancement | Slot-budget: **5 combat + 2 Flavor slots** per tier; spending both advances + resets. Core = 2 combat slots; Training/Ability = 1; Flavor = 1 from Flavor budget. `tier_combat_spent`/`tier_flavor_spent` public. |
| Passive wounds | +1 Max Wounds at T2, +1 at T4 (cumulative +2). At `start_combat()` via `_tier_wound_bonus(tier)`; base `.tres` never mutated. |
| Player base Dominion | d4 (`player_default.tres`); `dom_core` L1→d6, L2→d8, L3→d10 via `_stat_size()`. |
| Physical keep grade | `_physical_keep_grade()` = `maxi(_training_keep_grade(), physical_keep nodes)`. Physical Strike only. Off-hand strikes use `_strike_mod` (resolved from `chosen_weapon`) for tier/flat/pool/keep; weapon-tag node bonuses (`weapon_flat`, `weapon_keep`) are matched against `chosen_weapon.tags`. |
| Defensive keep grade | `_defense_keep_grade(state, pool)` = `maxi(_training_keep_grade(), <pool>_keep nodes)`. Mirrors physical. At guard rolls in `_resolve_attack`, `_cast_mind_rend`, and `_cast_time_lock`. |
| Brutal Trade | RoundHUD toggle (visible when `dom_brutal >= 1`): VT −5, Flat +5 on player physical attack. |
| Earthshatter | Post-keep Dominion die on Stance physical attacks when `dom_earthshatter` purchased. Passed as `post_keep_bonus_size`. |
| Meat for the Grinder | `InterruptHandler` (`meat_for_the_grinder`, `on_massive_wound`, priority 20) at `start_combat()`. On a Massive Wound to the player, `_find_interrupts` fires it → emits `player_massive_incoming`, awaits `_massive_decision_gate`; a charge → 1 Wound instead of 2. |
| Wounds Training | `dom_wounds` entries (`training_wounds`, +1 each) summed by `_wounds_node_bonus()` at `start_combat()`. |
| Lucidity L1 | Proactive: lower Fervor 1 step, costs the turn, unlimited. Hidden at d4 (`_can_use_lucidity()`). `await _escalate_fervor(_player, -1)`; negative steps skip Burnout check + cap clamp. |
| Lucidity L2 | Reactive interrupt: a positive escalation that would Burnout prompts (`player_burnout_imminent`) to spend 1 charge/combat. If spent, Burnout cancelled but **Fervor stays at cap** (precarious truce). `InterruptHandler` (`lucidity_prevent_burnout`, `on_burnout`, priority 10); via `_try_prevent_burnout()` inside `_escalate_fervor()`, NOT `_resolve_interrupt`. |
| Mind Detonation | True spell (L1 tier≥2, prereq Spellcasting L1). Placement = pool=1 Ingenuity scratch vs Stance (Fervor die, no bonuses, gear-independent); applies `mind_detonation_primed` (duration=3; freezes `fervor_at_prime`+`md_level`+`cast_tier`+`cast_pool_bonus`+`cast_keep_bonus`+`cast_flat_bonus`). At Phase 2.1, if primed + `_current_round_player_breaches["stance"]`, `_detonate_mind_bomb` removes the status and explodes vs Resolve via `_resolve_attack` using frozen Fervor + frozen cast values (no escalation; bonuses via `_collect_spell_bonuses`). Legacy statuses without `cast_*` keys fall back to full Tier. Fizzle logged on expiry. L2 (tier≥3, prereq ing_core L3): +1 explosion keep. Simplification: breach tracking is global (any Stance breach triggers all primed bombs). |
| Hex Mastery / Mind Rend | True spell (L1 tier≥3, prereq Spellcasting L1). Mind Rend attacks Resolve via `_cast_mind_rend` (bypasses `_resolve_attack` to suppress the breach wound). On breach: applies `hex_marked` (L1 duration 3 / "2 turns", L2 duration 7 / "4 turns"), no wound. On hold: nothing. While `hex_marked`, `_resolve_attack` adds `wounds_pending += 1` on every player breach (any pool); enemy-on-player never amplified. Own breach not self-amplified (mark applied after the hook). Fervor escalates normally. Combo with Mind Detonation: Stance breach +1 and explosion breach +1 from the same mark. |
| Echoing Mind / Mind Lash | True spell (L1 tier≥3, prereq Spellcasting L1). Mind Lash `tags=["arcane","echo"]`. After cast, applies `echoing_spell` **on the player**. Each `end_of_round`, `_resolve_spell_echo` routes through `_resolve_attack(true,…)` with frozen `fervor_at_cast`, frozen `cast_tier`/`cast_pool_bonus`/`cast_flat_bonus`, and decremented `current_kept_dice` (starts cast_kept−1 where cast_kept includes `cast_mod.keep_bonus`; −1 per echo; removed when next < 1). Focus keep baked into initial `current_kept_dice` — no separate `cast_keep_bonus` key in echo status. No escalation. `echo_flat = current_kept` at L2, 0 at L1. New cast overwrites the existing echo (latest wins — simplification). Echo is a full player attack: Hex + Mind Detonation interactions live. Cast with cast_kept=1 → no echo. |
| Chrono-Tinkering / Time Lock | True spell (L1 tier≥3, prereq Spellcasting L1). Time Lock attacks Resolve via `_cast_time_lock` (bypasses `_resolve_attack` to suppress the breach wound). On Resolve breach: applies `time_locked` CombatStatus on the enemy in ARMED phase (payload: `phase`, `locked_pool`, `skip_resets`, `frozen_value` all in `stat_overrides`). On Resolve hold: nothing. The armed status waits for the next player attack on this enemy routed through `_resolve_attack` (any pool, including echoes and MD explosions). At that attack's end, the status transitions ARMED→FROZEN: `locked_pool` = the attacked pool, `skip_resets` = node level (1 for L1, 2 for L2), `frozen_value` = post-attack guard value (0 on breach, remaining on hold). While frozen, `_end_of_round` skips `reset_guard()` for that pool and restores `frozen_value` instead (marking the pool as rolled, so it won't re-roll). Each `_end_of_round` decrements `skip_resets`; when it reaches 0 the status is removed and the pool resets normally. L2 (tier≥3, prereq chrono_tinkering L1): freeze lasts 2 rounds. The frozen value tracks the player's progress: if the player presses the frozen guard lower in a frozen round, that new value carries forward. Fizzle log in `_tick_statuses` for an armed status that expires without triggering. New cast overwrites existing status (`_add_status` deduplication). Group C is now COMPLETE. |

Next unimplemented items: Group D — Ingenuity Branch: Late Game and Hybrids.
