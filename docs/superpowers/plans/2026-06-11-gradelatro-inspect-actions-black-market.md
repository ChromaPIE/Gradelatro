# Gradelatro Inspect Actions and Black Market Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Consolidate all card transactions into the G-key inspect view with thin-outline action buttons, reduce the desk to a pure grading-progress board, and rebuild the market as a visual screen with a Black Market buy tab (boss-blind dealer with speech quips, three card offers including a gamble slot) and the Trends tab.

**Architecture:** Four slices. (A) Page flips reuse the `change_tab` mechanism — swap the `tab_contents` UIE object in place and recalculate, killing the overlay rebuild animation; every paged screen keeps a tab container (single-tab where needed). (B) The inspect view gains an outline-button action row (carry / submit-with-fee / sell-with-quote two-step); the desk drops submission entirely; the market temporarily keeps only Trends. (C) A pure `BlackMarket` service generates three offers on every won run — two open offers (raw or graded at premium, small-to-medium price float) and one mystery offer rendered undiscovered with a wider float band — priced through RAV, heat, and the system-sell premium band. (D) The Black Market tab: a boss-blind dealer in a speech bubble (vanilla `Card_Character:add_speech_bubble` pattern, quips in a freely editable localization array, "win a run to unlock" before the first win), three real card objects with outline buy buttons, G-inspect with a single buy+price action (mystery slot exempt from inspect to stay hidden).

**Tech Stack:** Lua 5.1/LuaJIT, SMODS, Balatro CardArea/UIBox/AnimatedSprite.

---

## Confirmed Mechanics (dump-verified)

- `G.FUNCS.change_tab` swaps `tab_contents.config.object` with a fresh UIBox from the tab definition and calls `UIBox:recalculate()` — no overlay rebuild. Pagination callbacks will do the same swap for the current tab.
- `Card_Character:add_speech_bubble(text_key, align, loc_vars, quip_args)` is the vanilla talking-head API; the dealer reuses its bubble/jiggle approach with the last-defeated boss blind icon as the face.
- Outline-style buttons: plain UIT containers with `colour = CLEAR, outline, outline_colour, button, hover` — code-drawn, no assets.

## Design Decisions (organized from the draft)

- Inspect action row (right panel, under details): `带入赛局/收回` plus `送评 + GXXX` (raw only) plus `出售 + GXXX` (raw or graded; two-click confirm, red outline when armed). All thin white outline, label and price stacked.
- Desk = grading progress only: single `评级进度` tab (keeps the tab container for animation-free paging), queue rows with progress bars, reveal notice. No fees, no submit rows.
- Black market offers: persisted in `collection.market.black_market`; regenerated on each win capture (run-id guarded against double generation); slots 1-2 visible (graded chance with premium), slot 3 mystery (undiscovered visual via a discovery-masked center copy, identity revealed on purchase, wider float band, higher big-float chance). Prices: `value = RAV(rarity, edition, heat) [* grade_mult if graded]`, offer price = `value * uniform(system_sell band) * float`; floats configurable (open ±15%, mystery 0.5x-2.0x with weighted tails). Purchase: funds check, add to collection (graded purchases allocate the next cert number), slot consumed until next win.
- Dealer face: boss blind key captured at win; before any win the tab shows only the localized "win a run to unlock" notice. Entering the tab triggers one random quip from `grdl_quips_black_market` (a plain string array in each localization file, freely editable).

## Tasks

### Slice A (commit `fix: in-place tab pagination`)

- [ ] `UICommon.swap_tab_contents(definition_fn)` mirroring `change_tab`; page callbacks swap in place with adapter refresh as fallback.

### Slice B (commit `feat: inspect action buttons and progress-only desk`)

- [ ] Outline action button helper in the inspect view; carry button migrated to it.
- [ ] `送评 + fee` (one click) and `出售 + quote` (two-click confirm) actions with handlers, reusing `BinderUI.submit_grading` and `Market.sell`.
- [ ] Desk reduced to the single progress tab; submission UI, fee map, and `Binder.desk_rows` removed with their tests and stale keys.
- [ ] Market reduced to the Trends tab; sell flow removed from `market_ui` (tests rewritten).

### Slice C (commit `feat: black market offers`)

- [ ] `src/black_market.lua` + config bands + deterministic tests (generation on win, slot composition, float bounds, purchase atomicity, cert allocation, double-generation guard).
- [ ] Win capture wiring (boss key + offer refresh).

### Slice D (commit `feat: black market screen`)

- [ ] Dealer column (blind icon + speech bubble + jiggle + entry quip), offers row with real cards and outline buy buttons, mystery undiscovered rendering, G-inspect buy action for open slots.
- [ ] Locked state before first win; localization (quips array + UI keys); smoke checklist.

## Acceptance Criteria

- Page flips never replay the overlay enter/exit animation on any screen.
- Inspect shows exactly the applicable actions per status; selling and submitting from inspect behave identically to the old flows (same services, same persistence).
- Black market offers are reproducible by seed, priced within the configured bands, regenerate only on a new won run, and the mystery slot stays visually hidden until bought.
- All new text localized except PSA trade dress; quips live in one editable array per locale.
