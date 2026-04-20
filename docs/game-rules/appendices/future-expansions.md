# Future Expansions

This appendix collects forward-looking design ideas that are valid extensions to the baseline rules but are not active mechanics yet.

Nothing in this file overrides current rules.
These are design spaces to draw from as the game grows.

---

## VT Modifiers from Nodes

Some nodes may grant modifiers that affect the actor's VT check.
The modifier is applied to the action total before comparing to the target's VT.

Examples:
- **Improved Initiative** — +2 to the VT check on any action.
- **Tactical Instinct** — +3 to the VT check when outnumbered.
- **Speed Casting** — +2 to the VT check on spell actions.
- **Duelist Reflexes** — +4 to the VT check when facing a single opponent.

Node-gated VT bonuses are exceptions to baseline behavior.
They apply only when the relevant node has been unlocked.

---

## VT Modifiers from Abilities, Items, and Features

Abilities, items, spells, and features may also carry VT modifiers independently of nodes.

Positive modifiers (acting faster than baseline):
- A **quick jab technique** might grant VT +3.
- A **speed ring** might grant VT +2.

Negative modifiers (acting slower than baseline, usually in exchange for higher output):
- A **slow ritual fireball** might impose VT −20.
- **Heavy armor** might impose a flat VT penalty.
- A **long charge-up attack** might impose VT −10 but deal significantly more damage.

### Slow-but-Powerful Design Space

Some actions may intentionally trade timing for output.
The VT modifier is the mechanical expression of that trade.

> **Ritual Fireball**: Massive destructive output. VT −20.

This pattern always resolves Slow, creating a clear tactical decision: commit to a devastating attack that lands late, or act Fast with a safer option.

---

## Manual Keep Selection

Currently Keep always takes the best dice automatically ("keep the best valid dice", per roll-keep.md).

A possible future extension: the player may choose a **Keep Mode** per action before rolling.

Rough idea:
- **Keep Highest** (default) — auto-select the best `keep_count` dice; current behaviour.
- **Keep Lowest** — auto-select the worst `keep_count` dice; useful for mechanics that reward low rolls (e.g. stealth, self-sacrifice effects).
- **Manual Pick** — after rolling, the player selects exactly which dice to keep from the full pool; most expressive but slowest.

Keep Mode could be a per-action option, a node-gated unlock, or a status effect.
Needs design refinement before adoption — interactions with Desperation, Fervor-tagged dice, and forced-keep rules (real Fervor dice) must be resolved first.

---

## Stacking Desperation

Currently Desperation is a fixed state: when the pool reaches 0 or below, roll 2 dice and keep the worst.

A possible future extension: Desperation scales with the degree of net Disadvantage beyond 0.

Rough idea:
- Pool = 0 → roll 2, keep worst (current rule)
- Pool = −1 → roll 3, keep worst
- Pool = −2 → roll 4, keep worst
- and so on

This would make severe Disadvantage increasingly punishing rather than hitting a flat floor.
Needs further design refinement before adoption — the current flat Desperation rule is intentionally simple.

---

## Synergy Expansions

These extend the baseline Synergy mechanic defined in [Skills](../core/skills.md) and [Effect Taxonomy](../reference/effect-taxonomy.md).

### Synergy as Extra Die
Synergy I or II may grant an extra pool die instead of a flat bonus.
When implemented, the skill description will state the bonus type explicitly (flat or extra die).

### Multi-Source Stacking
A skill's Synergy condition may be met by up to **2 different qualifying sources** (e.g., two separate items each carrying the required tag).
Each matching source contributes its Synergy bonus independently.
The stacking cap and per-source bonus are stated in the skill description.

### Inventory / Container Synergy
A skill may grant Synergy based on items in the player's bag, chest, or carried items — not only equipped slots.
This extends the prerequisite scope beyond the active equipped loadout.

---

## Additional Expansion Areas

Future categories that may draw from VT modifier design:

- **Environmental VT modifiers** — difficult terrain, darkness, or crowd effects changing the encounter's effective timing pressure.
- **Wounded-enemy timing** — enemies that become Slow after reaching a wound threshold.
- **Surprise and ambush** — first-round VT adjustments based on scouting or positioning.
- **VT scaling with Tier** — higher-Tier characters may have passive bonuses that close the gap against high-VT enemies.
