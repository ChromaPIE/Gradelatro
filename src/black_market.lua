local BlackMarket = {}

local function load_src(path)
    if rawget(_G, "SMODS") and SMODS.load_file then
        return assert(SMODS.load_file("src/" .. path))()
    end
    return dofile("src/" .. path)
end

local Condition = load_src("condition.lua")
local Economy = load_src("economy.lua")
local Market = load_src("market.lua")
local Rng = load_src("rng.lua")
local Storage = load_src("storage.lua")

local EDITION_ORDER = { "base", "foil", "holographic", "polychrome", "negative" }

local function ensure_market(state)
    state.market = type(state.market) == "table" and state.market or {}
    return state.market
end

local function roll_edition(config, rand)
    local weights = config.black_market.edition_weights
    local roll = rand()
    local cumulative = 0
    for _, edition in ipairs(EDITION_ORDER) do
        cumulative = cumulative + (weights[edition] or 0)
        if roll < cumulative then return edition end
    end
    return "base"
end

function BlackMarket.offer_value(config, state, offer)
    local heat = Market.heat_for(state, offer.mod_id)
    local rav = Economy.raw_anchor_value(config, {
        rarity = offer.rarity,
        edition = offer.edition,
        series_heat = heat
    })
    if offer.graded and offer.grade then
        return rav * Condition.grade_multiplier(offer.grade)
    end
    return rav
end

function BlackMarket.generate(config, state, args)
    args = args or {}
    if not state then return { ok = false, reason = "missing_collection" } end
    local catalog = args.catalog or {}
    if #catalog == 0 then return { ok = false, reason = "empty_catalog" } end

    local market = ensure_market(state)
    local run_id = tostring(args.run_id or "unknown")
    if market.black_market and market.black_market.run_id == run_id then
        return { ok = true, regenerated = false, black_market = market.black_market }
    end

    local now = args.now or os.time()
    local rand = Rng.lcg(args.rng_seed or now)
    local settings = config.black_market
    local sell_min = config.market.system_sell_min
    local sell_max = config.market.system_sell_max

    local offers = {}
    for slot = 1, 3 do
        local entry = catalog[math.floor(rand() * #catalog) + 1]
        local edition = roll_edition(config, rand)
        local condition = Condition.generate(math.floor(rand() * 2147483646) + 1, edition)
        local graded = rand() < settings.graded_chance
        local mystery = slot == 3

        local float_low, float_high = settings.open_float_min, settings.open_float_max
        if mystery and rand() < settings.mystery_wild_chance then
            float_low, float_high = settings.mystery_float_min, settings.mystery_float_max
        end
        local float = float_low + rand() * (float_high - float_low)
        local premium = sell_min + rand() * (sell_max - sell_min)

        local intel = nil
        if mystery then
            local reveal = settings.intel_reveal_chance or 0
            intel = {
                mod = rand() < reveal,
                rarity = rand() < reveal,
                edition = rand() < reveal,
                graded = rand() < reveal
            }
        end

        local offer = {
            slot = slot,
            center_key = entry.center_key,
            local_key = entry.local_key,
            series_key = entry.series_key,
            mod_id = entry.mod_id,
            mod_name = entry.mod_name or entry.mod_id,
            rarity = entry.rarity,
            edition = edition,
            condition = condition,
            graded = graded,
            grade = graded and Condition.grade(condition) or nil,
            mystery = mystery,
            intel = intel,
            sold = false
        }
        offer.price = math.max(1, math.floor(BlackMarket.offer_value(config, state, offer) * premium * float))
        offers[slot] = offer
    end

    market.black_market = {
        run_id = run_id,
        boss_key = args.boss_key,
        generated_at = now,
        offers = offers
    }
    return { ok = true, regenerated = true, black_market = market.black_market }
end

function BlackMarket.offers(state)
    local market = state and state.market or nil
    local black_market = market and market.black_market or nil
    return black_market and black_market.offers or nil
end

function BlackMarket.boss_key(state)
    local market = state and state.market or nil
    return market and market.black_market and market.black_market.boss_key or nil
end

function BlackMarket.purchase(config, state, args)
    args = args or {}
    if not state then return { ok = false, reason = "missing_collection" } end
    local offers = BlackMarket.offers(state)
    local offer = offers and offers[args.slot or 0] or nil
    if not offer then return { ok = false, reason = "no_offer" } end
    if offer.sold then return { ok = false, reason = "already_sold" } end

    if not Storage.spend_currency(state, offer.price) then
        return { ok = false, reason = "insufficient_funds", price = offer.price }
    end

    local now = args.now or os.time()
    local acquired_date = os.date("*t", now)
    local card = Storage.add_raw_card(state, {
        center_key = offer.center_key,
        local_key = offer.local_key,
        series_key = offer.series_key,
        mod_id = offer.mod_id,
        rarity = offer.rarity,
        edition = offer.edition,
        condition = offer.condition,
        acquired_at = now,
        acquired_year = acquired_date.year,
        acquired_month = acquired_date.month,
        acquired_day = acquired_date.day,
        acquired_price = offer.price,
        source = "black_market"
    })
    if offer.graded then
        card.status = "graded"
        card.grade = offer.grade
        card.graded_at = now
        card.grade_service = "standard"
        card.cert_number = Storage.allocate_cert_number(state)
    end
    offer.sold = true

    return { ok = true, card = card, offer = offer, price = offer.price }
end

return BlackMarket
