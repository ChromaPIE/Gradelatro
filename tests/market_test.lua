local H = dofile("tests/test_helper.lua")
local Config = dofile("src/config.lua")
local Storage = dofile("src/storage.lua")
local Market = dofile("src/market.lua")

local config = Config.normalize({})

H.assert_equal(config.market.refresh_cooldown, 86400, "default refresh cooldown is one real day")
H.assert_true(config.market.raw_sell_factor > 0 and config.market.raw_sell_factor < 1, "raw sell factor is a discount")

local state = Storage.normalize({})
H.assert_near(Market.heat_for(state, "Cryptid"), 1.0, 0.000001, "unknown series defaults to neutral heat")

local first = Market.refresh(config, state, { series_ids = { "Balatro", "Cryptid" }, now = 1767225600, rng_seed = 42 })
H.assert_equal(first.ok, true, "refresh succeeds")
H.assert_equal(first.refreshed, true, "first refresh runs")
H.assert_equal(state.market.last_refresh, 1767225600, "refresh timestamp stored")

local balatro_heat = Market.heat_for(state, "Balatro")
local cryptid_heat = Market.heat_for(state, "Cryptid")
H.assert_true(balatro_heat >= config.market.heat_min and balatro_heat <= config.market.heat_max, "heat stays in band")
H.assert_true(cryptid_heat >= config.market.heat_min and cryptid_heat <= config.market.heat_max, "second series heat stays in band")

local replay_state = Storage.normalize({})
Market.refresh(config, replay_state, { series_ids = { "Balatro", "Cryptid" }, now = 1767225600, rng_seed = 42 })
H.assert_near(Market.heat_for(replay_state, "Balatro"), balatro_heat, 0.000001, "same seed reproduces heat")

local cooled = Market.refresh(config, state, { series_ids = { "Balatro" }, now = 1767225600 + 3600 })
H.assert_equal(cooled.refreshed, false, "refresh inside cooldown is a no-op")
H.assert_near(Market.heat_for(state, "Balatro"), balatro_heat, 0.000001, "cooldown keeps heat unchanged")

local forced = Market.refresh(config, state, { series_ids = { "Balatro" }, now = 1767225600 + 3600, rng_seed = 7, force = true })
H.assert_equal(forced.refreshed, true, "forced refresh runs inside cooldown")

local extreme_config = Config.normalize({ market = { event_chance = 1.0, event_min = 5, event_max = 9 } })
local extreme_state = Storage.normalize({})
Market.refresh(extreme_config, extreme_state, { series_ids = { "Balatro" }, now = 1767225600, rng_seed = 3 })
local extreme_heat = Market.heat_for(extreme_state, "Balatro")
H.assert_true(extreme_heat >= extreme_config.market.heat_min and extreme_heat <= extreme_config.market.heat_max, "event bumps still clamp to band")

H.assert_equal(Market.trend_label(1.2), "hot", "hot label")
H.assert_equal(Market.trend_label(1.06), "rising", "rising label")
H.assert_equal(Market.trend_label(1.0), "stable", "stable label")
H.assert_equal(Market.trend_label(0.9), "cooling", "cooling label")

local sell_state = Storage.normalize({ currency_g = 10 })
local graded_card = Storage.add_raw_card(sell_state, {
    center_key = "j_joker",
    local_key = "joker",
    mod_id = "Balatro",
    rarity = "common",
    edition = "base",
    condition = { centering = 9.8, print_quality = 9.8, corners = 9.8, edges = 9.8, surface = 9.8 },
    acquired_at = 1000
})
graded_card.status = "graded"
graded_card.grade = 10
local raw_card = Storage.add_raw_card(sell_state, {
    center_key = "j_raw",
    local_key = "raw_joker",
    mod_id = "Balatro",
    rarity = "common",
    edition = "base",
    condition = { centering = 9.0, print_quality = 9.0, corners = 9.0, edges = 9.0, surface = 9.0 },
    acquired_at = 1001
})

H.assert_near(Market.card_value(config, sell_state, graded_card), 210, 0.000001, "gem mint common values at rav times grade mult")
H.assert_equal(Market.sell_quote(config, sell_state, graded_card), 159, "graded quote uses system buy midpoint")
H.assert_equal(Market.sell_quote(config, sell_state, raw_card), 19, "raw quote uses raw sell factor")

sell_state.market.series_heat["Balatro"] = { heat = 1.2 }
H.assert_equal(Market.sell_quote(config, sell_state, graded_card), 191, "heat scales the quote")
sell_state.market.series_heat["Balatro"] = nil

local rows = Market.sell_rows(config, sell_state)
H.assert_equal(#rows, 2, "sellable rows listed")
H.assert_equal(rows[1].id, raw_card.id, "newest first")
H.assert_equal(rows[1].quote, 19, "row carries quote")
H.assert_equal(rows[2].grade, 10, "row carries grade")

local missing = Market.sell(config, sell_state, { card_id = "grdl_999", now = 2000 })
H.assert_equal(missing.ok, false, "unknown card rejected")
H.assert_equal(missing.reason, "card_not_found", "unknown card reason")

local sold = Market.sell(config, sell_state, { card_id = graded_card.id, now = 2000 })
H.assert_equal(sold.ok, true, "sell succeeds")
H.assert_equal(sold.price, 159, "sell pays the quote")
H.assert_equal(sell_state.currency_g, 169, "currency credited")
H.assert_equal(graded_card.status, "sold", "card marked sold")
H.assert_equal(graded_card.sold_at, 2000, "sold timestamp stored")
H.assert_equal(graded_card.sold_price, 159, "sold price stored")

local resell = Market.sell(config, sell_state, { card_id = graded_card.id, now = 2001 })
H.assert_equal(resell.ok, false, "sold card cannot resell")
H.assert_equal(resell.reason, "not_sellable", "resell reason")

raw_card.status = "queued"
local queued_sell = Market.sell(config, sell_state, { card_id = raw_card.id, now = 2002 })
H.assert_equal(queued_sell.ok, false, "queued card cannot sell")
H.assert_equal(queued_sell.reason, "not_sellable", "queued sell reason")
H.assert_equal(#Market.sell_rows(config, sell_state), 0, "no sellable rows remain")

local slot_catalog = {
    { center_key = "j_a1", local_key = "a1", series_id = "Alpha", mod_id = "Alpha", mod_name = "Alpha", series_key = "Alpha Series", rarity = "common" },
    { center_key = "j_a2", local_key = "a2", series_id = "Alpha", mod_id = "Alpha", mod_name = "Alpha", series_key = "Alpha Series", rarity = "rare" },
    { center_key = "j_b1", local_key = "b1", series_id = "Beta", mod_id = "Beta", mod_name = "Beta", series_key = "Beta Series", rarity = "common" }
}
local slot_state = Storage.normalize({})
Storage.add_raw_card(slot_state, { center_key = "j_a1", local_key = "a1", mod_id = "Alpha", rarity = "common", edition = "base", condition = { centering = 9, print_quality = 9, corners = 9, edges = 9, surface = 9 }, acquired_at = 1 })
local slot_graded = Storage.add_raw_card(slot_state, { center_key = "j_a2", local_key = "a2", mod_id = "Alpha", rarity = "rare", edition = "base", condition = { centering = 9, print_quality = 9, corners = 9, edges = 9, surface = 9 }, acquired_at = 2 })
slot_graded.status = "graded"
slot_state.market.series_heat["Alpha"] = { heat = 1.2, event = { bump = 0.1, expires_at = 999999 } }

local slots = Market.trend_slots(slot_state, slot_catalog)
H.assert_equal(#slots, 2, "one slot per mod")
H.assert_equal(slots[1].series_id, "Alpha", "slots sorted by series name")
H.assert_equal(slots[1].mod_name, "Alpha", "slot mod name")
H.assert_equal(slots[1].series_key, "Alpha Series", "slot series key")
H.assert_equal(slots[1].pool_size, 2, "slot pool size")
H.assert_equal(#slots[1].center_keys, 2, "slot carousel keys")
H.assert_equal(slots[1].owned, 2, "slot owned count")
H.assert_equal(slots[1].graded, 1, "slot graded count")
H.assert_equal(slots[1].trend, "hot", "slot trend label from heat")
H.assert_equal(slots[1].label_key, "grdl_k_heat_hot", "slot trend localization key")
H.assert_equal(slots[1].event_active, true, "slot event flag")
H.assert_equal(slots[2].owned, 0, "unowned series counts zero")
H.assert_equal(slots[2].trend, "stable", "neutral heat is stable")
H.assert_equal(slots[2].event_active, false, "no event flag without event")

print("market tests ok")
