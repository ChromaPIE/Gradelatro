# Gradelatro Run Carry ("Golden Revolver") Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Let the player carry one raw collection card into a run, activate it for a single Blind per Ante as a normal Joker, return it with condition wear, and lose it permanently if it is sold, destroyed, or removed.

**Architecture:** Two rounds. Round 1 builds the pure `Carry` service on top of `Condition.apply_wear` (the per-edition wear weights already match the confirmed design): run selection with eligibility rules, per-Ante activation tracking, tiered wear rolls (seedable), permanent loss, and stale-run reconciliation. Round 2 does the runtime integration: the fixed left-HUD sleeve slot, activation between Blind select and the first played hand, spawning the Joker into the normal Joker area, return-or-loss detection at Blind end, and the binder entry point for choosing the carry card. Lovely patches stay dispatch-only.

**Tech Stack:** Lua 5.1/LuaJIT, SMODS, Lovely pattern patches, Balatro CardArea/UIBox.

---

## Confirmed Design Rules (from the concept session)

- At most one raw card per run; graded, queued, listed, sold, or lost cards can never be carried.
- While dormant the card has no effect, occupies no Joker slot, and never enters run logic; it is shown in a fixed left-HUD sleeve, not draggable, deliberately unlike Partner-API.
- Activation window: after the Blind is selected and before the first hand is played; requires a free normal Joker slot; the card occupies a normal slot while active.
- One Blind activation per Ante. At Blind end, if the card was not sold/destroyed/removed it returns to the sleeve and wear settles.
- Wear rolls are tiered: every activation leaves a trace; most are minor, some moderate, rarely a severe accident. Editions use `Condition.apply_wear` weights (Negative corners/edges 1.25, Polychrome surface 1.7, etc.). Only corners/edges/surface degrade.
- Sold, destroyed, sacrificed, or permanently removed while active = permanent collection loss (`Storage.mark_lost`).
- Non-destructive in-run modifications never write back to the collection record.
- Carry state persists in the collection (`state.carry`) keyed by `run_id`; starting or capturing a different run reconciles stale carry back to the sleeve.

## Round 1 Files (commit `feat: run carry service`)

- Create: `src/carry.lua`
  `select_for_run` (eligibility, one per run), `withdraw` (before run starts), `can_activate` (ante gate, free-slot check input), `apply_use` (seedable tiered wear via `Condition.apply_wear`, wear_count), `mark_lost`, `release` (run end), `reconcile` (stale run cleanup), `sleeve_info` (UI projection).
- Modify: `src/config.lua`
  `carry` defaults: wear tier chances and intensity bands (minor 0.70 / 0.05-0.15, moderate 0.25 / 0.20-0.40, severe 0.05 / 0.80-1.50).
- Create: `tests/carry_test.lua`
  Eligibility rejections, one-per-run, ante gating, deterministic wear rolls by seed, tier distribution sanity, loss, release, reconcile.
- Modify: `main.lua`, `tests/run_all.lua`.

## Round 2 Files (commit `feat: sleeve slot and carry integration`)

- Binder: carry select/withdraw entry on raw cards (or desk-style screen) writing through `Carry`.
- `src/carry_ui.lua`: left-HUD sleeve UIBox (card thumbnail, dormant/active state), activation button window, confirm flow.
- `lovely.toml`: thin patches — blind-select window open, first-hand close, blind-end return hook, joker-removal loss hook; every pattern verified single-hit against the dump first.
- Run save integration: active Joker tagged with the collection card id; reload-safety checks.

## Tasks

### Round 1: Carry Service

- [ ] Write failing `tests/carry_test.lua` covering the rules above.
- [ ] Add `carry` defaults to `src/config.lua`.
- [ ] Implement `src/carry.lua`; full suite + bytecode; commit.

### Round 2: Runtime Integration

- [ ] Research dump: blind select/end state events, joker area emplace path, sell/destroy dispatch points.
- [ ] Sleeve HUD + activation flow + Lovely patches; in-game smoke test checklist.

## Acceptance Criteria (Round 1)

- Selecting a non-raw or missing card fails with reason codes and changes nothing.
- A second select in the same run fails; withdraw restores the card to raw.
- `apply_use` only ever lowers corners/edges/surface, respects edition weights, is reproducible by seed, and increments `wear_count`.
- A severe roll can push the card below Gem Mint potential permanently (grade cap emerges from condition math, no special casing).
- Reconcile releases carry from a different run id without wear.
