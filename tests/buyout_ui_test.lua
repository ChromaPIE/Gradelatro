local H = dofile("tests/test_helper.lua")
local Config = dofile("src/config.lua")
local Storage = dofile("src/storage.lua")
local BuyoutUI = dofile("src/buyout_ui.lua")

local config = Config.normalize({})

local function candidate(id, price)
    return {
        id = id,
        center_key = "j_" .. id,
        local_key = id .. "_joker",
        series_id = "Balatro",
        series_key = "BALATRO Series",
        mod_id = "Balatro",
        rarity = "common",
        edition = "base",
        price = price
    }
end

local offer = {
    eligible = {
        candidate("one", 30),
        candidate("two", 40),
        candidate("three", 50)
    },
    blocked = {
        { id = "locked", reason = "rarity_locked" }
    },
    max_selection = 2,
    run_id = "RUNSEED",
    run_started_at = 1767225600,
    acquired_year = 2026
}

H.assert_true(BuyoutUI.has_offer(offer), "offer with candidates is visible")
H.assert_equal(BuyoutUI.has_offer({ eligible = {}, blocked = {} }), false, "empty offer hidden")

local state = BuyoutUI.default_state(offer)
H.assert_equal(state.text_keys.title, "grdl_k_buyout_title", "title uses localization key")
H.assert_equal(state.text_keys.confirm, "grdl_b_confirm_buyout", "confirm uses localization key")
H.assert_equal(state.max_selection, 2, "state uses offer max")
H.assert_equal(#state.selected_ids, 0, "state starts empty")
H.assert_equal(BuyoutUI.total_selected_price(state), 0, "empty total")

H.assert_true(BuyoutUI.toggle_selection(state, "one"), "first selection accepted")
H.assert_true(BuyoutUI.is_selected(state, "one"), "first id selected")
H.assert_true(BuyoutUI.toggle_selection(state, "two"), "second selection accepted")
H.assert_equal(BuyoutUI.total_selected_price(state), 70, "selected prices summed")
H.assert_equal(BuyoutUI.toggle_selection(state, "three"), false, "selection limit blocks third")
H.assert_equal(state.last_reason, "selection_limit", "selection limit reason stored")
H.assert_true(BuyoutUI.toggle_selection(state, "one"), "selected id toggles off")
H.assert_equal(BuyoutUI.is_selected(state, "one"), false, "first id unselected")
H.assert_equal(BuyoutUI.total_selected_price(state), 40, "total updates after deselect")
H.assert_equal(BuyoutUI.toggle_selection(state, "missing"), false, "missing candidate rejected")
H.assert_equal(state.last_reason, "not_in_offer", "missing candidate reason stored")

local empty_namespace = {
    config = config,
    collection = Storage.normalize({ currency_g = 100 }),
    pending_buyout_offer = offer
}
local empty_state = BuyoutUI.default_state(offer)
local empty_result = BuyoutUI.confirm(empty_namespace, empty_state, 1800000000)
H.assert_equal(empty_result.ok, false, "empty confirmation rejected")
H.assert_equal(empty_result.reason, "no_selection", "empty confirmation reason")
H.assert_equal(empty_namespace.collection.currency_g, 100, "empty confirmation keeps currency")
H.assert_equal(#empty_namespace.collection.cards, 0, "empty confirmation adds no cards")

local poor_namespace = {
    config = config,
    collection = Storage.normalize({ currency_g = 20 }),
    pending_buyout_offer = offer
}
local poor_state = BuyoutUI.default_state(offer)
BuyoutUI.toggle_selection(poor_state, "one")
local poor_result = BuyoutUI.confirm(poor_namespace, poor_state, 1800000000)
H.assert_equal(poor_result.ok, false, "insufficient confirmation rejected")
H.assert_equal(poor_result.reason, "insufficient_funds", "insufficient reason returned")
H.assert_equal(poor_namespace.pending_buyout_offer, offer, "failed confirmation keeps pending offer")
H.assert_equal(poor_namespace.collection.currency_g, 20, "failed confirmation keeps currency")
H.assert_equal(#poor_namespace.collection.cards, 0, "failed confirmation adds no cards")

local success_namespace = {
    config = config,
    collection = Storage.normalize({ currency_g = 100 }),
    pending_buyout_offer = offer,
    mod = { id = "Gradelatro", config = {} }
}
local previous_smods_global = rawget(_G, "SMODS")
local save_count = 0
_G.SMODS = {
    save_mod_config = function(mod)
        H.assert_equal(mod, success_namespace.mod, "buyout saves namespace mod")
        save_count = save_count + 1
        return true
    end
}
local success_state = BuyoutUI.default_state(offer)
BuyoutUI.toggle_selection(success_state, "one")
BuyoutUI.toggle_selection(success_state, "two")
local success_result = BuyoutUI.confirm(success_namespace, success_state, 1800000000)
H.assert_equal(success_result.ok, true, "confirmation succeeds")
H.assert_equal(success_result.total_price, 70, "confirmation total")
H.assert_equal(success_namespace.collection.currency_g, 30, "success spends currency")
H.assert_equal(#success_namespace.collection.cards, 2, "success adds selected cards")
H.assert_equal(success_namespace.collection.cards[1].acquired_year, 2026, "success preserves acquired year")
H.assert_equal(success_namespace.collection.cards[1].source_run_id, "RUNSEED", "success preserves run id")
H.assert_equal(success_namespace.pending_buyout_offer, nil, "success clears pending offer")
H.assert_equal(success_namespace.last_buyout_result, success_result, "success stores last result")
H.assert_equal(save_count, 1, "success saves collection")
_G.SMODS = previous_smods_global

success_namespace.pending_buyout_offer = offer
success_namespace.buyout_ui_state = success_state
BuyoutUI.skip(success_namespace)
H.assert_equal(success_namespace.pending_buyout_offer, nil, "skip clears pending offer")
H.assert_equal(success_namespace.buyout_ui_state, nil, "skip clears ui state")

local runtime_namespace = {
    config = config,
    collection = Storage.normalize({ currency_g = 100 }),
    pending_buyout_offer = offer
}
local runtime = { FUNCS = {} }
local adapter = {
    opened = 0,
    refreshed = 0,
    closed = 0
}
function adapter.open_overlay()
    adapter.opened = adapter.opened + 1
end
function adapter.refresh_overlay()
    adapter.refreshed = adapter.refreshed + 1
end
function adapter.close_overlay()
    adapter.closed = adapter.closed + 1
end

H.assert_true(BuyoutUI.install_runtime(runtime_namespace, runtime, adapter), "runtime callbacks installed")
runtime.FUNCS.grdl_open_buyout()
H.assert_true(runtime_namespace.buyout_ui_state ~= nil, "open creates ui state")
H.assert_equal(adapter.opened, 1, "open adapter called")

runtime.FUNCS.grdl_toggle_buyout_card({ config = { ref_table = { id = "one" } } })
H.assert_true(BuyoutUI.is_selected(runtime_namespace.buyout_ui_state, "one"), "callback toggles selection")
H.assert_equal(adapter.refreshed, 1, "toggle refreshes overlay")

runtime.FUNCS.grdl_confirm_buyout()
H.assert_equal(#runtime_namespace.collection.cards, 1, "callback confirms selection")
H.assert_equal(runtime_namespace.pending_buyout_offer, nil, "callback success clears offer")
H.assert_equal(adapter.closed, 1, "callback success closes overlay")

runtime_namespace.pending_buyout_offer = offer
runtime_namespace.buyout_ui_state = BuyoutUI.default_state(offer)
runtime.FUNCS.grdl_skip_buyout()
H.assert_equal(runtime_namespace.pending_buyout_offer, nil, "runtime skip clears offer")
H.assert_equal(adapter.closed, 2, "runtime skip closes overlay")

print("buyout ui tests ok")
