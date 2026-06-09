local H = dofile("tests/test_helper.lua")
local Config = dofile("src/config.lua")
local Catalog = dofile("src/catalog.lua")
local Storage = dofile("src/storage.lua")
local Buyout = dofile("src/buyout.lua")

local config = Config.normalize({})
local centers = {
    j_common = { key = "j_common", original_key = "common_joker", set = "Joker", rarity = 1, name = "Common", order = 1 },
    j_uncommon = { key = "j_uncommon", original_key = "uncommon_joker", set = "Joker", rarity = 2, name = "Uncommon", order = 2 },
    j_rare = { key = "j_rare", original_key = "rare_joker", set = "Joker", rarity = 3, name = "Rare", order = 3 },
    j_exotic = { key = "j_exotic", original_key = "exotic_joker", set = "Joker", rarity = "exotic", name = "Exotic", order = 4, mod_id = "Cryptid" }
}
local mods = {
    Balatro = { id = "Balatro", name = "BALATRO" },
    Cryptid = { id = "Cryptid", name = "Cryptid" }
}
local catalog = Catalog.discover(config, centers, mods)

local function card(center_key, edition)
    return {
        id = "card_" .. center_key,
        config = { center = { key = center_key } },
        edition = edition
    }
end

local state = Storage.normalize({ currency_g = 500 })
local offer = Buyout.prepare_offer(config, state, {
    catalog = catalog,
    jokers = {
        card("j_common"),
        card("j_rare", { negative = true }),
        card("j_missing")
    },
    stake_level = 2,
    stake_anchors = { stake_red = 2, stake_blue = 5, stake_gold = 8 },
    series_heat = { ["Balatro"] = 1.0 }
})

H.assert_equal(offer.gate, "red", "red stake gate")
H.assert_equal(#offer.eligible, 1, "only common eligible at red")
H.assert_equal(offer.eligible[1].center_key, "j_common", "common eligible")
H.assert_equal(offer.eligible[1].price, 30, "first common buyout price")
H.assert_equal(offer.eligible[1].edition, "base", "missing edition is base")
H.assert_equal(#offer.blocked, 2, "blocked rare and missing")
H.assert_equal(offer.blocked[1].reason, "rarity_locked", "rare blocked by stake")
H.assert_equal(offer.blocked[2].reason, "not_in_catalog", "missing catalog blocked")

H.assert_equal(Buyout.edition_from_card(card("j_common", { key = "e_negative" })), "negative", "edition key normalized")
H.assert_equal(Buyout.edition_from_card(card("j_common", { holo = true })), "holographic", "holo edition normalized")
H.assert_equal(Buyout.edition_from_card(card("j_common", { key = "e_cry_oversat" })), "cry_oversat", "custom edition key preserved before auth")

local too_many = {}
for i = 1, 6 do
    too_many[#too_many + 1] = {
        id = "c" .. tostring(i),
        center_key = "j_common",
        local_key = "common_joker",
        series_id = "Balatro",
        series_key = "BALATRO Series",
        mod_id = "Balatro",
        rarity = "common",
        edition = "base",
        price = 30,
        rav = 35
    }
end

local limit_state = Storage.normalize({ currency_g = 1000 })
local limit_result = Buyout.purchase(config, limit_state, {
    candidates = too_many,
    selected_ids = { "c1", "c2", "c3", "c4", "c5", "c6" },
    now = 1000,
    acquired_year = 2026
})
H.assert_equal(limit_result.ok, false, "selection limit rejected")
H.assert_equal(limit_result.reason, "selection_limit", "selection limit reason")
H.assert_equal(limit_state.currency_g, 1000, "selection limit keeps currency")
H.assert_equal(#limit_state.cards, 0, "selection limit adds no cards")

local poor_state = Storage.normalize({ currency_g = 10 })
local poor_result = Buyout.purchase(config, poor_state, {
    candidates = offer.eligible,
    selected_ids = { offer.eligible[1].id },
    now = 1000,
    acquired_year = 2026
})
H.assert_equal(poor_result.ok, false, "insufficient funds rejected")
H.assert_equal(poor_result.reason, "insufficient_funds", "insufficient reason")
H.assert_equal(poor_state.currency_g, 10, "insufficient keeps currency")
H.assert_equal(#poor_state.cards, 0, "insufficient adds no cards")

local buy_state = Storage.normalize({ currency_g = 149 })
local buy_offer = Buyout.prepare_offer(config, buy_state, {
    catalog = catalog,
    jokers = { card("j_common", { key = "e_negative" }) },
    stake_level = 2,
    stake_anchors = { stake_red = 2, stake_blue = 5, stake_gold = 8 },
    run_id = "run_1",
    run_started_at = 900,
    now = 1000,
    acquired_year = 2026
})
local buy_result = Buyout.purchase(config, buy_state, {
    candidates = buy_offer.eligible,
    selected_ids = { buy_offer.eligible[1].id },
    now = 1000,
    acquired_year = 2026,
    run_id = "run_1",
    run_started_at = 900,
    condition_seed = 12345
})

H.assert_equal(buy_result.ok, true, "purchase succeeds")
H.assert_equal(buy_result.total_price, 149, "negative common buyout price")
H.assert_equal(buy_state.currency_g, 0, "currency clamps after exact spend path")
H.assert_equal(#buy_state.cards, 1, "one raw card added")
H.assert_equal(buy_state.cards[1].center_key, "j_common", "card center stored")
H.assert_equal(buy_state.cards[1].local_key, "common_joker", "card local key stored")
H.assert_equal(buy_state.cards[1].edition, "negative", "authenticated edition stored")
H.assert_equal(buy_state.cards[1].source, "win_buyout", "source stored")
H.assert_equal(buy_state.cards[1].acquired_year, 2026, "purchase year stored")
H.assert_equal(buy_state.cards[1].source_run_id, "run_1", "purchase run id stored")
H.assert_equal(buy_state.cards[1].source_run_started_at, 900, "purchase run start stored")
H.assert_true(buy_state.cards[1].condition.surface ~= nil, "condition generated")

local gold_offer = Buyout.prepare_offer(config, Storage.normalize({ currency_g = 1000 }), {
    catalog = catalog,
    jokers = { card("j_exotic") },
    stake_level = 8,
    stake_anchors = { stake_red = 2, stake_blue = 5, stake_gold = 8 }
})
H.assert_equal(#gold_offer.eligible, 1, "gold plus allows exotic")

print("buyout tests ok")
