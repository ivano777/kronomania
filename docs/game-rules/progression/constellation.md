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
