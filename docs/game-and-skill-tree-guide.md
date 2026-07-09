# Kronomania — Game & Skill Tree Guide

A single-file introduction to how the game plays and how character progression
(the **Constellation** skill tree) works. Written for someone who has never seen
the project — no code knowledge assumed.

It covers both **what is implemented today** and **what is planned but not yet
built**, so the two are never confused.

> **Status legend**
> - ✅ **Implemented** — in the game right now.
> - 🛠️ **Planned** — designed and on the roadmap, not yet coded.
> - 💭 **Undesigned** — an idea with no finalized mechanic; blocked on a design decision.

> **Source of truth:** the canonical design lives in `docs/game-rules/`. This
> guide is a synthesized overview; where a detail matters, that folder wins.

---

## 1. What the game is

Kronomania is a **2D turn-based, dark-fantasy duel RPG**. You play a lone fighter
working through a gauntlet of one-on-one (and small-group) duels. Between fights
you rest at a campfire and spend earned points in a skill tree to grow stronger.

The feel is **tense and strategic**, not twitchy: every attack is a small gamble
of dice, defense, and timing. The art is hand-drawn dark-fantasy pixel art and the
UI is meant to feel like a tangible RPG rulebook.

**Core fantasy of a build:** you decide *how* you win — brute physical force
(**Dominion**), unbreakable defense (**Negation**), or mind-bending magic
(**Ingenuity**). Most characters mix two.

---

## 2. The core engine — one resolution rule for everything

Almost every action in the game — a sword swing, a spell, a defensive block —
runs through the **same five-step pipeline**:

> **Build Pool → Roll → Keep → Flat → Outcome**

| Step | What happens |
|---|---|
| **Build Pool** | You gather a number of dice equal to your **Tier** (T1 = 1 die … T4 = 4 dice). |
| **Roll** | Roll all pool dice. Each die's *size* (d4/d6/d8/d10) comes from the relevant stat. |
| **Keep** | Keep the best **N** dice, where N is your **Keep grade** for that action (Keep 1 / 2 / 3). Discard the rest. |
| **Flat** | Add flat bonuses (from weapons, nodes, spells) after keeping. |
| **Outcome** | Compare the final total against the target's Guard (attacks) or Velocity Threshold (timing). |

Two numbers therefore drive power: **Pool size = Tier** (how many dice) and
**die size = stat** (how big each die). **Keep** decides how much of a big pool you
actually get to use.

---

## 3. Stats and dice

Three **core stats**, each with a defensive expression:

| Core stat | Role | Defensive pool it powers |
|---|---|---|
| **Dominion** | Offense / physical force | **Stamina** |
| **Negation** | Defense | **Stance** |
| **Ingenuity** | Mental / control / magic | **Resolve** |

- **Die sizes** progress **d4 → d6 → d8 → d10**. That is the whole stable ladder.
- **d2** and **d12** exist only as exceptional/temporary states (e.g. a magic trance).
- The player starts every stat at **d4**, Tier 1. ✅

---

## 4. Defense and Guard — three pools

Defense is **active**, not passive armor. When you're attacked, you roll a defense
pool to generate **Guard**, and Guard absorbs the hit.

Three independent pools, each fed by a different stat:

| Pool | Fed by | Flavor |
|---|---|---|
| **Stance** | Negation | Physical footwork / blocking |
| **Resolve** | Ingenuity | Mental fortitude |
| **Stamina** | Dominion | Bodily endurance |

**Key Guard rules:**
- A pool is **rolled once per round**, the first time it's pressured. Same-round
  pressure on that pool reuses the existing Guard — it does **not** re-roll.
- Guard **resets to 0 at the start of each round**. Nothing carries over.
- **Breach:** an attack breaches when `attack_total ≥ guard` (tying at 0 still
  breaches).

This is why **mixed threats are dangerous**: an enemy (or your own build) that
forces you to defend Stance *and* Resolve *and* Stamina in one round makes you
spread thin. Magic deliberately bypasses Stance and hammers Resolve/Stamina to set
up a follow-up physical strike.

> 💭 **Cumulative Disadvantage** — the design says the 2nd+ different pool rolled
> in one round should take stacking Disadvantage. This is **deferred**; each pool
> currently rolls cleanly.

---

## 5. Timing — Velocity Threshold (VT)

There is no initiative list. Timing is decided per action against the enemy's
**Velocity Threshold (VT)**, a static number that belongs to the *enemy*.

- You roll your action. **Roll ≥ VT → Fast** (you act before the enemy).
  **Roll < VT → Slow** (the enemy acts first).
- The enemy never rolls for timing — its speed is baked into its VT.
- Being **Slow doesn't mean failing** — it just means your action lands later in
  the round, after Fast actions.

Typical VT bands: horde ≈ 10, veteran ≈ 12–14, boss ≈ 15–18, superhuman 20+.

---

## 6. Wounds, Massive Damage, and Defeat

- A breach deals **1 Wound**.
- **Massive Wound = 2 Wounds:** triggered when `(attack − guard) > defender's
  defensive die size`. A hit that overwhelms the pool by more than a whole die is
  brutal.
- **Defeat:** `wounds ≥ max_wounds`.
- Player base **Max Wounds = 3**, raised passively by Tier (+1 at T2, +1 at T4 →
  up to 5) and by the **Wounds Training** node.

---

## 7. The round loop (what a turn looks like)

1. **Start of round** — guards are already 0; ongoing status effects tick.
2. **You choose an intent** — Attack, Magic, or (stub) Item.
3. **You pick a tool** — which weapon to strike with, or which casting implement /
   spell to use.
4. **You confirm execution** — see a roll preview, optionally toggle special
   options (e.g. Brutal Trade), then commit.
5. **Resolution** — everyone's actions resolve in phase order: **Slow enemies →
   You → Fast enemies** (your Fast/Slow position is set by your roll vs VT).
6. **End of round** — end-of-round effects fire (some magic echoes here), guards
   reset, brief pause, next round begins.

This repeats until one side is defeated.

**ATK / DEF modes** ✅ let you tune pacing:
- **ATK: Manual** (default) walks the full menu; **ATK: Auto** fires your pinned
  default action (or a scored heuristic if you haven't pinned one) after you pick
  the intent.
- **DEF: Auto** (default) resolves defense instantly; **DEF: Observe** pauses to
  show incoming attack info before your defense rolls.

---

## 8. Magic — Fervor and Burnout

Magic uses the same Build→Roll→Keep→Flat engine, plus one subsystem: **Fervor**.

**Two kinds of magic:**

| | **Cantrips** | **True Spells** |
|---|---|---|
| Cost | None | A real **Fervor die** |
| Pool die | Ingenuity | Ingenuity (+ optional aspect dice) |
| Risk | Safe, simple | Riskier, stronger |
| During Burnout | ✅ Usable | ❌ Blocked |
| Unlocked by | **Minor Studies** node | **Spellcasting** node |

**Fervor** is a player-only escalating resource tracked on the **d4 → d6 → d8 →
d10** ladder:
- The **Fervor cap** = your current Ingenuity die face. You may act *at* the cap.
- Casting a true spell adds a real **Fervor die** to the roll (post-Keep, always
  counted — a "forced" die).
- **Escalation:** after a true spell, Fervor climbs by `(number of maxed primary
  dice) + (1 if the Fervor die itself maxed)`. Roll high → your magic gets more
  unstable.
- Escalating **beyond** the cap causes **Burnout**.

**Burnout** blocks all true spells (cantrips still work) and persists across
fights. It's cleared by a **Long Rest** (which also resets Fervor to d4) or a
**Recovery**.

Fervor and Burnout **persist between combats** — you carry your instability with
you until you rest.

---

## 9. The game loop (a run)

- A **run** is a fixed **8-encounter gauntlet**. Encounters chain (`→` = next wave
  same fight) and stack (`+` = multiple enemies at once): ✅

  | # | Encounter |
  |---|---|
  | 1 | Grunt |
  | 2 | Grunt → Grunt |
  | 3 | Grunt + Grunt |
  | 4 | Soldier |
  | 5 | Grunt → Grunt + Soldier |
  | 6 | Grunt × 3 |
  | 7 | Grunt + Soldier → Soldier + Soldier |
  | 8 | Knight (boss) |

- **Enemy roster:** Grunt (T1, d4/d4, VT 10, 2 wounds), Soldier (T1, d6/d6, VT 12,
  3 wounds), Knight (T2, d8/d8, VT 15, 4 wounds, Keep 2). ✅
- **Reward:** +1 skill point per kill; you start with 3.
- **Between fights → the Campfire:** ✅
  - **Short Rest** (once per run): −1 Wound, cool Fervor 1 step, clear Burnout.
  - **Long Rest:** full heal + Fervor reset, but a **50% − luck%** chance of an
    ambush → Disadvantage next fight.
  - Open the **Constellation** to spend points, swap weapons, or **Give Up**.
- **Save system:** 3 JSON slots, auto-save on entering the campfire. ✅

**Flow:** `Main Menu → Battle → (win) Campfire → Battle → … → win #8 → Main Menu`
(defeat or Give Up also return to the Main Menu).

---

## 10. The Constellation — how the skill tree works

All character growth happens in the **Constellation**, a **triangle-shaped** skill
tree:

- **Three vertices** = the three Core stats (Dominion, Negation, Ingenuity).
- **Edges** = hybrid nodes bridging two stats.
- **Interior** = training and ability nodes, grouped by their dominant stat.
- **Center** = a purely visual "heart" showing your Tier and HP.
- **Background / Traits tab** = a separate list holding **Flavor** nodes (identity,
  not combat power).

### Node categories

| Category | What it does | Slot cost |
|---|---|---|
| **Core** | Raises a stat's die size (d4→d6→d8→d10) | **2 Combat slots** per level |
| **Training** | Keep-grade & discipline growth (e.g. Wounds, Martial Arts) | 1 Combat slot |
| **Ability** | Broad competences, spells, special moves | 1 Combat slot |
| **Flavor** | Narrative identity / background | 1 **Flavor** slot |

Core, Training, and Ability are collectively **Combat Nodes**.

### Tiers and the slot budget ✅

Each Tier hands you a fixed budget: **5 Combat slots + 2 Flavor slots**.

- Spend a Combat slot to raise any Core/Training/Ability node one level (Core
  costs **2**).
- Spend a Flavor slot to buy a Flavor node.
- The two budgets are independent.
- When **both** budgets are fully spent, you **automatically advance to the next
  Tier** and get a fresh 5 + 2.
- **Tier 4 is the hard cap** (you keep the T4 budget but Tier stops rising).

Because a maxed Core node alone costs 6 Combat slots (more than a whole Tier's
Combat budget), you **cannot** take everything — builds require sacrifice.

### Multi-level nodes ✅

Most nodes have internal levels (e.g. `L2 / L3`). Each purchase advances the level
by 1. Prerequisites are written as **`NodeName LN`** (e.g. "requires Core Dominion
L2") and are all **AND** conditions — every listed requirement must be met at once.
Some nodes also gate on a minimum **Tier**.

### Keep-grade baseline ✅

Four keep nodes are **auto-granted at L1 for free** at the start of a run:
Martial Arts (physical attacks), Stance / Stamina / Resolve guards. L1 = the free
baseline (Keep 1); higher levels raise you to Keep 2 then Keep 3. Convention
throughout: **effect value N means "keep N dice."**

---

## 11. The Dominion tree (physical) — ✅ IMPLEMENTED

The "meat tank" path: raw force, melee mastery, and endurance. **11 nodes, 24
possible level-ups** — but only ~20 fit in a full-run budget, so you must choose.

**Prerequisite map:**

```
Core Dominion (L1/L2/L3)
    ├── Wounds (L1/L2/L3)
    │     └── Meat for the Grinder (L1/L2)   [req: Wounds L2]
    └── Martial Arts (L1/L2)   [req: Core Dominion L2]
            ├── Melee (L1/L2)   [req: Martial Arts L1]
            │     ├── Dual Wield (L1/L2)      [req: Melee L1]
            │     ├── Titan's Grip (L1/L2)    [req: Melee L1]
            │     │     └── Brutal (L1/L2/L3) [req: Titan's Grip L1]
            │     │           └── Earthshatter (L1) [req: Brutal L3]
            │     └── Disarm (L1/L2)          [req: Melee L1]
            └── Ranged (L1/L2)   [req: Martial Arts L1]
```

**Node reference:**

| Node | Levels | Effect |
|---|---|---|
| **Core Dominion** | L1–L3 | Dominion die: d4→d6→d8→d10. |
| **Wounds** | L1–L3 | +1 Max Wounds per level (cumulative up to +3). |
| **Martial Arts** | keep grade | Raises Keep on all physical attacks (baseline free L1 → Keep 2 → Keep 3). |
| **Melee** | L1–L2 | L1: +1 Flat on melee attacks. L2 (**Space Domination**): a melee hit that breaks Guard grants Advantage on your next Stamina defense this combat. |
| **Ranged** | L1–L2 | 💭 Mechanics TBD (parallel branch, doesn't need Melee). |
| **Dual Wield** | L1–L2 | 💭 Mechanics TBD. |
| **Titan's Grip** | L1–L2 | L1: +1 Flat with two-handed weapons. L2: immune to disarm. |
| **Disarm** | L1–L2 | L1: a successful Disarm makes the enemy drop their weapon. L2: if Melee is maxed, also grants Advantage on your next attack. |
| **Brutal** | L1–L3 | L1 (**Reckless Assault / Brutal Trade**): opt-in −5 VT for +5 Flat on an attack. L2 (**Cleave**): 🛠️ overflow to next enemy — deferred. L3 (**Heavy Momentum**): +1 Keep with two-handed weapons. |
| **Meat for the Grinder** | L1–L2 | Reactive: once (L1) / twice (L2) per combat, degrade a Massive Wound (2) back to 1 Wound by spending a charge. |
| **Earthshatter** | L1 | Adds one post-Keep Dominion die (current size) to Stance/melee attacks — always counted, like a Fervor die. |

> Within Dominion, **Ranged**, **Dual Wield**, and **Disarm's** deeper mechanics are
> still design stubs (💭), and **Brutal L2 Cleave** (🛠️) awaits multi-target overflow
> rules.

---

## 12. The Ingenuity branch (magic) — ✅ IMPLEMENTED

The caster path. Design philosophy: **grows wide early** (disciplines are reachable
without buying mandatory passives), **spells are physically granted by the node
that unlocks them**, and **magic targets Resolve/Stamina** to bypass physical
Stance and set up warrior follow-ups.

### Foundation

| Node | Levels | Effect |
|---|---|---|
| **Ingenuity Core** | L1–L3 | Ingenuity die d4→d6→d8→d10; automatically raises the Fervor cap. |
| **Minor Studies** | L1 | Unlocks cantrips; grants **Arcane Bolt** (vs Stance) and **Arcane Touch** (vs Resolve). No Fervor cost; usable during Burnout. |

### The engine — Spellcasting (L1–L3) ✅

Prerequisite: Minor Studies. Unlocks the real Fervor die and true spells.

- **L1** — grants **Arcane Missile** (vs Stance) + **Arcane Mark** (vs Resolve);
  turns on Fervor & escalation.
- **L2** — all arcane spells gain **Keep 2**; Arcane Missile +1 Flat; an Arcane
  Mark breach → enemy Stance Flat −2.
- **L3** — all arcane spells gain **Keep 3**; Arcane Missile +2 Flat total; an
  Arcane Mark breach *also* → enemy Stance Keep −1 (**Frattura Totale** — the L2 and
  L3 debuffs stack and fire together).

### Fervor self-control — Lucidity (cross-tier, L1–L2) ✅

One identity, two depths:
- **L1** (Tier 1, proactive): spend your turn to cool Fervor by 1 step. Unlimited.
- **L2** (Tier 3, reactive): once per combat, when escalation *would* trigger
  Burnout, spend a charge to cancel it — Burnout averted, but Fervor stays pinned
  at the cap (a precarious truce).

### The four Disciplines ✅

Horizontal, pick-what-you-like specializations (each L1–L2). Every one injects its
own true spell and targets a mental pool:

| Discipline | Spell | What it does |
|---|---|---|
| **Mind Detonation** | *Mind Detonation* | Plants a psychic charge (a weak, gear-independent placement scratch vs Stance). If you then **breach that enemy's Stance** this round, the charge **detonates against Resolve** using your frozen Fervor. L2: +1 explosion Keep. |
| **Hex Mastery** | *Mind Rend* (vs Resolve) | On a Resolve breach, suppresses the wound and **brands** the enemy (`hex_marked`). While marked, **every** breach you land on that enemy (any pool) deals **+1 Wound**. L2: mark lasts longer. |
| **Echoing Mind** | *Mind Lash* (echo tag) | After casting, the spell **echoes at the end of each round**, re-attacking with your frozen Fervor and one fewer kept die each time — fading out as the "kept dice" decay. L2: each echo carries a Flat bonus. |
| **Chrono-Tinkering** | *Time Lock* (vs Resolve) | On a Resolve breach, **arms** a time lock. Your next attack on that enemy **freezes** that guard pool — it won't renew next round, letting you press the same value again. L1: 1 round frozen. L2: 2 rounds. |

These disciplines are designed to **combo**: e.g. Hex + Mind Detonation means both
the Stance breach *and* the detonation breach get the +1-Wound amplification from
the same mark.

### Casting implements ✅

Casting is gated by your hands, not capped by them (equip-requirements rework):

- **Cantrips** need **truly empty hands** (both slots) or an equipped **Magic Focus**.
- **True spells** always need an equipped **Magic Focus** — steel in both hands means
  no spellcasting at all until you swap gear at a campfire.
- Focus content: **Arcane Focus** (one hand, Cast flat +1) and **Wizard Staff**
  (two-handed, Cast flat +1 and pool +1, can also bonk).

The chosen conduit's "cast" profile adds its bonuses to your spell pool:

`pool = full Tier + tool pool bonus + school bonus`

- Items never cap Tier — your expressed dice are throttled by keep grades (training).
- **Bare hands** (cantrips only) → full Tier, no bonuses.
- **Mind Detonation's placement** is always gear-independent (pool = 1), but priming
  it is a true-spell cast, so it still needs a focus in hand.

---

## 13. Negation branch (defense) — partially built

- **Negation Core** (L1–L3) ✅ exists — raises the Negation die (Stance).
- **Stance Guard** training node ✅ exists — raises Stance Keep grade.
- 💭 A full **Negation training/ability subtree** (beyond core + guard) is **not yet
  designed**.

---

## 14. Flavor nodes — ✅ IMPLEMENTED

Twenty identity/background nodes (Street Rat, Hedge Knight, Mercenary, Exile's
Brand, Haunted Past, etc.) plus Warrior's Oath. They live in the **Background /
Traits** tab and are bought with the separate **Flavor** budget, signaling they're
narrative choices rather than combat optimization. (Most are currently
identity-flavor; mechanical hooks are minimal by design.)

---

## 15. Planned / not-yet-implemented

### 🛠️ Group D — Ingenuity late-game & hybrids (designed, next up)

| Node | Concept |
|---|---|
| **Purple Hollow** (L1) | A suicide trance: temporary **d12** Ingenuity with an escalation threshold of 10 and consequences when it expires. |
| **Blood Channeling** (Dominion + Ingenuity hybrid) | Cast **during Burnout** by paying HP (self-damage); Keep grade scales with node level. |
| **Cataclysmic Arts / Meteor Shower** (hybrid) | A big hybrid spell using Dominion as its aspect stat. |

### 💭 Undesigned / blocked

- **Ranged, Dual Wield, Disarm** deeper mechanics (Dominion) — design stubs.
- **Brutal L2 (Cleave)** — needs multi-enemy overflow rules.
- **Negation & Ingenuity non-magic subtrees** — training/ability nodes beyond
  Core + Guard not designed.
- **aether_barrier** & **chrono_shift** cantrips — mechanics undefined (each has 2–3
  candidate designs to choose between).
- **Cumulative Disadvantage** on multiple defense pools — deferred since Group 1.
- **Active DEF Mode** — letting the player pick a defensive tool/action; needs
  per-weapon defensive action design.
- **Meat for the Grinder relocation** — planned to become a Dominion/Negation hybrid
  "physical mitigation" node (same mechanic, new home).
- **Magic defense** — a caster's defensive identity (prevention/manipulation/evasion
  rather than damage-soak); design direction only.
- **Cantrip "known slots" cap** — currently every purchased cantrip is always
  available; a slot formula is not designed.

---

## 16. One-page cheat sheet

| Thing | Rule |
|---|---|
| Resolution | Build Pool → Roll → Keep → Flat → Outcome |
| Pool size | = Tier (T1=1 … T4=4 dice) |
| Die size | from stat (d4/d6/d8/d10) |
| Keep | N = keep N best dice |
| Breach | `attack_total ≥ guard` |
| Wound | 1 per breach; 2 (Massive) if `(attack − guard) > defensive die size` |
| Defeat | `wounds ≥ max_wounds` (player base 3) |
| Timing | Roll ≥ enemy VT → Fast; < VT → Slow |
| Guard | rolled once/round when first pressured; resets to 0 each round |
| Fervor | d4→d10, cap = Ingenuity face; escalates on max rolls; over cap → Burnout |
| Cantrip | Ingenuity die, no Fervor, works in Burnout |
| True spell | Ingenuity + Fervor die, blocked by Burnout |
| Tier budget | 5 Combat + 2 Flavor slots; spend both → advance Tier (max T4) |
| Core node cost | 2 Combat slots/level; others 1 |
| Passive wounds | +1 at T2, +1 at T4 |

---

*This guide summarizes both shipped systems and the roadmap. For exact mechanics
and edge cases, consult `docs/game-rules/` (design source of truth) and
`docs/project-status.md` (current implementation status).*
