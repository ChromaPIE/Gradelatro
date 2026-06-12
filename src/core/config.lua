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
        minimum_fee = 15,
        time_scale = "arcade",
        durations = {
            arcade = {
                economy = 1200,
                standard = 600,
                priority = 240,
                express = 60
            },
            hobbyist = {
                economy = 86400,
                standard = 28800,
                priority = 7200,
                express = 1800
            },
            realistic = {
                economy = 2592000,
                standard = 864000,
                priority = 259200,
                express = 86400
            }
        }
    },
    market = {
        heat_min = 0.75,
        heat_max = 1.35,
        system_buy_min = 0.70,
        system_buy_max = 0.82,
        system_sell_min = 1.15,
        system_sell_max = 1.35,
        special_order_min = 1.35,
        special_order_max = 1.75,
        refresh_cooldown = 86400,
        raw_sell_factor = 0.75,
        trend_step = 0.03,
        trend_max = 0.15,
        cycle_amplitude = 0.06,
        cycle_days = 14,
        event_chance = 0.10,
        event_min = 0.08,
        event_max = 0.18,
        event_min_days = 2,
        event_max_days = 4
    },
    catalog = {
        series_format = "#1# Series"
    },
    wear = {
        minor_chance = 0.70,
        minor_min = 0.05,
        minor_max = 0.15,
        moderate_chance = 0.25,
        moderate_min = 0.20,
        moderate_max = 0.40,
        severe_chance = 0.05,
        severe_min = 0.80,
        severe_max = 1.50
    },
    black_market = {
        graded_chance = 0.35,
        open_float_min = 0.85,
        open_float_max = 1.15,
        mystery_float_min = 0.50,
        mystery_float_max = 2.00,
        mystery_wild_chance = 0.60,
        intel_reveal_chance = 0.40,
        edition_weights = {
            base = 0.70,
            foil = 0.12,
            holographic = 0.08,
            polychrome = 0.06,
            negative = 0.04
        }
    },
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
