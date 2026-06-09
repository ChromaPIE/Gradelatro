# Gradelatro Run-End Capture Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Capture ending-run Joker snapshots at win time and prepare a pending Gradelatro buyout offer for later UI consumption.

**Architecture:** Add a small `RunEnd` integration module that adapts Balatro runtime objects into the already-tested `Buyout` service. Lovely patches only stamp the run start timestamp and call `RunEnd.capture_win_buyout_offer()` before the win overlay; they do not contain business rules or UI text.

**Tech Stack:** Lua 5.1/LuaJIT, SMODS, Lovely pattern patches.

---

## Scope

This phase does not render the post-win buyout screen and does not purchase cards automatically. It prepares `Gradelatro.pending_buyout_offer` after a won run so the next UI phase can present eligible/blocked cards and call `Buyout.purchase`.

## Files

- Create: `src/run_end.lua`  
  Snapshot ending Jokers, derive stake anchors, preserve run-start metadata, and call `Buyout.prepare_offer`.
- Create: `tests/run_end_test.lua`  
  Cover runtime adapter behavior with fake `G`/`SMODS` tables.
- Modify: `main.lua`  
  Attach `RunEnd`.
- Modify: `tests/run_all.lua`  
  Run the new tests.
- Create: `lovely.toml`  
  Patch game object creation to stamp `grdl_run_started_at`; patch `win_game()` to call the adapter before the win overlay.

## Tasks

### Task 1: Runtime Adapter

- [x] Write `tests/run_end_test.lua` with failing tests for Joker-only snapshot collection, dynamic stake anchors, run-start metadata, and pending offer storage.
- [x] Run `luajit tests\run_end_test.lua` and verify it fails because `src/run_end.lua` does not exist.
- [x] Create `src/run_end.lua`.
- [x] Run `luajit tests\run_end_test.lua` and verify it passes.

### Task 2: Wiring and Lovely Patches

- [x] Attach `RunEnd` in `main.lua` after `Buyout`.
- [x] Add `dofile("tests/run_end_test.lua")` to `tests/run_all.lua`.
- [x] Create `lovely.toml` with two small patches: one for `game.lua` run-start timestamp and one for `functions/state_events.lua` win offer capture.
- [x] Run `luajit tests\run_all.lua`.
- [x] Run LuaJIT bytecode syntax check for every `.lua` file.
- [x] Commit with message `feat: capture win buyout offers`.

## Acceptance Criteria

- The adapter only collects cards currently passed in through `G.jokers.cards`.
- Non-Joker cards are ignored even if accidentally present in the area.
- Stake gates use `G.P_STAKES.stake_red/stake_blue/stake_gold.stake_level` when available.
- Run metadata includes `run_id`, `run_started_at`, and `acquired_year`.
- Lovely patches call into `Gradelatro.RunEnd` and never embed buyout pricing or storage logic.
- Patch failures do not block the win overlay.
