# Combat Invariants — Discipline & Effect Internals

Deep "do not accidentally fix this" notes for the CombatManager async spine, the
`combat/effects/` handler layer, and the four magic disciplines. Load this before
editing `autoloads/CombatManager.gd`, `combat/`, `combat/effects/`, or any
discipline (Mind Detonation, Hex Mastery, Echoing Mind, Chrono-Tinkering).

CLAUDE.md keeps the general, always-relevant fragile rows; the specialist rows
below were moved here to keep the always-on context small.

## Status / outcome / interrupt bookkeeping

| Area | Why it's correct |
|---|---|
| `pending_guard_debuffs` consumed/erased before the roll | Single-use; consuming first guarantees apply-once |
| `_current_round_player_breaches` on `CombatManager` not `CombatantState` | Round-scoped, resets every `_begin_round()` |
| `status_to_apply` is `.duplicate()`'d before adding | Each application independent; otherwise duration ticks share state across enemies |
| `bonus_keep`/`bonus_flat` in `SpellOutcomeEffect` `push_warning` at dispatch | Reserved for Group D outcome-driven bonuses; warning prevents silent misuse |
| `SpellBonusEffect` with `spell_id` set matches OR-style with tag | `spell_id` non-empty = name filter; empty = tag match; both true is harmless (summed once) |
| `"hit"/"breach"` false even when `attack_total >= guard` | They mean "round's FIRST breach on the target_pool"; an already-breached pool yields false |
| InterruptHandler priority 10/20 | Lucidity L2 (10, `_escalate_fervor`) before MftG (20) — deliberate order |
| InterruptHandler charges on the handler, not `CombatantState` | Each handler manages its own resource; same-trigger handlers have independent charges |
| Interrupt registration in `start_combat`, not on purchase | Handlers are combat-scoped; charges reset every combat |
| `wounds_pending` reassigned inside the interrupt loop | Loop modifies wounds only on the player-defender/massive path; final `wounds := wounds_pending` is the applied count |

## Fervor / escalation

| Area | Why it's correct |
|---|---|
| `_escalate_fervor` accepts negative steps | Lucidity L1 cools Fervor; `clampi` floors at 0; Burnout check + cap clamp gated to `steps > 0` |
| `_escalate_fervor` is a coroutine | Awaits `_try_prevent_burnout` on the positive-step Burnout path; both call sites use `await`; the cooling path never hits an await |
| `_try_prevent_burnout` separate from `_resolve_interrupt` | `_resolve_interrupt` is wounds-shaped (`_resolve_attack`); `_try_prevent_burnout` is bool-shaped (`_escalate_fervor`) — different fire point + return contract |
| Three round coroutines share `_run_enemy_attacks(slow_phase, …)` | Phase 1/3 Slow/Fast enemy loops extracted; `brutal_trade` VT offset is a param (strike passes it, cantrip/spell pass false) |

## Mind Detonation

| Area | Why it's correct |
|---|---|
| Mind Detonation placement roll uses pool=1, not tier | Driven by `SpellData.placement_scratch=true`; deliberate weak gear-independent scratch (literal `1`, `net_advantage=0`, no `_pool_bonus`) |
| Status removed BEFORE `_resolve_attack` in `_detonate_mind_bomb` | Prevents re-trigger: MD fires on Stance breach, explosion hits Resolve; removing first is the clean guarantee |
| Mind Detonation explosion does not escalate Fervor | Delayed payoff using frozen `fervor_at_prime`, not a fresh cast |
| Explosion uses frozen cast values from `MindBombPayload`/`CastSnapshot` | Frozen at prime time via `CastSnapshot.from_mod`; read back with `MindBombPayload.from_status`. Legacy statuses without keys fall back to `_effective_tier(_player, null)`. Do not read live `_player_cast_weapon` in `_detonate_mind_bomb` |

## Hex Mastery / Mind Rend

| Area | Why it's correct |
|---|---|
| `_cast_mind_rend` bypasses `_resolve_attack` | Mind Rend suppresses the breach wound and applies a mark instead; the standard path always deals the wound |
| Hex amplification is `HexEffect.on_wound_calc` (+1), not inline | The spine's generic wound loop calls handlers only for player-on-enemy breaches; `HexEffect` returns +1 and logs "hex flares" |
| Mind Rend's own breach does not self-amplify | Mark applied AFTER the on_breach hook; wound suppressed regardless |
| Hex + Mind Detonation: both Stance breach and explosion breach amplified | Both route through `_resolve_attack` with the same mark; each amplification independent — designed combo |

## Echoing Mind / Mind Lash

| Area | Why it's correct |
|---|---|
| `echoing_spell` lives on the PLAYER, not the target | The caster echoes; one echo train at a time; new cast overwrites old; moves with the caster regardless of which enemy is alive |
| `current_kept_dice` self-terminates the echo, not `duration_rounds` | Kept-dice decay is the design; `duration_rounds=20` is a safety bound that should never trip (`_tick_statuses` logs `[debug]` if it does) |
| Echo routes through `_resolve_attack` but does NOT escalate Fervor | `_escalate_fervor` is in `_resolve_round_spell` after Phase 3, not in `_resolve_attack`; echo bypasses the cast path (frozen Fervor, delayed payoff) |
| New cast of an echoing spell overwrites the existing `echoing_spell` | Stacking echo trains rejected as too complex; latest wins (known simplification) |
| Echo uses frozen cast values from `EchoPayload`; keep NOT present | `EchoPayload` omits `cast_keep_bonus` (`CastSnapshot.write(include_keep=false)`) — focus keep is baked into `current_kept_dice` at arming and decays with the train |

## Chrono-Tinkering / Time Lock

| Area | Why it's correct |
|---|---|
| `_cast_time_lock` bypasses `_resolve_attack` | Intentional — Time Lock suppresses the breach wound, mirrors `_cast_mind_rend`; the Resolve attack never routes through the standard pipeline |
| `cast_mind_rend`/`cast_time_lock` emit `attack_resolved` themselves (wounds_dealt 0, did_breach = breach) | Presentation contract: `_resolve_round_spell` emits `combatant_attacking` before EVERY cast branch; each windup needs a matching `attack_resolved` or AttackPresenter hangs dimmed. These casts bypass `_resolve_attack` (which emits it for all other paths), so they close their own windup. breach+0-wounds combo is unreachable from `_resolve_attack` — presenter renders it "Breached!" |
| `time_locked` is a two-phase status (armed→frozen) | Intentional — armed waits for the next player attack; frozen locks that pool. `TimeLockEffect.on_player_attack_resolved` transitions it (via `ctx.did_breach`); `on_guard_reset` restores the frozen pool each `_end_of_round`. Payload via `TimeLockPayload` (typed view over `stat_overrides`) |
| Frozen pools survive `reset_guard()` across `_end_of_round` | `TimeLockEffect.on_guard_reset` runs AFTER the reset: restores `frozen_value` (from `TimeLockPayload`), marks the pool rolled, decrements `skip_resets`, removes the status at 0 |
| The armed→frozen transition fires for echoes and MD explosions too | Intentional — any player attack through `_resolve_attack` hits the generic post-attack handler loop (`attacker_is_player=true`); echoes and explosions included |

## Async spine sequencing

| Area | Why it's correct |
|---|---|
| `_process_statuses_hook` has `await` but not all callers `await` it | Only `end_of_round` fires async (echo); `start_of_round`/`on_breach` run synchronously — fire-and-forget is safe there |
| `_end_of_round` checks `_all_enemies_defeated()` mid-function and returns early | An echo can kill the last enemy; `_end_combat()` before the timer; callers guard with `if _all_enemies_defeated(): return` before `_begin_round()` |
| Cast tool list mirrors strike list in `_build_tool_entries("magic")` | Bare Hands entry appears only when no equipped item has `"cast"` key — same logic as attack Bare Hands |
