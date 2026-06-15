local Buyout = {}

local function load_src(path)
    return assert(SMODS.load_file("src/" .. path))()
end

local Catalog = load_src("domain/catalog.lua")
local Condition = load_src("domain/condition.lua")
local Economy = load_src("domain/economy.lua")
local Stakes = load_src("domain/stakes.lua")
local Storage = load_src("core/storage.lua")

local function catalog_index(catalog)
    local out = {}
    for _, entry in ipairs(catalog or {}) do
        out[entry.center_key] = entry
    end
    return out
end

local function value_from_map(map, first_key, second_key, fallback)
    if type(map) ~= "table" then return fallback end
    if first_key and map[first_key] then return map[first_key] end
    if second_key and map[second_key] then return map[second_key] end
    return fallback
end

local function selected_id_set(selected_ids)
    local out = {}
    for _, id in ipairs(selected_ids or {}) do
        out[id] = true
    end
    return out
end

local function acquired_year(args)
    if args.acquired_year then return args.acquired_year end
    return tonumber(os.date("%Y", args.now or os.time()))
end

function Buyout.prepare_offer(config, state, args)
    args = args or {}
    local gate = args.gate or Stakes.gate_for_level(args.stake_anchors, args.stake_level)
    local by_center = catalog_index(args.catalog)
    local state_index = Storage.build_index(state)
    local eligible = {}
    local blocked = {}

    for source_index, card in ipairs(args.jokers or {}) do
        local center_key = Catalog.center_key_from_card(card)
        local entry = center_key and by_center[center_key] or nil
        if not entry then
            blocked[#blocked + 1] = {
                id = card and card.id or tostring(source_index),
                center_key = center_key,
                source_index = source_index,
                reason = "not_in_catalog"
            }
        elseif not Stakes.can_buyout(gate, entry.rarity) then
            blocked[#blocked + 1] = {
                id = card and card.id or tostring(source_index),
                center_key = center_key,
                source_index = source_index,
                rarity = entry.rarity,
                reason = "rarity_locked"
            }
        else
            local raw_edition = Catalog.edition_from_card(card)
            local edition = Catalog.normalize_edition(config, raw_edition)
            local series_heat = value_from_map(args.series_heat, entry.series_id, entry.series_key, 1.0)
            local availability_mult = value_from_map(args.availability_mult, center_key, entry.series_id, 1.0)
            local rav = Economy.raw_anchor_value(config, {
                rarity = entry.rarity,
                edition = edition,
                series_heat = series_heat,
                availability_mult = availability_mult
            })
            local owned_count = Storage.count_owned_center(state, center_key, state_index)
            local price = Economy.buyout_price(config, {
                rav = rav,
                owned_count = owned_count
            })
            eligible[#eligible + 1] = {
                id = card and card.id or (center_key .. ":" .. tostring(source_index)),
                center_key = center_key,
                local_key = entry.local_key,
                source_index = source_index,
                series_id = entry.series_id,
                series_key = entry.series_key,
                mod_id = entry.mod_id,
                rarity = entry.rarity,
                edition = edition,
                raw_edition = raw_edition,
                owned_count = owned_count,
                rav = rav,
                price = price
            }
        end
    end

    return {
        gate = gate,
        max_selection = args.max_selection or 5,
        eligible = eligible,
        blocked = blocked
    }
end

function Buyout.purchase(config, state, args)
    args = args or {}
    local candidates = args.candidates or {}
    local max_selection = args.max_selection or 5
    local selected_ids = args.selected_ids
    if not selected_ids then
        selected_ids = {}
        for _, candidate in ipairs(candidates) do
            selected_ids[#selected_ids + 1] = candidate.id
        end
    end

    if #selected_ids > max_selection then
        return { ok = false, reason = "selection_limit" }
    end

    local wanted = selected_id_set(selected_ids)
    local selected = {}
    local total_price = 0
    for _, candidate in ipairs(candidates) do
        if wanted[candidate.id] then
            selected[#selected + 1] = candidate
            total_price = total_price + math.floor(candidate.price or 0)
        end
    end

    if #selected ~= #selected_ids then
        return { ok = false, reason = "not_in_offer" }
    end

    if (state.currency_g or 0) < total_price then
        return { ok = false, reason = "insufficient_funds", total_price = total_price }
    end

    if not Storage.spend_currency(state, total_price) then
        return { ok = false, reason = "insufficient_funds", total_price = total_price }
    end

    local created = {}
    local seed = args.condition_seed or args.now or os.time()
    local acquired_date = os.date("*t", args.run_started_at or args.now or os.time())
    for index, candidate in ipairs(selected) do
        local condition = candidate.condition or Condition.generate(seed + index - 1, candidate.edition)
        created[#created + 1] = Storage.add_raw_card(state, {
            center_key = candidate.center_key,
            local_key = candidate.local_key,
            series_key = candidate.series_key,
            mod_id = candidate.mod_id,
            rarity = candidate.rarity,
            edition = candidate.edition,
            condition = condition,
            acquired_at = args.now,
            acquired_year = acquired_year(args),
            acquired_month = acquired_date.month,
            acquired_day = acquired_date.day,
            acquired_price = math.floor(candidate.price or 0),
            source_run_id = args.run_id,
            source_run_started_at = args.run_started_at,
            source = args.source or "win_buyout"
        })
    end

    return {
        ok = true,
        total_price = total_price,
        cards = created
    }
end

return Buyout
