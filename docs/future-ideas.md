# Future Ideas & Design Notes

Unscoped brainstorming. Review when planning each new group.

---

## Visuals

- **Stat-colored spell VFX** — color effects by dice contribution: Dominion=red, Ingenuity=violet, Negation=azure. Mixed-pool spells blend colors. Group 6 art pass.

---

## Spell system

- **Keyword mechanics** — add `keywords: PackedStringArray` to `SpellData`; resolve in `CombatManager._resolve_round_spell()` after damage. Differentiates spells that otherwise share pool+stat.
  - `stun` — target skips next action or suffers pool penalty next round
  - `charm` — force missed action or prevent enemy action
  - `on_fire` — apply On Fire status (see Status Effects)
  - `poison` — apply Poisoned status (wound-over-time)
  - `flat_N` — already partially supported via `SpellData.flat_bonus`
  - Note: weapons and active abilities can carry these keywords too, not only spells.

- **Spell differentiation goal** — no two spells granted by the same node should feel identical. Uniqueness levers: target pool, aspect stat, flat bonus, keywords, status effects applied.

- **Per-spell tier scaling** — add `flat_per_tier: int` to `SpellData` (default 0 = no scaling). Resolved at cast: `effective_flat = flat_bonus + flat_per_tier * tier`. Designer sets per spell (e.g. a void-school spell might use `flat_per_tier=1`, giving +1/+2/+3/+4; a fire spell relies on pool/keep bonuses instead). Avoids a global formula that breaks balance at the edges.

---

## Equipment

- **Weapon crit chance** — `crit_chance: float` on `EquipmentData`; random roll post-resolve triggers +1 Wound or flat bonus. Applied in `CombatManager._resolve_attack()`.

- **One-use magic shield** (pendant equip) — if enemy attack would breach guard, grant +10 to that pool, then the item breaks. Needs runtime item state on `CombatantState` (currently `CombatantData.equipped_weapon` is immutable config).

- **Weapon/item prerequisites** — two gate types on `EquipmentData`:
  - `required_stat: String` + `required_stat_size: int` — stat threshold, checked against `_stat_size()` runtime value (not raw `CombatantData`). Example: a colossal sword requires Dominion ≥ d8.
  - `required_node: NodeData` — node gate. Example: a magic focus requires `has_spellcasting`. Both fields optional; checked at combat init.

- **Item-gated spells** — `required_item_tag: String` on `SpellData`; checked in `player_chose_spell()` against equipped weapon tags. Follows the existing tag-matching pattern from `SpellBonusEffect`. Example: certain arcane spells require a "Wand" tagged item.

---

## Firearms & Dice mechanics

- **Firearms / scaling dice** — dedicated weapon type with its own stat path; die size scales with weapon tier rather than a caster stat. Requires a separate resolution branch in `CombatManager`.

- **Snake eyes** — rolling min on *all* dice triggers a catastrophic failure (weapon jam, self-hit, etc.). Post-roll check in `RollEngine.resolve()` before the keep step.

- **Explosive dice** — rolling max on a die triggers a re-roll-and-add (Savage Worlds style); loops until non-max.
  - Ordering rule: **keep happens after all explosions**, so all exploded dice are eligible for keep (rewards the mechanic).
  - Design note: explosive dice significantly raise expected value and introduce variance spikes — requires isolated playtesting before integration with the full combat loop. The interaction with keep-best is non-obvious; settle the ordering rule in the design doc before any implementation.

---

## Abilities system (direction, Group 6+)

### Architecture — recommended hierarchy

```
AbilityData (base Resource)
  name, description, tags, trigger_condition
  └─ ActiveAbilityData extends AbilityData
       stat, target_pool, flat_bonus, keywords
       └─ SpellData extends ActiveAbilityData
            aspect_stat, aspect_dice, is_cantrip
```

- Passive abilities use `AbilityData` directly — no roll fields needed.
- Active non-caster abilities use `ActiveAbilityData` — stat roll, no fervor.
- Spells remain `SpellData` — adds aspect dice + fervor path (implicit: non-cantrip active → fervor).
- `NodeData` would migrate from `spells: Array[SpellData]` → `effects: Array[AbilityData]` to cover passives and actives in one array.
- `SpellBonusEffect` stays separate — it is a modifier, not an action.
- Godot inspector note: parent `@export` fields appear on all child `.tres` — cosmetic clutter, not a blocker.

### Active abilities (non-caster)

- Examples: Stunning Strike, Powerful Blow.
- Use Dominion or Negation instead of Ingenuity for the roll.
- Support condition/trigger on use: only on Fast round, only after a Massive hit, etc.
- Some abilities require a specific state to activate (see Desperation below).

### Passive abilities

- Bonus effects with conditions. Will merge with the Reaction system when built.
- Trigger types:
  - Event-based: `on_breach`, `on_fast_round`, `on_wound_taken`
  - State-based: `while_burned_out`, `while_wounds_gte_2`

### Desperation / Burnout-gated abilities

- Nodes that require `is_burned_out == true` to activate — makes Burnout double-edged (risk vs. unlock) rather than a pure punishment.
- `required_state: String` on ability; checked at action time.
- These nodes are children of a "Desperation" gate node in the constellation. Desperation itself should be constellation-gated (not freely available) to preserve its identity and strategic weight.

---

## Reaction system

Triggered abilities that fire in response to combat events (enemy attack, guard breach, etc.):

- Counter-damage reaction — a node requiring high Dominion + Negation could fire on being attacked
- Pool boost reaction — spend a resource mid-round to raise a defense pool
- Magic shield — see Equipment above

Implementation notes:
- Needs new signal hooks in `CombatManager` (e.g. `before_guard_resolved`, `on_breach`)
- Node-triggered reactions need a new `effect_type` on `NodeData` + a resolver in `CombatManager`
- Runtime item state slot on `CombatantState` required for breakable equips
- Most complex idea here — tackle after Group 5 game loop is stable

---

## Status effects system

- Runtime `active_statuses: Array` on `CombatantState`; each entry is a `StatusEffect` resource: `effect_name`, `duration_rounds`, `effect_type` (`damage_per_round`, `stat_debuff`, `action_skip`, `pool_penalty`), `value`.
- Resolution pass in `_begin_round()` — tick duration, apply effect, emit signal.
- Sources: spell keywords, weapon tags (e.g. "Venomous"), active ability effects.
- Interactions: fire-tagged spells get a bonus vs `on_fire` targets; poison stacks (add new entry, do not replace existing).
- **Resistance / resistibility:** TBD — needs a dedicated brainstorm session before implementation. Key design question: is status application automatic on keyword hit, or does it require breaching a secondary guard roll? Answer changes the feel significantly.
- UI: status icons on `CombatantHUD` (Group 6 art pass).
