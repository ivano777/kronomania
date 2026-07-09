# Equipment Requirements Rework — Implementation Plan

**Status: IMPLEMENTED 2026-07-09 — all phases.** Phases 1, 2, 4 first pass (152 tests);
Phase 3 enemy weapon strip completed same day as follow-up (153 tests + headless green).

Approved 2026-07-09. Items lose all cap values; throttle lives exclusively in skill
nodes (keep grades). Skills gain equipment requirements: casting is gated on a
MagicFocus-tagged item (or truly empty hands for cantrips).

## Design decisions (user-confirmed)

- Items = tags + bonuses + special abilities. **No tier caps on items.**
- Attack/defense throttle = existing node keep grades (Martial Arts, Stance/Resolve/
  Stamina training). No new cap mechanic.
- **Cantrip**: requires BOTH hands empty OR a MagicFocus item equipped.
- **True spell**: requires a MagicFocus item equipped (empty hands not enough).
- Focus occupies 1 hand; wizard staff variant = `TwoHanded` + `MagicFocus`.
- Shields keep flat guard bonus (+ future special abilities). Same no-cap rule.
- Same rules for enemies (smoothness); enemy weapon strip done as follow-up (Phase 3).
- Unavailable magic intent shown greyed with reason, not hidden.

## Phase 1 — cap removal

- `resources/ActionModifier.gd`: delete `tier_cap`.
- `resources/EquipmentData.gd`: delete deprecated `potency` (other deprecated flats stay).
- `combat/CombatMath.gd`: `effective_tier(state)` drops the `mod` param; call sites
  updated mechanically (CombatManager, Disciplines, CastSnapshot doc comment).
- Weapon `.tres` ×4: strip `tier_cap` + `potency` lines.
- UI cap strings removed: RoundHUD summaries, CustomTooltip Potency/Tier-cap rows,
  CombatManager defense log `cap_str`, Disciplines `cap_str`, debug widget potency refs.
- Tests: cap-behaviour tests dropped/rewritten (`test_cast_modifier.gd`,
  `test_combat_math.gd`, `test_combat_rules.gd`).

Balance note: Knight (T2, greatsword defend was cap 1) now defends 2d8 keep 2 —
guard roughly doubles. Accepted; retune belongs to the deferred enemy pass.

## Phase 2 — cast gating + focus items

- Tag constant: `"MagicFocus"`.
- Helpers over `PlayerProgression.main_hand/off_hand`: `has_equipped_tag(tag)`,
  `hands_empty()`.
- Gates: `player_magic_available` emits, `_emit_player_intents`,
  `player_chose_spell/_cantrip` guards (defense in depth), RoundHUD
  `_build_tool_entries("magic")` (list foci; bare hands only when truly empty),
  ATK Auto `_try_auto_magic`.
- UI: greyed magic intent + "Requires: Magic Focus" reason.
- Content: `resources/data/weapons/arcane_focus.tres` (1H, MagicFocus, cast flat +1),
  `resources/data/weapons/wizard_staff.tres` (TwoHanded + MagicFocus, cast flat +1
  pool +1, Blunt strike). Sprites via pixel-sprites pipeline. Campfire selector
  exposure. Debug widget support for off-hand focus (testability).
- Tests: gating matrix — sword+empty → no cast; empty+empty → cantrip only;
  sword+focus → all; burnout+focus → cantrip only; auto-cast respects gate.

## Phase 3 — enemy weapon strip (COMPLETE, follow-up pass)

Enemy `.tres` drop `equipped_weapon`; strike/defend live natively in `bare_hands_actions`
(Grunt: Club Smash; Soldier: Sword Slash flat+1; Knight: Greatsword Cleave flat+1; all: Guard).
Mechanically identical. Log flavor via `action_name` (`attacker_weapon_name` strike fallback,
defend-name fallbacks in `_resolve_attack` + `Disciplines.roll_enemy_guard`);
`DebugEquipmentDisplay` summarizes weaponless enemies by action list. Matches
`enemy-guidelines.md` actor model. Still future: multi-attack/trigger schema, Knight retune.

## Phase 4 — docs (after validation)

- `docs/game-rules/core/equipment.md`: delete Potency + Inefficiency; tags/prereqs canonical.
- `docs/game-rules/core/skills.md`: bare-hands section rewrite (no Potency; empty-hands cantrip rule).
- `docs/game-rules/magic/cantrips.md`, `magic/spell-resolution.md`,
  `ingenuity-rework-overview.md` casting-implement section: formula loses tier_cap,
  gains focus requirement.
- `docs/game-rules/summary.md` cantrip/true-spell rows; reference/cheat-sheet.
- `CLAUDE.md`: fragile-table rows (potency shim row removed, cast-modifier rows updated).
- `docs/impl/combat-invariants.md` review (CastSnapshot survives — tier resolved at capture).
- `docs/project-status.md` one-liner.

## Deferred overall

Named strike skills (Piercing Strike…), skill-tree requirement rework, multi-attack/trigger
enemy schema, Knight guard retune (playtest first), remaining deprecated EquipmentData flats,
shield special abilities.
