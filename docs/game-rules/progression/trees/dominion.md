# Dominion Path — The Meat Tank

The Dominion path specialises in raw offensive force, melee mastery, and physical endurance. It is the primary driver for close-quarters combat and max-wounds growth.

**Total level-ups available: 24 across 11 nodes.**
The tier budget (5 Combat slots × 4 Tiers = 20 total) means players will choose 20 out of 24 possible level-ups. Not every node can be maxed — meaningful sacrifice is intended.

---

## Prerequisite Tree

```
Core Dominion (L1 / L2 / L3)
    ├── Wounds (L1 / L2 / L3)
    │     [L1 req: Core Dominion L1]
    │     [L2 req: Wounds L1 + Core Dominion L2]
    │     [L3 req: Wounds L2 + Core Dominion L3]
    │     └── Meat for the Grinder (L1 / L2)  [req: Wounds L2]
    │
    └── Martial Arts (L1 / L2)  [req: Core Dominion L2]
            ├── Melee (L1 / L2)  [req: Martial Arts L1]
            │     ├── Dual Wield (L1 / L2)    [req: Melee L1]
            │     ├── Titan's Grip (L1 / L2)  [req: Melee L1]
            │     │     └── Brutal (L1 / L2 / L3)  [req: Titan's Grip L1]
            │     │           └── Earthshatter (L1)  [req: Brutal L3]
            │     └── Disarm (L1 / L2)  [req: Melee L1; L2 synergy: Melee maxed]
            └── Ranged (L1 / L2)  [req: Martial Arts L1]
```

---

## Node Reference

### Core Dominion Size
| | |
|---|---|
| **Category** | Core |
| **Max Level** | 3 |
| **Prerequisites** | — |

| Level | Name | Effect |
|---|---|---|
| L1 | Dominion I | Dominion die size: d4 → d6 |
| L2 | Dominion II | Dominion die size: d6 → d8 |
| L3 | Dominion III | Dominion die size: d8 → d10 |

> The base Dominion stat is **d4**. All three levels must be purchased to reach the d10 cap.

---

### Wounds
| | |
|---|---|
| **Category** | Training |
| **Max Level** | 3 |
| **Prerequisites** | L1: Core Dominion L1 · L2: Wounds L1 + Core Dominion L2 · L3: Wounds L2 + Core Dominion L3 |

| Level | Effect |
|---|---|
| L1 | Max Wounds +1 |
| L2 | Max Wounds +1 (cumulative: +2 total) |
| L3 | Max Wounds +1 (cumulative: +3 total) |

---

### Martial Arts
| | |
|---|---|
| **Category** | Training |
| **Max Level** | 2 |
| **Prerequisites** | Core Dominion L2 |

| Level | Effect |
|---|---|
| L1 | Keep 2 on all physical attacks |
| L2 | Keep 3 on all physical attacks |

---

### Melee
| | |
|---|---|
| **Category** | Ability |
| **Max Level** | 2 |
| **Prerequisites** | Martial Arts L1 |

| Level | Name | Effect |
|---|---|---|
| L1 | Melee Fundamentals | Permanent **Forging I** on any melee attack (+1 Flat to the attack total). |
| L2 | Space Domination | If your melee attack successfully damages an enemy (breaks Guard), gain **Advantage** on your next Stamina defense roll this combat. |

---

### Ranged
| | |
|---|---|
| **Category** | Ability |
| **Max Level** | 2 |
| **Prerequisites** | Martial Arts L1 |

| Level | Effect |
|---|---|
| L1 | General ranged efficiency (heavy bows / thrown weapons). *Mechanics: TBD — Ranged design session.* |
| L2 | *Mechanics: TBD.* |

> Ranged is a **parallel branch** off Martial Arts. It does not require Melee.

---

### Dual Wield
| | |
|---|---|
| **Category** | Ability |
| **Max Level** | 2 |
| **Prerequisites** | Melee L1 |

| Level | Effect |
|---|---|
| L1 | Proficiency with two weapons. *Mechanics: TBD — Dual Wield design session.* |
| L2 | *Mechanics: TBD.* |

---

### Titan's Grip
| | |
|---|---|
| **Category** | Ability |
| **Max Level** | 2 |
| **Prerequisites** | Melee L1 |

| Level | Name | Effect |
|---|---|---|
| L1 | Two-Handed Mastery | **Forging I** on attacks made with a 2-handed weapon (+1 Flat). Stacks with other Forging sources. |
| L2 | Iron Grip | You ignore all disarm effects. |

---

### Disarm
| | |
|---|---|
| **Category** | Ability |
| **Max Level** | 2 |
| **Prerequisites** | Melee L1 |

| Level | Effect |
|---|---|
| L1 | A successful Disarm action (attack beats Guard) forces the enemy to drop their weapon. |
| L2 | **Synergy I** — if Melee is at max level (L2), a successful Disarm additionally grants Advantage on your next attack. |

---

### Brutal
| | |
|---|---|
| **Category** | Ability |
| **Max Level** | 3 |
| **Prerequisites** | Titan's Grip L1 |

| Level | Name | Effect |
|---|---|---|
| L1 | Reckless Assault | Before declaring an attack, you may choose to accept **−5 Speed Threshold** for **+5 Flat damage** on that attack. The VT penalty applies only to the Fast/Slow check for that round; it does not affect future rounds. |
| L2 | Cleave | If your attack reduces the target to 0 wounds and there is overflow (attack total − Guard > 0 after defeat), the overflow damage carries to the next enemy's Guard. *Deferred until Group 5 (enemy roster / multi-target resolution).* |
| L3 | Heavy Momentum | +1 Keep when attacking with a 2-handed weapon. |

---

### Meat for the Grinder
| | |
|---|---|
| **Category** | Ability |
| **Max Level** | 2 |
| **Prerequisites** | Wounds L2 |

| Level | Name | Effect |
|---|---|---|
| L1 | Thick Skin | Once per combat, when you would suffer Massive Damage (2 Wounds), you may spend this charge to degrade the result to 1 Wound. |
| L2 | Unyielding | As L1, but usable twice per combat. |

> This is a **reactive** ability triggered after the attack resolves but before wounds are applied. The player must be prompted to choose whether to spend a charge.

---

### Earthshatter
| | |
|---|---|
| **Category** | Ability |
| **Max Level** | 1 |
| **Prerequisites** | Brutal L3 |

| Level | Effect |
|---|---|
| L1 | After the Keep step of any Stance-pool or melee attack, add 1 Dominion die (at current stable Dominion die size) to the total. This die is added post-Keep and is not subject to the Keep rule — it always contributes. |

> Earthshatter's extra die is analogous to the Fervor die pattern: additive, post-Keep, always counted. The die size scales with the player's current stable Dominion size, not a fixed value.

---

## Design Notes

- **Ranged and Dual Wield** are parallel branches off Martial Arts L1. Neither requires Melee.
- **Disarm L2 synergy** uses the canonical Synergy effect-taxonomy pattern (see `docs/game-rules/reference/effect-taxonomy.md`).
- **Brutal L1** is a player-declared trade before each attack — it is not a passive. The UI must surface a toggle when `Brutal ≥ L1`.
- **Brutal L2 (Cleave)** requires multi-enemy routing and is deferred to Group 5.
- **Melee L2 (Space Domination)** grants a one-round reactive Advantage flag on the player's Stamina pool. This requires a stateful flag on `CombatantState` (cleared at round start).
- **Earthshatter** is deliberately narrow: Stance-pool attacks and melee physical attacks only. It does not apply to magical attacks or Resolve/Stamina-pool physical options.
- The **base Dominion stat starts at d4**. This is a change from the current `player_default.tres` (d6). The implementation plan (Group 4.8) flags this for confirmation before authoring data files.
