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
    game_state = game_state or {}
    if game_state.run_id then return tostring(game_state.run_id) end
    if game_state.pseudorandom and game_state.pseudorandom.seed then
        return tostring(game_state.pseudorandom.seed)
    end
    if game_state.seed then return tostring(game_state.seed) end
    return "unknown"
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
