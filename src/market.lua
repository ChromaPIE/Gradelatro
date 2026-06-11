local Market = {}

local function load_src(path)
    if rawget(_G, "SMODS") and SMODS.load_file then
        return assert(SMODS.load_file("src/" .. path))()
    end
    return dofile("src/" .. path)
end

local Condition = load_src("condition.lua")
local Economy = load_src("economy.lua")
local Rng = load_src("rng.lua")
local Storage = load_src("storage.lua")

local function clamp(value, min_value, max_value)
    if value < min_value then return min_value end
    if value > max_value then return max_value end
    return value
end

local function series_phase(series_id)
    local hash = 0
    local text = tostring(series_id or "")
    for index = 1, #text do
        hash = (hash * 31 + text:byte(index)) % 997
    end
    return hash / 997
end

local function ensure_market(state)
    state.market = type(state.market) == "table" and state.market or {}
    state.market.series_heat = type(state.market.series_heat) == "table" and state.market.series_heat or {}
    return state.market
end

function Market.heat_for(state, series_id)
    local market = state and state.market or nil
    local entry = market and market.series_heat and market.series_heat[series_id] or nil
    return entry and entry.heat or 1.0
end

function Market.heat_map(state)
    local map = {}
    local market = state and state.market or nil
    for series_id, entry in pairs(market and market.series_heat or {}) do
        if type(entry) == "table" and entry.heat then
            map[series_id] = entry.heat
        end
    end
    return map
end

function Market.trend_label(heat)
    heat = heat or 1.0
    if heat >= 1.15 then return "hot" end
    if heat >= 1.04 then return "rising" end
    if heat > 0.96 then return "stable" end
    return "cooling"
end

function Market.refresh(config, state, args)
    args = args or {}
    if not state then return { ok = false, reason = "missing_collection" } end
    local market = ensure_market(state)
    local now = args.now or os.time()
    local settings = config.market

    if not args.force and market.last_refresh and (now - market.last_refresh) < settings.refresh_cooldown then
        return { ok = true, refreshed = false }
    end

    local rand = Rng.lcg(args.rng_seed or now)
    local day = math.floor(now / 86400)

    for _, series_id in ipairs(args.series_ids or {}) do
        local entry = market.series_heat[series_id]
        if type(entry) ~= "table" then
            entry = { heat = 1.0, trend = 0 }
            market.series_heat[series_id] = entry
        end

        entry.trend = clamp((entry.trend or 0) + (rand() * 2 - 1) * settings.trend_step, -settings.trend_max, settings.trend_max)
        local cycle = settings.cycle_amplitude * math.sin(2 * math.pi * (day / settings.cycle_days + series_phase(series_id)))

        if entry.event and (entry.event.expires_at or 0) <= now then
            entry.event = nil
        end
        if not entry.event and rand() < settings.event_chance then
            local magnitude = settings.event_min + rand() * (settings.event_max - settings.event_min)
            local sign = rand() < 0.5 and -1 or 1
            local days = settings.event_min_days + math.floor(rand() * (settings.event_max_days - settings.event_min_days + 1))
            entry.event = { bump = sign * magnitude, expires_at = now + days * 86400 }
        end

        local bump = entry.event and entry.event.bump or 0
        entry.heat = clamp(1 + entry.trend + cycle + bump, settings.heat_min, settings.heat_max)
        entry.updated_at = now
    end

    market.last_refresh = now
    return { ok = true, refreshed = true }
end

local function is_sellable(card)
    local status = card.status or "raw"
    return status == "raw" or status == "graded"
end

function Market.card_value(config, state, card)
    local heat = Market.heat_for(state, card.mod_id)
    local rav = Economy.raw_anchor_value(config, {
        rarity = card.rarity,
        edition = card.edition,
        series_heat = heat
    })
    if card.status == "graded" and card.grade then
        return rav * Condition.grade_multiplier(card.grade)
    end
    return rav * config.market.raw_sell_factor
end

function Market.sell_quote(config, state, card)
    local rate = (config.market.system_buy_min + config.market.system_buy_max) / 2
    return math.floor(Market.card_value(config, state, card) * rate)
end

function Market.sell_rows(config, state)
    local rows = {}
    for _, card in ipairs((state and state.cards) or {}) do
        if is_sellable(card) then
            rows[#rows + 1] = {
                id = card.id,
                center_key = card.center_key,
                name_key = card.local_key or card.center_key or card.id,
                edition = card.edition or "base",
                status = card.status or "raw",
                grade = card.grade,
                acquired_at = card.acquired_at or 0,
                quote = Market.sell_quote(config, state, card)
            }
        end
    end
    table.sort(rows, function(a, b)
        if a.acquired_at ~= b.acquired_at then return a.acquired_at > b.acquired_at end
        return tostring(a.id) < tostring(b.id)
    end)
    return rows
end

function Market.sell(config, state, args)
    args = args or {}
    if not state then return { ok = false, reason = "missing_collection" } end
    local card = Storage.find_card(state, args.card_id)
    if not card then
        return { ok = false, reason = "card_not_found" }
    end
    if not is_sellable(card) then
        return { ok = false, reason = "not_sellable" }
    end

    local price = Market.sell_quote(config, state, card)
    Storage.add_currency(state, price)
    card.status = "sold"
    card.sold_at = args.now or os.time()
    card.sold_price = price

    return { ok = true, price = price, card = card }
end

return Market
