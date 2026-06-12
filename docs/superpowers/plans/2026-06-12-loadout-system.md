# Loadout System Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the carry/peek-card system with the loadout system per `docs/superpowers/specs/2026-06-12-loadout-system-design.md`: 12-level license ladder, five transport schedules, graded/raw loadout membership, boss-payout entry windows, and the six-tier proficiency progression.

**Architecture:** Three new modules — `src/loadout.lua` (pure membership/license/transport/schedule logic), `src/proficiency.lua` (pure counting/perk-gate logic), `src/loadout_ui.lua` (screens, entry popup, run hooks) — plus surgical extensions to `binder_ui.lua` (G-view buttons), `slab_ui.lua` (tooltip info box + tint), and full demolition of `carry.lua`/`carry_ui.lua`.

**Tech Stack:** Lua 5.1 (LuaJIT), SMODS + Lovely Balatro mod. Headless tests via `dofile`, no test framework.

---

## Project conventions (read once, apply to every task)

- **Test command (always full output, never truncate):**
  `C:/Users/ChromaPIE/AppData/Local/Programs/LuaJIT/bin/luajit.exe tests/run_all.lua` from repo root `C:/Users/ChromaPIE/AppData/Roaming/Balatro/Mods/Gradelatro`.
- **Bytecode check each changed .lua:** `luajit.exe -bl <file> > /dev/null` → expect exit 0.
- **Text-leak scan after src changes:** `grep -rn $'[\xe4-\xe9]' src/*.lua` → expect no output (no hardcoded CJK in src; all user strings via localization keys).
- **Localization:** every new key goes to BOTH `localization/en-us.lua` and `localization/zh_CN.lua`, in the inner `dictionary` table (same nesting as existing `grdl_k_*` keys). zh file is UTF-8; edit it with a Python script via Bash heredoc if your editor tooling corrupts CJK (precedent in repo history).
- **Module header template** (used by every src module):

```lua
local function load_src(path)
    if rawget(_G, "SMODS") and SMODS.load_file then
        return assert(SMODS.load_file("src/" .. path))()
    end
    return dofile("src/" .. path)
end
```

- **Test header template:** `local H = dofile("tests/test_helper.lua")` then `dofile("src/<module>.lua")` style requires (see any existing test). `H.assert_equal(actual, expected, msg)`, `H.assert_true(v, msg)`, `H.assert_near(a, b, eps, msg)`.
- **UI runtime calls** that touch game objects are `pcall`'d. UI text via `UICommon.localize_text` (alias `safe_localize`), which falls back to the key string when `localize` is absent — tests assert key strings.
- **Commit after every green task** with the message given in the task.

### Engine facts established during research (trust these, do not re-derive)

- `G.FUNCS.cash_out(e)` (button_callbacks.lua:3349) runs on the payout button click for EVERY round. Inside it, vanilla itself uses `G.GAME.round_resets.blind_states.Boss == 'Defeated'` to detect a boss cash-out. At that moment `ease_ante(1)` has already run, so the defeated ante = `G.GAME.round_resets.ante - 1`.
- `info_tip_from_rows(desc_nodes, name)` (UI_definitions.lua:1386) is the vanilla info-queue box builder. `desc_nodes` = array of row-node-arrays; each entry is wrapped in a `G.UIT.R`. Optional `desc_nodes.background_colour`.
- `create_text_input(args)` (UI_definitions.lua:2811): args `{ ref_table, ref_value, max_length (default 16), prompt_text, all_caps, w, h, text_scale }`. Binds the typed string into `ref_table[ref_value]`. ASCII corpus only — acceptable per spec.
- `Card:set_eternal(_eternal)` exists (card.lua:696).
- `SMODS.add_card{ key=..., edition="e_<x>" | no_edition=true }` spawns into `G.jokers` ignoring UI purchase limits; negative editions bump `card_limit` (= "0-slot") automatically via `set_edition`.
- slab_ui's `G.UIDEF.card_h_popup` wrap + `popup_column(popup)` navigation (`popup.nodes[1].nodes`) is the proven tooltip-injection channel.
- `UIElement:remove()` removes `config.object`; `Node:remove()` cascades `children` — attached UIBoxes/sprites clean up with their parents.

---

### Task 1: Demolish carry, migrate saves, rename wear config

**Files:**
- Delete: `src/carry.lua`, `src/carry_ui.lua`, `tests/carry_test.lua`, `tests/carry_ui_test.lua`
- Create: `src/loadout.lua` (minimal: `run_identity` only), `tests/loadout_test.lua` (minimal)
- Modify: `src/storage.lua` (migration), `src/config.lua` (`carry` → `wear`), `src/binder_ui.lua` (strip carry), `src/binder.lua` (drop `carried` status key), `src/run_end.lua` (use Loadout.run_identity), `main.lua` (drop Carry/CarryUI wiring), `tests/run_all.lua`, `tests/binder_ui_test.lua` (drop carry block), `tests/config_test.lua` + `tests/storage_test.lua` (new assertions), `localization/en-us.lua` + `localization/zh_CN.lua` (drop carry keys)

- [ ] **Step 1: Write the failing migration test.** In `tests/storage_test.lua`, append before the final `print`:

```lua
local migrated = Storage.normalize({
    cards = {
        { id = "grdl_m1", center_key = "j_joker", status = "carried", edition = "base" }
    },
    carry = { card_id = "grdl_m1", run_id = "OLD" }
})
H.assert_equal(migrated.cards[1].status, "raw", "legacy carried card migrates to raw")
H.assert_equal(migrated.carry, nil, "legacy carry block cleared")
```

And in `tests/config_test.lua`, locate every assertion referencing `config.carry` and change the table name to `config.wear` (keep the assertions themselves). Add one new line near them:

```lua
H.assert_equal(config.carry, nil, "carry config renamed to wear")
```

- [ ] **Step 2: Run suite, verify the new assertions fail** (`expected raw, got carried` and/or `carry config renamed`). Run the full-suite command. Carry tests still pass at this point.

- [ ] **Step 3: Implement migration + rename.**
  - `src/config.lua`: rename the `carry = { ... }` block in `Config.DEFAULTS` to `wear = { ... }` (same six chance/min/max fields).
  - `src/storage.lua`: inside `Storage.normalize`, after the existing per-card normalization loop, add:

```lua
    for _, card in ipairs(state.cards) do
        if card.status == "carried" then card.status = "raw" end
    end
    state.carry = nil
```

- [ ] **Step 4: Create minimal `src/loadout.lua`** (so `run_end.lua` keeps a `run_identity` provider after carry.lua dies):

```lua
local Loadout = {}

function Loadout.run_identity(game_state)
    game_state = game_state or {}
    if game_state.run_id then return tostring(game_state.run_id) end
    if game_state.pseudorandom and game_state.pseudorandom.seed then
        return tostring(game_state.pseudorandom.seed)
    end
    if game_state.seed then return tostring(game_state.seed) end
    return "unknown"
end

return Loadout
```

(Copy the exact body from `Carry.run_identity` in `src/carry.lua` before deleting — including its final fallback return line if it differs from the above.)

Create `tests/loadout_test.lua`:

```lua
local H = dofile("tests/test_helper.lua")
local Loadout = dofile("src/loadout.lua")

H.assert_equal(Loadout.run_identity({ pseudorandom = { seed = "ABC" } }), "ABC", "run identity from seed")
H.assert_equal(Loadout.run_identity({}), "unknown", "run identity fallback")

print("loadout tests ok")
```

- [ ] **Step 5: Strip carry from consumers.**
  - `src/run_end.lua`: replace `local Carry = load_src("carry.lua")` with `local Loadout = load_src("loadout.lua")`, and `local run_id = Carry.run_identity` with `local run_id = Loadout.run_identity`.
  - `src/binder_ui.lua`: remove `local Carry = load_src("carry.lua")` (line ~11); remove the carry-reconcile block inside `BinderUI.open` (lines ~115-120, the `if namespace.collection.carry then ... end` block); remove `BinderUI.toggle_carry` entirely (lines ~251-280); remove the carry button block in `inspect_action_row` (lines ~671-678, the `if entry.status == "raw" and in_run_now and not (... collection.carry) then ... grdl_carry_toggle ...` block — keep the `in_run_now` local, Task 5 reuses it); remove the `runtime.FUNCS.grdl_carry_toggle = function ...` handler (lines ~845-858).
  - `src/binder.lua`: remove the `carried = "grdl_k_status_carried",` line from `STATUS_KEYS`.
  - `main.lua`: remove lines 50-55 (the `Carry` and `CarryUI` load/attach/install block) and insert in their place:

```lua
local Loadout = load_src("loadout.lua")
Bootstrap.attach(Gradelatro, "Loadout", Loadout)
```

  - `tests/run_all.lua`: replace the two lines `dofile("tests/carry_test.lua")` / `dofile("tests/carry_ui_test.lua")` with `dofile("tests/loadout_test.lua")`.
  - `tests/binder_ui_test.lua`: delete the carry-toggle block (the lines between the `grdl_carry_toggle` registration assert and the `grdl_inspect_sell` registration assert — search `toggle_carry` and `carry`, remove all such asserts incl. the fake `_G.G = { STAGE = 1, STAGES = { RUN = 1 }, ...}` block used only there).
  - Delete files: `src/carry.lua`, `src/carry_ui.lua`, `tests/carry_test.lua`, `tests/carry_ui_test.lua` (`git rm`).

- [ ] **Step 6: Remove carry localization keys from BOTH locale files.** Grep `carry` in `localization/` — remove every matching key line (`grdl_b_carry`, `grdl_b_activate_carry`, `grdl_k_carry_active`, `grdl_k_reason_carry_taken`, `grdl_k_reason_carry_locked`, `grdl_k_reason_no_carry`, and any other `carry`-named keys present), plus `grdl_k_status_carried` and `grdl_k_reason_not_in_run`. KEEP `grdl_k_reason_spawn_failed` and `grdl_k_reason_insufficient_funds` (reused later). After removal run `grep -rn "carry" src/ localization/ tests/ main.lua` — expect zero hits (except the word inside `modifiers.carryover` if it ever appears in dump references — none in our tree).

- [ ] **Step 7: Run full suite → all green; bytecode-check every changed file; leak scan.**

- [ ] **Step 8: Commit** — `git add -A` then:

```
refactor: demolish carry system, migrate saves to loadout era

Removes carry/peek-card modules, strips binder carry actions,
migrates legacy carried cards back to raw and clears the old
carry block, renames config.carry to config.wear, and seeds
src/loadout.lua with the shared run_identity helper.
```

---

### Task 2: Loadout core (licenses, matrix, transports, schedule)

**Files:**
- Modify: `src/loadout.lua` (full core), `src/config.lua` (add `loadout` defaults), `src/storage.lua` (normalize `state.loadout`), `tests/loadout_test.lua` (full), `tests/config_test.lua` (loadout defaults sanity)

- [ ] **Step 1: Write the failing tests.** Replace `tests/loadout_test.lua` with:

```lua
local H = dofile("tests/test_helper.lua")
local Config = dofile("src/config.lua")
local Storage = dofile("src/storage.lua")
local Loadout = dofile("src/loadout.lua")

local config = Config.normalize({})

H.assert_equal(Loadout.run_identity({ pseudorandom = { seed = "ABC" } }), "ABC", "run identity from seed")
H.assert_equal(Loadout.run_identity({}), "unknown", "run identity fallback")

-- config shape
H.assert_equal(#config.loadout.license_prices, 12, "twelve license prices")
H.assert_true(config.loadout.license_prices[12] > config.loadout.license_prices[1], "prices ascend")
H.assert_true(config.loadout.transports.gold.price > config.loadout.transports.blue.price, "gold transport priciest")

-- tier/capacity math
H.assert_equal(Loadout.capacity(0), 0, "no license no capacity")
H.assert_equal(Loadout.capacity(1), 1, "entry x1 capacity")
H.assert_equal(Loadout.capacity(2), 2, "entry x2 capacity")
H.assert_equal(Loadout.capacity(3), 3, "entry x3 capacity")
H.assert_equal(Loadout.capacity(12), 3, "capacity caps at three")
H.assert_equal(Loadout.tier(1), 1, "level one is entry tier")
H.assert_equal(Loadout.tier(12), 4, "level twelve is g-cert tier")
H.assert_equal(Loadout.within(5), 2, "level five is x2")
H.assert_equal(Loadout.rarity_rank("common"), 1, "common rank")
H.assert_equal(Loadout.rarity_rank("legendary"), 4, "legendary rank")
H.assert_equal(Loadout.rarity_rank("cry_exotic"), 4, "modded rarity ranks as top tier")

local mint = { centering = 9.8, print_quality = 9.8, corners = 9.8, edges = 9.8, surface = 9.8 }
local state = Storage.normalize({ currency_g = 100000 })
local function add(rarity, status)
    local card = Storage.add_raw_card(state, {
        center_key = "j_" .. rarity .. tostring(math.random(1e6)),
        local_key = rarity, rarity = rarity, edition = "base",
        condition = { centering = 9.8, print_quality = 9.8, corners = 9.8, edges = 9.8, surface = 9.8 },
        acquired_at = 1000
    })
    if status then card.status = status end
    return card
end

H.assert_equal(state.loadout.license, 0, "normalize seeds loadout block")

-- sequential license purchase
H.assert_equal(Loadout.purchase_license(config, state).level, 1, "first purchase reaches level one")
local spent = 100000 - state.currency_g
H.assert_equal(spent, config.loadout.license_prices[1], "level one price charged")
local broke = Storage.normalize({ currency_g = 0 })
H.assert_equal(Loadout.purchase_license(config, broke).reason, "insufficient_funds", "broke purchase rejected")
for _ = 2, 12 do Loadout.purchase_license(config, state) end
H.assert_equal(state.loadout.license, 12, "ladder completes")
H.assert_equal(Loadout.purchase_license(config, state).reason, "maxed", "thirteenth purchase rejected")

-- matrix validation: the six spec examples
local function check(level, rarities, expected_reason)
    local probe = Storage.normalize({})
    probe.loadout.license = level
    local ids = {}
    for _, rarity in ipairs(rarities) do
        local card = Storage.add_raw_card(probe, {
            center_key = "j_x" .. tostring(#ids), local_key = "x", rarity = rarity,
            edition = "base", condition = mint, acquired_at = 1
        })
        ids[#ids + 1] = card.id
    end
    local result = Loadout.validate(probe, ids)
    if expected_reason then
        H.assert_equal(result.reason, expected_reason, "level " .. level .. " rejects: " .. expected_reason)
    else
        H.assert_equal(result.ok, true, "level " .. level .. " accepts " .. #rarities .. " cards")
    end
end
check(1, { "common" })                                    -- 入门X1: 1 common
check(1, { "uncommon" }, "rarity_locked")                 -- 入门X1: no uncommon
check(1, { "common", "common" }, "over_capacity")         -- 入门X1: one card only
check(3, { "common", "common", "common" })                -- 入门X3: 3 commons
check(4, { "common", "common", "uncommon" })              -- 进阶X1: ≤1 uncommon
check(4, { "common", "uncommon", "uncommon" }, "rarity_quota")
check(8, { "uncommon", "rare", "rare" })                  -- 专业X2: all-uncommon ok, ≤2 rare
check(8, { "rare", "rare", "rare" }, "rarity_quota")
check(10, { "rare", "rare", "legendary" })                -- G-Cert X1: ≤1 legendary
check(10, { "rare", "legendary", "legendary" }, "rarity_quota")
check(12, { "legendary", "legendary", "cry_exotic" })     -- G-Cert X3: unlimited

-- membership
state.loadout.card_ids = {}
local c1 = add("common")
local c2 = add("common")
H.assert_equal(Loadout.add_card(state, c1.id).ok, true, "add accepted")
H.assert_equal(Loadout.add_card(state, c1.id).reason, "duplicate", "duplicate rejected")
H.assert_equal(Loadout.contains(state, c1.id), true, "contains reports membership")
local queued = add("common", "queued")
H.assert_equal(Loadout.add_card(state, queued.id).reason, "invalid_status", "queued card rejected")
H.assert_equal(Loadout.add_card(state, "grdl_nope").reason, "unknown_card", "unknown card rejected")
Loadout.add_card(state, c2.id)
c2.status = "sold"
H.assert_equal(Loadout.reconcile(state).removed, 1, "reconcile drops sold members")
H.assert_equal(#state.loadout.card_ids, 1, "membership shrinks after reconcile")
H.assert_equal(Loadout.remove_card(state, c1.id).ok, true, "remove accepted")
H.assert_equal(Loadout.remove_card(state, c1.id).reason, "not_in_loadout", "double remove rejected")

-- transports
H.assert_equal(Loadout.purchase_transport(config, state, "nope").reason, "unknown_transport", "unknown transport rejected")
H.assert_equal(Loadout.purchase_transport(config, state, "blue").ok, true, "blue purchased")
H.assert_equal(state.loadout.active_transport, "blue", "first transport auto-activates")
H.assert_equal(Loadout.purchase_transport(config, state, "blue").reason, "already_owned", "double purchase rejected")
Loadout.purchase_transport(config, state, "gold")
H.assert_equal(Loadout.set_active_transport(state, "gold").ok, true, "owned transport activates")
H.assert_equal(Loadout.set_active_transport(state, "red").reason, "not_owned", "unowned transport rejected")

-- schedule windows
state.loadout.card_ids = {}
local g1 = add("common")
local g2 = add("common")
local g3 = add("common")
Loadout.add_card(state, g1.id); Loadout.add_card(state, g2.id); Loadout.add_card(state, g3.id)
local run_state = Loadout.begin_run(state, "RUN1")
H.assert_equal(run_state.transport, "gold", "run snapshot captures active transport")
H.assert_equal(Loadout.window(config, state, run_state, 2), nil, "gold has no ante-two window")
local window = Loadout.window(config, state, run_state, 1)
H.assert_equal(window.picks, 2, "gold first window allows two")
H.assert_equal(#window.card_ids, 3, "all members offered")
Loadout.mark_entered(run_state, g1.id)
Loadout.mark_entered(run_state, g2.id)
local second = Loadout.window(config, state, run_state, 4)
H.assert_equal(second.picks, 1, "gold second window capped by schedule and remainder")
H.assert_equal(#second.card_ids, 1, "entered cards excluded")
H.assert_equal(second.card_ids[1], g3.id, "remaining card offered")
Loadout.mark_entered(run_state, g3.id)
H.assert_equal(Loadout.window(config, state, run_state, 4), nil, "exhausted loadout opens no window")
local no_transport = Loadout.begin_run(Storage.normalize({}), "RUN2")
H.assert_equal(Loadout.window(config, state, no_transport, 1), nil, "no transport no window")

-- wear roll
local tier, intensity = Loadout.roll_wear(config, 42)
H.assert_true(tier == "minor" or tier == "moderate" or tier == "severe", "wear tier named")
H.assert_true(intensity > 0, "wear intensity positive")
local tier2, intensity2 = Loadout.roll_wear(config, 42)
H.assert_equal(tier, tier2, "wear roll deterministic")
H.assert_near(intensity, intensity2, 1e-9, "wear intensity deterministic")

print("loadout tests ok")
```

- [ ] **Step 2: Run suite → loadout_test fails** (`license_prices` nil etc.).

- [ ] **Step 3: Implement.**
  - `src/config.lua`, add to `Config.DEFAULTS` after the `black_market` block:

```lua
    loadout = {
        license_prices = { 80, 160, 300, 500, 750, 1050, 1400, 1850, 2400, 3200, 4200, 5500 },
        transports = {
            blue   = { price = 200,  antes = { 5, 6, 7 }, picks = { 1, 1, 1 } },
            green  = { price = 450,  antes = { 3, 5, 7 }, picks = { 1, 1, 1 } },
            red    = { price = 800,  antes = { 2, 4, 6 }, picks = { 1, 1, 1 } },
            purple = { price = 1400, antes = { 1, 3, 5 }, picks = { 1, 1, 1 } },
            gold   = { price = 2200, antes = { 1, 4 },    picks = { 2, 1 } }
        }
    },
```

  - `src/storage.lua`, in `Storage.normalize` after the migration lines from Task 1:

```lua
    state.loadout = type(state.loadout) == "table" and state.loadout or {}
    state.loadout.license = tonumber(state.loadout.license) or 0
    state.loadout.transports = type(state.loadout.transports) == "table" and state.loadout.transports or {}
    state.loadout.card_ids = type(state.loadout.card_ids) == "table" and state.loadout.card_ids or {}
```

  - `src/loadout.lua`, full module (keep `run_identity`, add the rest):

```lua
local Loadout = {}

local function load_src(path)
    if rawget(_G, "SMODS") and SMODS.load_file then
        return assert(SMODS.load_file("src/" .. path))()
    end
    return dofile("src/" .. path)
end

local Rng = load_src("rng.lua")
local Storage = load_src("storage.lua")

local MAX_LEVEL = 12
local RARITY_RANK = { common = 1, uncommon = 2, rare = 3, legendary = 4 }

function Loadout.run_identity(game_state)
    -- (unchanged from Task 1)
end

local function ensure(state)
    state.loadout = type(state.loadout) == "table" and state.loadout or {}
    local loadout = state.loadout
    loadout.license = tonumber(loadout.license) or 0
    loadout.transports = type(loadout.transports) == "table" and loadout.transports or {}
    loadout.card_ids = type(loadout.card_ids) == "table" and loadout.card_ids or {}
    return loadout
end

function Loadout.rarity_rank(rarity)
    return RARITY_RANK[tostring(rarity or "common")] or 4
end

function Loadout.tier(level) return math.ceil(level / 3) end
function Loadout.within(level) return ((level - 1) % 3) + 1 end

function Loadout.capacity(level)
    if level <= 0 then return 0 end
    if level >= 3 then return 3 end
    return level
end

local function eligible_status(status)
    return status == "raw" or status == "graded"
end

function Loadout.validate(state, card_ids)
    local loadout = ensure(state)
    local level = loadout.license
    if #card_ids > Loadout.capacity(level) then return { ok = false, reason = "over_capacity" } end
    local top = level > 0 and Loadout.tier(level) or 0
    local quota = level > 0 and Loadout.within(level) or 0
    local seen = {}
    local top_count = 0
    for _, card_id in ipairs(card_ids) do
        if seen[card_id] then return { ok = false, reason = "duplicate" } end
        seen[card_id] = true
        local card = Storage.find_card(state, card_id)
        if not card then return { ok = false, reason = "unknown_card" } end
        if not eligible_status(card.status) then return { ok = false, reason = "invalid_status" } end
        local rank = Loadout.rarity_rank(card.rarity)
        if rank > top then return { ok = false, reason = "rarity_locked" } end
        if rank == top then
            top_count = top_count + 1
            if top_count > quota then return { ok = false, reason = "rarity_quota" } end
        end
    end
    return { ok = true }
end

function Loadout.contains(state, card_id)
    for _, id in ipairs(ensure(state).card_ids) do
        if id == card_id then return true end
    end
    return false
end

function Loadout.add_card(state, card_id)
    local loadout = ensure(state)
    local candidate = {}
    for index, id in ipairs(loadout.card_ids) do
        if id == card_id then return { ok = false, reason = "duplicate" } end
        candidate[index] = id
    end
    candidate[#candidate + 1] = card_id
    local checked = Loadout.validate(state, candidate)
    if not checked.ok then return checked end
    loadout.card_ids = candidate
    return { ok = true, count = #candidate }
end

function Loadout.remove_card(state, card_id)
    local loadout = ensure(state)
    for index, id in ipairs(loadout.card_ids) do
        if id == card_id then
            table.remove(loadout.card_ids, index)
            return { ok = true, count = #loadout.card_ids }
        end
    end
    return { ok = false, reason = "not_in_loadout" }
end

function Loadout.reconcile(state)
    local loadout = ensure(state)
    local kept = {}
    local removed = 0
    for _, id in ipairs(loadout.card_ids) do
        local card = Storage.find_card(state, id)
        if card and eligible_status(card.status) then
            kept[#kept + 1] = id
        else
            removed = removed + 1
        end
    end
    loadout.card_ids = kept
    return { removed = removed }
end

function Loadout.next_license(config, state)
    local level = ensure(state).license
    if level >= MAX_LEVEL then return nil end
    return level + 1, config.loadout.license_prices[level + 1]
end

function Loadout.purchase_license(config, state)
    local loadout = ensure(state)
    if loadout.license >= MAX_LEVEL then return { ok = false, reason = "maxed" } end
    local price = config.loadout.license_prices[loadout.license + 1]
    if not Storage.spend_currency(state, price) then
        return { ok = false, reason = "insufficient_funds", price = price }
    end
    loadout.license = loadout.license + 1
    return { ok = true, level = loadout.license, price = price }
end

function Loadout.purchase_transport(config, state, key)
    local loadout = ensure(state)
    local transport = config.loadout.transports[key]
    if not transport then return { ok = false, reason = "unknown_transport" } end
    if loadout.transports[key] then return { ok = false, reason = "already_owned" } end
    if not Storage.spend_currency(state, transport.price) then
        return { ok = false, reason = "insufficient_funds", price = transport.price }
    end
    loadout.transports[key] = true
    if not loadout.active_transport then loadout.active_transport = key end
    return { ok = true, transport = key }
end

function Loadout.set_active_transport(state, key)
    local loadout = ensure(state)
    if key ~= nil and not loadout.transports[key] then return { ok = false, reason = "not_owned" } end
    loadout.active_transport = key
    return { ok = true }
end

function Loadout.begin_run(state, run_id)
    return {
        run_id = tostring(run_id or "unknown"),
        transport = ensure(state).active_transport,
        entered = {}
    }
end

function Loadout.mark_entered(run_state, card_id)
    run_state.entered = run_state.entered or {}
    run_state.entered[#run_state.entered + 1] = card_id
end

function Loadout.window(config, state, run_state, defeated_ante)
    local transport = run_state and run_state.transport or nil
    local schedule = transport and config.loadout.transports[transport] or nil
    if not schedule then return nil end
    local picks = nil
    for index, ante in ipairs(schedule.antes) do
        if ante == defeated_ante then picks = schedule.picks[index] break end
    end
    if not picks then return nil end
    local entered = {}
    for _, id in ipairs((run_state and run_state.entered) or {}) do entered[id] = true end
    local remaining = {}
    for _, id in ipairs(ensure(state).card_ids) do
        if not entered[id] then
            local card = Storage.find_card(state, id)
            -- members sold or sent to grading mid-run never reach an entry window
            if card and eligible_status(card.status) then remaining[#remaining + 1] = id end
        end
    end
    if #remaining == 0 then return nil end
    return { picks = math.min(picks, #remaining), card_ids = remaining }
end

function Loadout.roll_wear(config, rng_seed)
    local settings = config.wear
    local rand = Rng.lcg(rng_seed)
    local roll = rand()
    if roll < settings.minor_chance then
        return "minor", settings.minor_min + rand() * (settings.minor_max - settings.minor_min)
    end
    if roll < settings.minor_chance + settings.moderate_chance then
        return "moderate", settings.moderate_min + rand() * (settings.moderate_max - settings.moderate_min)
    end
    return "severe", settings.severe_min + rand() * (settings.severe_max - settings.severe_min)
end

return Loadout
```

(`Storage.find_card(state, card_id)` and `Storage.spend_currency(state, amount)` already exist — check their exact names in `src/storage.lua` before wiring; `find_card` takes an optional index third arg, omit it.)

- [ ] **Step 4: Run suite → green.** Add a `config_test.lua` line asserting `#config.loadout.license_prices == 12` if not already covered by loadout_test (it is — skip if redundant; do not duplicate).

- [ ] **Step 5: Bytecode + leak scan + commit:**

```
feat: loadout core - license matrix, transports, schedule windows
```

---

### Task 3: Proficiency core

**Files:**
- Create: `src/proficiency.lua`, `tests/proficiency_test.lua`
- Modify: `tests/run_all.lua` (add line after loadout_test), `main.lua` (attach)

- [ ] **Step 1: Write the failing test** `tests/proficiency_test.lua`:

```lua
local H = dofile("tests/test_helper.lua")
local Proficiency = dofile("src/proficiency.lua")

local card = { status = "graded" }
H.assert_equal(Proficiency.level(card), 0, "fresh card level zero")
H.assert_equal(Proficiency.next_threshold(card), 5, "first threshold five")

for _ = 1, 5 do Proficiency.record_ante(card) end
H.assert_equal(Proficiency.antes(card), 5, "antes accumulate")
H.assert_equal(Proficiency.level(card), 1, "level one at five")
H.assert_equal(Proficiency.allows_edition(card), true, "level one unlocks edition")
H.assert_equal(Proficiency.can_note(card), false, "note locked below two")

card.proficiency.antes = 13
H.assert_equal(Proficiency.level(card), 2, "level two at thirteen")
H.assert_equal(Proficiency.can_note(card), true, "note unlocked")
card.proficiency.antes = 34
H.assert_equal(Proficiency.level(card), 3, "level three at thirty-four")
H.assert_equal(Proficiency.can_eternal(card), true, "eternal unlocked")
card.proficiency.antes = 89
H.assert_equal(Proficiency.level(card), 4, "level four at eighty-nine")
H.assert_equal(Proficiency.can_badge(card), true, "badge unlocked")
card.proficiency.antes = 100
H.assert_equal(Proficiency.level(card), 5, "g level at one hundred")
H.assert_equal(Proficiency.can_tint(card), true, "tint unlocked")
H.assert_equal(Proficiency.next_threshold(card), nil, "maxed has no next threshold")
H.assert_equal(Proficiency.level_label(5), "G", "g label")
H.assert_equal(Proficiency.level_label(0), "0", "zero label")
H.assert_equal(Proficiency.level_label(3), "III", "roman label")

local raw = { status = "raw", proficiency = { antes = 100 } }
H.assert_equal(Proficiency.level(raw), 0, "raw card pinned to level zero")
H.assert_equal(Proficiency.record_ante(raw), false, "raw card never accrues")
H.assert_equal(Proficiency.allows_edition(raw), false, "raw card never has edition")

-- metadata setters
local low = { status = "graded", proficiency = { antes = 5 } }
H.assert_equal(Proficiency.set_note(low, "hi").reason, "locked", "note gated")
local high = { status = "graded", proficiency = { antes = 100 } }
H.assert_equal(Proficiency.set_note(high, "my note").ok, true, "note set")
H.assert_equal(high.proficiency.note, "my note", "note stored")
H.assert_equal(Proficiency.set_badge(high, "OG COLLECTION").ok, true, "badge set")
H.assert_equal(Proficiency.set_eternal(high, true).ok, true, "eternal pref set")
H.assert_equal(high.proficiency.eternal, true, "eternal stored")
H.assert_equal(Proficiency.set_tint(high, "#1A2b3C").ok, true, "tint accepts hash hex")
H.assert_equal(high.proficiency.tooltip_colour, "1A2B3C", "tint stored upper no hash")
H.assert_equal(Proficiency.set_tint(high, "red").reason, "invalid_hex", "garbage hex rejected")
H.assert_equal(Proficiency.set_tint(high, "").ok, true, "empty clears tint")
H.assert_equal(high.proficiency.tooltip_colour, nil, "tint cleared")

local colour = Proficiency.parse_hex("FF8000")
H.assert_near(colour[1], 1, 0.001, "red channel")
H.assert_near(colour[2], 0.502, 0.001, "green channel")
H.assert_near(colour[3], 0, 0.001, "blue channel")
H.assert_equal(colour[4], 1, "alpha one")
H.assert_equal(Proficiency.parse_hex("12345"), nil, "short hex rejected")

print("proficiency tests ok")
```

- [ ] **Step 2: Run → fails** (module missing).

- [ ] **Step 3: Implement `src/proficiency.lua`:**

```lua
local Proficiency = {}

local THRESHOLDS = { 5, 13, 34, 89, 100 }
local LABELS = { "0", "I", "II", "III", "IV", "G" }

function Proficiency.ensure(card)
    card.proficiency = type(card.proficiency) == "table" and card.proficiency or {}
    card.proficiency.antes = tonumber(card.proficiency.antes) or 0
    return card.proficiency
end

function Proficiency.antes(card)
    return (card and card.proficiency and tonumber(card.proficiency.antes)) or 0
end

function Proficiency.level(card)
    if not card or card.status ~= "graded" then return 0 end
    local antes = Proficiency.antes(card)
    local level = 0
    for index, threshold in ipairs(THRESHOLDS) do
        if antes >= threshold then level = index end
    end
    return level
end

function Proficiency.level_label(level)
    return LABELS[(level or 0) + 1] or "0"
end

function Proficiency.next_threshold(card)
    local antes = Proficiency.antes(card)
    for _, threshold in ipairs(THRESHOLDS) do
        if antes < threshold then return threshold end
    end
    return nil
end

function Proficiency.record_ante(card)
    if not card or card.status ~= "graded" then return false end
    local meta = Proficiency.ensure(card)
    meta.antes = meta.antes + 1
    return true
end

function Proficiency.allows_edition(card) return Proficiency.level(card) >= 1 end
function Proficiency.can_note(card) return Proficiency.level(card) >= 2 end
function Proficiency.can_eternal(card) return Proficiency.level(card) >= 3 end
function Proficiency.can_badge(card) return Proficiency.level(card) >= 4 end
function Proficiency.can_tint(card) return Proficiency.level(card) >= 5 end

function Proficiency.parse_hex(text)
    local hex = tostring(text or ""):gsub("^#", "")
    if not hex:match("^%x%x%x%x%x%x$") then return nil end
    return {
        tonumber(hex:sub(1, 2), 16) / 255,
        tonumber(hex:sub(3, 4), 16) / 255,
        tonumber(hex:sub(5, 6), 16) / 255,
        1
    }
end

local function gated_set(card, gate, apply)
    if not gate(card) then return { ok = false, reason = "locked" } end
    apply(Proficiency.ensure(card))
    return { ok = true }
end

function Proficiency.set_note(card, text)
    return gated_set(card, Proficiency.can_note, function(meta)
        meta.note = (text and text ~= "") and tostring(text) or nil
    end)
end

function Proficiency.set_badge(card, text)
    return gated_set(card, Proficiency.can_badge, function(meta)
        meta.badge_text = (text and text ~= "") and tostring(text) or nil
    end)
end

function Proficiency.set_eternal(card, enabled)
    return gated_set(card, Proficiency.can_eternal, function(meta)
        meta.eternal = enabled and true or false
    end)
end

function Proficiency.set_tint(card, text)
    if not Proficiency.can_tint(card) then return { ok = false, reason = "locked" } end
    local meta = Proficiency.ensure(card)
    if text == nil or text == "" then
        meta.tooltip_colour = nil
        return { ok = true }
    end
    local hex = tostring(text):gsub("^#", ""):upper()
    if not Proficiency.parse_hex(hex) then return { ok = false, reason = "invalid_hex" } end
    meta.tooltip_colour = hex
    return { ok = true }
end

return Proficiency
```

- [ ] **Step 4: Wire** — `tests/run_all.lua`: add `dofile("tests/proficiency_test.lua")` after the loadout line. `main.lua`: after the Loadout attach add:

```lua
local Proficiency = load_src("proficiency.lua")
Bootstrap.attach(Gradelatro, "Proficiency", Proficiency)
```

- [ ] **Step 5: Run suite → green. Bytecode + leak scan. Commit:**

```
feat: proficiency core - thresholds, accrual, perk gates, hex tint
```

---

### Task 4: Loadout screens (main + license shop) and binder entry button

**Files:**
- Create: `src/loadout_ui.lua`, `tests/loadout_ui_test.lua`
- Modify: `src/binder_ui.lua` (button row), `main.lua` (attach + install), `tests/run_all.lua`, both localization files

- [ ] **Step 1: Write the failing test** `tests/loadout_ui_test.lua`:

```lua
local H = dofile("tests/test_helper.lua")
local Config = dofile("src/config.lua")
local Storage = dofile("src/storage.lua")
local Loadout = dofile("src/loadout.lua")
local LoadoutUI = dofile("src/loadout_ui.lua")

local config = Config.normalize({})
local namespace = {
    config = config,
    mod = { id = "Gradelatro", config = {} },
    collection = Storage.normalize({ currency_g = 5000 })
}

local previous_smods = rawget(_G, "SMODS")
local save_count = 0
_G.SMODS = { save_mod_config = function() save_count = save_count + 1 return true end }

local runtime = { FUNCS = {} }
local adapter = { loadout_opened = 0, license_opened = 0 }
function adapter.open_loadout() adapter.loadout_opened = adapter.loadout_opened + 1 end
function adapter.open_license() adapter.license_opened = adapter.license_opened + 1 end

H.assert_true(LoadoutUI.install_runtime(namespace, runtime, adapter), "runtime callbacks installed")
H.assert_equal(LoadoutUI.open(nil), nil, "missing namespace rejected")

runtime.FUNCS.grdl_open_loadout()
local state = namespace.loadout_ui_state
H.assert_true(state ~= nil, "loadout state stored")
H.assert_equal(adapter.loadout_opened, 1, "loadout overlay opened")
H.assert_equal(state.license, 0, "license level surfaced")
H.assert_equal(state.capacity, 0, "capacity surfaced")
H.assert_equal(#state.entries, 0, "no member entries yet")
H.assert_equal(state.active_transport, nil, "no transport yet")

-- member entries resolve to card records
local mint = { centering = 9.8, print_quality = 9.8, corners = 9.8, edges = 9.8, surface = 9.8 }
local card = Storage.add_raw_card(namespace.collection, {
    center_key = "j_joker", local_key = "joker", rarity = "common",
    edition = "base", condition = mint, acquired_at = 1000
})
namespace.collection.loadout.license = 3
Loadout.add_card(namespace.collection, card.id)
card.status = "sold"
LoadoutUI.open(namespace)
H.assert_equal(#namespace.loadout_ui_state.entries, 0, "open reconciles dead members")
card.status = "raw"
Loadout.add_card(namespace.collection, card.id)
LoadoutUI.open(namespace)
H.assert_equal(namespace.loadout_ui_state.entries[1].id, card.id, "member entry carries record")
H.assert_equal(namespace.loadout_ui_state.capacity, 3, "capacity follows license")

-- license purchase handler
runtime.FUNCS.grdl_open_license()
H.assert_equal(adapter.license_opened, 1, "license overlay opened")
local before = namespace.collection.currency_g
runtime.FUNCS.grdl_license_buy()
H.assert_equal(namespace.collection.loadout.license, 4, "license purchase advances")
H.assert_equal(before - namespace.collection.currency_g, config.loadout.license_prices[4], "license price charged")
H.assert_equal(save_count, 1, "license purchase saves")
H.assert_true(namespace.loadout_ui_state.feedback ~= "", "purchase feedback bound")

-- transport purchase + activation handlers
runtime.FUNCS.grdl_transport_buy({ config = { ref_table = { key = "blue" } } })
H.assert_equal(namespace.collection.loadout.transports.blue, true, "transport purchased")
H.assert_equal(namespace.collection.loadout.active_transport, "blue", "first transport activates")
H.assert_equal(save_count, 2, "transport purchase saves")
runtime.FUNCS.grdl_transport_buy({ config = { ref_table = { key = "gold" } } })
runtime.FUNCS.grdl_transport_activate({ config = { ref_table = { key = "gold" } } })
H.assert_equal(namespace.collection.loadout.active_transport, "gold", "activation switches")
H.assert_equal(save_count, 4, "activation saves")
local poor = namespace.collection.currency_g
namespace.collection.currency_g = 0
runtime.FUNCS.grdl_license_buy()
H.assert_equal(namespace.loadout_ui_state.feedback, "grdl_k_reason_insufficient_funds", "broke purchase feedback")
namespace.collection.currency_g = poor

_G.SMODS = previous_smods
print("loadout ui tests ok")
```

- [ ] **Step 2: Run → fails** (module missing).

- [ ] **Step 3: Implement `src/loadout_ui.lua` (part 1 — state, screens, handlers).** Follow `market_ui.lua` as the structural template (open → state table; `create_*_definition`; `install_runtime` with default adapter using `G.FUNCS.overlay_menu`). Full module:

```lua
local LoadoutUI = {}

local function load_src(path)
    if rawget(_G, "SMODS") and SMODS.load_file then
        return assert(SMODS.load_file("src/" .. path))()
    end
    return dofile("src/" .. path)
end

local Catalog = load_src("catalog.lua")
local Condition = load_src("condition.lua")
local Loadout = load_src("loadout.lua")
local Persistence = load_src("persistence.lua")
local Proficiency = load_src("proficiency.lua")
local Storage = load_src("storage.lua")
local UICommon = load_src("ui_common.lua")

local safe_localize = UICommon.localize_text
local ui_text = UICommon.text_node
local row = UICommon.row
local col = UICommon.col

local TRANSPORT_ORDER = { "blue", "green", "red", "purple", "gold" }
local TIER_KEYS = { "grdl_k_tier_1", "grdl_k_tier_2", "grdl_k_tier_3", "grdl_k_tier_4" }

function LoadoutUI.license_label(level)
    if not level or level <= 0 then return safe_localize("grdl_k_license_none") end
    return safe_localize("grdl_k_license_level_format", {
        safe_localize(TIER_KEYS[Loadout.tier(level)]),
        Loadout.within(level)
    })
end

function LoadoutUI.open(namespace)
    if not namespace or not namespace.collection then return nil end
    local collection = namespace.collection
    Loadout.reconcile(collection)
    local entries = {}
    for _, card_id in ipairs(collection.loadout.card_ids) do
        local card = Storage.find_card(collection, card_id)
        if card then entries[#entries + 1] = card end
    end
    namespace.loadout_ui_state = {
        license = collection.loadout.license,
        capacity = Loadout.capacity(collection.loadout.license),
        entries = entries,
        transports = collection.loadout.transports,
        active_transport = collection.loadout.active_transport,
        feedback = ""
    }
    return namespace.loadout_ui_state
end

local function feedback(namespace, result, ok_key)
    local state = namespace.loadout_ui_state
    if not state then return end
    if result.ok then
        state.feedback = safe_localize(ok_key)
    else
        state.feedback = safe_localize("grdl_k_reason_" .. tostring(result.reason))
    end
end

-- ===== overlay definitions =====

local function loadout_cards_row(namespace, state)
    if not (rawget(_G, "CardArea") and rawget(_G, "Card") and rawget(_G, "G") and G.P_CENTERS) then
        return row({ ui_text(safe_localize("grdl_k_loadout_empty"), 0.32, G.C.UI.TEXT_INACTIVE) })
    end
    local area = CardArea(
        G.ROOM.T.x + 0.2 * G.ROOM.T.w / 2, G.ROOM.T.h,
        3.25 * G.CARD_W, 0.95 * G.CARD_H,
        { card_limit = 3, type = "title", highlight_limit = 0, collection = true })
    for _, entry in ipairs(state.entries) do
        local center = G.P_CENTERS[entry.center_key]
        if center then
            local card = Card(area.T.x + area.T.w / 2, area.T.y, G.CARD_W, G.CARD_H,
                (G.P_CARDS and G.P_CARDS.empty or nil), center)
            UICommon.suppress_selection(card)
            local flags = Catalog.edition_flags(entry.edition)
            if flags then card:set_edition(flags, true, true) end
            card.grdl_record = entry
            area:emplace(card)
        end
    end
    if #state.entries == 0 then
        return row({ ui_text(safe_localize("grdl_k_loadout_empty"), 0.32, G.C.UI.TEXT_INACTIVE) }, { padding = 0.3 })
    end
    return row({ { n = G.UIT.O, config = { object = area } } }, { padding = 0.05, no_fill = true })
end

function LoadoutUI.create_overlay_definition(namespace)
    namespace = namespace or rawget(_G, "Gradelatro") or {}
    local state = namespace.loadout_ui_state or LoadoutUI.open(namespace)
    if not state then
        return create_UIBox_generic_options({ back_func = "grdl_open_binder", contents = {} })
    end
    local transport_name = state.active_transport
        and safe_localize("grdl_k_transport_" .. state.active_transport)
        or safe_localize("grdl_k_transport_none")
    local rows = {
        row({ ui_text(safe_localize("grdl_k_loadout_title"), 0.55, G.C.WHITE) }),
        row({
            UICommon.stat_chip(LoadoutUI.license_label(state.license)),
            UICommon.stat_chip(safe_localize("grdl_k_capacity", { state.capacity })),
            UICommon.stat_chip(safe_localize("grdl_k_active_transport", { transport_name }))
        }, { padding = 0.09 }),
        loadout_cards_row(namespace, state),
        row({ ui_text(safe_localize("grdl_k_loadout_hint"), 0.27, G.C.UI.TEXT_INACTIVE) }),
        row({
            UIBox_button({
                button = "grdl_open_license",
                label = { safe_localize("grdl_b_license") },
                minw = 2.8, maxw = 2.8, minh = 0.7, scale = 0.34,
                colour = G.C.PURPLE,
                focus_args = { nav = "wide" }
            })
        }, { padding = 0.08 }),
        row({ { n = G.UIT.T, config = { ref_table = state, ref_value = "feedback", scale = 0.3, colour = G.C.GOLD } } })
    }
    return create_UIBox_generic_options({
        back_func = "grdl_open_binder",
        minw = 7.2, padding = 0.12,
        colour = G.C.L_BLACK, outline_colour = G.C.RED,
        contents = rows
    })
end

local function license_cell(config_table, state, level)
    local owned = state.license >= level
    local next_level = state.license + 1 == level
    local label = LoadoutUI.license_label(level)
    local price = config_table.loadout.license_prices[level]
    if next_level then
        return col({ UICommon.outline_button({
            button = "grdl_license_buy",
            minw = 1.55, minh = 0.75,
            lines = {
                { text = label, scale = 0.26 },
                { text = safe_localize("grdl_k_grading_fee", { price }), scale = 0.24, colour = G.C.GOLD }
            }
        }) }, { align = "cm", minw = 1.7 })
    end
    local colour = owned and G.C.GREEN or G.C.UI.TEXT_INACTIVE
    local status = owned and safe_localize("grdl_k_owned") or safe_localize("grdl_k_locked")
    return col({
        row({ ui_text(label, 0.26, colour) }, { padding = 0.01 }),
        row({ ui_text(status, 0.22, colour) }, { padding = 0.01 })
    }, { align = "cm", minw = 1.7 })
end

local function transport_cell(config_table, state, key)
    local transport = config_table.loadout.transports[key]
    local name = safe_localize("grdl_k_transport_" .. key)
    local antes = table.concat(transport.antes, "/")
    if not state.transports[key] then
        return col({ UICommon.outline_button({
            button = "grdl_transport_buy",
            ref = { key = key },
            minw = 1.35, minh = 0.85,
            lines = {
                { text = name, scale = 0.25 },
                { text = safe_localize("grdl_k_transport_antes", { antes }), scale = 0.21 },
                { text = safe_localize("grdl_k_grading_fee", { transport.price }), scale = 0.23, colour = G.C.GOLD }
            }
        }) }, { align = "cm", minw = 1.5 })
    end
    if state.active_transport == key then
        return col({
            row({ ui_text(name, 0.25, G.C.GREEN) }, { padding = 0.01 }),
            row({ ui_text(safe_localize("grdl_k_transport_antes", { antes }), 0.21, G.C.GREEN) }, { padding = 0.01 }),
            row({ ui_text(safe_localize("grdl_k_enabled"), 0.22, G.C.GREEN) }, { padding = 0.01 })
        }, { align = "cm", minw = 1.5 })
    end
    return col({ UICommon.outline_button({
        button = "grdl_transport_activate",
        ref = { key = key },
        minw = 1.35, minh = 0.85,
        lines = {
            { text = name, scale = 0.25 },
            { text = safe_localize("grdl_k_transport_antes", { antes }), scale = 0.21 },
            { text = safe_localize("grdl_b_enable"), scale = 0.23 }
        }
    }) }, { align = "cm", minw = 1.5 })
end

function LoadoutUI.create_license_definition(namespace)
    namespace = namespace or rawget(_G, "Gradelatro") or {}
    local state = namespace.loadout_ui_state or LoadoutUI.open(namespace)
    if not state then
        return create_UIBox_generic_options({ back_func = "grdl_open_loadout", contents = {} })
    end
    local config_table = namespace.config
    local ladder = {}
    for tier = 1, 4 do
        local cells = { row({ ui_text(safe_localize(TIER_KEYS[tier]), 0.3, G.C.WHITE) }, { padding = 0.02 }) }
        for within = 1, 3 do
            cells[#cells + 1] = row({ license_cell(config_table, state, (tier - 1) * 3 + within) }, { padding = 0.02 })
        end
        ladder[#ladder + 1] = col(cells, { align = "tm", minw = 1.8, padding = 0.03 })
    end
    local transports = {}
    for _, key in ipairs(TRANSPORT_ORDER) do
        transports[#transports + 1] = transport_cell(config_table, state, key)
    end
    local rows = {
        row({ ui_text(safe_localize("grdl_k_license_title"), 0.5, G.C.WHITE) }),
        row(ladder, { padding = 0.04 }),
        row({ ui_text(safe_localize("grdl_k_transport_title"), 0.38, G.C.WHITE) }, { padding = 0.04 }),
        row(transports, { padding = 0.04 }),
        row({ { n = G.UIT.T, config = { ref_table = state, ref_value = "feedback", scale = 0.3, colour = G.C.GOLD } } })
    }
    return create_UIBox_generic_options({
        back_func = "grdl_open_loadout",
        minw = 8.0, padding = 0.12,
        colour = G.C.L_BLACK, outline_colour = G.C.RED,
        contents = rows
    })
end

-- ===== runtime install =====

local function default_adapter(runtime)
    runtime = runtime or rawget(_G, "G")
    local function show(definition)
        if not runtime or not runtime.FUNCS or not runtime.FUNCS.overlay_menu then return end
        if runtime.SETTINGS then runtime.SETTINGS.paused = true end
        runtime.FUNCS.overlay_menu({ definition = definition })
    end
    return {
        open_loadout = function(namespace) show(LoadoutUI.create_overlay_definition(namespace)) end,
        open_license = function(namespace) show(LoadoutUI.create_license_definition(namespace)) end
    }
end

local function event_key(event)
    return event and event.config and event.config.ref_table and event.config.ref_table.key or nil
end

function LoadoutUI.install_runtime(namespace, runtime, adapter)
    namespace = namespace or rawget(_G, "Gradelatro")
    runtime = runtime or rawget(_G, "G")
    if not namespace or not runtime or not runtime.FUNCS then return false end
    adapter = adapter or default_adapter(runtime)

    runtime.FUNCS.grdl_open_loadout = function(event)
        local state = LoadoutUI.open(namespace)
        if state and adapter.open_loadout then adapter.open_loadout(namespace, state, event) end
    end

    runtime.FUNCS.grdl_open_license = function(event)
        if not namespace.loadout_ui_state then LoadoutUI.open(namespace) end
        if adapter.open_license then adapter.open_license(namespace, namespace.loadout_ui_state, event) end
    end

    local function refresh_license(event)
        if adapter.open_license then adapter.open_license(namespace, namespace.loadout_ui_state, event) end
    end

    runtime.FUNCS.grdl_license_buy = function(event)
        if not namespace.loadout_ui_state then LoadoutUI.open(namespace) end
        local result = Loadout.purchase_license(namespace.config, namespace.collection)
        if result.ok then
            namespace.last_save_ok = Persistence.save(namespace)
            LoadoutUI.open(namespace)
            feedback(namespace, result, "grdl_k_license_bought")
            refresh_license(event)
        else
            feedback(namespace, result, "grdl_k_license_bought")
            if rawget(_G, "play_sound") then pcall(play_sound, "tarot2", 0.76, 0.4) end
        end
    end

    runtime.FUNCS.grdl_transport_buy = function(event)
        if not namespace.loadout_ui_state then LoadoutUI.open(namespace) end
        local result = Loadout.purchase_transport(namespace.config, namespace.collection, event_key(event))
        if result.ok then
            namespace.last_save_ok = Persistence.save(namespace)
            LoadoutUI.open(namespace)
            feedback(namespace, result, "grdl_k_transport_bought")
            refresh_license(event)
        else
            feedback(namespace, result, "grdl_k_transport_bought")
            if rawget(_G, "play_sound") then pcall(play_sound, "tarot2", 0.76, 0.4) end
        end
    end

    runtime.FUNCS.grdl_transport_activate = function(event)
        if not namespace.loadout_ui_state then LoadoutUI.open(namespace) end
        local result = Loadout.set_active_transport(namespace.collection, event_key(event))
        if result.ok then
            namespace.last_save_ok = Persistence.save(namespace)
            LoadoutUI.open(namespace)
            feedback(namespace, result, "grdl_k_transport_enabled")
            refresh_license(event)
        else
            feedback(namespace, result, "grdl_k_transport_enabled")
        end
    end

    return true
end

return LoadoutUI
```

Note: `refresh_license` reopens the license overlay after a successful purchase (rebuild-in-place via overlay reopen is acceptable here — the license screen is not a tab). Note the handlers call `LoadoutUI.open(namespace)` after success so the freshly-built state (incl. `feedback`) is rebuilt — then `feedback(...)` writes onto the NEW state. Keep that order exactly as shown.

- [ ] **Step 4: Wire.**
  - `main.lua` after the Proficiency block:

```lua
local LoadoutUI = load_src("loadout_ui.lua")
Bootstrap.attach(Gradelatro, "LoadoutUI", LoadoutUI)
LoadoutUI.install_runtime(Gradelatro, rawget(_G, "G"))
```

  - `src/binder_ui.lua`: in `BinderUI.create_overlay_definition`'s controls row (after the market button col, line ~440), add:

```lua
    controls[#controls + 1] = col({
        UIBox_button({
            button = "grdl_open_loadout",
            label = { safe_localize("grdl_b_loadout") },
            minw = 2.2,
            maxw = 2.2,
            minh = 0.7,
            scale = 0.34,
            colour = G.C.PURPLE,
            focus_args = { nav = "wide" }
        })
    })
```

  - `tests/run_all.lua`: add `dofile("tests/loadout_ui_test.lua")` after the proficiency line.

- [ ] **Step 5: Localization batch 1** — add to BOTH files (en shown; zh values in parentheses):

```lua
grdl_b_loadout = "Loadout",                              -- 装配方案
grdl_k_loadout_title = "Loadout",                        -- 装配方案
grdl_b_license = "Licenses",                             -- 装配许可证
grdl_k_license_title = "Loadout Licenses",               -- 装配许可证
grdl_k_license_none = "No License",                      -- 未持有许可证
grdl_k_license_level_format = "#1# X#2#",                -- #1# X#2#
grdl_k_tier_1 = "Entry",                                 -- 入门
grdl_k_tier_2 = "Advanced",                              -- 进阶
grdl_k_tier_3 = "Professional",                          -- 专业
grdl_k_tier_4 = "G-Cert",                                -- G-Cert
grdl_k_capacity = "Capacity #1#",                        -- 容量 #1#
grdl_k_active_transport = "Transport: #1#",              -- 运输：#1#
grdl_k_transport_none = "None",                          -- 未启用
grdl_k_transport_title = "Shipping Services",            -- 运输服务
grdl_k_transport_blue = "Blue Shipping",                 -- 蓝色运输
grdl_k_transport_green = "Green Shipping",               -- 绿色运输
grdl_k_transport_red = "Red Shipping",                   -- 红色运输
grdl_k_transport_purple = "Purple Shipping",             -- 紫色运输
grdl_k_transport_gold = "Gold Shipping",                 -- 金色运输
grdl_k_transport_antes = "Antes #1#",                    -- 底注 #1#
grdl_b_enable = "Use",                                   -- 启用
grdl_k_enabled = "Active",                               -- 使用中
grdl_k_owned = "Owned",                                  -- 已解锁
grdl_k_locked = "Locked",                                -- 未解锁
grdl_k_loadout_empty = "Loadout is empty.",              -- 装配方案为空
grdl_k_loadout_hint = "Add cards from their G-key detail view.",  -- 在卡牌详情（G 键）中加入装配
grdl_k_license_bought = "License upgraded.",             -- 许可证已升级。
grdl_k_transport_bought = "Service unlocked.",           -- 运输服务已解锁。
grdl_k_transport_enabled = "Service active.",            -- 已启用该运输服务。
grdl_k_reason_maxed = "Already at the top license.",     -- 许可证已是最高级。
grdl_k_reason_already_owned = "Already unlocked.",       -- 已解锁过该服务。
grdl_k_reason_not_owned = "Unlock this service first.",  -- 需先解锁该服务。
grdl_k_reason_unknown_transport = "Unknown service.",    -- 未知的运输服务。
```

(Both v_dictionary-style `#1#` keys go in the same `dictionary` table — `UICommon.localize_text` tries variable lookup first, plain second; follow how `grdl_k_grading_fee` is registered today and mirror it for the `#1#` keys.)

- [ ] **Step 6: Run suite → green. Bytecode + leak scan (loadout_ui.lua, binder_ui.lua, main.lua). Commit:**

```
feat: loadout screens - main view, license ladder, transport shop
```

---

### Task 5: G-view loadout/perk buttons and input overlays

**Files:**
- Modify: `src/binder_ui.lua` (inspect action row, handlers, input overlays, in-run inspect variant), `main.lua` (G-key route), both localization files
- Test: `tests/binder_ui_test.lua`

- [ ] **Step 1: Write the failing tests.** In `tests/binder_ui_test.lua`, after the sell block (search `sell_from_inspect`), append:

```lua
-- loadout membership from inspect
local Loadout = dofile("src/loadout.lua")
namespace.collection.loadout.license = 3
local member_card = Storage.add_raw_card(namespace.collection, {
    center_key = "j_member", local_key = "member", rarity = "common",
    edition = "base", condition = mint_condition, acquired_at = 9000
})
member_card.status = "graded"
member_card.grade = 9

H.assert_true(type(runtime.FUNCS.grdl_loadout_toggle) == "function", "loadout toggle registered")
BinderUI.open_inspect(namespace, member_card.id)
local added = BinderUI.toggle_loadout(namespace, member_card.id)
H.assert_equal(added.ok, true, "graded card joins loadout in one click")
H.assert_equal(Loadout.contains(namespace.collection, member_card.id), true, "membership stored")
local removed = BinderUI.toggle_loadout(namespace, member_card.id)
H.assert_equal(removed.ok, true, "second toggle removes")
H.assert_equal(Loadout.contains(namespace.collection, member_card.id), false, "membership cleared")

-- raw card needs the armed second click
local raw_member = Storage.add_raw_card(namespace.collection, {
    center_key = "j_rawm", local_key = "rawm", rarity = "common",
    edition = "base", condition = mint_condition, acquired_at = 9001
})
BinderUI.open_inspect(namespace, raw_member.id)
local armed_add = BinderUI.toggle_loadout(namespace, raw_member.id)
H.assert_equal(armed_add.pending, true, "raw add arms first")
H.assert_equal(Loadout.contains(namespace.collection, raw_member.id), false, "raw not yet added")
H.assert_equal(namespace.inspect_ui_state.last_reason_text, "grdl_k_loadout_raw_hint", "raw warning bound")
local confirmed_add = BinderUI.toggle_loadout(namespace, raw_member.id)
H.assert_equal(confirmed_add.ok, true, "raw add confirms second click")
H.assert_equal(Loadout.contains(namespace.collection, raw_member.id), true, "raw added")

-- in-run lock
local previous_lock_g = rawget(_G, "G")
_G.G = { STAGE = 1, STAGES = { RUN = 1 } }
H.assert_equal(BinderUI.toggle_loadout(namespace, member_card.id).reason, "loadout_locked", "membership locked in run")
_G.G = previous_lock_g

-- perk handlers
local Proficiency = dofile("src/proficiency.lua")
member_card.proficiency = { antes = 100 }
BinderUI.open_inspect(namespace, member_card.id)
H.assert_true(type(runtime.FUNCS.grdl_prof_eternal) == "function", "eternal toggle registered")
runtime.FUNCS.grdl_prof_eternal({ config = { ref_table = { id = member_card.id } } })
H.assert_equal(member_card.proficiency.eternal, true, "eternal preference flipped")
H.assert_equal(BinderUI.commit_prof_text(namespace, member_card.id, "note", "hello").ok, true, "note commit")
H.assert_equal(member_card.proficiency.note, "hello", "note stored")
H.assert_equal(BinderUI.commit_prof_text(namespace, member_card.id, "badge", "OG").ok, true, "badge commit")
H.assert_equal(BinderUI.commit_prof_text(namespace, member_card.id, "tint", "1A2B3C").ok, true, "tint commit")
H.assert_equal(member_card.proficiency.tooltip_colour, "1A2B3C", "tint stored")
H.assert_equal(BinderUI.commit_prof_text(namespace, member_card.id, "tint", "zzz").reason, "invalid_hex", "bad tint rejected")
local low_card = Storage.add_raw_card(namespace.collection, {
    center_key = "j_low", local_key = "low", rarity = "common",
    edition = "base", condition = mint_condition, acquired_at = 9002
})
low_card.status = "graded"
H.assert_equal(BinderUI.commit_prof_text(namespace, low_card.id, "note", "x").reason, "locked", "perk gate enforced")
```

- [ ] **Step 2: Run → fails** (`grdl_loadout_toggle` nil).

- [ ] **Step 3: Implement in `src/binder_ui.lua`.**
  - Requires at top: `local Loadout = load_src("loadout.lua")` and `local Proficiency = load_src("proficiency.lua")`.
  - Public toggle (place near the old toggle_carry position):

```lua
function BinderUI.toggle_loadout(namespace, card_id)
    if not namespace or not namespace.collection then return { ok = false, reason = "missing_collection" } end
    local runtime = rawget(_G, "G")
    if runtime and runtime.STAGE ~= nil and runtime.STAGES and runtime.STAGE == runtime.STAGES.RUN then
        return { ok = false, reason = "loadout_locked" }
    end
    local collection = namespace.collection
    if Loadout.contains(collection, card_id) then
        local removed = Loadout.remove_card(collection, card_id)
        if removed.ok then namespace.last_save_ok = Persistence.save(namespace) end
        return removed
    end
    local card = Storage.find_card(collection, card_id)
    if not card then return { ok = false, reason = "unknown_card" } end
    local inspect_state = namespace.inspect_ui_state
    if card.status == "raw" and inspect_state and not inspect_state.pending_loadout_add then
        inspect_state.pending_loadout_add = true
        inspect_state.last_reason_text = UICommon.localize_text("grdl_k_loadout_raw_hint")
        return { ok = true, pending = true }
    end
    if inspect_state then inspect_state.pending_loadout_add = nil end
    local added = Loadout.add_card(collection, card_id)
    if added.ok then namespace.last_save_ok = Persistence.save(namespace) end
    return added
end
```

  - Auto-removal on sell/submit (spec §4.1): in the existing `grdl_inspect_sell` success path and the `grdl_inspect_submit` success path (both already call `Persistence.save`), insert one line immediately BEFORE the save call:

```lua
        Loadout.reconcile(namespace.collection)
```

  - Text-perk commit helper (public for tests):

```lua
function BinderUI.commit_prof_text(namespace, card_id, kind, text)
    if not namespace or not namespace.collection then return { ok = false, reason = "missing_collection" } end
    local card = Storage.find_card(namespace.collection, card_id)
    if not card then return { ok = false, reason = "unknown_card" } end
    local result
    if kind == "note" then result = Proficiency.set_note(card, text)
    elseif kind == "badge" then result = Proficiency.set_badge(card, text)
    elseif kind == "tint" then result = Proficiency.set_tint(card, text)
    else return { ok = false, reason = "unknown_kind" } end
    if result.ok then namespace.last_save_ok = Persistence.save(namespace) end
    return result
end
```

  - In `inspect_action_row` (where the carry button used to be), add — outside a run, for `entry.status == "raw" or entry.status == "graded"` and NOT `state.offer_mode`:

```lua
    if not state.offer_mode and not in_run_now and (entry.status == "raw" or entry.status == "graded") then
        local member = Loadout.contains(namespace.collection, entry.id)
        actions[#actions + 1] = inspect_action_button("grdl_loadout_toggle", entry.id, {
            { text = safe_localize(member and "grdl_b_loadout_remove" or "grdl_b_loadout_add") }
        })
    end
```

   and perk buttons (graded only; shown in both contexts, incl. the in-run loadout variant added below):

```lua
    if entry.status == "graded" then
        local card = Storage.find_card(namespace.collection, entry.id)
        if card and Proficiency.can_note(card) then
            actions[#actions + 1] = inspect_action_button("grdl_prof_note", entry.id, {
                { text = safe_localize("grdl_b_prof_note") } }, regular_font)
        end
        if card and Proficiency.can_eternal(card) then
            actions[#actions + 1] = inspect_action_button("grdl_prof_eternal", entry.id, {
                { text = safe_localize((card.proficiency and card.proficiency.eternal)
                    and "grdl_b_prof_eternal_on" or "grdl_b_prof_eternal_off") } }, regular_font)
        end
        if card and Proficiency.can_badge(card) then
            actions[#actions + 1] = inspect_action_button("grdl_prof_badge", entry.id, {
                { text = safe_localize("grdl_b_prof_badge") } }, regular_font)
        end
        if card and Proficiency.can_tint(card) then
            actions[#actions + 1] = inspect_action_button("grdl_prof_tint", entry.id, {
                { text = safe_localize("grdl_b_prof_tint") } }, regular_font)
        end
    end
```

   In the in-run loadout inspect variant (`state.loadout_mode == true`, set by `BinderUI.inspect_loadout` below): the submit/sell/loadout-toggle buttons must all be suppressed — gate the existing submit/sell button blocks with `and not state.loadout_mode`.

  - IV badge display: in the inspect details column where the PSA badge row is built, after it add:

```lua
    local inspected_card = Storage.find_card(namespace.collection, entry.id)
    local badge_text = inspected_card and inspected_card.proficiency and inspected_card.proficiency.badge_text or nil
    if badge_text and rawget(_G, "create_badge") then
        detail_rows[#detail_rows + 1] = row({ create_badge(badge_text, G.C.PURPLE, G.C.WHITE) }, { padding = 0.03 })
    end
```

   (`detail_rows` = whatever local table collects the PSA badge row — match the surrounding code.)

  - In-run inspect entry point:

```lua
function BinderUI.inspect_loadout(namespace, card_id)
    local state = BinderUI.open_inspect(namespace, card_id)
    if state then state.loadout_mode = true end
    return state
end
```

  - Handlers in `install_runtime`:

```lua
    runtime.FUNCS.grdl_loadout_toggle = function(event)
        local card_id = event_card_id(event)
        local result = BinderUI.toggle_loadout(namespace, card_id)
        namespace.last_loadout_result = result
        if result.ok and not result.pending then
            reopen_inspect(namespace, card_id)
        elseif not result.ok then
            local inspect_state = namespace.inspect_ui_state
            if inspect_state then
                inspect_state.last_reason_text = safe_localize("grdl_k_reason_" .. tostring(result.reason))
            end
            if rawget(_G, "play_sound") then pcall(play_sound, "tarot2", 0.76, 0.4) end
        end
    end

    runtime.FUNCS.grdl_prof_eternal = function(event)
        local card_id = event_card_id(event)
        local card = Storage.find_card(namespace.collection, card_id)
        if not card then return end
        local enabled = not (card.proficiency and card.proficiency.eternal)
        local result = Proficiency.set_eternal(card, enabled)
        if result.ok then
            namespace.last_save_ok = Persistence.save(namespace)
            local game = rawget(_G, "G")
            for _, joker in ipairs((game and game.jokers and game.jokers.cards) or {}) do
                if joker.ability and joker.ability.grdl_loadout_id == card_id then
                    if joker.set_eternal then pcall(joker.set_eternal, joker, enabled)
                    else joker.ability.eternal = enabled or nil end
                end
            end
            reopen_inspect(namespace, card_id)
        end
    end

    runtime.FUNCS.grdl_prof_note = function(event)
        BinderUI.open_prof_input(namespace, event_card_id(event), "note")
    end
    runtime.FUNCS.grdl_prof_badge = function(event)
        BinderUI.open_prof_input(namespace, event_card_id(event), "badge")
    end
    runtime.FUNCS.grdl_prof_tint = function(event)
        BinderUI.open_prof_input(namespace, event_card_id(event), "tint")
    end
    runtime.FUNCS.grdl_prof_commit = function(event)
        local input = namespace.prof_input
        if not input then return end
        local result = BinderUI.commit_prof_text(namespace, input.card_id, input.kind, input.text)
        if result.ok then
            reopen_inspect(namespace, input.card_id)
        else
            input.feedback = safe_localize("grdl_k_reason_" .. tostring(result.reason))
            if rawget(_G, "play_sound") then pcall(play_sound, "tarot2", 0.76, 0.4) end
        end
    end
    runtime.FUNCS.grdl_hex_preview = function(element)
        local input = namespace.prof_input
        if not input or not element or not element.config then return end
        local parsed = Proficiency.parse_hex(input.text)
        local target = element.config.colour
        if parsed and type(target) == "table" then
            target[1], target[2], target[3], target[4] = parsed[1], parsed[2], parsed[3], 1
        end
    end
```

   (`reopen_inspect` already exists from the buy-flow work — reuse it. If its current form is local, keep calling it the same way the existing handlers do.)

  - Input overlay builder:

```lua
function BinderUI.open_prof_input(namespace, card_id, kind)
    local runtime = rawget(_G, "G")
    if not runtime or not runtime.FUNCS or not runtime.FUNCS.overlay_menu or not rawget(_G, "create_text_input") then return end
    local card = Storage.find_card(namespace.collection, card_id)
    if not card then return end
    local meta = card.proficiency or {}
    local current = (kind == "note" and meta.note) or (kind == "badge" and meta.badge_text)
        or (kind == "tint" and meta.tooltip_colour) or ""
    namespace.prof_input = { card_id = card_id, kind = kind, text = current or "", feedback = "" }
    local nodes = {
        row({ ui_text(safe_localize("grdl_b_prof_" .. kind), 0.4, G.C.WHITE) }),
        row({ create_text_input({
            ref_table = namespace.prof_input,
            ref_value = "text",
            max_length = kind == "tint" and 6 or 24,
            all_caps = kind == "tint",
            prompt_text = kind == "tint" and safe_localize("grdl_k_hex_prompt") or nil,
            w = 4
        }) }, { padding = 0.06 })
    }
    if kind == "tint" then
        nodes[#nodes + 1] = row({
            { n = G.UIT.C, config = {
                minw = 1.2, minh = 0.4, r = 0.1, emboss = 0.05,
                colour = Proficiency.parse_hex(namespace.prof_input.text) or { 0.2, 0.2, 0.2, 1 },
                func = "grdl_hex_preview"
            }, nodes = {} }
        }, { padding = 0.05 })
    end
    nodes[#nodes + 1] = row({ UICommon.outline_button({
        button = "grdl_prof_commit",
        solid = true,
        minw = 1.6, minh = 0.6,
        lines = { { text = safe_localize("grdl_b_confirm"), scale = 0.3 } }
    }) }, { padding = 0.06 })
    nodes[#nodes + 1] = row({ { n = G.UIT.T, config = { ref_table = namespace.prof_input, ref_value = "feedback", scale = 0.28, colour = G.C.GOLD } } })
    if runtime.SETTINGS then runtime.SETTINGS.paused = true end
    runtime.FUNCS.overlay_menu({ definition = create_UIBox_generic_options({
        back_func = "grdl_open_binder",
        minw = 5.5, padding = 0.12,
        colour = G.C.L_BLACK, outline_colour = G.C.RED,
        contents = nodes
    }) })
end
```

   Note: the hex preview node's `colour` table is mutated in place by `grdl_hex_preview` every frame — the UIE reads `config.colour` at draw time, so the swatch live-follows the typed value.

  - `main.lua` G-key handler: extend the routing chain:

```lua
            if target and target.grdl_record then
                BinderUI.inspect_from_card(Gradelatro, target)
            elseif target and target.grdl_offer then
                BinderUI.inspect_offer(Gradelatro, target.grdl_offer)
            elseif target and target.ability and target.ability.grdl_loadout_id then
                BinderUI.inspect_loadout(Gradelatro, target.ability.grdl_loadout_id)
            end
```

   `inspect_from_card`/`inspect_offer` open the overlay themselves — check how they show the overlay and make `inspect_loadout` reuse exactly the same display call (it goes through `open_inspect`, which the existing flow already displays; verify against `inspect_from_card`'s body and mirror it).

- [ ] **Step 4: Localization batch 2** (both files):

```lua
grdl_b_loadout_add = "Add to Loadout",          -- 加入装配
grdl_b_loadout_remove = "Remove from Loadout",  -- 移出装配
grdl_k_loadout_raw_hint = "Raw card: wears on entry, never gains proficiency. Click again to confirm.",
                                                -- 未评级卡：入场会磨损且无熟练度。再次点击确认。
grdl_k_reason_loadout_locked = "Loadout is locked during a run.",  -- 赛局中无法调整装配。
grdl_k_reason_over_capacity = "Loadout is full.",                  -- 装配容量已满。
grdl_k_reason_rarity_locked = "License tier too low for this rarity.",  -- 许可证等级不足以装配该稀有度。
grdl_k_reason_rarity_quota = "Too many cards of this rarity.",     -- 该稀有度数量超出许可上限。
grdl_k_reason_invalid_status = "This card cannot be loaded out.",  -- 该卡当前状态无法装配。
grdl_k_reason_duplicate = "Already in the loadout.",               -- 已在装配方案中。
grdl_k_reason_not_in_loadout = "Not in the loadout.",              -- 不在装配方案中。
grdl_k_reason_unknown_card = "Card not found.",                    -- 找不到该卡牌。
grdl_k_reason_locked = "Proficiency too low.",                     -- 熟练度不足。
grdl_k_reason_invalid_hex = "Invalid HEX colour.",                 -- 无效的 HEX 色值。
grdl_b_prof_note = "Custom Note",       -- 自定义文本
grdl_b_prof_badge = "Custom Badge",     -- 自定义徽章
grdl_b_prof_tint = "Tooltip Colour",    -- 自定义底色
grdl_b_prof_eternal_on = "Eternal: On",   -- 永恒：开
grdl_b_prof_eternal_off = "Eternal: Off", -- 永恒：关
grdl_b_confirm = "Confirm",             -- 确认
grdl_k_hex_prompt = "RRGGBB",           -- RRGGBB
```

- [ ] **Step 5: Run suite → green. Bytecode + leak scan. Commit:**

```
feat: loadout and proficiency actions in the G-key inspect view
```

---

### Task 6: Run integration — entry windows, spawning, proficiency counting

**Files:**
- Modify: `src/loadout_ui.lua` (run hooks + entry popup + spawn), `tests/loadout_ui_test.lua`

- [ ] **Step 1: Write the failing tests.** Append to `tests/loadout_ui_test.lua` before the final print/restore:

```lua
-- ===== run integration =====
local previous_run_g = rawget(_G, "G")
local Proficiency = dofile("src/proficiency.lua")
local mintc = { centering = 9.8, print_quality = 9.8, corners = 9.8, edges = 9.8, surface = 9.8 }
local run_ns = {
    config = config,
    mod = { id = "Gradelatro", config = {} },
    collection = Storage.normalize({ currency_g = 0 })
}
run_ns.collection.loadout.license = 3
run_ns.collection.loadout.transports.gold = true
run_ns.collection.loadout.active_transport = "gold"
local function run_card(key, status, antes)
    local card = Storage.add_raw_card(run_ns.collection, {
        center_key = key, local_key = key, rarity = "common",
        edition = "negative", condition = { centering = 9.8, print_quality = 9.8, corners = 9.8, edges = 9.8, surface = 9.8 },
        acquired_at = 1
    })
    if status then card.status = status end
    if antes then card.proficiency = { antes = antes } end
    return card
end
local graded_novice = run_card("j_gn", "graded", 0)   -- level 0: spawns editionless
local graded_adept = run_card("j_ga", "graded", 40)   -- level III + eternal pref
graded_adept.proficiency.eternal = true
local raw_entry = run_card("j_raw", nil, nil)         -- raw: wears, editionless
Loadout.add_card(run_ns.collection, graded_novice.id)
Loadout.add_card(run_ns.collection, graded_adept.id)
Loadout.add_card(run_ns.collection, raw_entry.id)

local spawned = {}
local set_eternal_calls = {}
_G.SMODS.add_card = function(args)
    local joker = { ability = {}, set_eternal = function(self, flag) set_eternal_calls[#set_eternal_calls + 1] = flag self.ability.eternal = flag end }
    spawned[#spawned + 1] = { args = args, joker = joker }
    return joker
end

local funcs = { cash_out = function(e) return "paid" end }
local game_class = {}
function game_class.start_run(self, args) return "started" end
local env = { funcs = funcs, game_class = game_class }
H.assert_equal(LoadoutUI.install(run_ns, env), true, "run hooks installed")
H.assert_equal(LoadoutUI.install(run_ns, env), true, "second install is a no-op")

_G.G = {
    GAME = {
        pseudorandom = { seed = "LOADRUN" },
        round_resets = { ante = 2, blind_states = { Boss = "Defeated" } }
    },
    jokers = { cards = {} },
    STATE = 1
}

game_class.start_run({}, {})
local run_state = _G.G.GAME.grdl_loadout
H.assert_true(run_state ~= nil, "run state seeded on start")
H.assert_equal(run_state.run_id, "LOADRUN", "run id captured")
H.assert_equal(run_state.transport, "gold", "transport snapshot taken")

-- boss cash-out for ante 1 (round_resets.ante already eased to 2)
funcs.cash_out({ config = {} })
H.assert_true(run_ns.loadout_entry_window ~= nil, "entry window staged")
H.assert_equal(run_ns.loadout_entry_window.picks, 2, "gold first window allows two")

-- confirm two entries
local result = LoadoutUI.spawn_entries(run_ns, { graded_novice.id, graded_adept.id }, 7777)
H.assert_equal(result.ok, true, "entries spawn")
H.assert_equal(#spawned, 2, "two jokers spawned")
H.assert_equal(spawned[1].args.no_edition, true, "level zero spawns editionless")
H.assert_equal(spawned[2].args.edition, "e_negative", "level three keeps its edition")
H.assert_equal(set_eternal_calls[1], true, "eternal preference applied")
H.assert_equal(spawned[1].joker.ability.grdl_loadout_id, graded_novice.id, "spawn tagged")
H.assert_equal(#run_state.entered, 2, "entries consumed")

-- proficiency counts on next boss; raw never counts
_G.G.jokers.cards = { spawned[1].joker, spawned[2].joker }
_G.G.GAME.round_resets.ante = 5
funcs.cash_out({ config = {} })
H.assert_equal(graded_novice.proficiency.antes, 1, "present graded card counts the ante")
H.assert_equal(graded_adept.proficiency.antes, 41, "count accumulates on top")
funcs.cash_out({ config = {} })
H.assert_equal(graded_novice.proficiency.antes, 1, "same ante never double counts")

-- removed joker stops counting
_G.G.jokers.cards = { spawned[2].joker }
_G.G.GAME.round_resets.ante = 7
funcs.cash_out({ config = {} })
H.assert_equal(graded_novice.proficiency.antes, 1, "missing joker stops accruing")
H.assert_equal(graded_adept.proficiency.antes, 42, "surviving joker keeps accruing")

-- raw wear on entry
local surface_before = raw_entry.condition.surface
LoadoutUI.spawn_entries(run_ns, { raw_entry.id }, 8888)
H.assert_equal(#spawned, 3, "raw card spawned")
H.assert_equal(spawned[3].args.no_edition, true, "raw card spawns editionless")
H.assert_true(raw_entry.condition.surface < surface_before, "raw card wears on entry")
H.assert_equal(raw_entry.proficiency, nil, "raw card gains no proficiency block")

-- non-boss cash-out does nothing
run_ns.loadout_entry_window = nil
_G.G.GAME.round_resets.blind_states.Boss = "Upcoming"
funcs.cash_out({ config = {} })
H.assert_equal(run_ns.loadout_entry_window, nil, "small blind opens no window")

_G.G = previous_run_g
```

(The run-integration block restores the previous `G` global it captured at its start — same save/restore discipline as the rest of the file.)

- [ ] **Step 2: Run → fails** (`LoadoutUI.install` nil).

- [ ] **Step 3: Implement in `src/loadout_ui.lua`.** Add below the screens code:

```lua
-- ===== run integration =====

function LoadoutUI.on_run_start(namespace)
    local runtime = rawget(_G, "G")
    if not namespace or not namespace.collection or not runtime or not runtime.GAME then return end
    local run_id = Loadout.run_identity(runtime.GAME)
    local existing = runtime.GAME.grdl_loadout
    if not existing or existing.run_id ~= run_id then
        runtime.GAME.grdl_loadout = Loadout.begin_run(namespace.collection, run_id)
    end
end

function LoadoutUI.count_proficiency(namespace, runtime, run_state)
    local changed = false
    for _, card_id in ipairs(run_state.entered or {}) do
        local present = false
        for _, joker in ipairs((runtime.jokers and runtime.jokers.cards) or {}) do
            if joker.ability and joker.ability.grdl_loadout_id == card_id then present = true break end
        end
        if present then
            local card = Storage.find_card(namespace.collection, card_id)
            if card and Proficiency.record_ante(card) then changed = true end
        end
    end
    if changed then namespace.last_save_ok = Persistence.save(namespace) end
end

function LoadoutUI.on_boss_cash_out(namespace)
    local runtime = rawget(_G, "G")
    if not namespace or not namespace.collection or not runtime or not runtime.GAME then return end
    local resets = runtime.GAME.round_resets or {}
    if not resets.blind_states or resets.blind_states.Boss ~= "Defeated" then return end
    local run_state = runtime.GAME.grdl_loadout
    if not run_state then return end
    local defeated_ante = (resets.ante or 1) - 1
    if run_state.counted_ante == defeated_ante then return end
    run_state.counted_ante = defeated_ante

    LoadoutUI.count_proficiency(namespace, runtime, run_state)

    local window = Loadout.window(namespace.config, namespace.collection, run_state, defeated_ante)
    if not window then return end
    namespace.loadout_entry_window = window
    if runtime.E_MANAGER and rawget(_G, "Event") then
        runtime.E_MANAGER:add_event(Event({
            trigger = "after",
            delay = 0.7,
            blockable = false,
            func = function()
                pcall(LoadoutUI.open_entry, namespace)
                return true
            end
        }))
    end
end

function LoadoutUI.spawn_entries(namespace, card_ids, now)
    local runtime = rawget(_G, "G")
    local smods = rawget(_G, "SMODS")
    if not runtime or not runtime.GAME or not runtime.GAME.grdl_loadout then
        return { ok = false, reason = "no_run" }
    end
    if not smods or type(smods.add_card) ~= "function" then
        return { ok = false, reason = "spawn_failed" }
    end
    local run_state = runtime.GAME.grdl_loadout
    local collection = namespace.collection
    now = now or os.time()
    local spawned = 0
    for index, card_id in ipairs(card_ids or {}) do
        local card = Storage.find_card(collection, card_id)
        if card and (card.status == "raw" or card.status == "graded") then
            local spawn_args = { key = card.center_key }
            if card.status == "graded" and Proficiency.allows_edition(card) and card.edition ~= "base" then
                spawn_args.edition = "e_" .. card.edition
            else
                spawn_args.no_edition = true
            end
            local ok, joker = pcall(smods.add_card, spawn_args)
            if ok and joker then
                joker.ability = joker.ability or {}
                joker.ability.grdl_loadout_id = card.id
                if card.status == "graded" and Proficiency.can_eternal(card)
                    and card.proficiency and card.proficiency.eternal then
                    if joker.set_eternal then pcall(joker.set_eternal, joker, true)
                    else joker.ability.eternal = true end
                end
                if card.status == "raw" then
                    local _, intensity = Loadout.roll_wear(namespace.config, now + index * 7919)
                    card.condition = Condition.apply_wear(card.condition, card.edition, intensity)
                    card.wear_count = (card.wear_count or 0) + 1
                end
                Loadout.mark_entered(run_state, card.id)
                spawned = spawned + 1
            end
        end
    end
    namespace.last_save_ok = Persistence.save(namespace)
    return { ok = spawned > 0, spawned = spawned, reason = spawned == 0 and "spawn_failed" or nil }
end

-- ===== entry popup =====

function LoadoutUI.create_entry_definition(namespace)
    local window = namespace.loadout_entry_window
    if not window then
        return create_UIBox_generic_options({ no_back = true, contents = {} })
    end
    local collection = namespace.collection
    local nodes = {
        row({ ui_text(safe_localize("grdl_k_entry_title"), 0.5, G.C.WHITE) }),
        row({ ui_text(safe_localize("grdl_k_entry_pick", { window.picks }), 0.32, G.C.UI.TEXT_LIGHT) }, { padding = 0.04 })
    }
    if rawget(_G, "CardArea") and rawget(_G, "Card") and rawget(_G, "G") and G.P_CENTERS then
        local area = CardArea(
            G.ROOM.T.x + 0.2 * G.ROOM.T.w / 2, G.ROOM.T.h,
            3.25 * G.CARD_W, 0.95 * G.CARD_H,
            { card_limit = 3, type = "title", highlight_limit = window.picks, collection = true })
        namespace.loadout_entry_area = area
        for _, card_id in ipairs(window.card_ids) do
            local record = Storage.find_card(collection, card_id)
            local center = record and G.P_CENTERS[record.center_key] or nil
            if center then
                local card = Card(area.T.x + area.T.w / 2, area.T.y, G.CARD_W, G.CARD_H,
                    (G.P_CARDS and G.P_CARDS.empty or nil), center)
                local flags = Catalog.edition_flags(record.edition)
                if flags then card:set_edition(flags, true, true) end
                card.grdl_record = record
                card.click = function(self)
                    if self.highlighted then
                        self.highlighted = false
                    else
                        local count = 0
                        for _, other in ipairs(area.cards) do
                            if other.highlighted then count = count + 1 end
                        end
                        if count >= window.picks then
                            if rawget(_G, "play_sound") then pcall(play_sound, "cancel") end
                            return
                        end
                        self.highlighted = true
                    end
                    if self.juice_up then self:juice_up(0.3, 0.3) end
                end
                area:emplace(card)
            end
        end
        nodes[#nodes + 1] = row({ { n = G.UIT.O, config = { object = area } } }, { padding = 0.05, no_fill = true })
    end
    nodes[#nodes + 1] = row({
        col({ UICommon.outline_button({
            button = "grdl_entry_confirm",
            solid = true,
            minw = 1.8, minh = 0.65,
            lines = { { text = safe_localize("grdl_b_entry_confirm"), scale = 0.32 } }
        }) }, { align = "cm", minw = 2.2 }),
        col({ UICommon.outline_button({
            button = "grdl_entry_skip",
            minw = 1.5, minh = 0.65,
            lines = { { text = safe_localize("grdl_b_entry_skip"), scale = 0.3 } }
        }) }, { align = "cm", minw = 1.9 })
    }, { padding = 0.08 })
    return create_UIBox_generic_options({
        back_func = "grdl_entry_skip",
        minw = 6.6, padding = 0.12,
        colour = G.C.L_BLACK, outline_colour = G.C.RED,
        contents = nodes
    })
end

function LoadoutUI.open_entry(namespace)
    local runtime = rawget(_G, "G")
    if not namespace or not namespace.loadout_entry_window then return end
    if not runtime or not runtime.FUNCS or not runtime.FUNCS.overlay_menu then return end
    if runtime.SETTINGS then runtime.SETTINGS.paused = true end
    runtime.FUNCS.overlay_menu({ definition = LoadoutUI.create_entry_definition(namespace) })
end

-- ===== hooks =====

function LoadoutUI.install(namespace, env)
    env = env or {}
    if not namespace then return false end
    if namespace.loadout_hooks_installed then return true end

    local funcs = env.funcs or (rawget(_G, "G") and G.FUNCS) or nil
    if not funcs then return false end

    local game_class = env.game_class or rawget(_G, "Game")
    if game_class and type(game_class.start_run) == "function" then
        local original_start = game_class.start_run
        game_class.start_run = function(self, args)
            local result = original_start(self, args)
            pcall(LoadoutUI.on_run_start, namespace)
            return result
        end
    end

    if type(funcs.cash_out) == "function" then
        local original_cash_out = funcs.cash_out
        funcs.cash_out = function(e)
            local result = original_cash_out(e)
            pcall(LoadoutUI.on_boss_cash_out, namespace)
            return result
        end
    end

    namespace.loadout_hooks_installed = true
    return true
end
```

   Entry confirm/skip handlers — add inside `install_runtime` (Task 4's function):

```lua
    runtime.FUNCS.grdl_entry_confirm = function(event)
        local area = namespace.loadout_entry_area
        local picked = {}
        for _, card in ipairs((area and area.cards) or {}) do
            if card.highlighted and card.grdl_record then picked[#picked + 1] = card.grdl_record.id end
        end
        if #picked > 0 then
            LoadoutUI.spawn_entries(namespace, picked, os.time())
        end
        namespace.loadout_entry_window = nil
        namespace.loadout_entry_area = nil
        if runtime.FUNCS.exit_overlay_menu then runtime.FUNCS.exit_overlay_menu() end
    end

    runtime.FUNCS.grdl_entry_skip = function(event)
        namespace.loadout_entry_window = nil
        namespace.loadout_entry_area = nil
        if runtime.FUNCS.exit_overlay_menu then runtime.FUNCS.exit_overlay_menu() end
    end
```

   And wire `main.lua` after `LoadoutUI.install_runtime(...)`:

```lua
pcall(LoadoutUI.install, Gradelatro)
```

   Note the test drives `funcs.cash_out` and reads `namespace.loadout_entry_window` directly (no E_MANAGER in tests — the event-queued `open_entry` only runs in game). `spawn_entries(namespace, card_ids, now)` signature: namespace, ids array, seed/now.

- [ ] **Step 4: Localization batch 3** (both files):

```lua
grdl_k_entry_title = "Transport Arrival",  -- 运输入场
grdl_k_entry_pick = "Pick up to #1#",      -- 至多选择 #1# 张
grdl_b_entry_confirm = "Deploy",           -- 确认入场
grdl_b_entry_skip = "Skip",                -- 跳过
grdl_k_reason_no_run = "No active run.",   -- 当前没有进行中的赛局。
```

- [ ] **Step 5: Run suite → green. Bytecode + leak scan. Commit:**

```
feat: loadout run integration - entry windows, spawning, ante counting
```

---

### Task 7: Proficiency tooltip surfaces (info box + tint) and final sweep

**Files:**
- Modify: `src/slab_ui.lua` (wrap extension), `tests/slab_ui_test.lua`

- [ ] **Step 1: Write the failing tests.** In `tests/slab_ui_test.lua`, study the existing `env.ui_def.card_h_popup` test harness (it builds a fake popup tree). Append after the existing wrap assertions:

```lua
local Proficiency = dofile("src/proficiency.lua")

-- proficiency info box appended for graded cards with antes
local prof_card = {
    children = {},
    grdl_record = {
        status = "graded", grade = 9, center_key = "j_joker",
        proficiency = { antes = 13, note = "my note", tooltip_colour = "FF8000" }
    }
}
local prof_popup = env.ui_def.card_h_popup(prof_card)
local prof_column = prof_popup.nodes[1].nodes
local info_box = prof_column[#prof_column]
H.assert_equal(info_box.grdl_prof_box, true, "proficiency box appended last")
local found_level = false
local function scan(node)
    if type(node) ~= "table" then return end
    if node.config and type(node.config.text) == "string" and node.config.text:find("II", 1, true) then found_level = true end
    for _, child in ipairs(node.nodes or {}) do scan(child) end
end
scan(info_box)
H.assert_true(found_level, "level label rendered in info box")

-- tint recolours the main box
local tinted = nil
local function find_tint(node)
    if type(node) ~= "table" then return end
    if node.config and type(node.config.colour) == "table" and node.config.colour[1] == 1 and math.abs(node.config.colour[2] - 0.502) < 0.01 then tinted = true end
    for _, child in ipairs(node.nodes or {}) do find_tint(child) end
end
find_tint(prof_popup)
H.assert_true(tinted, "tooltip tinted with the custom colour")

-- in-run loadout joker resolves its record through the namespace
local run_namespace = env.namespace
run_namespace.collection = {
    cards = {
        { id = "grdl_lj1", status = "graded", center_key = "j_joker",
          proficiency = { antes = 100 } }
    }
}
local loadout_joker = { children = {}, ability = { grdl_loadout_id = "grdl_lj1" } }
local joker_popup = env.ui_def.card_h_popup(loadout_joker)
local joker_column = joker_popup.nodes[1].nodes
H.assert_equal(joker_column[#joker_column].grdl_prof_box, true, "loadout joker gets the proficiency box")
```

(Adapt the fake-popup construction and `env` plumbing to match the existing test file's harness exactly — the wrap test there already builds `env.ui_def` and graded/raw fake cards; extend that same structure. The fake popup tree must give `popup.nodes[1].nodes` with at least one nested level, as the existing tests already do, AND its last column node plus that node's first child must each carry a `config.colour` table so the tint has a target. `env.namespace` is whatever namespace table the existing test passes to `SlabUI.install` — reuse it. The test must run the wrap with the level label "II" reaching the box via `proficiency_rows`'s composed text "grdl_k_prof_level II".)

- [ ] **Step 2: Run → fails.**

- [ ] **Step 3: Implement in `src/slab_ui.lua`.**
  - Add requires: `local Proficiency = load_src("proficiency.lua")`.
  - Add builders above `SlabUI.install`:

```lua
local function proficiency_rows(record)
    local level = Proficiency.level(record)
    local rows = {}
    -- compose prefix-key + value in code: the test environment's localize
    -- fallback returns bare keys, so #1# variable keys would not substitute
    rows[#rows + 1] = { { n = G.UIT.T, config = {
        text = UICommon.localize_text("grdl_k_prof_level") .. " " .. Proficiency.level_label(level),
        scale = 0.3, colour = G.C.UI.TEXT_DARK } } }
    local next_threshold = Proficiency.next_threshold(record)
    local progress = next_threshold
        and (UICommon.localize_text("grdl_k_prof_progress") .. " " .. tostring(Proficiency.antes(record)) .. "/" .. tostring(next_threshold))
        or UICommon.localize_text("grdl_k_prof_maxed")
    rows[#rows + 1] = { { n = G.UIT.T, config = { text = progress, scale = 0.27, colour = G.C.UI.TEXT_DARK } } }
    local note = record.proficiency and record.proficiency.note or nil
    if note and level >= 2 then
        rows[#rows + 1] = { { n = G.UIT.T, config = { text = note, scale = 0.27, colour = G.C.UI.TEXT_DARK } } }
    end
    return rows
end

local function fallback_info_box(rows, title)
    local row_nodes = {
        { n = G.UIT.R, config = { align = "cm", padding = 0.03 }, nodes = {
            { n = G.UIT.T, config = { text = title, scale = 0.3, colour = G.C.UI.TEXT_LIGHT } }
        } }
    }
    for _, cells in ipairs(rows) do
        row_nodes[#row_nodes + 1] = { n = G.UIT.R, config = { align = "cm", padding = 0.02 }, nodes = cells }
    end
    return { n = G.UIT.R, config = { align = "cm", padding = 0.05, r = 0.1, colour = G.C.WHITE }, nodes = row_nodes }
end

local function append_proficiency_box(popup, record)
    local column = popup_column(popup)
    if type(column) ~= "table" then return end
    local rows = proficiency_rows(record)
    local title = UICommon.localize_text("grdl_k_prof_title")
    local box
    if rawget(_G, "info_tip_from_rows") then
        box = info_tip_from_rows(rows, title)
    else
        box = fallback_info_box(rows, title)
    end
    box.grdl_prof_box = true
    column[#column + 1] = box
end

local function apply_tooltip_tint(popup, record)
    local hex = record.proficiency and record.proficiency.tooltip_colour or nil
    local colour = hex and Proficiency.parse_hex(hex) or nil
    if not colour then return end
    local column = popup_column(popup)
    local level_two = type(column) == "table" and column[#column] or nil
    if type(level_two) == "table" and level_two.config and level_two.config.colour then
        level_two.config.colour = colour
    end
    local level_three = type(level_two) == "table" and level_two.nodes and level_two.nodes[1] or nil
    if type(level_three) == "table" and level_three.config and level_three.config.colour then
        level_three.config.colour = colour
    end
end

local function resolve_loadout_record(namespace, card)
    local card_id = card and card.ability and card.ability.grdl_loadout_id or nil
    if not card_id or not namespace or not namespace.collection then return nil end
    for _, record in ipairs(namespace.collection.cards or {}) do
        if record.id == card_id then return record end
    end
    return nil
end
```

  - Rework the wrap body in `SlabUI.install`:

```lua
    local original_popup = ui_def.card_h_popup
    ui_def.card_h_popup = function(card)
        local popup = original_popup(card)
        if not popup or not card then return popup end
        if card.grdl_record then
            pcall(append_badge, popup, card)
            if card.grdl_record.status == "graded" then
                pcall(insert_slab_anchor, namespace, popup, card)
            end
            pcall(apply_tooltip_tint, popup, card.grdl_record)
            if card.grdl_record.status == "graded" then
                pcall(append_proficiency_box, popup, card.grdl_record)
            end
        else
            local record = resolve_loadout_record(namespace, card)
            if record then
                pcall(apply_tooltip_tint, popup, record)
                if record.status == "graded" then
                    pcall(append_proficiency_box, popup, record)
                end
            end
        end
        return popup
    end
```

   ORDER MATTERS: `apply_tooltip_tint` must run BEFORE `append_proficiency_box` (the tint targets `column[#column]`, which must still be the vanilla main box, not our appended one). Keep the call order exactly as shown above — tint first, then append. (The test appends the box last and tints earlier nodes; if your test ordering disagrees, fix the test to match this order.)

  - Localization batch 4 (both files):

```lua
grdl_k_prof_title = "Proficiency",      -- 熟练度
grdl_k_prof_level = "Level",            -- 等级
grdl_k_prof_progress = "Progress",      -- 进度
grdl_k_prof_maxed = "Mastered",         -- 已满级
```

- [ ] **Step 4: Run suite → green. Bytecode + leak scan.**

- [ ] **Step 5: Final sweep.**
  - `grep -rn "carry" src/ tests/ localization/ main.lua lovely.toml` → zero hits.
  - `grep -rn "grdl_k_" src/ main.lua | grep -oP "grdl_k_[a-z_0-9]+" | sort -u` and verify each key exists in BOTH locale files (spot-check with grep; any miss = add it).
  - Full suite green, complete output.

- [ ] **Step 6: Commit:**

```
feat: proficiency tooltip info box and custom tint

Closes out the loadout system: the card_h_popup wrap now renders the
vanilla-style proficiency info box (level, progress, custom note) for
graded collection cards and in-run loadout jokers, and applies the
G-tier custom tooltip tint.
```

---

## Post-plan smoke checklist (manual, in game)

1. 卡册 → 装配方案按钮 → 主界面（许可证 chips/实体卡/许可证按钮）；
2. 许可证界面：按序购买、运输购买与切换、余额不足反馈；
3. G 视图：评级卡一键加入、raw 卡二次确认文案、赛局内锁定提示；
4. 赛局：金档底注 1 boss 后弹窗（选 2 张/跳过/ESC）、负片 0 槽、0 级无版本、III 级永恒贴纸；
5. 熟练度：过底注后数值+1（存档生效）、tooltip 信息框等级/进度/自定义文本；
6. perk 输入框：II 文本、IV 徽章、G HEX 实时预览与 tooltip 底色；
7. 旧存档加载：carried 卡变回 raw，无报错。

## Tunables expected to need iteration

License/transport prices (`config.loadout`), entry popup delay (0.7s), license screen cell sizes, info box text scales, tint target node (level_two vs level_three — verify visually which is the dark-grey base and drop the other if it looks wrong).
