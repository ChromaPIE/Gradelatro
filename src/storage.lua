local Storage = {}

local CURRENT_SCHEMA = 1

local function copy_condition(condition)
    condition = condition or {}
    return {
        centering = condition.centering,
        print_quality = condition.print_quality,
        corners = condition.corners,
        edges = condition.edges,
        surface = condition.surface
    }
end

local function is_owned_status(status)
    return status ~= "lost" and status ~= "sold"
end

function Storage.normalize(input)
    local state = type(input) == "table" and input or {}
    state.schema_version = CURRENT_SCHEMA
    state.currency_g = math.max(0, math.floor(state.currency_g or 0))
    state.next_card_id = math.max(1, math.floor(state.next_card_id or 1))
    state.next_cert_id = math.max(1, math.floor(state.next_cert_id or 1))
    state.cards = type(state.cards) == "table" and state.cards or {}
    state.grading_queue = type(state.grading_queue) == "table" and state.grading_queue or {}
    state.market = type(state.market) == "table" and state.market or { series_heat = {} }
    state.market.series_heat = type(state.market.series_heat) == "table" and state.market.series_heat or {}
    return state
end

function Storage.allocate_cert_number(state)
    local cert_number = string.format("%06d", state.next_cert_id or 1)
    state.next_cert_id = (state.next_cert_id or 1) + 1
    return cert_number
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
        local_key = args.local_key,
        series_key = args.series_key or args.set_key,
        mod_id = args.mod_id,
        rarity = args.rarity,
        edition = args.edition,
        condition = copy_condition(args.condition),
        acquired_at = args.acquired_at,
        acquired_year = args.acquired_year,
        source_run_id = args.source_run_id,
        source_run_started_at = args.source_run_started_at,
        source = args.source
    }
    state.cards[#state.cards + 1] = card
    return card
end

function Storage.build_index(state)
    local index = {
        by_id = {},
        center_counts = {}
    }
    for _, card in ipairs(state.cards or {}) do
        index.by_id[card.id] = card
        if card.center_key and is_owned_status(card.status) then
            index.center_counts[card.center_key] = (index.center_counts[card.center_key] or 0) + 1
        end
    end
    return index
end

function Storage.find_card(state, card_id, index)
    if index and index.by_id then return index.by_id[card_id] end
    for _, card in ipairs(state.cards or {}) do
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

function Storage.count_owned_center(state, center_key, index)
    if index and index.center_counts then
        return index.center_counts[center_key] or 0
    end

    local count = 0
    for _, card in ipairs(state.cards or {}) do
        if card.center_key == center_key and is_owned_status(card.status) then
            count = count + 1
        end
    end
    return count
end

return Storage
