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
