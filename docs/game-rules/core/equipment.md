# Equipment

Equipment modifies the shared engine instead of replacing it.

## Common Equipment Properties
- **Potency**
- **Bonus**
- **Special Ability**

## Potency
Potency caps how much of the user's Tier may be expressed through that item.

## Bonus Types
- **Flat Bonus** -> applied after Keep
- **Extra Dice** -> added to the pool before Keep

## Inefficiency
Using relevant equipment without the required training causes **Inefficiency**.

Default inefficiency:
- Potency becomes 1
- Flat bonus becomes 0
- special abilities are ignored

Equipment does not normally rewrite stable stat Size.

## Tags

Tags are descriptive labels attached to weapons and tools.
They are the basis for skill prerequisites and Synergy conditions.

Tags are **open-ended** — new tags are defined as items are authored.
Multiple tags may appear on a single item.

Examples: `[Sharp]`, `[Pointed]`, `[Flame]`, `[Heavy]`, `[Blunt]`, `[2H]`

- `[2H]` — Two-Handed. Marks weapons designed for two-handed use. Required by skills that gate effects on two-handed weapons (e.g. Titan's Grip, Brutal L3 Heavy Momentum).

## Skill Prerequisites

A skill may require a specific tag to be present on an **equipped** item before the skill is available.
If the prerequisite is not met, the skill is unavailable regardless of training or nodes.
Prerequisites are stated in the skill description.

See [Skills](./skills.md) for the skill entry format and full prerequisite rules.
