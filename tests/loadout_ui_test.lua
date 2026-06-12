local H = dofile("tests/test_helper.lua")
local Config = dofile("src/config.lua")
local Storage = dofile("src/storage.lua")
local Loadout = dofile("src/loadout.lua")
local LoadoutUI = dofile("src/loadout_ui.lua")

local config = Config.normalize({})
local namespace = {
    config = config,
    mod = { id = "Gradelatro", config = {} },
    collection = Storage.normalize({ currency_g = 5000 })
}

local previous_smods = rawget(_G, "SMODS")
local save_count = 0
_G.SMODS = { save_mod_config = function() save_count = save_count + 1 return true end }

local runtime = { FUNCS = {} }
local adapter = { loadout_opened = 0, license_opened = 0 }
function adapter.open_loadout() adapter.loadout_opened = adapter.loadout_opened + 1 end
function adapter.open_license() adapter.license_opened = adapter.license_opened + 1 end

H.assert_true(LoadoutUI.install_runtime(namespace, runtime, adapter), "runtime callbacks installed")
H.assert_equal(LoadoutUI.open(nil), nil, "missing namespace rejected")

runtime.FUNCS.grdl_open_loadout()
local state = namespace.loadout_ui_state
H.assert_true(state ~= nil, "loadout state stored")
H.assert_equal(adapter.loadout_opened, 1, "loadout overlay opened")
H.assert_equal(state.license, 0, "license level surfaced")
H.assert_equal(state.capacity, 0, "capacity surfaced")
H.assert_equal(#state.entries, 0, "no member entries yet")
H.assert_equal(state.active_transport, nil, "no transport yet")

-- member entries resolve to card records
local mint = { centering = 9.8, print_quality = 9.8, corners = 9.8, edges = 9.8, surface = 9.8 }
local card = Storage.add_raw_card(namespace.collection, {
    center_key = "j_joker", local_key = "joker", rarity = "common",
    edition = "base", condition = mint, acquired_at = 1000
})
namespace.collection.loadout.license = 3
Loadout.add_card(namespace.collection, card.id)
card.status = "sold"
LoadoutUI.open(namespace)
H.assert_equal(#namespace.loadout_ui_state.entries, 0, "open reconciles dead members")
card.status = "raw"
Loadout.add_card(namespace.collection, card.id)
LoadoutUI.open(namespace)
H.assert_equal(namespace.loadout_ui_state.entries[1].id, card.id, "member entry carries record")
H.assert_equal(namespace.loadout_ui_state.capacity, 3, "capacity follows license")

-- license label helper
H.assert_equal(LoadoutUI.license_label(0), "grdl_k_license_none", "level zero label")
H.assert_true(LoadoutUI.license_label(5):find("grdl_k_tier_2", 1, true) ~= nil, "level five labels advanced tier")

-- license purchase handler
runtime.FUNCS.grdl_open_license()
H.assert_equal(adapter.license_opened, 1, "license overlay opened")
local before = namespace.collection.currency_g
runtime.FUNCS.grdl_license_buy()
H.assert_equal(namespace.collection.loadout.license, 4, "license purchase advances")
H.assert_equal(before - namespace.collection.currency_g, config.loadout.license_prices[4], "license price charged")
H.assert_equal(save_count, 1, "license purchase saves")
H.assert_true(namespace.loadout_ui_state.feedback ~= "", "purchase feedback bound")

-- transport purchase + activation handlers
runtime.FUNCS.grdl_transport_buy({ config = { ref_table = { key = "blue" } } })
H.assert_equal(namespace.collection.loadout.transports.blue, true, "transport purchased")
H.assert_equal(namespace.collection.loadout.active_transport, "blue", "first transport activates")
H.assert_equal(save_count, 2, "transport purchase saves")
runtime.FUNCS.grdl_transport_buy({ config = { ref_table = { key = "gold" } } })
runtime.FUNCS.grdl_transport_activate({ config = { ref_table = { key = "gold" } } })
H.assert_equal(namespace.collection.loadout.active_transport, "gold", "activation switches")
H.assert_equal(save_count, 4, "activation saves")
local poor = namespace.collection.currency_g
namespace.collection.currency_g = 0
runtime.FUNCS.grdl_license_buy()
H.assert_equal(namespace.loadout_ui_state.feedback, "grdl_k_reason_insufficient_funds", "broke purchase feedback")
H.assert_equal(save_count, 4, "failed purchase does not save")
namespace.collection.currency_g = poor

_G.SMODS = previous_smods
print("loadout ui tests ok")
