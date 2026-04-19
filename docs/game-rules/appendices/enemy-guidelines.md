# Enemy Guidelines

Enemies use a simplified actor model compatible with the same combat engine as player characters, but without the same build complexity.

These are authoring guidelines for encounter design, not a full enemy creation subsystem.

## Enemy Actor Model

### Baseline Structure
Every enemy has:
- **Wound capacity** — determines durability (how many Wounds the enemy can take before Defeat).
- **Stat sizes** — the die sizes used by the enemy's actions and defenses.
- **Actions** — a small set of predefined actions, expressed in the same resolution language as player actions.
- **Features / Traits** (optional) — special rules that modify enemy behavior or interact with subsystems.

### Enemy Actions
Enemy actions are authored in the same format as player actions.

Format: `Action Name: [pool] vs [defense pool]`

Examples:
- `Club Attack: 3 Dominion + 3 Flat vs Stance`
- `Fetid Breath: 2 Dominion + 1 Ingenuity vs Stamina`
- `Fireball: 2 Dominion + 1 Ingenuity vs Stance`
- `Charm Person: 1 Dominion + 2 Ingenuity vs Resolve`

Defense pool mapping (use these consistently — never substitute stat names for defense pool names):
- **Stance** — physical / kinetic pressure
- **Stamina** — endurance / environmental / breath pressure
- **Resolve** — mental / social / magical coercion

Do not write "vs Ingenuity" or "vs Dominion" — always use the defense pool name (Stance, Stamina, or Resolve).

## Enemy Tiers

### Minion
- Wound capacity: 1–2
- Few actions (1–2)
- No internal complexity or special features
- Intended to be defeated quickly or in small groups

### Standard
- Wound capacity: 3–4
- A few actions (2–3)
- Limited features; may have one situational trait
- Moderate threat; requires coordinated pressure to defeat

### Elite / Boss
- Wound capacity: 5+
- More actions (3+), stronger features
- May interact with subsystems (e.g., impose Guard pressure, apply status effects, trigger special conditions)
- Possibly a unique subsystem or phase structure

## Notes
- Enemy Wound capacity values above correspond to encounter authoring guidance, not a global formula.
- These tiers loosely align with the wound guideline in [Wounds and Massive Damage](../combat-options/wounds-and-massive-damage.md).
- Enemies do not use the progression / constellation system.
