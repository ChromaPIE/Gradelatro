# Gradelatro Binder Collection View and Smoke-Test Remediation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Fix the three smoke-test findings (binder button missing on first options open, variable text rendering as ERROR, text-only binder) and rebuild the binder as a collection-style card grid with native hover tooltips and a PSA slab label info box for graded cards.

**Architecture:** Three commits. First, data-level fixes: the Lovely options patch anchors on the stage-independent `local your_collection = nil` declaration with a local button variable, and all `#1#` strings move into `misc.v_dictionary` because `localize{type='variable'}` only reads `v_dictionary_parsed`. Second, a review-driven refactor extracts shared UI helpers into `ui_common.lua` and consolidates card-field extraction into `catalog.lua`. Third, the binder becomes a real CardArea grid modeled on `create_UIBox_your_collection_jokers`, transactions move to a separate Grading Desk screen (collection cards are not clickable: `highlight_limit = 0` fails `CardArea:can_highlight`), and a wrapped `G.UIDEF.card_h_popup` injects a code-drawn PSA-style red-frame slab label above the hover popup for graded cards (precedent: SealsOnEverything, PotatoPatchUtils).

**Tech Stack:** Lua 5.1/LuaJIT, SMODS, Lovely pattern patches, Balatro CardArea/UIBox.

---

## Root Causes Found

- Binder button: the previous patch payload sat inside the `if G.STAGE == G.STAGES.RUN` branch of `create_UIBox_options()`, so it never ran at the main menu; the payload also leaked a global `grdl_binder` which persisted after one in-run open, explaining the "appears later" behavior.
- ERROR text: `localize{type='variable'}` resolves only `G.localization.misc.v_dictionary_parsed[key]` and returns the literal string `'ERROR'` on a miss. Parameterized keys lived in `misc.dictionary`.
- The en-us font (m6x11plus) does not cover the `Ⓖ` glyph; English strings switch to a plain `G` prefix while zh_CN keeps `Ⓖ`.

## Design Rules

- The binder is display-only: a paged grid of real `Card` objects (authenticated editions applied via `set_edition`) so vanilla hover/info queue works untouched.
- All grading transactions live in the Grading Desk screen reachable from the binder; the desk reuses the row/fee/queue UI and remains fully localized.
- Reveal-on-open processing runs when either the binder or the desk opens.
- The slab label is intentionally rendered in PSA trade-dress English on every locale (uppercase, four lines per the slab spec); it is a stylized artifact, not UI copy, and `Label.slab_lines` stays the single source of its content.
- The hover wrapper must be defensive: install once, `pcall` the injection, and fall back to the unmodified popup on any structural surprise.
- Cards whose center is no longer loaded are hidden from the grid but stay in the data; a localized note reports the hidden count.
- Back navigation: binder returns to the options menu (`back_func = 'options'`), desk returns to the binder.

## Files

- Modify: `lovely.toml`
  Replace the run-branch button patch with one anchored at `local your_collection = nil` (unique, both stages, local variable).
- Modify: `localization/en-us.lua`, `localization/zh_CN.lua`
  Add `misc.v_dictionary` with every parameterized key; en strings use `G`; add desk/binder-grid keys; drop unused `grdl_k_currency`.
- Create: `src/ui_common.lua`
  ERROR-aware localize helpers, UI node builders, event ref-table id extraction.
- Modify: `src/catalog.lua`
  Add `mod_name` to entries; absorb `center_key_from_card` and `edition_from_card`.
- Modify: `src/buyout.lua`, `src/run_end.lua`
  Consume the catalog helpers; drop local duplicates.
- Modify: `src/binder.lua`
  Replace `card_rows` with `entries` (missing-center detection via optional centers table), `page` math, and `desk_rows`.
- Create: `src/slab_ui.lua`
  Pure `label_args` mapping, UIT label box builder, pure popup-tree `inject`, idempotent `install` wrapping `G.UIDEF.card_h_popup`.
- Modify: `src/binder_ui.lua`
  Grid overlay with page cycle (`grdl_binder_page`), desk overlay (`grdl_open_desk`), submit callback, reveal-on-open, hover index for slab data.
- Modify: `src/buyout_ui.lua`
  Consume `ui_common`; remove duplicated helpers and dead text key.
- Modify: `main.lua`, `tests/run_all.lua`
  Attach `UICommon`/`SlabUI`; run new tests.
- Modify/Create: `tests/binder_test.lua`, `tests/binder_ui_test.lua`, `tests/slab_ui_test.lua`, `tests/catalog_test.lua`, `tests/buyout_test.lua`
  Cover the new models and moved helpers.

## Tasks

### Task 1: Menu Entry and Localization Fixes (commit `fix: binder menu entry and variable localization`)

- [ ] Rewrite the options-menu Lovely patch anchored at `local your_collection = nil` with a local `grdl_binder` and pcall-wrapped runtime install.
- [ ] Verify both patterns hit exactly once against the game dump.
- [ ] Restructure both localization files: parameterized keys into `misc.v_dictionary`, en `Ⓖ` -> `G`.
- [ ] Run `luajit tests\run_all.lua` and bytecode checks; commit.

### Task 2: Review Refactor (commit `refactor: extract shared ui and catalog helpers`)

- [ ] Write failing tests for `Catalog.center_key_from_card`, `Catalog.edition_from_card`, and `mod_name` on entries.
- [ ] Move the helpers into `catalog.lua`; update `buyout.lua`/`run_end.lua` and their tests.
- [ ] Create `src/ui_common.lua`; switch `buyout_ui.lua` to it; remove `grdl_k_currency`.
- [ ] Run the full suite; commit.

### Task 3: Binder Grid, Desk, Slab Label (commit `feat: binder collection grid with slab labels`)

- [ ] Write failing tests for `Binder.entries`/`Binder.page`/`Binder.desk_rows`, slab `label_args`/`inject`, and the reworked `BinderUI` state machine (open processes due gradings, desk fees, submit callback, page changes).
- [ ] Implement `binder.lua` model changes.
- [ ] Implement `slab_ui.lua` with the red-frame label drawn from `Label.slab_lines` data.
- [ ] Rewrite `binder_ui.lua`: grid overlay, page cycle, desk overlay, callbacks, slab install on open.
- [ ] Add localization keys for desk, page note, hidden-card note.
- [ ] Wire `main.lua` and `tests/run_all.lua`; run the full suite and bytecode checks; commit.

## Acceptance Criteria

- Binder button appears in the options menu on first open at the main menu and in-run, with no leaked globals.
- No `ERROR` strings: every parameterized key resolves through `v_dictionary`; en shows `G` amounts, zh shows `Ⓖ`.
- Binder renders owned cards as real cards with editions; hovering shows the vanilla tooltip plus, for graded cards, the PSA-style red-frame slab label (year + mod, key + grade text, edition + grade number, cert number; all uppercase).
- Grading submissions and the queue live in the desk screen; reveal still happens on open; all desk text localized.
- No duplicated `safe_localize`/node-builder/card-field helpers remain across UI and service modules.
- Full LuaJIT suite passes; all Lovely patterns single-hit against the current dump.
