# Gradelatro Grading Queue Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Let players submit raw collection cards for PSA-style grading, wait real time per service tier, and reveal grade plus certificate number when the binder is opened.

**Architecture:** Add a pure `Grading` service module on top of the existing `Condition`, `Economy`, and `Storage` modules. The binder UI becomes the reveal point: opening it processes due grading queue entries, shows newly revealed grades, lists pending submissions with ETA, and offers a Grade button on raw card rows. No new Lovely patches are required; the existing binder entry point carries the whole loop.

**Tech Stack:** Lua 5.1/LuaJIT, SMODS config persistence.

---

## Scope

This phase covers grading submission, fee payment, real-time queue, reveal, and certificate allocation for the four full grading services (economy, standard, priority, express). Pre-screen fuzzy reports, regrade/crack-resubmit, grader noise, slab label info-queue rendering, and market sale of graded cards stay out of scope.

## Design Rules

- Hidden condition is generated at acquisition; grading only reveals `Condition.grade(card.condition)`. Paying for faster service never changes the score.
- Time scale presets are configurable: `arcade` (minutes, default), `hobbyist` (hours), `realistic` (days). Durations live in config, not code paths.
- `grading_fee = max(minimum_fee, ceil(RAV * service_rate))` reuses `Economy.grading_fee`; RAV uses the stored card rarity and edition with neutral series heat until the market phase lands.
- Only `raw` cards can be submitted. `queued`, `graded`, `sold`, and `lost` are rejected with reason codes.
- Certificate numbers come exclusively from `Storage.allocate_cert_number` at reveal time, keeping submission order as cert order.
- Reveal happens when the binder opens: `Grading.process_due` flips due cards to `graded`, then a successful reveal saves through `Persistence.save`.
- All player-facing text goes through localization keys; service modules return reason codes only.

## Files

- Create: `src/grading.lua`
  Submission validation, fee charge, queue entries with `due_at`, due processing, queue rows for UI.
- Create: `tests/grading_test.lua`
  Cover duration presets, submit validation and atomicity, reveal grading, cert allocation order.
- Modify: `src/config.lua`
  Add `grading.time_scale` and `grading.durations` defaults for the three presets.
- Modify: `src/binder_ui.lua`
  Process due gradings on open, show revealed notice, queue section with ETA, Grade button on raw rows, `grdl_submit_grading` callback.
- Modify: `tests/binder_ui_test.lua`
  Cover reveal-on-open with save, submit callback wiring, fee map exposure.
- Modify: `localization/en-us.lua`, `localization/zh_CN.lua`
  Grade button, queue title, ETA text, service names, revealed notice, new reason codes.
- Modify: `main.lua`
  Attach `Grading`.
- Modify: `tests/run_all.lua`
  Run the new tests.

## Tasks

### Task 1: Grading Service

- [x] Write `tests/grading_test.lua` with failing tests for duration presets, unknown card, unknown service, insufficient funds atomicity, happy-path submit, double-submit rejection, early/late `process_due`, cert number ordering, and queue rows.
- [x] Run `luajit tests\grading_test.lua` and verify it fails because `src/grading.lua` does not exist.
- [x] Add `grading.time_scale` and `grading.durations` defaults to `src/config.lua`.
- [x] Create `src/grading.lua`.
- [x] Run `luajit tests\grading_test.lua` and verify it passes.

### Task 2: Binder Integration

- [x] Extend `tests/binder_ui_test.lua` with failing tests for reveal-on-open (due entry becomes graded, save triggered, revealed count exposed), grading fee map for raw rows, and the `grdl_submit_grading` runtime callback.
- [x] Run `luajit tests\binder_ui_test.lua` and verify the new assertions fail.
- [x] Extend `src/binder_ui.lua` with due processing on open, queue rows with ETA, fee map, submit handler, and overlay sections.
- [x] Run `luajit tests\binder_ui_test.lua` and verify it passes.

### Task 3: Wiring, Localization, Verification

- [x] Attach `Grading` in `main.lua`.
- [x] Add `dofile("tests/grading_test.lua")` to `tests/run_all.lua`.
- [x] Add new dictionary keys to `localization/en-us.lua` and `localization/zh_CN.lua`.
- [x] Run `luajit tests\run_all.lua`.
- [x] Run LuaJIT bytecode syntax check for every `.lua` file.
- [x] Scan for player-facing text outside `localization/`.
- [x] Commit with message `feat: add PSA grading queue`.

## Acceptance Criteria

- Submitting a raw card charges the fee atomically: any rejection leaves currency, card status, and queue untouched.
- Queue entries persist inside the collection state so quitting the game does not lose submissions.
- A due entry reveals the grade derived from the hidden condition, assigns the next six-digit cert number, stamps `graded_at`, and leaves the queue.
- Opening the binder is sufficient to trigger reveals; no run needs to be played.
- Service tier and time scale changes are config-only.
- No UI literals in `src/` outside localization fallback keys.
