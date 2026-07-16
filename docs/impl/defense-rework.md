# Defense & Gating Rework — Implementation Plan

Status: **PROPOSED — awaiting approval.** No code or rules changes made yet.
Design discussed 2026-07-16. Companion rules edits listed in §8 require explicit approval
(`docs/game-rules/` is design source of truth).

## 1. Problems being solved

1. **Defense keep nodes feel like a tax** — `dom_stamina` / `neg_stance` / `ing_resolve`
   are pure passive keep upgrades with no identity, and every build feels forced to buy
   all three because enemies can pressure any pool.
2. **Dominion grants too many HP** — base Max Wounds 3 + `dom_wounds` (+3) doubles HP,
   on top of Meat for the Grinder and stamina keep. Dominion out-tanks Negation,
   which is supposed to be the defense branch.
3. **`required_tier` gates are abstract** — replace node-level Tier requirements with
   "spend N points in branch X" gates (supports future hybrids: N in one branch + M in another).

## 2. Agreed design decisions

- Defense nodes stay one per branch, 3 levels, keep grade = purchased level (1/2/3).
  L1 remains the free auto-granted baseline (`_grant_default_keep_nodes()`), **no riders on L1**.
- Riders live on L2/L3 and are branch-flavored:
  - **Dominion** = wounds (passive +1 Max Wounds).
  - **Ingenuity** = Magic Shield (active charges, break-only, works on every pool).
  - **Negation** = raw guard numbers; cross-pool crown only at L3.
- Rider scope rule: wound-layer riders global (MG), charge actives global-by-trigger (Shield),
  passive number riders home-pool until L3 (Negation).
- `dom_wounds` node **deleted**; net HP bonus drops from +3 to +1 (fold into `dom_stamina` L2).
- Meat for the Grinder stays a **standalone** node, re-gated on `dom_stamina` L2.
- Magic Shield implemented now inside Ingenuity (rider on `ing_resolve`); future neg/ing
  hybrid placement is a data-only re-gate via branch-spend requirements.
- Tier itself **survives** — it is pool size in every roll and auto-advances via the
  slot budget (5 combat + 2 flavor per tier). Only its use as a node prerequisite is replaced.
- Slot budget per tier is unchanged and keeps global pacing.

## 3. Node table (after)

Keep grade for defense nodes = purchased node level (see §4 schema note).

| Node | Level | Cost | Gate (branch spend) | Prereqs | Effect |
|---|---|---|---|---|---|
| `dom_stamina` | L1 | free | — | auto-grant | Stamina keep 1 |
| | L2 | 2 | 2 in Dominion | dom_core L1 | Stamina keep 2 + **+1 Max Wounds** |
| | L3 | 2 | 5 in Dominion | dom_core L2 | Stamina keep 3 |
| `ing_resolve` | L1 | free | — | auto-grant | Resolve keep 1 |
| | L2 | 2 | 2 in Ingenuity | ing_core L1 | Resolve keep 2 + **Magic Shield, 1 charge** |
| | L3 | 2 | 5 in Ingenuity | ing_core L2 | Resolve keep 3 + **Magic Shield, 2 charges** |
| `neg_stance` | L1 | free | — | auto-grant | Stance keep 1 |
| | L2 | 1 | 2 in Negation | neg_core L1 | Stance keep 2 + **+2 flat on Stance guard** |
| | L3 | 2 | 5 in Negation | neg_core L2 | Stance keep 3 + **+1 Negation-size die on EVERY defense pool roll** |
| `dom_meat_grinder` | L1 | 1 | 4 in Dominion | **dom_stamina L2** (was dom_wounds L2) | degrade 1 Massive Wound/combat |
| | L2 | 1 | 7 in Dominion | — | 2 charges |
| `dom_wounds` | — | — | — | — | **DELETED** |

Costs and spend thresholds are first-pass numbers — tuning knobs, see §10.

**Magic Shield spec** (player only, like Lucidity):
- Trigger: any defense pool of the player **would break**
  (`attack_total >= current_guard`, checked after the pool's roll/reuse, before breach commits).
- Prompt (never auto-fire): show incoming total, current guard, dice about to roll.
  Player spends a charge → roll **N dice of Ingenuity size** (N = `ing_resolve` purchased level,
  die = `_stat_size(state, "ingenuity")` so status overrides like Purple Hollow apply),
  add total to that pool's guard, re-check breach. Shield can fail — tension intended.
- One prompt per attack even with 2 charges (no double-shield on the same hit).
- Guard-layer only: direct-wound effects (Mind Detonation payload, etc.) bypass it.
  Echo / Time Lock pressure that goes through `_resolve_attack` **can** be shielded.
- If the shield saves the guard: no breach → no massive check → MG never prompted.
  If declined/failed: normal breach path, MG can still fire on massive. Order is
  Shield (pre-breach) → MG (post-breach, massive only) — the two never contend.

**Negation L3 mechanics**: defense roll passes 1 aspect die of Negation size into
`RollEngine.resolve()` (optional `aspect_stat_size`/`aspect_count` args already exist).
Extra pool dice help via keep selection even without a keep bump — deliberate,
no cross-pool keep.

## 4. Schema changes

### 4a. Keep grade from node level (frees `effect_type` for riders)

`NodeLevelData` has a single `effect_type` per level, but fused levels need
keep + rider. Chosen approach (**B**): defense keep is *implicit* —

```
_defense_keep_grade(state, pool) =
    maxi(_training_keep_grade(state), purchased_level(DEFENSE_NODE_FOR_POOL[pool]))
```

with `DEFENSE_NODE_FOR_POOL = {stance: neg_stance, resolve: ing_resolve, stamina: dom_stamina}`
in `CombatMath`. The `stance_keep`/`resolve_keep`/`stamina_keep` effect types are retired,
and each level's `effect_type` now carries the rider:

- `dom_stamina` L2 → `effect_type="training_wounds"`, `effect_value=1`
  (existing `CombatMath.node_effect_sum("training_wounds")` picks it up — zero new code for HP).
- `ing_resolve` L2/L3 → `effect_type="magic_shield"`, `uses_per_combat=1/2`
  (charges resolved like `meat_grinder_charges`).
- `neg_stance` L2 → `effect_type="stance_flat"`, `effect_value=2`.
- `neg_stance` L3 → `effect_type="guard_aspect_all"`, `effect_value=1`.

Alternative (A, rejected for now): add `effects: Array` of sub-resources to NodeLevelData —
more general, but a bigger migration and a new class_name; revisit if a future node
needs 2+ riders on one level.

### 4b. Branch-spend gating

- `NodeData` gains `@export var branch: String = ""` — `"dominion" | "negation" | "ingenuity" | ""`.
  Assignment: `dom_*`/`neg_*`/`ing_*` by prefix; discipline abilities
  (`hex_mastery`, `chrono_tinkering`, `echoing_mind`, `mind_detonation`) and
  `spellcasting`/`minor_studies`/`lucidity` → `"ingenuity"`; Flavor nodes → `""` (count nowhere).
- `NodeLevelData` gains `@export var branch_spend: Dictionary = {}` — e.g. `{"dominion": 5}`;
  hybrid gates are just `{"negation": 3, "ingenuity": 3}`. Empty = ungated.
- `PlayerProgression.get_branch_spent(branch) -> int` — **derived** by summing `ld.cost`
  of purchased levels whose node `branch` matches. No new save field, no migration;
  recomputed from `node_levels`.
- `can_upgrade()`: the `_tier < ld.required_tier` check is replaced by the branch_spend
  check. Free Buy debug mode bypasses it like it bypasses everything else.
- `required_tier` stays on the schema as a deprecated shim (ignored at runtime),
  values zeroed out during .tres migration — same pattern as EquipmentData flat fields.
- Threshold mapping for all other nodes currently using `required_tier`
  (first pass, per node's own branch): T2 → spend 3, T3 → spend 6, T4 (`dom_earthshatter`) → spend 9.

## 5. Combat changes (CombatManager + combat/)

- **New interrupt trigger `"on_guard_break"`** — third dispatch path beside
  `on_massive_wound` (wounds-shaped) and `on_burnout` (bool-shaped); this one is guard-shaped.
  - Registered at `start_combat()` when player has `ing_resolve` L2+ — mirrors the MG
    registration block (handler_id `"magic_shield"`, charges from node, priority 10).
  - Fire point in `_resolve_attack()`: after guard value determined (fresh roll or reuse),
    if `defender_is_player and attack_total >= current_guard` and a charged handler exists:
    emit `player_shield_opportunity(charges, incoming, guard, dice_count, die_size)`,
    `await _shield_decision_gate` (same signal/await contract as `_massive_decision_gate`).
    On accept: consume charge, roll, `set_guard_val()`, emit `guard_changed` + log, re-check breach.
  - Async spine touch is **additive only** — read `docs/impl/combat-invariants.md` first.
- **Negation L3**: defense roll site (`_resolve_attack` guard block) passes
  `aspect_stat_size = _stat_size(defender, "negation")`, `aspect_count = 1` when defender
  has the node. Verify `RollEngine.resolve()` arg order at implementation time.
- **Negation L2 flat**: added to `defend_mod.flat_bonus` for stance-pool rolls only.
- **HP fold**: `training_wounds` sum drops automatically when `dom_wounds` is deleted
  and `dom_stamina` L2 carries the effect. Check save-load skips unknown node_ids
  (old saves reference `dom_wounds`).
- `_defense_keep_grade` moves to node-level lookup (§4a). Enemy path unchanged
  (training grade stays the floor).

## 6. Progression / UI changes

- `PlayerProgression.can_upgrade()` + `get_branch_spent()` (§4b).
- **NodeDetailPanel**: requirement line shows "Spend N in <Branch> (have M)" instead of "Tier N".
- **ConstellationScene**: lock state driven by same check; no layout change.
- **BattleScene/RoundHUD**: shield prompt widget — mirror the existing
  `player_massive_incoming` prompt flow (buttons: Shield / Take it). Show dice preview
  ("Shield: 2d8"). Wire disconnect in `_teardown_signals`.
- **Debug/testability (rule 2b)**: Training Room with `training_dummy_attacks` ON +
  DebugProgressionControl Free Buy exercises the shield prompt end-to-end interactively.
  Branch-spend gating exercised via existing constellation debug (Free Buy toggles gate off,
  normal mode shows lock text). No new debug widget needed — log-only additions documented here.

## 7. Tests

- **Update**: `tests/unit/player_progression/test_player_progression.gd` (tier-gate tests →
  branch-spend tests); any combat test referencing `dom_wounds` or `*_keep` effect types.
- **New unit**: keep-from-level math (training floor vs node level); shield charge resolution;
  `get_branch_spent()` derivation; `can_upgrade()` gating matrix incl. hybrid dict;
  negation flat/aspect-die application (seeded `RollEngine`).
- **New integration**: shield prompt flow — seeded roll forces would-break, accept/decline paths,
  charge consumption, no-double-prompt on same attack; constellation lock text.
- All deterministic: `seed(N)` before every `RollEngine` call.

## 8. Rules-doc edits (need explicit approval, applied only after clean validation)

- `docs/game-rules/core/defense-and-guard.md`: Magic Shield section (break-only trigger,
  guard-layer only), Negation cross-pool die at L3.
- Constellation/progression rules page(s): fused node table, branch-spend gates replace
  Tier gates on nodes (Tier keeps its roll/pool role), `dom_wounds` removal, MG re-gate.
- `docs/game-rules/summary.md`: rules→code map rows for the above.
- `CLAUDE.md`: fragile-areas additions (keep-from-level lookup; `required_tier` deprecated shim;
  shield = third interrupt dispatch path, guard-shaped). `/refresh-index` after schema fields land.

## 9. Phases (compact between phases)

1. **Gating** — schema fields (`branch`, `branch_spend`), `get_branch_spent`, `can_upgrade`,
   .tres migration (all nodes), NodeDetailPanel/lock UI, progression tests. Validate.
2. **Node fusion** — keep-from-level in `CombatMath`, retire `*_keep` effect types,
   `dom_wounds` delete + HP fold + MG re-gate, Negation L2/L3 riders in defense roll,
   combat tests. Validate.
3. **Magic Shield** — `on_guard_break` trigger + registration + `_resolve_attack` fire point,
   prompt UI in BattleScene/RoundHUD, integration tests. Validate.
4. **Docs** — §8 edits + `/refresh-index`, then `/ship`.

## 10. Open questions / tuning knobs

1. Spend thresholds (2/5 on defense lines, 3/6/9 replacing T2/T3/T4) — confirm or tune.
2. Negation L2 flat value: +2 proposed.
3. Defense L2/L3 costs: proposed 2 (rich packages; neg L2 kept at 1 since flat is small). OK?
4. Shield prompt: confirmed one prompt per attack (no chaining 2 charges on one hit)?
5. `dom_stamina` L3 has no rider (keep 3 alone) — acceptable, since MG standalone is the
   dominion active. Alternative: fold MG L1 charge here and make MG node L2-only.
