# Effect Taxonomy

This reference defines a consistent naming convention for recurring effect packages across rules, nodes, items, spells, and future content.

The goal is to reduce wording drift and enable data-driven implementation by giving every common modifier type a canonical label.

---

## Notation Pattern

**[Family] [Grade]**

- **Family** — a thematic label for the type of effect.
- **Grade** — I, II, or III for standard magnitudes. Exceptional or legendary effects may use IV+.

Examples:
- `Forging I` — +1 flat physical damage
- `Warding II` — +2 flat guard bonus
- `VT +3` — positive timing modifier (numeric, not graded)

---

## Effect Families

### Forging — Flat Physical Damage Bonus
Adds to the final total of a physical attack after Keep.

| Name | Flat Bonus |
|---|---|
| Forging I | +1 |
| Forging II | +2 |
| Forging III | +3 |

### Channeling — Flat Magical Damage Bonus
Adds to the final total of a magical attack or cantrip after Keep.

| Name | Flat Bonus |
|---|---|
| Channeling I | +1 |
| Channeling II | +2 |
| Channeling III | +3 |

### Warding — Flat Guard Bonus
Adds to the total of a defense roll after Keep.

| Name | Flat Bonus |
|---|---|
| Warding I | +1 |
| Warding II | +2 |
| Warding III | +3 |

### Fortitude — Maximum Wound Bonus
Increases the target's maximum wound capacity.

| Name | Max Wounds Bonus |
|---|---|
| Fortitude I | +1 |
| Fortitude II | +2 |

### Potency / Diminishment — Status-Size Modifier
Modifies the effective die Size of a stat (Status modifier layer).

| Name | Size Steps |
|---|---|
| Potency I | +1 step (e.g., d6 → d8) |
| Potency II | +2 steps (e.g., d6 → d10) |
| Diminishment I | −1 step (e.g., d8 → d6) |
| Diminishment II | −2 steps (e.g., d8 → d4) |

### Surge / Drain — Pool-Size Modifier
Adds or removes dice from the roll pool before Keep (Situation modifier layer).

| Name | Pool Change |
|---|---|
| Surge I | +1 die |
| Surge II | +2 dice |
| Drain I | −1 die |
| Drain II | −2 dice |

---

## VT Modifiers — Timing

VT modifiers use **numeric notation directly**, not the grade system.
The values are too variable for fixed grades to be useful.

- Positive: **VT +N** (faster; easier to act Fast against the target)
- Negative: **VT −N** (slower; harder to act Fast)

Examples:
- Quick jab technique: VT +3
- Tactical Instinct node: VT +2
- Ritual Fireball: VT −20
- Heavy armor: VT −4

---

## Usage Notes

- Use canonical names in all node descriptions, item text, and spell descriptions.
  Write "grants **Forging I**" rather than "+1 to attack."
- Multiple instances of the same family stack unless a rule explicitly says otherwise.
- VT modifiers always use numeric form for precision. Do not invent grade names for VT.
- This taxonomy covers common recurring effects. Unique or one-off effects may use plain description without requiring a canonical label.
