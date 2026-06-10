# Gradelatro Market MVP Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add the simulated market layer: per-series heat that drifts over real time and influences prices, plus a market screen where players sell raw or graded cards to the system for G.

**Architecture:** A pure `Market` service owns the heat engine and sell flow, persisted inside the collection's `market` table. Heat follows the confirmed model (`baseline + slow trend walk + phased cycle + occasional event bump`, clamped to the configured band) and refreshes at most once per cooldown window using a seedable RNG so tests stay deterministic. The UI is a `MarketUI` overlay reached from the binder, following the desk pattern: heat board with localized trend words (never formulas), sellable card rows with live quotes, and a two-step confirm because selling permanently removes the card. Run-end capture refreshes heat and feeds the heat map into buyout pricing, closing the economic loop.

**Tech Stack:** Lua 5.1/LuaJIT, SMODS config persistence.

---

## Design Rules

- The market is immersion-grade simulation only: no real-world data, trend words instead of numbers, influence capped by `heat_min`/`heat_max`.
- Heat is keyed by `series_id` (the mod id), matching the catalog and the buyout `series_heat` argument.
- Refresh is cooldown-gated (default one real day) and seedable; entries initialize at 1.0 and only walk on refresh.
- Valuation shares the RAV anchor: graded cards use `RAV * grade_multiplier`, raw cards use `RAV * raw_sell_factor`; the system buys at the midpoint of the configured buy band, keeping `buyout + grading fee` above the raw resale value (anti-arbitrage).
- Selling is permanent: status flips to `sold` with `sold_at`/`sold_price`; queued, lost, or sold cards are rejected with reason codes.
- The sell button requires a second confirming click on the same card; failures update bound text in place with the fail sound, successes rebuild and report the payout.

## Files

- Create: `src/market.lua` — heat engine, trend labels, valuation, quotes, sell, sell rows.
- Create: `tests/market_test.lua` — deterministic heat refresh, cooldown, clamping, labels, valuation math, sell state machine.
- Modify: `src/config.lua` — market defaults: refresh cooldown, raw sell factor, trend/cycle/event knobs.
- Create: `src/market_ui.lua` + `tests/market_ui_test.lua` — overlay state, two-step sell, runtime callbacks.
- Modify: `src/binder_ui.lua` — market button beside the desk button.
- Modify: `src/run_end.lua` + `tests/run_end_test.lua` — refresh heat on win capture, pass heat map into the buyout offer.
- Modify: `localization/en-us.lua`, `localization/zh_CN.lua` — market title/buttons, trend words, sold/reason texts.
- Modify: `main.lua`, `tests/run_all.lua`.

## Tasks

### Task 1: Market Service (commit `feat: market heat engine and system sales`)

- [x] Write failing `tests/market_test.lua`: refresh initializes/walks heat deterministically by seed, cooldown no-op, force flag, clamping, trend labels, heat map defaults, graded/raw valuation and quotes (with and without heat), sell happy path and rejections, sell rows.
- [x] Add market defaults to `src/config.lua`.
- [x] Implement `src/market.lua`; run the test green; commit.

### Task 2: UI and Integration (commit `feat: market screen with heat board`)

- [x] Write failing `tests/market_ui_test.lua`: open refreshes heat once per cooldown, sell rows with quotes, two-step confirm, failure keeps state in place with reason text, success rebuilds and reports payout, runtime callbacks.
- [x] Implement `src/market_ui.lua`; add the binder button; register callbacks.
- [x] Wire `RunEnd.capture_win_buyout_offer` to refresh heat and pass the heat map to `Buyout.prepare_offer`; update `tests/run_end_test.lua` with a pinned market state for deterministic prices.
- [x] Localization keys for both locales; attach modules in `main.lua`; extend `tests/run_all.lua`.
- [x] Full suite + bytecode + text scan; commit.

## Acceptance Criteria

- Same seed and inputs produce identical heat; heat never leaves the configured band; refresh inside the cooldown changes nothing.
- Selling a Gem Mint common at neutral heat pays `floor(35 * 6.0 * 0.76) = 159`; raw resale stays below buyout-plus-fee.
- Sold cards leave the binder/desk views permanently but stay in the data with sale metadata.
- Buyout offers after a win price through the current heat map.
- All market-facing text localized except numbers; trend words only.
