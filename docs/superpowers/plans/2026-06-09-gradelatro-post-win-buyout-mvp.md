# Gradelatro Post-Win Buyout MVP Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add the pure, testable service layer for buying out ending-run Jokers into the Gradelatro collection.

**Architecture:** Keep Balatro/Lovely integration thin by exposing a `Buyout` module that accepts ending Joker snapshots, current catalog data, stake anchors, and collection state. The module returns localizable reason codes and performs atomic currency/card mutations through existing `Storage`, `Economy`, `Stakes`, `Catalog`, and `Condition` modules.

**Tech Stack:** Lua 5.1/LuaJIT, SMODS/Lovely integration points deferred, existing Gradelatro pure modules.

---

## Scope

This phase does not create the post-win UI or Lovely patches. It builds the service API that a later win-flow patch can call after a won run, with all user-facing text represented as codes/data for localization.

## Files

- Modify: `src/storage.lua`  
  Persist raw-card acquisition metadata needed by later slab labels and binder display.
- Create: `src/buyout.lua`  
  Build buyout offers, derive card editions, quote prices, enforce stake/selection/currency rules, and add raw cards atomically.
- Modify: `main.lua`  
  Attach `Buyout` to `Gradelatro`.
- Modify: `tests/storage_test.lua`  
  Cover acquisition metadata persistence.
- Create: `tests/buyout_test.lua`  
  Cover offer filtering, price quoting, selection cap, insufficient funds atomicity, and successful purchase.
- Modify: `tests/run_all.lua`  
  Run buyout tests in the foundation suite.

## Tasks

### Task 1: Storage Acquisition Metadata

- [x] Write a failing assertion that `Storage.add_raw_card` stores `local_key`, `acquired_year`, `source_run_id`, and `source_run_started_at`.
- [x] Run `luajit tests\storage_test.lua` and verify the new assertion fails.
- [x] Store those fields in `src/storage.lua`, keeping unknown fields nil-safe.
- [x] Run `luajit tests\storage_test.lua` and verify it passes.

### Task 2: Buyout Service

- [x] Create `tests/buyout_test.lua` with failing tests for red-stake rarity filtering, dynamic quote calculation, selection limit, insufficient funds atomicity, and successful purchase.
- [x] Run `luajit tests\buyout_test.lua` and verify it fails because `src/buyout.lua` is missing.
- [x] Create `src/buyout.lua` with:
  - `edition_from_card(card)` for vanilla Balatro edition snapshots.
  - `prepare_offer(config, state, args)` returning `gate`, `eligible`, and `blocked`.
  - `purchase(config, state, args)` enforcing max 5 selected cards, atomic total-price payment, and raw-card creation through `Storage.add_raw_card`.
- [x] Run `luajit tests\buyout_test.lua` and verify it passes.

### Task 3: Wiring and Verification

- [x] Attach `Buyout` in `main.lua` after `Label`.
- [x] Add `dofile("tests/buyout_test.lua")` to `tests/run_all.lua`.
- [x] Run `luajit tests\run_all.lua`.
- [x] Run LuaJIT bytecode syntax check for every `.lua` file.
- [x] Commit with message `feat: add post-win buyout service`.

## Acceptance Criteria

- Buyout logic has no UI text literals; it returns stable reason codes such as `rarity_locked`, `not_in_catalog`, `selection_limit`, and `insufficient_funds`.
- Only ending Joker snapshots passed into the service can be purchased; the service does not discover arbitrary cards itself.
- Stake gates are delegated to `Stakes.gate_for_level` and `Stakes.can_buyout`.
- Prices use `Economy.raw_anchor_value` and `Economy.buyout_price`.
- Purchases are atomic: if funds are insufficient or selection exceeds the cap, no currency or card mutation occurs.
- Raw cards contain acquisition metadata needed for future slab labels.
