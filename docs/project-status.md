# Project Status

Tracks what is implemented and what remains. Updated after each feature ships.

---

## Implemented

### Core engine
- **RollEngine** (`autoloads/RollEngine.gd`) — stateless dice resolver.
  Build Pool → Roll → Keep → Flat → Outcome. Returns `Dictionary` with `dice`, `kept`, `total`, `pool_size`, `die_size`, `keep_count`, `flat`.
  Includes `flat` post-Keep numeric bonus parameter (already wired, currently passed as 0 everywhere).
  Helpers: `is_fast(total, vt)`, `is_massive(attack, guard, defensive_size)`.
- **CombatantData** (`resources/CombatantData.gd`) — immutable combatant config as a `.tres` Resource.
  Fields: `combatant_name`, `tier`, `dominion_size`, `negation_size`, `keep_grade`, `velocity_threshold`, `max_wounds`.
  Both player and enemy `max_wounds` are configurable; player default = 3, enemy values vary per `.tres` file.
- **CombatManager** (`autoloads/CombatManager.gd`) — 1v1 combat state machine.
  Owns all runtime state via inner class `CombatantState` (fields: `data`, `current_wounds`, `current_guard`, `stance_rolled`, `is_defeated`).
  Round loop: `_begin_round → player_chose_strike → _resolve_round → _resolve_attack × 2 → loop`.
  Defeat is checked after each `_resolve_attack()`; if triggered, second attack and timer are skipped.

### Combat mechanics
- **Roll / Keep** — Tier-based pool, grade-based keep (0→1, 1→2, 2→3).
- **VT / initiative** — only the player's roll is compared to the enemy's static VT; Fast → player first, Slow → enemy first. Enemy timing is implicit in VT — no roll.
- **Active Guard** — Stance is rolled once per round when first pressured (`stance_rolled` flag on `CombatantState`). Subsequent same-round pressure reuses the existing Guard value without re-rolling. Guard resets to 0 and `stance_rolled` resets to `false` at round start.
  *Future: replace the boolean flag with a per-pool data structure tracking `{ guard: int, rolled: bool }` for each of Stance / Resolve / Stamina.*
- **Advantage / Disadvantage** — `net_advantage` parameter on `RollEngine.resolve()`. Positive = extra dice, negative = fewer dice. Net pool ≤ 0 triggers Desperation (roll 2d, keep worst). Applied to player attack only; enemy A/D deferred.
- **Multiple defense pools** — Stance (Negation), Resolve (Ingenuity), Stamina (Dominion) tracked independently per combatant via per-pool guard/rolled state in `CombatantState`. `guard_changed` signal carries pool name. `CombatantHUD` shows all 3 pools. Debug pool selector in `scenes/debug/` lets you target any pool mid-combat.
- **Breach** — `attack_total >= guard`.
- **Massive damage** — `(attack - guard) > defensive_size` → 2 Wounds instead of 1.
- **Wound tracking + Defeat** — `wounds >= max_wounds`.

### Data
- `resources/data/player_default.tres` — Tier 1, d6 off/def, keep grade 0, max wounds 3. (`velocity_threshold` field is present due to shared schema but unused for the player.)
- `resources/data/enemy_grunt.tres` — Tier 1, d6 off / d4 def, keep grade 0, VT 10, max wounds 2.

### UI (prototype-quality)
- **BattleScene** (`scenes/battle/`) — root scene wiring CombatManager signals to HUDs.
- **CombatantHUD** — name, wound slots, guard value per combatant.
- **RoundHUD** — round label, phase label, Strike button, scrollable BBCode combat log.
- **Combatant** — placeholder visual (colored rect + name label).
- **Combat narrative** — BBCode-formatted log with attack rolls, speed check, breach/wound outcomes, and Massive highlights.

### Tooling
- `/ship` — Conventional Commit, pull --rebase, and push in one command.
- `/audit-docs` — deploy the `docs-alignment-auditor` agent to cross-check all docs against the codebase.
- `docs-alignment-auditor` agent (`.claude/agents/docs-alignment-auditor.md`) — reads all docs and code, reports misalignments with severity and proposed fixes.
- Headless validation: `"$GODOT" --headless --path "<project>" --quit-after 5`.
- `CLAUDE.md` — engine setup, Autonomous Feature Loop workflow, architecture, rules summary.

---

## Roadmap

Ordered by dependency. Items within a group can be parallelized.

### Group 1 — Mechanics completions (no new systems)
- [x] **Advantage / Disadvantage** — pool modifier; cancels 1-for-1; net Disadvantage to 0 → Desperation (roll 2, keep worst). Debug UI in `scenes/debug/` (removable at release).
  *Integration point: tied to status effects and equipment traits; does not interact with Fervor dice.*
- [x] **Multiple defense pools** — Resolve (Ingenuity) and Stamina (Dominion) alongside the already-implemented Stance.
  *Deferred: cumulative Disadvantage on 2nd+ different pool per turn; mixed-threat enemy actions.*

### Group 2 — Equipment and effect system
- [ ] **Equipment resource** — Potency cap, flat bonus, tags. Inefficiency rule when used without training.
  *Defines the tag set that Group 2b applies.*
- [ ] **Effect Taxonomy integration** — Forging / Channeling / Warding / Fortitude / Surge / Drain applied from item data.
  *Requires equipment tags to be defined first. See `docs/game-rules/reference/effect-taxonomy.md`.*

### Group 3 — Progression / Constellation
- [ ] **Node resource** — data type for constellation nodes (category, effect, unlock condition).
- [ ] **Constellation scene** — visual skill tree; spend points to unlock nodes.
- [ ] **Tier advancement** — breadth check across Core / Training / Ability / Flavor categories.
- [ ] **Keep grade from Training nodes** — replace hardcoded `keep_grade` in CombatantData.

### Group 4 — Magic system
- [ ] **Fervor subsystem** — real Fervor dice (additive post-keep, cannot be discarded), substitution dice (normal pool, Fervor-tagged), escalation per max roll, cap = current modified Ingenuity.
- [ ] **Burnout state** — triggered after a spell resolves if Fervor would exceed the Ingenuity cap. Blocks true spells; cantrips unaffected. Removed by Long Rest or Recovery Scene.
  *Applied post-resolution, not mid-cast. Does not block the spell that caused it.*
- [ ] **Cantrips** — Minor Studies unlock, known cantrip count formula, no Fervor cost, available during Burnout.
- [ ] **True spells** — Spellcasting node required; full spell resolution order (see cheat sheet).

### Group 5 — Full game loop
- [ ] **Hub scene** — safe zone; access to character sheet, rest, loadout.
- [ ] **Character sheet UI** — stats, wounds, constellation summary.
- [ ] **Rest / recovery** — Long Rest (remove Burnout + reset Fervor), Recovery Scene (remove Burnout only).
- [ ] **Enemy roster** — author 3+ enemy types per `docs/game-rules/appendices/enemy-guidelines.md`; vary VT, stat sizes, and action sets.
- [ ] **Reward loop** — XP gain, item drops, point allocation after duel.
- [ ] **Dungeon / encounter flow** — sequence of duels, progression between them.

### Group 6 — Polish
- [ ] **Art pass** — replace placeholder colored rects with actual sprites / animations.
- [ ] **Sound** — attack, guard break, wound, defeat SFX.
- [ ] **Save / load** — persist character state between sessions.
