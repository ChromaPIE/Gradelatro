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
