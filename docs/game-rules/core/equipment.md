# Equipment

Equipment modifies the shared engine instead of replacing it.

## Common Equipment Properties
- **Tags**
- **Bonus**
- **Special Ability**

Items never cap Tier. The throttle on how many rolled dice are expressed is the
character's training (node keep grades) — see [Roll / Keep](./roll-keep.md) and
[Nodes](../progression/nodes.md). An item's power lives in its tags (which skills
it enables), its bonuses, and its special abilities.

## Bonus Types
- **Flat Bonus** -> applied after Keep
- **Extra Dice** -> added to the pool before Keep

Equipment does not normally rewrite stable stat Size.

## Tags

Tags are descriptive labels attached to weapons and tools.
They are the basis for skill prerequisites and Synergy conditions.

Tags are **open-ended** — new tags are defined as items are authored.
Multiple tags may appear on a single item.

Examples: `[Sharp]`, `[Pointed]`, `[Flame]`, `[Heavy]`, `[Blunt]`, `[2H]`, `[MagicFocus]`

- `[2H]` — Two-Handed. Marks weapons designed for two-handed use. Required by skills that gate effects on two-handed weapons (e.g. Titan's Grip, Brutal L3 Heavy Momentum). Occupies both hand slots.
- `[MagicFocus]` — Magic Focus. Marks an item as a casting conduit. **True spells require an equipped `[MagicFocus]` item.** Cantrips require an equipped `[MagicFocus]` item OR truly empty hands (both slots). A focus normally occupies one hand; a two-handed staff carries both `[2H]` and `[MagicFocus]`.

## Skill Prerequisites

A skill may require a specific tag to be present on an **equipped** item before the skill is available.
If the prerequisite is not met, the skill is unavailable regardless of training or nodes.
Prerequisites are stated in the skill description.

Casting is the first implemented prerequisite: spells and cantrips are gated by
`[MagicFocus]` / empty hands as described above.

See [Skills](./skills.md) for the skill entry format and full prerequisite rules.
