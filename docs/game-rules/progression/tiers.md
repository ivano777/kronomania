# Tiers

Tier is the main progression term for base pool size.

Baseline mapping:
- Tier 1 → 1 die
- Tier 2 → 2 dice
- Tier 3 → 3 dice
- Tier 4 → 4 dice

Tier is distinct from:
- stat Size
- Keep
- Flat

## Tier Hard Cap

**Tier 4 is the maximum.** A player may continue spending the Tier 4 budget, but Tier will not increase past 4.

## Tier Advancement Rule

Each tier has a fixed slot budget:

| Tier | Base Pool | Combat slots (this tier) | Flavor slots (this tier) |
|------|-----------|--------------------------|--------------------------|
| 1    | 1 die     | 5                        | 2                        |
| 2    | 2 dice    | 5                        | 2                        |
| 3    | 3 dice    | 5                        | 2                        |
| 4    | 4 dice    | 5 (no further advance)   | 2 (no further advance)   |

**Combat slots** are consumed by unlocking any node with category **Core**, **Training**, or **Ability**.
**Flavor slots** are consumed by unlocking any node with category **Flavor**.

> **Core-node cost:** Core-category upgrades consume **2 Combat slots each** (not 1). A single Core node with 3 levels costs 6 Combat slots total. See [Nodes — Node Costs](./nodes.md) for the full cost table.

The two budgets are independent. Exhausting Combat slots blocks further Combat unlocks for that tier but does not affect Flavor slots, and vice versa.

Once **both** budgets for the current tier are fully spent, the player automatically advances to the next tier and receives a fresh 5 Combat + 2 Flavor budget. There is no way to unlock additional nodes in a tier beyond its budget.

## Passive Max Wounds

Reaching certain Tiers permanently increases the player's Max Wounds. These bonuses are applied at combat initialisation and are not baked into base `.tres` data files.

| Tier reached | Max Wounds bonus |
|--------------|-----------------|
| Tier 1       | +0              |
| Tier 2       | +1              |
| Tier 3       | +0              |
| Tier 4       | +1 (total +2)   |

A player who reaches Tier 4 has a cumulative +2 Max Wounds on top of their base value.
