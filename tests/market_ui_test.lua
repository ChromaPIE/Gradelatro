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
H.assert_equal(#state.heat_rows, 0, "no heat rows without runtime centers")
H.assert_equal(state.heat_page, 1, "heat page starts at one")

for index = 1, 25 do
    state.heat_rows[index] = {
        series_key = "Series " .. tostring(index),
        label = "stable",
        label_key = "grdl_k_heat_stable"
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

print("market ui tests ok")
