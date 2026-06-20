local H = dofile("tests/test_helper.lua")
local Config = dofile("src/core/config.lua")
local Storage = dofile("src/core/storage.lua")
local Condition = dofile("src/domain/condition.lua")
local BlackMarket = dofile("src/domain/black_market.lua")
local rng = H.install_pseudorandom_stub()

local config = Config.normalize({})

H.assert_true(config.black_market.graded_chance > 0 and config.black_market.graded_chance < 1, "graded chance is a probability")
H.assert_true(config.black_market.mystery_float_max > config.black_market.open_float_max, "mystery band is wider")

local catalog = {
    { center_key = "j_a1", local_key = "a1", series_id = "Alpha", mod_id = "Alpha", mod_name = "Alpha", series_key = "Alpha Series", rarity = "common" },
    { center_key = "j_a2", local_key = "a2", series_id = "Alpha", mod_id = "Alpha", mod_name = "Alpha", series_key = "Alpha Series", rarity = "rare" },
    { center_key = "j_b1", local_key = "b1", series_id = "Beta", mod_id = "Beta", mod_name = "Beta", series_key = "Beta Series", rarity = "uncommon" },
    { center_key = "j_b2", local_key = "b2", series_id = "Beta", mod_id = "Beta", mod_name = "Beta", series_key = "Beta Series", rarity = "legendary" }
}

H.assert_equal(BlackMarket.generate(config, Storage.normalize({}), { catalog = {}, run_id = "R1", now = 1000 }).reason, "empty_catalog", "empty catalog rejected")

local restricted_catalog = {
    { center_key = "j_worm", local_key = "worm", series_id = "Wormhole", mod_id = "Wormhole", mod_name = "Wormhole", series_key = "Wormhole Series", rarity = "unknown_high", raw_rarity = "worm_otherworldly" },
    { center_key = "j_mythic", local_key = "mythic", series_id = "MythicMod", mod_id = "MythicMod", mod_name = "Mythic Mod", series_key = "Mythic Series", rarity = "unknown_high", raw_rarity = "Mythic" },
    { center_key = "j_cry_exotic", local_key = "cry_exotic", series_id = "Cryptid", mod_id = "Cryptid", mod_name = "Cryptid", series_key = "Cryptid Series", rarity = "cry_exotic", raw_rarity = "cry_exotic" },
    { center_key = "j_soe_basic", local_key = "soe_basic", series_id = "SealsOnEverything", mod_id = "SealsOnEverything", mod_name = "Seals On Everything", series_key = "SOE Series", rarity = "soe_basic", raw_rarity = "soe_basic" }
}
local restricted_state = Storage.normalize({ currency_g = 100000 })
local restricted = BlackMarket.generate(config, restricted_state, { catalog = restricted_catalog, run_id = "R1", now = 1767225600, rng_seed = 11 })
H.assert_equal(restricted.ok, true, "restricted catalog generation succeeds")
local allowed_centers = { j_cry_exotic = true, j_soe_basic = true }
for slot, offer in ipairs(restricted_state.market.black_market.offers) do
    H.assert_true(allowed_centers[offer.center_key] == true, "slot " .. tostring(slot) .. " uses a specific-base rarity")
    H.assert_true(offer.rarity ~= "unknown_high", "slot " .. tostring(slot) .. " does not use fallback rarity")
end
H.assert_equal(restricted_state.market.black_market.offers[1].center_key, "j_soe_basic", "public slot one uses public allowlist")
H.assert_equal(restricted_state.market.black_market.offers[2].center_key, "j_soe_basic", "public slot two uses public allowlist")

local public_restricted_catalog = {
    { center_key = "j_common", local_key = "common", series_id = "Balatro", mod_id = "Balatro", mod_name = "Balatro", series_key = "Balatro Series", rarity = "common", raw_rarity = 1 },
    { center_key = "j_rare", local_key = "rare", series_id = "Balatro", mod_id = "Balatro", mod_name = "Balatro", series_key = "Balatro Series", rarity = "rare", raw_rarity = 3 },
    { center_key = "j_legendary", local_key = "legendary", series_id = "Balatro", mod_id = "Balatro", mod_name = "Balatro", series_key = "Balatro Series", rarity = "legendary", raw_rarity = 4 },
    { center_key = "j_cry_epic", local_key = "cry_epic", series_id = "Cryptid", mod_id = "Cryptid", mod_name = "Cryptid", series_key = "Cryptid Series", rarity = "cry_epic", raw_rarity = "cry_epic" },
    { center_key = "j_soe_unique", local_key = "soe_unique", series_id = "SealsOnEverything", mod_id = "SealsOnEverything", mod_name = "Seals On Everything", series_key = "SOE Series", rarity = "soe_unique", raw_rarity = "soe_unique" },
    { center_key = "j_soe_fabled", local_key = "soe_fabled", series_id = "SealsOnEverything", mod_id = "SealsOnEverything", mod_name = "Seals On Everything", series_key = "SOE Series", rarity = "soe_fabled", raw_rarity = "soe_fabled" }
}
local public_restricted_state = Storage.normalize({ currency_g = 100000 })
local public_restricted = BlackMarket.generate(config, public_restricted_state, {
    catalog = public_restricted_catalog,
    run_id = "R1",
    now = 1767225600,
    rng_seed = 21
})
H.assert_equal(public_restricted.ok, true, "public restricted generation succeeds")
local public_allowed = {
    common = true,
    uncommon = true,
    rare = true,
    soe_basic = true,
    soe_unusual = true,
    soe_unique = true
}
H.assert_true(public_allowed[public_restricted_state.market.black_market.offers[1].rarity] == true, "slot one uses public rarity allowlist")
H.assert_true(public_allowed[public_restricted_state.market.black_market.offers[2].rarity] == true, "slot two uses public rarity allowlist")
H.assert_equal(public_restricted_state.market.black_market.offers[3].mystery, true, "slot three remains mystery")

local unpriced_state = Storage.normalize({})
local unpriced = BlackMarket.generate(config, unpriced_state, {
    catalog = {
        { center_key = "j_worm", local_key = "worm", series_id = "Wormhole", mod_id = "Wormhole", series_key = "Wormhole Series", rarity = "unknown_high", raw_rarity = "worm_otherworldly" }
    },
    run_id = "R1",
    now = 1767225600,
    rng_seed = 12
})
H.assert_equal(unpriced.ok, false, "all fallback rarity catalog rejected")
H.assert_equal(unpriced.reason, "empty_catalog", "all fallback rarity reports empty catalog")
H.assert_equal(unpriced_state.market.black_market, nil, "all fallback rarity does not create offers")

local state = Storage.normalize({ currency_g = 100000 })
local generated = BlackMarket.generate(config, state, { catalog = catalog, run_id = "R1", boss_key = "bl_hook", now = 1767225600, rng_seed = 42 })
H.assert_equal(generated.ok, true, "generation succeeds")
H.assert_equal(#state.market.black_market.offers, 3, "three offers generated")
H.assert_equal(state.market.black_market.run_id, "R1", "run id stored")
H.assert_equal(state.market.black_market.boss_key, "bl_hook", "boss key stored")
H.assert_true(rng.has_call("pseudorandom", "grdl_black_market_"), "black market generation uses native pseudorandom")

local offers = BlackMarket.offers(state)
H.assert_equal(#offers, 3, "offers readable")
local EDITION_SET = { base = true, foil = true, holographic = true, polychrome = true, negative = true }
for index, offer in ipairs(offers) do
    H.assert_equal(offer.slot, index, "offer slot index")
    H.assert_true(offer.center_key ~= nil, "offer has a center")
    H.assert_true(EDITION_SET[offer.edition] == true, "offer edition authenticated")
    H.assert_true(offer.condition ~= nil and offer.condition.surface ~= nil, "offer carries hidden condition")
    H.assert_true(offer.price >= 1, "offer price positive")
    H.assert_equal(offer.sold, false, "offer starts unsold")
    if offer.graded then
        H.assert_equal(offer.grade, Condition.grade(offer.condition), "graded offer grade matches condition")
    end
    local value = BlackMarket.offer_value(config, state, offer)
    local float_min = offer.mystery and math.min(config.black_market.open_float_min, config.black_market.mystery_float_min) or config.black_market.open_float_min
    local float_max = offer.mystery and config.black_market.mystery_float_max or config.black_market.open_float_max
    H.assert_true(offer.price >= math.floor(value * config.market.system_sell_min * float_min), "price above band floor")
    H.assert_true(offer.price <= math.ceil(value * config.market.system_sell_max * float_max), "price below band ceiling")
end
H.assert_equal(offers[1].mystery, false, "slot one is open")
H.assert_equal(offers[2].mystery, false, "slot two is open")
H.assert_equal(offers[3].mystery, true, "slot three is the mystery")

H.assert_true(config.black_market.intel_reveal_chance > 0 and config.black_market.intel_reveal_chance < 1, "intel reveal chance is a probability")
H.assert_equal(offers[1].intel, nil, "open offers have no intel")
H.assert_equal(offers[2].intel, nil, "second open offer has no intel")
H.assert_true(offers[3].intel ~= nil, "mystery offer rolls intel")
for _, field in ipairs({ "mod", "rarity", "edition", "graded" }) do
    H.assert_true(type(offers[3].intel[field]) == "boolean", "intel field " .. field .. " is a boolean")
end

local intel_config = Config.normalize({})
intel_config.black_market.intel_reveal_chance = 1
local open_state = Storage.normalize({})
BlackMarket.generate(intel_config, open_state, { catalog = catalog, run_id = "R1", now = 1767225600, rng_seed = 5 })
for _, field in ipairs({ "mod", "rarity", "edition", "graded" }) do
    H.assert_equal(open_state.market.black_market.offers[3].intel[field], true, "chance one reveals " .. field)
end
intel_config.black_market.intel_reveal_chance = 0
local closed_state = Storage.normalize({})
BlackMarket.generate(intel_config, closed_state, { catalog = catalog, run_id = "R1", now = 1767225600, rng_seed = 5 })
for _, field in ipairs({ "mod", "rarity", "edition", "graded" }) do
    H.assert_equal(closed_state.market.black_market.offers[3].intel[field], false, "chance zero hides " .. field)
end

local replay_state = Storage.normalize({})
rng.reset()
BlackMarket.generate(config, replay_state, { catalog = catalog, run_id = "R1", boss_key = "bl_hook", now = 1767225600, rng_seed = 42 })
H.assert_equal(replay_state.market.black_market.offers[1].center_key, offers[1].center_key, "same seed reproduces offers")
H.assert_equal(replay_state.market.black_market.offers[1].price, offers[1].price, "same seed reproduces prices")
for _, field in ipairs({ "mod", "rarity", "edition", "graded" }) do
    H.assert_equal(replay_state.market.black_market.offers[3].intel[field], offers[3].intel[field], "same seed reproduces intel " .. field)
end

local guard = BlackMarket.generate(config, state, { catalog = catalog, run_id = "R1", now = 1767225700, rng_seed = 99 })
H.assert_equal(guard.ok, true, "same run regeneration is safe")
H.assert_equal(guard.regenerated, false, "same run does not regenerate")
H.assert_equal(state.market.black_market.offers[1].price, offers[1].price, "same run keeps offers")

local missing = BlackMarket.purchase(config, state, { slot = 9, now = 2000 })
H.assert_equal(missing.ok, false, "unknown slot rejected")
H.assert_equal(missing.reason, "no_offer", "unknown slot reason")

local poor_state = Storage.normalize({ currency_g = 0 })
BlackMarket.generate(config, poor_state, { catalog = catalog, run_id = "R1", now = 1767225600, rng_seed = 42 })
local broke = BlackMarket.purchase(config, poor_state, { slot = 1, now = 2000 })
H.assert_equal(broke.ok, false, "insufficient funds rejected")
H.assert_equal(broke.reason, "insufficient_funds", "insufficient funds reason")
H.assert_equal(#poor_state.cards, 0, "no card added without funds")

local before_cards = #state.cards
local currency_before = state.currency_g
local bought = BlackMarket.purchase(config, state, { slot = 1, now = 1767225700 })
H.assert_equal(bought.ok, true, "purchase succeeds")
H.assert_equal(#state.cards, before_cards + 1, "card added to collection")
H.assert_equal(state.currency_g, currency_before - offers[1].price, "price charged")
H.assert_equal(bought.card.center_key, offers[1].center_key, "purchased card center matches offer")
H.assert_equal(bought.card.edition, offers[1].edition, "purchased card edition matches offer")
H.assert_equal(bought.card.acquired_price, offers[1].price, "purchase price recorded")
H.assert_equal(bought.card.source, "black_market", "purchase source marked")
H.assert_equal(bought.card.acquired_year, 2026, "purchase date recorded")
if offers[1].graded then
    H.assert_equal(bought.card.status, "graded", "graded offer arrives graded")
    H.assert_true(bought.card.cert_number ~= nil, "graded purchase gets a cert")
else
    H.assert_equal(bought.card.status, "raw", "open offer arrives raw")
end
H.assert_equal(state.market.black_market.offers[1].sold, true, "offer marked sold")

local resale = BlackMarket.purchase(config, state, { slot = 1, now = 2001 })
H.assert_equal(resale.ok, false, "sold slot cannot repurchase")
H.assert_equal(resale.reason, "already_sold", "double purchase reason")

local regen = BlackMarket.generate(config, state, { catalog = catalog, run_id = "R2", boss_key = "bl_wall", now = 1767312000, rng_seed = 7 })
H.assert_equal(regen.ok, true, "new run regenerates")
H.assert_equal(regen.regenerated, true, "regeneration flagged")
H.assert_equal(state.market.black_market.run_id, "R2", "new run id stored")
H.assert_equal(state.market.black_market.boss_key, "bl_wall", "new boss stored")
H.assert_equal(state.market.black_market.offers[1].sold, false, "fresh offers unsold")

rng.restore()
print("black market tests ok")
