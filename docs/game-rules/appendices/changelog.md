# Changelog

## Equip-Requirements Rework (2026-07)

- **Items never cap Tier** — `ActionModifier.tier_cap` and `EquipmentData.potency`
  removed; the only throttle on expressed dice is node keep grades (training).
- **Casting is equipment-gated**: cantrips need truly empty hands OR an equipped
  `[MagicFocus]` item; true spells always need a `[MagicFocus]` item.
- New conduit items: Arcane Focus (1H, Cast flat +1), Wizard Staff (2H, Cast flat +1 / pool +1).
- "Inefficiency" (untrained-equipment Potency penalty) removed with the Potency concept.
- Skill tag-prerequisite system (skills.md) unchanged and now the single gating model;
  named weapon-gated strike skills remain future work.

## Current Rewrite

### Standardized
- Tier as the main pool progression term
- stable dice scale as d4 / d6 / d8 / d10
- massive-result language with formal definition: (total - Guard) > defensive Size
- default stat assignments: Dominion (offense), Negation (defense), Ingenuity (mental/control)

### Clarified
- three defense pools: Stance / Resolve / Stamina
- one roll per defense pool per turn by default
- rolled pool absorbs pressure until depleted or turn ends; does not re-roll
- Guard resets at start of each new turn
- additional different pool in same turn: cumulative Disadvantage
- Burnout triggers after spell resolution
- Fervor cap = current modified Ingenuity (not stable Ingenuity)
- Fervor is clamped at cap; clamping is not recovery and does not remove Burnout
- cantrips remain available during Burnout
- Recovery Scene removes Burnout without lowering Fervor
- Minor Studies progression:
  - Unlock / Grade 0 = access, +0
  - Grade 1 = +1
  - Grade 2 = +2
- Cantrip knowledge table extended to include d2 (1) and d12 (6)
- Spellcasting node structure: Minor Studies for cantrips; Spellcasting node for true spells
- Two categories of Fervor-tagged dice: real Fervor dice (additive, post-keep) vs substitution dice (normal pool, Fervor-tagged)
- Escalation applies to all Fervor-tagged dice at maximum, even if discarded
- Advantage/Disadvantage cancel 1-for-1; net Disadvantage to 0 = Desperation
- Desperation applies to normal pool only; real Fervor dice unaffected
- Player character Max Wounds = 3; Defeat when Wounds >= Max Wounds
- Safe Venting remains node-based, not baseline

## Ingenuity Rework (Groups B/C, Phase D-pre)

_Implemented after the Current Rewrite above. Supersedes the older Minor Studies grade model and defers some clarified-but-unimplemented rules. Full design: [Ingenuity Branch Rework](../ingenuity-rework-overview.md)._

### Added
- **Spellcasting L1–L3** — Arcane Missile (vs Stance) + Arcane Mark (vs Resolve); progressive Keep 2/3 on all arcane spells; Arcane Mark breach debuffs (Stance flat −2 at L2, keep −1 "Frattura Totale" at L3).
- **Lucidity L1–L2** — L1 proactive Fervor cooling (lower 1 step, costs the turn, unlimited); L2 reactive anti-Burnout interrupt (1 charge/combat, Fervor stays at cap).
- **Disciplines** — Mind Detonation (prime vs Stance → detonate vs Resolve), Hex Mastery / Mind Rend (mark on Resolve breach amplifies later wounds), Echoing Mind / Mind Lash (spell echoes each end-of-round, decaying with kept dice), Chrono-Tinkering / Time Lock (freeze an enemy guard so it does not renew).
- **Casting implement system (Phase D-pre)** — spells/cantrips select a **casting tool** each round; pool routes through the tool's `"cast"` modifier `tier_cap` (mundane weapons cap at 1 die; bare hands = full Tier).

### Superseded / deferred (relative to older entries above)
- **Cumulative Disadvantage on 2nd+ defense pools** — clarified as a rule but **deferred**; not implemented (tracked in `docs/project-status.md` → Future).
- **Minor Studies grade tiers (0/1/2)** — deferred; `minor_studies` currently grants base cantrips (Arcane Bolt, Arcane Touch) with no grade progression.
- **Spell school nodes** — removed in Phase B2; ideas archived in `appendices/legacy-archive.md`.
