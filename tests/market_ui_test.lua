local H = dofile("tests/test_helper.lua")
local Config = dofile("src/core/config.lua")
local Storage = dofile("src/core/storage.lua")
local MarketUI = dofile("src/ui/market_ui.lua")

local config = Config.normalize({})

local namespace = {
    config = config,
    mod = { id = "Gradelatro", config = {} },
    collection = Storage.normalize({ currency_g = 10 })
}

local runtime = { FUNCS = {} }
local adapter = { opened = 0, refreshed = 0 }
function adapter.open_market()
    adapter.opened = adapter.opened + 1
end
function adapter.refresh_market()
    adapter.refreshed = adapter.refreshed + 1
end

H.assert_true(MarketUI.install_runtime(namespace, runtime, adapter), "runtime callbacks installed")
H.assert_equal(MarketUI.open(nil), nil, "missing namespace rejected")

runtime.FUNCS.grdl_open_market()
local state = namespace.market_ui_state
H.assert_true(state ~= nil, "market state stored")
H.assert_equal(adapter.opened, 1, "market overlay opened")
H.assert_equal(state.text_keys.title, "grdl_k_market_title", "market title key")
H.assert_equal(state.text_keys.tab_trends, "grdl_k_tab_trends", "trends tab key")
H.assert_equal(#state.trend_slots, 0, "no trend slots without runtime centers")
H.assert_equal(state.heat_page, 1, "heat page starts at one")

for index = 1, 25 do
    state.trend_slots[index] = {
        series_id = "Mod" .. tostring(index),
        mod_name = "Mod " .. tostring(index),
        series_key = "Series " .. tostring(index),
        center_keys = { "j_x" },
        pool_size = 1,
        owned = 0,
        graded = 0,
        trend = "stable",
        label_key = "grdl_k_heat_stable",
        event_active = false
    }
end
MarketUI.set_page(namespace, 2)
H.assert_equal(state.heat_page, 2, "heat page switched")
MarketUI.set_page(namespace, 99)
H.assert_equal(state.heat_page, 3, "heat page clamps to max")

local refreshed_before = adapter.refreshed
runtime.FUNCS.grdl_market_heat_page({ cycle_config = { current_option = 1 } })
H.assert_equal(state.heat_page, 1, "heat page callback applies cycle option")
H.assert_equal(adapter.refreshed, refreshed_before + 1, "heat page callback falls back to overlay refresh")

H.assert_equal(state.market_tab, "blackmarket", "market opens on the black market tab")
H.assert_equal(state.bm_locked, true, "black market locked before any win")
H.assert_equal(state.bm_text, "", "no purchase feedback initially")

local previous_smods = rawget(_G, "SMODS")
local save_count = 0
_G.SMODS = {
    save_mod_config = function() save_count = save_count + 1 return true end
}

local mint = { centering = 9.8, print_quality = 9.8, corners = 9.8, edges = 9.8, surface = 9.8 }
namespace.collection.currency_g = 100
namespace.collection.market = namespace.collection.market or {}
namespace.collection.market.black_market = {
    run_id = "R1",
    boss_key = "bl_hook",
    generated_at = 1000,
    offers = {
        { slot = 1, center_key = "j_a", local_key = "a", series_key = "A Series", mod_id = "A", mod_name = "A", rarity = "common", edition = "base", condition = mint, graded = true, grade = 10, mystery = false, sold = false, price = 40 },
        { slot = 2, center_key = "j_b", local_key = "b", series_key = "A Series", mod_id = "A", mod_name = "A", rarity = "common", edition = "foil", condition = mint, graded = false, mystery = false, sold = false, price = 99999 },
        { slot = 3, center_key = "j_c", local_key = "c", series_key = "A Series", mod_id = "A", mod_name = "A", rarity = "common", edition = "base", condition = mint, graded = false, mystery = true, sold = false, price = 70 }
    }
}
runtime.FUNCS.grdl_open_market()
local bm_state = namespace.market_ui_state
H.assert_equal(bm_state.bm_locked, false, "offers unlock the black market")
H.assert_equal(#bm_state.bm_offers, 3, "offers exposed to the ui")
H.assert_equal(bm_state.bm_boss_key, "bl_hook", "dealer boss key exposed")

H.assert_true(type(runtime.FUNCS.grdl_bm_buy) == "function", "buy callback registered")
local bought = MarketUI.buy(namespace, 1, 2000)
H.assert_equal(bought.ok, true, "purchase succeeds")
H.assert_equal(namespace.collection.currency_g, 60, "price charged")
H.assert_equal(save_count, 1, "purchase saves config")
H.assert_true(bm_state.bm_text ~= "", "purchase feedback set")
H.assert_equal(namespace.collection.market.black_market.offers[1].sold, true, "offer sold")
H.assert_equal(namespace.collection.cards[#namespace.collection.cards].status, "graded", "graded offer arrives graded")

local resale = MarketUI.buy(namespace, 1, 2001)
H.assert_equal(resale.ok, false, "sold slot rejected")
H.assert_equal(bm_state.bm_text, "grdl_k_reason_already_sold", "failure reason bound")

local broke = MarketUI.buy(namespace, 2, 2002)
H.assert_equal(broke.ok, false, "insufficient funds rejected")
H.assert_equal(bm_state.bm_text, "grdl_k_reason_insufficient_funds", "insufficient reason bound")
H.assert_equal(save_count, 1, "failed purchases do not save")

_G.SMODS = previous_smods

local center_class = { set = "Joker", unlocked = true }
center_class.__index = center_class
local modded_center = setmetatable({
    key = "j_mod_legend",
    pos = { x = 0, y = 0 },
    discovered = true,
    atlas = "ModAtlas"
}, center_class)
local display = MarketUI.mystery_display_center(modded_center)
H.assert_true(display ~= modded_center, "mystery display is a copy")
H.assert_equal(display.set, "Joker", "metatable fields survive the copy")
H.assert_equal(display.discovered, false, "mystery copy stays hidden")
H.assert_equal(display.unlocked, true, "mystery copy bypasses lock art")
H.assert_equal(display.key, "j_mod_legend", "instance fields copied")
H.assert_equal(modded_center.discovered, true, "real center untouched")

local previous_tick_g = rawget(_G, "G")
local plain_center = { key = "j_one", set = "Joker" }
local soul_center = { key = "j_two", set = "Joker", soul_pos = { x = 1, y = 0 } }
_G.G = { P_CENTERS = { j_one = plain_center, j_two = soul_center } }
local morphs = {}
local trend_card = {
    config = { center = plain_center, center_key = "j_one" },
    children = {},
    T = { x = 5, y = 6, r = 0.1 },
    grdl_carousel = { keys = { "j_one", "j_two" }, index = 1, last = -1e9 },
    set_ability = function(self, center, initial)
        morphs[#morphs + 1] = { center = center, initial = initial }
        -- the real set_ability teleports T back to the build position
        self.T.x, self.T.y, self.T.r = -99, -99, 0
    end
}
runtime.FUNCS.grdl_trend_tick({ config = { ref_table = { cards = { trend_card } } } })
H.assert_equal(#morphs, 1, "due carousel morphs once")
H.assert_equal(morphs[1].center, soul_center, "morph targets the next center")
H.assert_equal(morphs[1].initial, true, "morph skips deck bookkeeping")
H.assert_equal(trend_card.grdl_carousel.index, 2, "carousel index advanced")
H.assert_near(trend_card.T.x, 5, 1e-9, "morph keeps the live x position")
H.assert_near(trend_card.T.y, 6, 1e-9, "morph keeps the live y position")
H.assert_near(trend_card.T.r, 0.1, 1e-9, "morph keeps the live rotation")
runtime.FUNCS.grdl_trend_tick({ config = { ref_table = { cards = { trend_card } } } })
H.assert_equal(#morphs, 1, "fresh morph waits for the interval")

local staggered_card = {
    config = { center = plain_center, center_key = "j_one" },
    children = {},
    T = { x = 0, y = 0, r = 0 },
    grdl_carousel = { keys = { "j_one", "j_two" }, index = 1, phase = 0.74 },
    set_ability = function(self) morphs[#morphs + 1] = {} end
}
runtime.FUNCS.grdl_trend_tick({ config = { ref_table = { cards = { staggered_card } } } })
H.assert_equal(#morphs, 1, "staggered card does not morph on its first tick")
H.assert_true(type(staggered_card.grdl_carousel.last) == "number", "stagger seeds the swap clock with its phase")
_G.G = previous_tick_g

local revealed_rows = MarketUI.intel_rows({
    mystery = true,
    mod_name = "Alpha",
    rarity = "cry_epic",
    edition = "foil",
    graded = false,
    intel = { mod = true, rarity = true, edition = true, graded = true }
})
H.assert_equal(#revealed_rows, 4, "four intel rows")
H.assert_equal(revealed_rows[1].label, "grdl_k_intel_mod", "mod label key")
H.assert_equal(revealed_rows[1].value, "Alpha", "revealed mod shows the mod name")
H.assert_equal(revealed_rows[2].value, "cry_epic", "unlocalized rarity falls back to the raw value")
H.assert_equal(revealed_rows[3].value, "grdl_k_intel_edition_yes", "revealed edition only discloses presence")
H.assert_equal(revealed_rows[4].value, "grdl_k_intel_graded_no", "revealed grading discloses raw status")

local hidden_rows = MarketUI.intel_rows({
    mystery = true,
    mod_name = "Alpha",
    rarity = "common",
    edition = "base",
    graded = true,
    intel = { mod = false, rarity = false, edition = false, graded = false }
})
for index = 1, 4 do
    H.assert_equal(hidden_rows[index].value, "grdl_k_intel_unknown", "hidden intel row " .. index .. " masked")
end

local single_quip = MarketUI.quip_lines("hello")
H.assert_equal(#single_quip, 1, "string quip wraps into one line")
H.assert_equal(single_quip[1], "hello", "string quip preserved")
local multi_quip = MarketUI.quip_lines({ "line one", "line two" })
H.assert_equal(#multi_quip, 2, "array quip keeps its lines")
H.assert_equal(multi_quip[2], "line two", "array quip line preserved")

H.assert_equal(MarketUI.reveal_mystery(namespace, { offer = { slot = 3, mystery = true }, card = { center_key = "j_c" } }), false, "reveal is a safe no-op without runtime")

print("market ui tests ok")
