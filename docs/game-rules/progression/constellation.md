# Constellation

The **Constellation** is the game's progression structure.

Characters improve by unlocking **nodes** grouped into official categories.

The Constellation exists to:
- organize growth
- prevent one-axis optimization
- connect mechanics and identity
- host exceptions that do not belong in baseline rules

## Official Categories
- **Core**
- **Training**
- **Ability**
- **Flavor**

Tier advancement requires both Combat Node breadth and Flavor Node breadth. See [tiers.md](./tiers.md) for the full advancement rule.

## Visual Layout

The skill tree is structured as a **Triangle**.

### Triangle structure
- **Vertices** — the three Core stats (Dominion, Negation, Ingenuity) sit at the three corners of the triangle.
- **Edges** — hybrid path nodes connecting two stats run along the edges between vertices (e.g. a Dominion–Negation edge hosts martial/endurance paths).
- **Interior** — Training and general Ability nodes populate the space inside the triangle, grouped loosely by their dominant stat affiliation.

### Heart/Core (center element)
A non-interactive aesthetic element sits at the geometric center of the triangle. It displays:
- The player's current **Tier** number.
- The player's current **HP / Max Wounds** slots.

This element is purely visual. It does not accept input and holds no game state of its own.

### Background / Traits tab
**Flavor nodes are not shown on the main triangle.** They live in a dedicated **"Background / Traits"** tab, visually separated from the combat skill tree. The tab renders Flavor nodes in a scrollable list or compact grid.

This separation communicates to the player that Flavor choices are identity/narrative purchases rather than combat optimisations, while still making them visible and accessible.

---

## Multi-Level Nodes

Most progression paths use **Multi-Level Nodes**: a single graphical entity in the Constellation UI with an internal level counter. Spending one Combat slot on a node advances its level by 1, up to the node's maximum.

### Level notation

Node cards display the current and maximum level (e.g. `L0 / L3`, `L2 / L2`). Visual pip indicators may be used in place of numbers. A node at `L0` is unpurchased; a node at its maximum level is fully maxed and its upgrade button is disabled.

### Level-based prerequisites

Prerequisites on Multi-Level Nodes are expressed as **`NodeName LN`** — for example, "requires Core Dominion L2". This means the source node must be at level 2 or above before the dependent node can be upgraded.

All prerequisites are AND conditions: every listed requirement must be simultaneously satisfied before an upgrade is permitted.

### Connection lines

A connection line between two nodes lights up progressively as the source node's level meets the threshold required by the dependent node. A line that is not yet lit indicates the dependency is not yet satisfied.

### Effect delivery

Each level of a Multi-Level Node delivers a distinct effect (or a cumulative increment of the same effect). The full per-level effect list lives in the dedicated tree file, not on the node card itself.

### Backward compatibility

Existing single-upgrade nodes (all current `.tres` files) are treated as Multi-Level Nodes with `max_level = 1`. No schema change is required for existing data until they are explicitly migrated to the multi-level format.
