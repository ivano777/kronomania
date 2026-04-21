# Future Ideas & Design Notes

Unscoped brainstorming. Review when planning each new group.

---

## Visuals

- **Stat-colored spell VFX** — color effects by dice contribution: Dominion=red, Ingenuity=violet, Negation=azure. Mixed-pool spells blend colors. Group 6 art pass.

---

## Spell system

- **Keyword mechanics** — add `keywords: PackedStringArray` to `SpellData`; resolve in `CombatManager._resolve_round_spell()` after damage. Differentiates spells that otherwise share pool+stat.
  - `stun` — target skips next action or suffers pool penalty next round
  - `debuff` — reduce enemy stat size or impose Disadvantage
  - `buff` — boost player pool/keep for next roll, or restore a wound
  - `flat_N` — already partially supported via `SpellData.flat_bonus`
  - Status effects need a runtime container on `CombatantState`

---

## Equipment

- **Weapon crit chance** — `crit_chance: float` on `EquipmentData`; random roll post-resolve triggers +1 Wound or flat bonus. Applied in `CombatManager._resolve_attack()`.
- **One-use magic shield** (pendant equip) — if enemy attack would breach guard, grant +10 to that pool, then the item breaks. Needs runtime item state on `CombatantState` (currently `CombatantData.equipped_weapon` is immutable config).

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
