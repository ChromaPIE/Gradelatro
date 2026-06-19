local RunEnd = {}

local function load_src(path)
    return assert(SMODS.load_file("src/" .. path))()
end

local BlackMarket = load_src("domain/black_market.lua")
local Buyout = load_src("domain/buyout.lua")
local Catalog = load_src("domain/catalog.lua")
local Loadout = load_src("domain/loadout.lua")
local Market = load_src("domain/market.lua")
local Persistence = load_src("core/persistence.lua")
local Settlement = load_src("domain/settlement.lua")
local StakeEconomy = load_src("domain/stake_economy.lua")
local Stakes = load_src("domain/stakes.lua")

local function copy_shallow_table(value)
    if type(value) ~= "table" then return value end
    local out = {}
    for k, v in pairs(value) do
        out[k] = v
    end
    return out
end

local function set_from_card(card)
    if not card then return nil end
    if card.config and card.config.center and card.config.center.set then
        return card.config.center.set
    end
    if card.ability and card.ability.set then return card.ability.set end
    if card.set then return card.set end
    return nil
end

local function snapshot_id(card, center_key, index)
    return tostring(card.id or card.ID or card.sort_id or (tostring(center_key or "unknown") .. ":" .. tostring(index)))
end

local function stake_level(stake)
    if type(stake) ~= "table" then return nil end
    return stake.stake_level or stake.order
end

local run_id = Loadout.run_identity

function RunEnd.year_from_timestamp(timestamp)
    return tonumber(os.date("%Y", timestamp or os.time()))
end

function RunEnd.ensure_run_started_at(game_state, now)
    if not game_state then return now or os.time() end
    game_state.grdl_run_started_at = game_state.grdl_run_started_at or now or os.time()
    return game_state.grdl_run_started_at
end

function RunEnd.stake_anchors(p_stakes)
    p_stakes = p_stakes or {}
    return {
        stake_red = stake_level(p_stakes.stake_red) or 2,
        stake_blue = stake_level(p_stakes.stake_blue) or 5,
        stake_gold = stake_level(p_stakes.stake_gold) or 8
    }
end

function RunEnd.snapshot_card(card, index)
    local center_key = Catalog.center_key_from_card(card)
    if not center_key then return nil end
    if set_from_card(card) ~= "Joker" then return nil end
    return {
        id = snapshot_id(card, center_key, index),
        center_key = center_key,
        config = { center = { key = center_key } },
        edition = copy_shallow_table(card.edition),
        source_index = index
    }
end

function RunEnd.collect_joker_snapshots(area)
    local cards = area and area.cards or area or {}
    local out = {}
    for index, card in ipairs(cards) do
        local snapshot = RunEnd.snapshot_card(card, index)
        if snapshot then out[#out + 1] = snapshot end
    end
    return out
end

function RunEnd.capture_win_buyout_offer(namespace, runtime, smods, now)
    namespace = namespace or rawget(_G, "Gradelatro")
    runtime = runtime or rawget(_G, "G")
    smods = smods or rawget(_G, "SMODS")
    if not namespace or not runtime or not runtime.GAME then return nil end

    local config = namespace.config or {}
    local collection = namespace.collection
    if not collection then return nil end
    local before = Persistence.snapshot(namespace)
    if not StakeEconomy.run_enabled(runtime) then
        namespace.pending_buyout_offer = nil
        if collection.pending_buyout_offer ~= nil then
            collection.pending_buyout_offer = nil
            namespace.last_save_ok = Persistence.save(namespace)
            if not namespace.last_save_ok then Persistence.restore(namespace, before) end
        end
        return nil
    end

    local run_started_at = RunEnd.ensure_run_started_at(runtime.GAME, now)
    local current_run_id = run_id(runtime.GAME)
    local catalog = Catalog.discover(config, runtime.P_CENTERS, smods and smods.Mods or nil)
    local snapshots = RunEnd.collect_joker_snapshots(runtime.jokers)
    local stake_anchors = RunEnd.stake_anchors(runtime.P_STAKES)
    local stake_level = StakeEconomy.stake_level_for_run(runtime)
    local gate = Stakes.gate_for_level(stake_anchors, stake_level)
    namespace.last_settlement_result = Settlement.apply(config, collection, {
        run_id = current_run_id,
        run_started_at = run_started_at,
        gate = gate,
        stake_level = stake_level,
        won = true,
        dollars = runtime.GAME.dollars,
        settled_at = now or os.time()
    })

    local series_ids = {}
    local seen_series = {}
    for _, entry in ipairs(catalog) do
        if not seen_series[entry.series_id] then
            seen_series[entry.series_id] = true
            series_ids[#series_ids + 1] = entry.series_id
        end
    end
    Market.refresh(config, collection, { series_ids = series_ids, now = now or os.time() })

    if namespace.last_settlement_result.ok and not namespace.last_settlement_result.duplicate then
        local boss_key = runtime.GAME.blind
            and runtime.GAME.blind.config
            and runtime.GAME.blind.config.blind
            and runtime.GAME.blind.config.blind.key
            or nil
        BlackMarket.generate(config, collection, {
            catalog = catalog,
            run_id = current_run_id,
            boss_key = boss_key,
            now = now or os.time()
        })
    end

    local offer = Buyout.prepare_offer(config, collection, {
        catalog = catalog,
        jokers = snapshots,
        stake_level = stake_level,
        stake_anchors = stake_anchors,
        series_heat = Market.heat_map(collection)
    })

    offer.run_id = current_run_id
    offer.run_started_at = run_started_at
    offer.acquired_year = RunEnd.year_from_timestamp(run_started_at)
    namespace.pending_buyout_offer = offer
    collection.pending_buyout_offer = offer
    namespace.last_save_ok = Persistence.save(namespace)
    if not namespace.last_save_ok then
        Persistence.restore(namespace, before)
        namespace.last_settlement_result = { ok = false, reason = "save_failed" }
        return nil
    end
    return offer
end

return RunEnd
