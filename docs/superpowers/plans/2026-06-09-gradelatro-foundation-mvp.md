# Gradelatro Foundation MVP Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build the testable foundation for Gradelatro: mod skeleton, configuration, persistent collection state, economic rules, Stake gates, authenticated editions, condition generation, PSA-style grading, and Joker catalog discovery.

**Architecture:** Keep Balatro/SMODS integration thin and place deterministic rules in small Lua modules under `src/`. Pure modules are tested with LuaJIT outside the game; in-game modules only load the namespace, register config, and prepare integration points for later UI and run hooks.

**Tech Stack:** Lua 5.1/LuaJIT, SMODS, Lovely, PowerShell, local LuaJIT test scripts.

---

## Scope

This plan covers the foundation MVP only. It creates a loadable SMODS mod shell and a tested rule/data layer. In-game UI, post-win buyout screens, real-time grading queue UI, market screens, and raw-card run activation receive separate plans after this foundation is merged.

## Execution Constraints

- Data persistence must stay centralized. Foundation work writes collection data only through `src/storage.lua`, and later integration work should continue to avoid scattered direct mutation of SMODS or profile state.
- Lovely patches are expected for out-of-the-box integration in later phases. This foundation should keep hook-facing APIs small and stable so Lovely patch payloads can call into Gradelatro modules instead of embedding business rules.
- Other Balatro mods may be used as references for SMODS conventions and UI patterns, but every borrowed pattern needs local judgment. Do not mirror a mod's structure just because it works there.

## Roadmap

1. **Foundation MVP:** This plan. Create skeleton, config, rules, storage, catalog discovery, and unit tests.
2. **Post-Win Buyout Integration:** Hook win flow, collect ending Joker candidates, apply Stake gates, charge `G-credit`, and create raw collection instances.
3. **Card Binder UI:** Add Gradelatro card binder screen, series filters, raw/graded/listed states, and missing-mod fallback display.
4. **Grading Queue and Market:** Add real-time queue processing, service tiers, simulated series heat, system buy/sell screens, and special orders.
5. **Raw Card Run Carry:** Add left HUD sleeve slot, pre-hand activation, Joker-slot insertion, return/loss handling, and wear settlement.

## File Structure

- Create: `manifest.json`  
  SMODS metadata, dependencies, entry file, and default config.
- Create: `main.lua`  
  Minimal entry point. Defines `Gradelatro`, normalizes config, loads modules, and exposes test-friendly functions.
- Create: `src/bootstrap.lua`  
  Module loader and namespace initializer.
- Create: `src/config.lua`  
  Default config, deep merge, and normalization.
- Create: `src/economy.lua`  
  `RAV`, buyout price, grading fees, settlement `G-credit`, and market spread math.
- Create: `src/stakes.lua`  
  Stake anchor comparison and rarity buyout eligibility.
- Create: `src/condition.lua`  
  Hidden condition generation, wear application, grade calculation, and grade multipliers.
- Create: `src/storage.lua`  
  Schema initialization, migration, collection instance creation, currency mutation, and safe missing-card records.
- Create: `src/catalog.lua`  
  Joker center discovery, series assignment, authenticated edition normalization, and rarity mapping.
- Create: `tests/test_helper.lua`  
  Tiny LuaJIT assertion helpers.
- Create: `tests/config_test.lua`  
  Config normalization tests.
- Create: `tests/economy_test.lua`  
  Value model tests.
- Create: `tests/stakes_test.lua`  
  Stake gate tests.
- Create: `tests/condition_test.lua`  
  Condition and grading tests.
- Create: `tests/storage_test.lua`  
  Storage and migration tests.
- Create: `tests/catalog_test.lua`  
  Catalog discovery and compatibility tests.
- Create: `tests/run_all.lua`  
  Single test runner for local verification.
- Create: `.gitignore`  
  Ignore editor caches, logs, Lua bytecode, and local dump artifacts.

---

### Task 1: Repository and Mod Skeleton

**Files:**
- Create: `.gitignore`
- Create: `manifest.json`
- Create: `main.lua`
- Create: `src/bootstrap.lua`

- [ ] **Step 1: Initialize git repository**

Run:

```powershell
git init
```

Expected: repository initialized in `C:\Users\ChromaPIE\AppData\Roaming\Balatro\Mods\Gradelatro`.

- [ ] **Step 2: Create `.gitignore`**

Create `.gitignore`:

```gitignore
# Editor and OS noise
.DS_Store
Thumbs.db
*.swp
*.tmp

# Lua build artifacts and logs
*.luac
*.log

# Local dump artifacts
lovely/dump/
lovely/game-dump/
```

- [ ] **Step 3: Create SMODS manifest**

Create `manifest.json`:

```json
{
  "id": "Gradelatro",
  "name": "Gradelatro",
  "display_name": "Gradelatro",
  "author": ["ChromaPIE"],
  "description": "Joker card collecting, authentication, grading, and light market systems for Balatro.",
  "prefix": "grdl",
  "main_file": "main.lua",
  "priority": 0,
  "badge_colour": "C8A45D",
  "badge_text_colour": "1E1A16",
  "version": "0.1.0",
  "dependencies": [
    "Steamodded (>=1.0.0~BETA-0323b)",
    "Lovely (>=0.6)"
  ],
  "allow_redistribution": true
}
```

- [ ] **Step 4: Create bootstrap module**

Create `src/bootstrap.lua`:

```lua
local Bootstrap = {}

function Bootstrap.init(mod)
    local Gradelatro = rawget(_G, "Gradelatro") or {}
    Gradelatro.mod = mod
    Gradelatro.path = mod and mod.path or "."
    Gradelatro.version = mod and mod.version or "0.1.0"
    Gradelatro.modules = Gradelatro.modules or {}
    _G.Gradelatro = Gradelatro
    return Gradelatro
end

function Bootstrap.attach(namespace, name, module)
    namespace.modules[name] = module
    namespace[name] = module
    return module
end

return Bootstrap
```

- [ ] **Step 5: Create main entry point**

Create `main.lua`:

```lua
local current_mod = SMODS and SMODS.current_mod or {
    path = ".",
    version = "0.1.0",
    config = {}
}

local function load_src(path)
    if SMODS and SMODS.load_file then
        return assert(SMODS.load_file("src/" .. path))()
    end
    return dofile("src/" .. path)
end

local Bootstrap = load_src("bootstrap.lua")
local Gradelatro = Bootstrap.init(current_mod)

local Config = load_src("config.lua")
Bootstrap.attach(Gradelatro, "Config", Config)

Gradelatro.config = Config.normalize(current_mod.config or {})
current_mod.config = Gradelatro.config

return Gradelatro
```

- [ ] **Step 6: Run syntax check**

Run:

```powershell
$lua='C:\Users\ChromaPIE\AppData\Local\Programs\LuaJIT\bin\luajit.exe'; & $lua -b main.lua NUL; & $lua -b src\bootstrap.lua NUL
```

Expected: no output and exit code `0`.

- [ ] **Step 7: Commit skeleton**

Run:

```powershell
git add .gitignore manifest.json main.lua src/bootstrap.lua
git commit -m "chore: add Gradelatro mod skeleton"
```

Expected: commit succeeds.

---

### Task 2: Config Normalization

**Files:**
- Create: `src/config.lua`
- Create: `tests/test_helper.lua`
- Create: `tests/config_test.lua`

- [ ] **Step 1: Write test helper**

Create `tests/test_helper.lua`:

```lua
local Helper = {}

function Helper.assert_equal(actual, expected, label)
    if actual ~= expected then
        error((label or "assert_equal") .. ": expected " .. tostring(expected) .. ", got " .. tostring(actual), 2)
    end
end

function Helper.assert_true(value, label)
    if not value then
        error((label or "assert_true") .. ": expected truthy value", 2)
    end
end

function Helper.assert_near(actual, expected, epsilon, label)
    epsilon = epsilon or 0.000001
    if math.abs(actual - expected) > epsilon then
        error((label or "assert_near") .. ": expected " .. tostring(expected) .. ", got " .. tostring(actual), 2)
    end
end

return Helper
```

- [ ] **Step 2: Write failing config tests**

Create `tests/config_test.lua`:

```lua
local H = dofile("tests/test_helper.lua")
local Config = dofile("src/config.lua")

local normalized = Config.normalize({
    economy = { buyout_mult = 1.25 },
    grading = { default_service = "priority" }
})

H.assert_equal(normalized.schema_version, 1, "schema version")
H.assert_near(normalized.economy.buyout_mult, 1.25, 0.000001, "override buyout mult")
H.assert_near(normalized.economy.rarity_base.common, 35, 0.000001, "default common base")
H.assert_equal(normalized.grading.default_service, "priority", "override grading service")
H.assert_near(normalized.market.heat_min, 0.75, 0.000001, "market heat min")

local empty = Config.normalize(nil)
H.assert_equal(empty.authenticated_editions.negative, true, "negative edition accepted")
H.assert_equal(empty.authenticated_editions.cry_exotic, nil, "unknown custom edition not accepted")

print("config tests ok")
```

- [ ] **Step 3: Run test to verify it fails**

Run:

```powershell
$lua='C:\Users\ChromaPIE\AppData\Local\Programs\LuaJIT\bin\luajit.exe'; & $lua tests\config_test.lua
```

Expected: FAIL because `src/config.lua` does not exist or does not return `normalize`.

- [ ] **Step 4: Create config module**

Create `src/config.lua`:

```lua
local Config = {}

Config.DEFAULTS = {
    schema_version = 1,
    economy = {
        buyout_mult = 1.0,
        first_copy_mult = 0.85,
        duplicate_mult = 1.0,
        hoard_mult = 1.15,
        rarity_base = {
            common = 35,
            uncommon = 85,
            rare = 220,
            legendary = 750,
            exotic = 1000,
            unknown_high = 1000
        },
        edition_mult = {
            base = 1.00,
            foil = 1.45,
            holographic = 1.80,
            polychrome = 2.80,
            negative = 5.00
        }
    },
    settlement = {
        cash_rate_win = 0.25,
        cash_rate_loss = 0.10,
        loss_cap = 20,
        gates = {
            red = { bonus = 20, cash_cap = 25 },
            blue = { bonus = 35, cash_cap = 40 },
            pre_gold = { bonus = 50, cash_cap = 60 },
            gold_plus = { bonus = 75, cash_cap = 85 }
        }
    },
    grading = {
        default_service = "standard",
        service_rates = {
            economy = 0.10,
            standard = 0.16,
            priority = 0.28,
            express = 0.45,
            prescreen = 0.06
        },
        minimum_fee = 15
    },
    market = {
        heat_min = 0.75,
        heat_max = 1.35,
        system_buy_min = 0.70,
        system_buy_max = 0.82,
        system_sell_min = 1.15,
        system_sell_max = 1.35,
        special_order_min = 1.35,
        special_order_max = 1.75
    },
    authenticated_editions = {
        base = true,
        foil = true,
        holographic = true,
        polychrome = true,
        negative = true
    }
}

local function is_array(value)
    if type(value) ~= "table" then return false end
    local count = 0
    for k, _ in pairs(value) do
        if type(k) ~= "number" then return false end
        count = count + 1
    end
    return count > 0
end

local function deep_copy(value)
    if type(value) ~= "table" then return value end
    local out = {}
    for k, v in pairs(value) do
        out[k] = deep_copy(v)
    end
    return out
end

local function deep_merge(base, override)
    if type(override) ~= "table" then return base end
    for k, v in pairs(override) do
        if type(v) == "table" and type(base[k]) == "table" and not is_array(v) then
            deep_merge(base[k], v)
        else
            base[k] = deep_copy(v)
        end
    end
    return base
end

function Config.normalize(input)
    local normalized = deep_copy(Config.DEFAULTS)
    if type(input) == "table" then
        deep_merge(normalized, input)
    end
    normalized.schema_version = Config.DEFAULTS.schema_version
    return normalized
end

return Config
```

- [ ] **Step 5: Run config tests**

Run:

```powershell
$lua='C:\Users\ChromaPIE\AppData\Local\Programs\LuaJIT\bin\luajit.exe'; & $lua tests\config_test.lua
```

Expected: `config tests ok`.

- [ ] **Step 6: Commit config**

Run:

```powershell
git add src/config.lua tests/test_helper.lua tests/config_test.lua
git commit -m "test: add config normalization"
```

Expected: commit succeeds.

---

### Task 3: Economy Rule Module

**Files:**
- Create: `src/economy.lua`
- Create: `tests/economy_test.lua`
- Modify: `main.lua`

- [ ] **Step 1: Write failing economy tests**

Create `tests/economy_test.lua`:

```lua
local H = dofile("tests/test_helper.lua")
local Config = dofile("src/config.lua")
local Economy = dofile("src/economy.lua")

local config = Config.normalize({})

local rav = Economy.raw_anchor_value(config, {
    rarity = "rare",
    edition = "polychrome",
    series_heat = 1.10,
    availability_mult = 1.0
})

H.assert_near(rav, 677.6, 0.000001, "rare polychrome RAV")
H.assert_equal(Economy.buyout_price(config, { rav = 100, owned_count = 0 }), 85, "first copy discount")
H.assert_equal(Economy.buyout_price(config, { rav = 100, owned_count = 1 }), 100, "second copy base")
H.assert_equal(Economy.buyout_price(config, { rav = 100, owned_count = 3 }), 115, "hoard multiplier")
H.assert_equal(Economy.grading_fee(config, 100, "standard"), 16, "standard fee")
H.assert_equal(Economy.grading_fee(config, 50, "prescreen"), 15, "minimum fee")
H.assert_equal(Economy.settlement_g(config, { gate = "blue", won = true, dollars = 100 }), 75, "blue win settlement")
H.assert_equal(Economy.settlement_g(config, { gate = "blue", won = false, dollars = 100 }), 10, "loss settlement")

print("economy tests ok")
```

- [ ] **Step 2: Run test to verify it fails**

Run:

```powershell
$lua='C:\Users\ChromaPIE\AppData\Local\Programs\LuaJIT\bin\luajit.exe'; & $lua tests\economy_test.lua
```

Expected: FAIL because `src/economy.lua` does not exist or does not return the expected functions.

- [ ] **Step 3: Create economy module**

Create `src/economy.lua`:

```lua
local Economy = {}

local function ceil(value)
    return math.ceil(value - 0.0000001)
end

function Economy.raw_anchor_value(config, args)
    args = args or {}
    local rarity = args.rarity or "common"
    local edition = args.edition or "base"
    local rarity_base = config.economy.rarity_base[rarity] or config.economy.rarity_base.unknown_high
    local edition_mult = config.economy.edition_mult[edition] or config.economy.edition_mult.base
    local series_heat = args.series_heat or 1.0
    local availability_mult = args.availability_mult or 1.0
    return rarity_base * edition_mult * series_heat * availability_mult
end

function Economy.buyout_price(config, args)
    args = args or {}
    local rav = args.rav or 0
    local owned_count = args.owned_count or 0
    local mult = config.economy.buyout_mult
    if owned_count <= 0 then
        mult = mult * config.economy.first_copy_mult
    elseif owned_count >= 3 then
        mult = mult * config.economy.hoard_mult
    else
        mult = mult * config.economy.duplicate_mult
    end
    return ceil(rav * mult)
end

function Economy.grading_fee(config, rav, service)
    service = service or config.grading.default_service
    local rate = config.grading.service_rates[service] or config.grading.service_rates.standard
    return math.max(config.grading.minimum_fee, ceil((rav or 0) * rate))
end

function Economy.settlement_g(config, args)
    args = args or {}
    local dollars = math.max(0, math.floor(args.dollars or 0))
    if not args.won then
        return math.min(math.floor(dollars * config.settlement.cash_rate_loss), config.settlement.loss_cap)
    end

    local gate = args.gate or "red"
    local gate_config = config.settlement.gates[gate] or config.settlement.gates.red
    local cash_g = math.min(math.floor(dollars * config.settlement.cash_rate_win), gate_config.cash_cap)
    return gate_config.bonus + cash_g
end

function Economy.graded_value(rav, grade, grade_mult)
    local mult = grade_mult and grade_mult[grade] or nil
    if not mult then return 0 end
    return rav * mult
end

return Economy
```

- [ ] **Step 4: Attach economy module in main**

Modify `main.lua` after attaching `Config`:

```lua
local Economy = load_src("economy.lua")
Bootstrap.attach(Gradelatro, "Economy", Economy)
```

- [ ] **Step 5: Run economy tests**

Run:

```powershell
$lua='C:\Users\ChromaPIE\AppData\Local\Programs\LuaJIT\bin\luajit.exe'; & $lua tests\economy_test.lua
```

Expected: `economy tests ok`.

- [ ] **Step 6: Commit economy rules**

Run:

```powershell
git add main.lua src/economy.lua tests/economy_test.lua
git commit -m "test: add Gradelatro economy rules"
```

Expected: commit succeeds.

---

### Task 4: Stake Gate and Rarity Eligibility

**Files:**
- Create: `src/stakes.lua`
- Create: `tests/stakes_test.lua`
- Modify: `main.lua`

- [ ] **Step 1: Write failing Stake tests**

Create `tests/stakes_test.lua`:

```lua
local H = dofile("tests/test_helper.lua")
local Stakes = dofile("src/stakes.lua")

local anchors = {
    stake_red = 2,
    stake_blue = 5,
    stake_gold = 8
}

H.assert_equal(Stakes.gate_for_level(anchors, 1), "red", "white below red")
H.assert_equal(Stakes.gate_for_level(anchors, 2), "red", "red gate")
H.assert_equal(Stakes.gate_for_level(anchors, 4), "blue", "between red and blue")
H.assert_equal(Stakes.gate_for_level(anchors, 6), "pre_gold", "between blue and gold")
H.assert_equal(Stakes.gate_for_level(anchors, 8), "gold_plus", "gold gate")
H.assert_equal(Stakes.can_buyout("red", "common"), true, "red common")
H.assert_equal(Stakes.can_buyout("red", "uncommon"), false, "red uncommon blocked")
H.assert_equal(Stakes.can_buyout("blue", "uncommon"), true, "blue uncommon")
H.assert_equal(Stakes.can_buyout("pre_gold", "rare"), true, "pre-gold rare")
H.assert_equal(Stakes.can_buyout("pre_gold", "legendary"), false, "pre-gold legendary blocked")
H.assert_equal(Stakes.can_buyout("gold_plus", "exotic"), true, "gold exotic")
H.assert_equal(Stakes.can_buyout("gold_plus", "unknown_high"), true, "gold unknown high")

print("stakes tests ok")
```

- [ ] **Step 2: Run test to verify it fails**

Run:

```powershell
$lua='C:\Users\ChromaPIE\AppData\Local\Programs\LuaJIT\bin\luajit.exe'; & $lua tests\stakes_test.lua
```

Expected: FAIL because `src/stakes.lua` does not exist or lacks expected functions.

- [ ] **Step 3: Create Stake module**

Create `src/stakes.lua`:

```lua
local Stakes = {}

local ALLOWED = {
    red = { common = true },
    blue = { common = true, uncommon = true },
    pre_gold = { common = true, uncommon = true, rare = true },
    gold_plus = {
        common = true,
        uncommon = true,
        rare = true,
        legendary = true,
        exotic = true,
        unknown_high = true
    }
}

function Stakes.gate_for_level(anchors, stake_level)
    stake_level = stake_level or 1
    local red = anchors.stake_red or 2
    local blue = anchors.stake_blue or 5
    local gold = anchors.stake_gold or 8
    if stake_level <= red then return "red" end
    if stake_level <= blue then return "blue" end
    if stake_level < gold then return "pre_gold" end
    return "gold_plus"
end

function Stakes.can_buyout(gate, rarity)
    local allowed = ALLOWED[gate] or ALLOWED.red
    return allowed[rarity] == true
end

return Stakes
```

- [ ] **Step 4: Attach Stake module in main**

Modify `main.lua` after attaching `Economy`:

```lua
local Stakes = load_src("stakes.lua")
Bootstrap.attach(Gradelatro, "Stakes", Stakes)
```

- [ ] **Step 5: Run Stake tests**

Run:

```powershell
$lua='C:\Users\ChromaPIE\AppData\Local\Programs\LuaJIT\bin\luajit.exe'; & $lua tests\stakes_test.lua
```

Expected: `stakes tests ok`.

- [ ] **Step 6: Commit Stake gates**

Run:

```powershell
git add main.lua src/stakes.lua tests/stakes_test.lua
git commit -m "test: add Stake buyout gates"
```

Expected: commit succeeds.

---

### Task 5: Condition, Wear, and PSA-Style Grade Rules

**Files:**
- Create: `src/condition.lua`
- Create: `tests/condition_test.lua`
- Modify: `main.lua`

- [ ] **Step 1: Write failing condition tests**

Create `tests/condition_test.lua`:

```lua
local H = dofile("tests/test_helper.lua")
local Condition = dofile("src/condition.lua")

local perfect = {
    centering = 9.8,
    print_quality = 9.8,
    corners = 9.8,
    edges = 9.8,
    surface = 9.8
}

local near_mint = {
    centering = 9.4,
    print_quality = 9.2,
    corners = 9.1,
    edges = 9.0,
    surface = 9.2
}

local damaged_surface = {
    centering = 9.8,
    print_quality = 9.8,
    corners = 9.8,
    edges = 9.8,
    surface = 7.0
}

H.assert_equal(Condition.grade(perfect), 10, "perfect grade")
H.assert_equal(Condition.grade(near_mint), 9, "near mint grade")
H.assert_equal(Condition.grade(damaged_surface), 7, "surface cap")

local worn = Condition.apply_wear(perfect, "polychrome", 0.50)
H.assert_true(worn.surface < perfect.surface, "wear lowers surface")
H.assert_equal(worn.centering, perfect.centering, "wear does not alter centering")
H.assert_equal(worn.print_quality, perfect.print_quality, "wear does not alter print quality")

local generated = Condition.generate(12345, "negative")
H.assert_true(generated.centering >= 6.0 and generated.centering <= 10.0, "generated centering range")
H.assert_true(generated.surface >= 6.0 and generated.surface <= 10.0, "generated surface range")

H.assert_near(Condition.grade_multiplier(10), 6.0, 0.000001, "grade 10 multiplier")
H.assert_near(Condition.grade_multiplier(8), 1.2, 0.000001, "grade 8 multiplier")

print("condition tests ok")
```

- [ ] **Step 2: Run test to verify it fails**

Run:

```powershell
$lua='C:\Users\ChromaPIE\AppData\Local\Programs\LuaJIT\bin\luajit.exe'; & $lua tests\condition_test.lua
```

Expected: FAIL because `src/condition.lua` does not exist or lacks expected functions.

- [ ] **Step 3: Create condition module**

Create `src/condition.lua`:

```lua
local Condition = {}

local WEAR = {
    base = { corners = 1.00, edges = 1.00, surface = 1.00 },
    foil = { corners = 0.90, edges = 0.90, surface = 1.30 },
    holographic = { corners = 1.00, edges = 1.00, surface = 1.50 },
    polychrome = { corners = 1.10, edges = 1.10, surface = 1.70 },
    negative = { corners = 1.25, edges = 1.25, surface = 1.40 }
}

local GRADE_MULT = {
    [10] = 6.0,
    [9] = 2.2,
    [8] = 1.2,
    [7] = 0.85,
    [6] = 0.65,
    [5] = 0.50,
    [4] = 0.40,
    [3] = 0.32,
    [2] = 0.26,
    [1] = 0.20
}

local function clamp(value, min_value, max_value)
    if value < min_value then return min_value end
    if value > max_value then return max_value end
    return value
end

local function lcg(seed)
    local state = seed % 2147483647
    return function()
        state = (state * 48271) % 2147483647
        return state / 2147483647
    end
end

local function average(condition)
    return (
        condition.centering +
        condition.print_quality +
        condition.corners +
        condition.edges +
        condition.surface
    ) / 5
end

local function min_mutable(condition)
    return math.min(condition.corners, condition.edges, condition.surface)
end

function Condition.generate(seed, edition)
    local rand = lcg(seed or os.time())
    local edition_surface_penalty = edition == "polychrome" and 0.20 or edition == "negative" and 0.15 or edition == "holographic" and 0.10 or 0
    return {
        centering = clamp(8.4 + rand() * 1.6, 6.0, 10.0),
        print_quality = clamp(8.2 + rand() * 1.8 - edition_surface_penalty, 6.0, 10.0),
        corners = clamp(8.1 + rand() * 1.9, 6.0, 10.0),
        edges = clamp(8.1 + rand() * 1.9, 6.0, 10.0),
        surface = clamp(8.0 + rand() * 2.0 - edition_surface_penalty, 6.0, 10.0)
    }
end

function Condition.apply_wear(condition, edition, intensity)
    intensity = intensity or 0.25
    local wear = WEAR[edition or "base"] or WEAR.base
    return {
        centering = condition.centering,
        print_quality = condition.print_quality,
        corners = clamp(condition.corners - intensity * wear.corners, 1.0, 10.0),
        edges = clamp(condition.edges - intensity * wear.edges, 1.0, 10.0),
        surface = clamp(condition.surface - intensity * wear.surface, 1.0, 10.0)
    }
end

function Condition.grade(condition)
    local avg = average(condition)
    local min_part = math.min(condition.centering, condition.print_quality, min_mutable(condition))
    if avg >= 9.65 and min_part >= 9.4 then return 10 end
    if avg >= 9.00 and min_part >= 8.5 then return 9 end
    if avg >= 8.00 and min_part >= 7.5 then return 8 end
    if avg >= 7.00 and min_part >= 6.5 then return 7 end
    if avg >= 6.00 and min_part >= 5.5 then return 6 end
    if avg >= 5.00 then return 5 end
    if avg >= 4.00 then return 4 end
    if avg >= 3.00 then return 3 end
    if avg >= 2.00 then return 2 end
    return 1
end

function Condition.grade_multiplier(grade)
    return GRADE_MULT[grade] or 0
end

return Condition
```

- [ ] **Step 4: Attach condition module in main**

Modify `main.lua` after attaching `Stakes`:

```lua
local Condition = load_src("condition.lua")
Bootstrap.attach(Gradelatro, "Condition", Condition)
```

- [ ] **Step 5: Run condition tests**

Run:

```powershell
$lua='C:\Users\ChromaPIE\AppData\Local\Programs\LuaJIT\bin\luajit.exe'; & $lua tests\condition_test.lua
```

Expected: `condition tests ok`.

- [ ] **Step 6: Commit condition rules**

Run:

```powershell
git add main.lua src/condition.lua tests/condition_test.lua
git commit -m "test: add card condition grading rules"
```

Expected: commit succeeds.

---

### Task 6: Storage Schema and Collection Records

**Files:**
- Create: `src/storage.lua`
- Create: `tests/storage_test.lua`
- Modify: `main.lua`

- [ ] **Step 1: Write failing storage tests**

Create `tests/storage_test.lua`:

```lua
local H = dofile("tests/test_helper.lua")
local Storage = dofile("src/storage.lua")

local state = Storage.normalize(nil)
H.assert_equal(state.schema_version, 1, "schema version")
H.assert_equal(state.currency_g, 0, "initial currency")
H.assert_equal(#state.cards, 0, "initial cards")

Storage.add_currency(state, 120)
Storage.add_currency(state, -20)
H.assert_equal(state.currency_g, 100, "currency mutation")

local card = Storage.add_raw_card(state, {
    center_key = "j_joker",
    set_key = "BALATRO Standard",
    mod_id = "Balatro",
    rarity = "common",
    edition = "base",
    condition = {
        centering = 9.1,
        print_quality = 9.0,
        corners = 8.9,
        edges = 9.2,
        surface = 9.0
    },
    acquired_at = 1000,
    source = "win_buyout"
})

H.assert_equal(card.id, "grdl_1", "first card id")
H.assert_equal(card.status, "raw", "raw status")
H.assert_equal(state.next_card_id, 2, "next id")
H.assert_equal(Storage.count_owned_center(state, "j_joker"), 1, "owned count")

Storage.mark_lost(state, card.id, "destroyed_in_run")
H.assert_equal(state.cards[1].status, "lost", "lost status")
H.assert_equal(state.cards[1].lost_reason, "destroyed_in_run", "lost reason")

print("storage tests ok")
```

- [ ] **Step 2: Run test to verify it fails**

Run:

```powershell
$lua='C:\Users\ChromaPIE\AppData\Local\Programs\LuaJIT\bin\luajit.exe'; & $lua tests\storage_test.lua
```

Expected: FAIL because `src/storage.lua` does not exist or lacks expected functions.

- [ ] **Step 3: Create storage module**

Create `src/storage.lua`:

```lua
local Storage = {}

local CURRENT_SCHEMA = 1

local function copy_condition(condition)
    return {
        centering = condition.centering,
        print_quality = condition.print_quality,
        corners = condition.corners,
        edges = condition.edges,
        surface = condition.surface
    }
end

function Storage.normalize(input)
    local state = type(input) == "table" and input or {}
    state.schema_version = CURRENT_SCHEMA
    state.currency_g = math.max(0, math.floor(state.currency_g or 0))
    state.next_card_id = math.max(1, math.floor(state.next_card_id or 1))
    state.cards = type(state.cards) == "table" and state.cards or {}
    state.grading_queue = type(state.grading_queue) == "table" and state.grading_queue or {}
    state.market = type(state.market) == "table" and state.market or { series_heat = {} }
    state.market.series_heat = type(state.market.series_heat) == "table" and state.market.series_heat or {}
    return state
end

function Storage.add_currency(state, amount)
    state.currency_g = math.max(0, math.floor((state.currency_g or 0) + (amount or 0)))
    return state.currency_g
end

function Storage.spend_currency(state, amount)
    amount = math.max(0, math.floor(amount or 0))
    if (state.currency_g or 0) < amount then return false end
    state.currency_g = state.currency_g - amount
    return true
end

function Storage.add_raw_card(state, args)
    local id = "grdl_" .. tostring(state.next_card_id)
    state.next_card_id = state.next_card_id + 1
    local card = {
        id = id,
        status = "raw",
        center_key = args.center_key,
        set_key = args.set_key,
        mod_id = args.mod_id,
        rarity = args.rarity,
        edition = args.edition,
        condition = copy_condition(args.condition),
        acquired_at = args.acquired_at,
        source = args.source
    }
    state.cards[#state.cards + 1] = card
    return card
end

function Storage.find_card(state, card_id)
    for _, card in ipairs(state.cards) do
        if card.id == card_id then return card end
    end
    return nil
end

function Storage.mark_lost(state, card_id, reason)
    local card = Storage.find_card(state, card_id)
    if not card then return false end
    card.status = "lost"
    card.lost_reason = reason or "unknown"
    return true
end

function Storage.count_owned_center(state, center_key)
    local count = 0
    for _, card in ipairs(state.cards) do
        if card.center_key == center_key and card.status ~= "lost" and card.status ~= "sold" then
            count = count + 1
        end
    end
    return count
end

return Storage
```

- [ ] **Step 4: Attach storage module and state in main**

Modify `main.lua` after attaching `Condition`:

```lua
local Storage = load_src("storage.lua")
Bootstrap.attach(Gradelatro, "Storage", Storage)

current_mod.config.collection = Storage.normalize(current_mod.config.collection)
Gradelatro.collection = current_mod.config.collection
```

- [ ] **Step 5: Run storage tests**

Run:

```powershell
$lua='C:\Users\ChromaPIE\AppData\Local\Programs\LuaJIT\bin\luajit.exe'; & $lua tests\storage_test.lua
```

Expected: `storage tests ok`.

- [ ] **Step 6: Commit storage**

Run:

```powershell
git add main.lua src/storage.lua tests/storage_test.lua
git commit -m "test: add collection storage schema"
```

Expected: commit succeeds.

---

### Task 7: Joker Catalog Discovery

**Files:**
- Create: `src/catalog.lua`
- Create: `tests/catalog_test.lua`
- Modify: `main.lua`

- [ ] **Step 1: Write failing catalog tests**

Create `tests/catalog_test.lua`:

```lua
local H = dofile("tests/test_helper.lua")
local Config = dofile("src/config.lua")
local Catalog = dofile("src/catalog.lua")

local config = Config.normalize({})
local centers = {
    j_joker = { key = "j_joker", set = "Joker", rarity = 1, name = "Joker" },
    j_rare = { key = "j_rare", set = "Joker", rarity = 3, name = "Rare Joker" },
    j_legendary = { key = "j_legendary", set = "Joker", rarity = 4, name = "Legendary Joker" },
    c_fool = { key = "c_fool", set = "Tarot", rarity = 1, name = "The Fool" },
    j_modded = { key = "j_modded", set = "Joker", rarity = "exotic", name = "Modded Joker", mod = { id = "Cryptid" } }
}

local catalog = Catalog.discover(config, centers)
H.assert_equal(#catalog, 4, "only Jokers are cataloged")
H.assert_equal(catalog[1].center_key, "j_joker", "sorted first key")
H.assert_equal(catalog[1].series_key, "BALATRO Standard", "vanilla series")
H.assert_equal(catalog[1].rarity, "common", "common rarity")
H.assert_equal(catalog[3].rarity, "legendary", "legendary rarity")
H.assert_equal(catalog[4].series_key, "Cryptid Expansion", "mod series")
H.assert_equal(catalog[4].rarity, "exotic", "exotic rarity")

H.assert_equal(Catalog.normalize_edition(config, nil), "base", "nil edition")
H.assert_equal(Catalog.normalize_edition(config, "negative"), "negative", "negative edition")
H.assert_equal(Catalog.normalize_edition(config, "cry_oversat"), "base", "custom edition rejected")

print("catalog tests ok")
```

- [ ] **Step 2: Run test to verify it fails**

Run:

```powershell
$lua='C:\Users\ChromaPIE\AppData\Local\Programs\LuaJIT\bin\luajit.exe'; & $lua tests\catalog_test.lua
```

Expected: FAIL because `src/catalog.lua` does not exist or lacks expected functions.

- [ ] **Step 3: Create catalog module**

Create `src/catalog.lua`:

```lua
local Catalog = {}

local function rarity_name(raw)
    if raw == 1 or raw == "common" or raw == "Common" then return "common" end
    if raw == 2 or raw == "uncommon" or raw == "Uncommon" then return "uncommon" end
    if raw == 3 or raw == "rare" or raw == "Rare" then return "rare" end
    if raw == 4 or raw == "legendary" or raw == "Legendary" then return "legendary" end
    if raw == "exotic" or raw == "Exotic" then return "exotic" end
    return "unknown_high"
end

local function mod_id_for_center(center)
    if center.mod and center.mod.id then return center.mod.id end
    if center.mod_id then return center.mod_id end
    return "Balatro"
end

local function series_for_mod(mod_id)
    if mod_id == "Balatro" then return "BALATRO Standard" end
    return tostring(mod_id) .. " Expansion"
end

function Catalog.normalize_edition(config, edition)
    local key = edition or "base"
    if config.authenticated_editions[key] then return key end
    return "base"
end

function Catalog.discover(config, centers)
    local out = {}
    for _, center in pairs(centers or {}) do
        if center.set == "Joker" then
            local mod_id = mod_id_for_center(center)
            out[#out + 1] = {
                center_key = center.key,
                name = center.name or center.key,
                mod_id = mod_id,
                series_key = series_for_mod(mod_id),
                rarity = rarity_name(center.rarity)
            }
        end
    end
    table.sort(out, function(a, b) return a.center_key < b.center_key end)
    return out
end

return Catalog
```

- [ ] **Step 4: Attach catalog module in main**

Modify `main.lua` after attaching `Storage`:

```lua
local Catalog = load_src("catalog.lua")
Bootstrap.attach(Gradelatro, "Catalog", Catalog)
```

- [ ] **Step 5: Run catalog tests**

Run:

```powershell
$lua='C:\Users\ChromaPIE\AppData\Local\Programs\LuaJIT\bin\luajit.exe'; & $lua tests\catalog_test.lua
```

Expected: `catalog tests ok`.

- [ ] **Step 6: Commit catalog**

Run:

```powershell
git add main.lua src/catalog.lua tests/catalog_test.lua
git commit -m "test: add Joker catalog discovery"
```

Expected: commit succeeds.

---

### Task 8: Test Runner and Foundation Smoke Check

**Files:**
- Create: `tests/run_all.lua`
- Modify: `main.lua`

- [ ] **Step 1: Create test runner**

Create `tests/run_all.lua`:

```lua
dofile("tests/config_test.lua")
dofile("tests/economy_test.lua")
dofile("tests/stakes_test.lua")
dofile("tests/condition_test.lua")
dofile("tests/storage_test.lua")
dofile("tests/catalog_test.lua")

print("all Gradelatro foundation tests ok")
```

- [ ] **Step 2: Verify main attaches all foundation modules**

Ensure `main.lua` contains these module attachments in this order:

```lua
local Config = load_src("config.lua")
Bootstrap.attach(Gradelatro, "Config", Config)

Gradelatro.config = Config.normalize(current_mod.config or {})
current_mod.config = Gradelatro.config

local Economy = load_src("economy.lua")
Bootstrap.attach(Gradelatro, "Economy", Economy)

local Stakes = load_src("stakes.lua")
Bootstrap.attach(Gradelatro, "Stakes", Stakes)

local Condition = load_src("condition.lua")
Bootstrap.attach(Gradelatro, "Condition", Condition)

local Storage = load_src("storage.lua")
Bootstrap.attach(Gradelatro, "Storage", Storage)

current_mod.config.collection = Storage.normalize(current_mod.config.collection)
Gradelatro.collection = current_mod.config.collection

local Catalog = load_src("catalog.lua")
Bootstrap.attach(Gradelatro, "Catalog", Catalog)
```

- [ ] **Step 3: Run all tests**

Run:

```powershell
$lua='C:\Users\ChromaPIE\AppData\Local\Programs\LuaJIT\bin\luajit.exe'; & $lua tests\run_all.lua
```

Expected:

```text
config tests ok
economy tests ok
stakes tests ok
condition tests ok
storage tests ok
catalog tests ok
all Gradelatro foundation tests ok
```

- [ ] **Step 4: Run syntax check for source files**

Run:

```powershell
$lua='C:\Users\ChromaPIE\AppData\Local\Programs\LuaJIT\bin\luajit.exe'; Get-ChildItem -Recurse -Filter *.lua | ForEach-Object { & $lua -b $_.FullName NUL; if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE } }; 'syntax ok'
```

Expected:

```text
syntax ok
```

- [ ] **Step 5: Commit test runner**

Run:

```powershell
git add main.lua tests/run_all.lua
git commit -m "test: add foundation test runner"
```

Expected: commit succeeds.

---

## Foundation Acceptance Criteria

- `manifest.json` loads `main.lua` as the SMODS entry point.
- `main.lua` creates a global `Gradelatro` namespace and attaches all foundation modules.
- Config normalization is deterministic and preserves user overrides.
- `RAV`, buyout price, grading fee, and settlement `G-credit` are tested.
- Stake gates use red/blue/gold anchors rather than enumerating every Stake name.
- Authenticated edition handling rejects custom editions by falling back to `base`.
- Condition generation, wear, and PSA-style grade calculation are deterministic under test.
- Collection storage never writes outside `SMODS.current_mod.config.collection`.
- Catalog discovery only includes Jokers and assigns modded Jokers to brand series.
- `tests/run_all.lua` passes with LuaJIT.
- Lua bytecode syntax check passes for every `.lua` file.

## Self-Review

**Spec coverage:** This plan covers the foundation needed by the confirmed design: separated `G-credit` economy, buyout pricing rules, Stake rarity gates, authenticated editions, hidden condition, grading math, collection storage, and mod-series cataloging. Post-win UI, binder UI, real-time queue screens, market interaction, and raw-card run carry are intentionally assigned to later plans because they need Balatro UI and run hooks.

**Placeholder scan:** The plan uses exact files, commands, expected outputs, and concrete Lua code for the foundation MVP. It does not contain open implementation markers.

**Type consistency:** Shared names are consistent across tasks: `Gradelatro`, `Config.normalize`, `Economy.raw_anchor_value`, `Stakes.gate_for_level`, `Condition.grade`, `Storage.normalize`, and `Catalog.discover`.
