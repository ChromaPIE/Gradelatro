local H = dofile("tests/test_helper.lua")
local Config = dofile("src/config.lua")
local Storage = dofile("src/storage.lua")
local MarketUI = dofile("src/market_ui.lua")

local config = Config.normalize({})

local namespace = {
    config = config,
    mod = { id = "Gradelatro", config = {} },
    collection = Storage.normalize({ currency_g = 10 })
}
local graded_card = Storage.add_raw_card(namespace.collection, {
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
local raw_card = Storage.add_raw_card(namespace.collection, {
    center_key = "j_raw",
    local_key = "raw_joker",
    mod_id = "Balatro",
    rarity = "common",
    edition = "base",
    condition = { centering = 9.0, print_quality = 9.0, corners = 9.0, edges = 9.0, surface = 9.0 },
    acquired_at = 1001
})

local previous_smods_global = rawget(_G, "SMODS")
local save_count = 0
_G.SMODS = {
    save_mod_config = function(mod)
        H.assert_equal(mod, namespace.mod, "market saves namespace mod")
        save_count = save_count + 1
        return true
    end
}

local runtime = { FUNCS = {} }
local adapter = { opened = 0, refreshed = 0, fail_notified = 0 }
function adapter.open_market()
    adapter.opened = adapter.opened + 1
end
function adapter.refresh_market()
    adapter.refreshed = adapter.refreshed + 1
end
function adapter.notify_failure()
    adapter.fail_notified = adapter.fail_notified + 1
end

H.assert_true(MarketUI.install_runtime(namespace, runtime, adapter), "runtime callbacks installed")
H.assert_equal(MarketUI.open(nil), nil, "missing namespace rejected")

runtime.FUNCS.grdl_open_market()
local state = namespace.market_ui_state
H.assert_true(state ~= nil, "market state stored")
H.assert_equal(adapter.opened, 1, "market overlay opened")
H.assert_equal(state.text_keys.title, "grdl_k_market_title", "market title key")
H.assert_equal(#state.rows, 2, "sellable rows listed")
H.assert_equal(state.rows[1].id, raw_card.id, "newest row first")
H.assert_equal(state.rows[1].quote, 19, "raw quote shown")
H.assert_equal(state.rows[2].quote, 159, "graded quote shown")
H.assert_equal(#state.heat_rows, 0, "no heat rows without runtime centers")
H.assert_equal(state.pending_sell_id, nil, "no pending sale initially")
H.assert_equal(state.sold_text, "", "no sold notice initially")
H.assert_equal(state.last_reason_text, "", "no failure text initially")

runtime.FUNCS.grdl_market_sell({ config = { ref_table = { id = graded_card.id } } })
H.assert_equal(namespace.market_ui_state.pending_sell_id, graded_card.id, "first click arms confirmation")
H.assert_equal(graded_card.status, "graded", "first click does not sell")
H.assert_equal(save_count, 0, "first click does not save")
H.assert_equal(adapter.refreshed, 1, "first click refreshes overlay")

runtime.FUNCS.grdl_market_sell({ config = { ref_table = { id = raw_card.id } } })
H.assert_equal(namespace.market_ui_state.pending_sell_id, raw_card.id, "clicking another card re-arms")
H.assert_equal(raw_card.status, "raw", "re-arm does not sell")
H.assert_equal(adapter.refreshed, 2, "re-arm refreshes overlay")

runtime.FUNCS.grdl_market_sell({ config = { ref_table = { id = raw_card.id } } })
H.assert_equal(raw_card.status, "sold", "confirming click sells the card")
H.assert_equal(namespace.collection.currency_g, 29, "sale credits currency")
H.assert_equal(save_count, 1, "sale saves config")
H.assert_equal(adapter.refreshed, 3, "sale refreshes overlay")
local rebuilt = namespace.market_ui_state
H.assert_true(rebuilt ~= state, "sale rebuilds market state")
H.assert_equal(#rebuilt.rows, 1, "sold card leaves the rows")
H.assert_equal(rebuilt.pending_sell_id, nil, "pending cleared after sale")
H.assert_true(rebuilt.sold_text ~= "", "sold notice set")

runtime.FUNCS.grdl_market_sell({ config = { ref_table = { id = graded_card.id } } })
graded_card.status = "queued"
local stable_state = namespace.market_ui_state
runtime.FUNCS.grdl_market_sell({ config = { ref_table = { id = graded_card.id } } })
H.assert_true(namespace.market_ui_state == stable_state, "failed sale keeps state in place")
H.assert_equal(stable_state.last_reason, "not_sellable", "failure reason surfaced")
H.assert_equal(stable_state.last_reason_text, "grdl_k_reason_not_sellable", "failure text bound")
H.assert_equal(stable_state.pending_sell_id, nil, "failure clears pending")
H.assert_equal(adapter.fail_notified, 1, "failure notifies")
H.assert_equal(save_count, 1, "failure does not save")

for index = 1, 9 do
    Storage.add_raw_card(namespace.collection, {
        center_key = "j_bulk_" .. tostring(index),
        local_key = "bulk_" .. tostring(index),
        mod_id = "Balatro",
        rarity = "common",
        edition = "base",
        condition = { centering = 9.0, print_quality = 9.0, corners = 9.0, edges = 9.0, surface = 9.0 },
        acquired_at = 3000 + index
    })
end
local paged = MarketUI.open(namespace, 4000)
H.assert_equal(paged.tab, "sell", "market opens on the sell tab")
H.assert_equal(paged.sell_page, 1, "sell page starts at one")
H.assert_equal(paged.heat_page, 1, "heat page starts at one")
H.assert_equal(#paged.rows, 9, "bulk rows listed")

MarketUI.set_page(namespace, "sell", 2)
H.assert_equal(namespace.market_ui_state.sell_page, 2, "sell page switched")
MarketUI.set_page(namespace, "sell", 99)
H.assert_equal(namespace.market_ui_state.sell_page, 2, "sell page clamps to max")
MarketUI.set_page(namespace, "heat", 99)
H.assert_equal(namespace.market_ui_state.heat_page, 1, "heat page clamps on empty board")

local refreshed_before = adapter.refreshed
runtime.FUNCS.grdl_market_sell_page({ cycle_config = { current_option = 1 } })
H.assert_equal(namespace.market_ui_state.sell_page, 1, "sell page callback applies cycle option")
H.assert_equal(adapter.refreshed, refreshed_before + 1, "sell page callback refreshes overlay")

_G.SMODS = previous_smods_global

print("market ui tests ok")
