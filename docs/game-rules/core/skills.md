# Skills

Skills are discrete actions a character may perform during combat or interaction.

Some skills are universally available. Others are **weapon-expressed actions** — they require a specific weapon or tool to be equipped before they can be used. Skills are the primary way equipment tags interact with the shared resolution engine.

## Skill Structure

Every skill has:
- **Name** — canonical label used in node descriptions, item text, and UI.
- **Prerequisite** (optional) — a tag that must be present on an **equipped** item for the skill to be available. If no prerequisite is listed, the skill is universally available.
- **Effect** — what the skill does, expressed using the shared engine: Build Pool → Roll → Keep → Flat → Outcome.
- **Synergy** (optional) — one or more conditions that grant a bonus when met. Each condition names its source (equipped tag or unlocked node), its grade (I or II), and its bonus (see [Effect Taxonomy](../reference/effect-taxonomy.md)).

## Prerequisites

A prerequisite is stated as: `[Tag] equipped`

Examples:
- `[Sharp] equipped` — requires any item tagged `[Sharp]` in an equipped slot.
- `[Flame] equipped` — requires any item tagged `[Flame]` in an equipped slot.

If the prerequisite is not met, the skill is unavailable regardless of the character's training or nodes.

Prerequisites may require a node instead of an item tag:
- `Unarmed Combat (Unlock) node` — requires the node to be unlocked.

## Synergy

Synergy is a conditional bonus applied on top of the base skill effect when a matching condition is present. The condition and bonus are stated in the skill description.

Synergy sources:
- An **equipped** item with a specific tag.
- An **unlocked node** of a specific type or tier.

Current synergy bonuses are **flat only** (applied after Keep). The grade and value are stated per skill:
- **Synergy I** → +1 flat
- **Synergy II** → +3 flat

See [Effect Taxonomy — Synergy](../reference/effect-taxonomy.md) for the canonical grades.

## Skill Entry Format

```
[Skill Name]
  Prerequisite: [Tag] equipped         (omit line if none)
  Effect: [description using shared engine]
  Synergy I ([condition]): +[value] flat   (omit line if none)
  Synergy II ([condition]): +[value] flat  (omit line if none)
```

Example:
```
Powerful Slash
  Prerequisite: [Sharp] equipped
  Effect: Dominion attack vs Stance
  Synergy I ([Flame] equipped): +1 flat
```

## Bare Hands

Bare hands are always available as implicit equipment.

Default bare-hands properties:
- Full Tier expression — items and bare hands never cap Tier; expressed dice are throttled by training keep grades.
- No tag — bare-hand actions do not carry weapon tags and cannot satisfy tag prerequisites (e.g. bare hands are not a `[MagicFocus]`).
- **Truly empty hands** (both slots empty) count as a casting conduit for **cantrips only**; true spells still require an equipped `[MagicFocus]` item. See [Equipment — Tags](./equipment.md).
- A small set of basic unarmed strikes is available without any node.
- No bonuses of any kind; unarmed-specific skills and bonuses come from the **Unarmed Combat** node. See [Nodes — Unarmed Combat](../progression/nodes.md).
