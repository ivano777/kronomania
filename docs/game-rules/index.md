# Game Rules

This documentation set defines the current high-level rules model for the game.

The files are written as an **implementation-facing rules reference**:
- focused on systems and behavior rather than table procedure;
- suitable as a design source for a game engine;
- modular, so each subsystem can evolve independently.

This is not a low-level technical specification.
It is a structured gameplay guideline that can be translated into code, tools, content data, or balance sheets.

## Recommended Reading Order

1. [Glossary](./glossary.md)
@./glossary.md
2. [Design Principles](./design-principles.md)
@./design-principles.md
3. [Core Rules Overview](./core/overview.md)
@./core/overview.md
4. [Progression Overview](./progression/overview.md)
@./progression/overview.md
5. [Magic Overview](./magic/overview.md)
@./magic/overview.md
6. [Combat Options Overview](./combat-options/overview.md)
@./combat-options/overview.md
7. [Reference / Cheat Sheet](./reference/cheat-sheet.md)
@./reference/cheat-sheet.md

## Sections

### Core
- [Overview](./core/overview.md)
@./core/overview.md
- [Stats and Dice](./core/stats-and-dice.md)
@./core/stats-and-dice.md
- [Roll / Keep](./core/roll-keep.md)
@./core/roll-keep.md
- [Modifiers](./core/modifiers.md)
@./core/modifiers.md
- [Equipment](./core/equipment.md)
@./core/equipment.md
- [Combat](./core/combat.md)
@./core/combat.md
- [Defense and Guard](./core/defense-and-guard.md)
@./core/defense-and-guard.md
- [Initiative and Speed](./core/initiative-and-speed.md)
@./core/initiative-and-speed.md

### Progression
- [Overview](./progression/overview.md)
@./progression/overview.md
- [Constellation](./progression/constellation.md)
@./progression/constellation.md
- [Tiers](./progression/tiers.md)
@./progression/tiers.md
- [Categories](./progression/categories.md)
@./progression/categories.md
- [Nodes](./progression/nodes.md)
@./progression/nodes.md

### Magic
- [Overview](./magic/overview.md)
@./magic/overview.md
- [Fervor](./magic/fervor.md)
@./magic/fervor.md
- [Burnout](./magic/burnout.md)
@./magic/burnout.md
- [Recovery](./magic/recovery.md)
@./magic/recovery.md
- [Spell Resolution](./magic/spell-resolution.md)
@./magic/spell-resolution.md
- [Cantrips](./magic/cantrips.md)
@./magic/cantrips.md

### Combat Options
- [Overview](./combat-options/overview.md)
@./combat-options/overview.md
- [Physical Attacks](./combat-options/physical-attacks.md)
@./combat-options/physical-attacks.md
- [Magical Attacks](./combat-options/magical-attacks.md)
@./combat-options/magical-attacks.md
- [Soft CC](./combat-options/soft-cc.md)
@./combat-options/soft-cc.md
- [Wounds and Massive Damage](./combat-options/wounds-and-massive-damage.md)
@./combat-options/wounds-and-massive-damage.md

### Reference
- [Cheat Sheet](./reference/cheat-sheet.md)
@./reference/cheat-sheet.md
- [Effect Taxonomy](./reference/effect-taxonomy.md)
@./reference/effect-taxonomy.md
- [Status Effects](./reference/status-effects.md)
@./reference/status-effects.md
- [Examples](./reference/examples.md)
@./reference/examples.md
- [FAQ](./reference/faq.md)
@./reference/faq.md

### Appendices
- [Enemy Guidelines](./appendices/enemy-guidelines.md)
@./appendices/enemy-guidelines.md
- [Future Expansions](./appendices/future-expansions.md)
@./appendices/future-expansions.md
- [Changelog](./appendices/changelog.md)
@./appendices/changelog.md
- [Rewrite Notes](./appendices/rewrite-notes.md)
@./appendices/rewrite-notes.md
- [Legacy Archive](./appendices/legacy-archive.md)
@./appendices/legacy-archive.md

## Current Design Decisions

- **Tier** is the main term for base pool growth.
- Stable dice progression is **d4 / d6 / d8 / d10**.
- **d2** and **d12** are exceptional or temporary states.
- The system uses one shared roll / keep engine for physical and magical actions.
- Defense uses three pool types: **Stance**, **Resolve**, and **Stamina**.
- Default stat assignments: **Dominion** (offense), **Negation** (defense), **Ingenuity** (mental / control).
- True spells use **Fervor**. The Fervor cap is based on **current modified Ingenuity**.
- Two categories of Fervor-tagged dice: real Fervor dice (additive, post-keep) and substitution dice (normal pool, Fervor-tagged).
- Cantrips do not use Fervor and remain available during Burnout.
- Player character **Max Wounds = 3** by default; Defeat when Wounds >= Max Wounds.
- **VT is a static enemy property.** The player has no authored VT. Both the player's and the enemy's action totals are compared against the enemy's VT to determine Fast / Slow.
