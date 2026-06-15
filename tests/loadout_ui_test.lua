local H = dofile("tests/test_helper.lua")
local Config = dofile("src/core/config.lua")
local Storage = dofile("src/core/storage.lua")
local Loadout = dofile("src/domain/loadout.lua")
local LoadoutUI = dofile("src/ui/loadout_ui.lua")
local rng = H.install_pseudorandom_stub()

local config = Config.normalize({})
local namespace = {
    config = config,
    mod = { id = "Gradelatro", config = {} },
    collection = Storage.normalize({ currency_g = 5000 })
}

local previous_smods = rawget(_G, "SMODS")
local save_count = 0
_G.SMODS = {
    load_file = previous_smods.load_file,
    save_mod_config = function() save_count = save_count + 1 return true end
}

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
local state_identity = namespace.loadout_ui_state
runtime.FUNCS.grdl_transport_buy({ config = { ref_table = { key = "gold" } } })
runtime.FUNCS.grdl_transport_activate({ config = { ref_table = { key = "gold" } } })
H.assert_equal(namespace.collection.loadout.active_transport, "gold", "activation switches")
H.assert_equal(namespace.loadout_ui_state, state_identity, "purchase handlers refresh state in place")
H.assert_equal(save_count, 4, "activation saves")
local poor = namespace.collection.currency_g
namespace.collection.currency_g = 0
runtime.FUNCS.grdl_license_buy()
H.assert_equal(namespace.loadout_ui_state.feedback, "grdl_k_reason_insufficient_funds", "broke purchase feedback")
H.assert_equal(save_count, 4, "failed purchase does not save")
namespace.collection.currency_g = poor

local previous_ui_g = rawget(_G, "G")
local previous_card_area = rawget(_G, "CardArea")
local previous_card = rawget(_G, "Card")
local previous_ui_button = rawget(_G, "UIBox_button")
local previous_generic_options = rawget(_G, "create_UIBox_generic_options")
local captured_area = nil
_G.G = {
    ROOM = { T = { x = 0, y = 0, w = 10, h = 10 } },
    CARD_W = 1,
    CARD_H = 1.4,
    UIT = { R = "R", C = "C", T = "T", O = "O", ROOT = "ROOT" },
    C = {
        WHITE = { 1, 1, 1, 1 },
        RED = { 1, 0, 0, 1 },
        L_BLACK = { 0.2, 0.2, 0.2, 1 },
        PURPLE = { 0.5, 0, 1, 1 },
        UI = {
            TEXT_INACTIVE = { 0.5, 0.5, 0.5, 1 },
            TEXT_DARK = { 0, 0, 0, 1 }
        }
    },
    P_CENTERS = { j_joker = { key = "j_joker" } },
    P_CARDS = { empty = {} },
    FONTS = {}
}
_G.CardArea = function(x, y, w, h)
    local area = { cards = {}, T = { x = x, y = y, w = w, h = h } }
    function area:emplace(card_obj)
        self.cards[#self.cards + 1] = card_obj
    end
    captured_area = area
    return area
end
_G.Card = function()
    return { set_edition = function() end }
end
_G.UIBox_button = function(args)
    return { n = G.UIT.C, config = args, nodes = {} }
end
_G.create_UIBox_generic_options = function(args) return args end
LoadoutUI.create_overlay_definition(namespace)
H.assert_true(captured_area ~= nil, "loadout definition creates a card area")
H.assert_equal(captured_area.cards[1].grdl_inspect_close_func, "grdl_open_loadout", "loadout UI cards return to loadout inspect context")
_G.create_UIBox_generic_options = previous_generic_options
_G.UIBox_button = previous_ui_button
_G.Card = previous_card
_G.CardArea = previous_card_area
_G.G = previous_ui_g

local previous_entry_g = rawget(_G, "G")
local previous_entry_card_area = rawget(_G, "CardArea")
local previous_entry_card = rawget(_G, "Card")
local previous_entry_button = rawget(_G, "UIBox_button")
local previous_entry_options = rawget(_G, "create_UIBox_generic_options")
local captured_entry_area = nil
_G.G = {
    ROOM = { T = { x = 0, y = 0, w = 10, h = 10 } },
    CARD_W = 1,
    CARD_H = 1.4,
    UIT = { R = "R", C = "C", T = "T", O = "O", ROOT = "ROOT" },
    C = {
        WHITE = { 1, 1, 1, 1 },
        GREEN = { 0, 1, 0, 1 },
        RED = { 1, 0, 0, 1 },
        L_BLACK = { 0.2, 0.2, 0.2, 1 },
        UI = {
            TEXT_LIGHT = { 1, 1, 1, 1 },
            TEXT_DARK = { 0, 0, 0, 1 }
        }
    },
    P_CENTERS = { j_joker = { key = "j_joker" } },
    P_CARDS = { empty = {} }
}
_G.CardArea = function(x, y, w, h)
    local area = { cards = {}, T = { x = x, y = y, w = w, h = h } }
    function area:emplace(card_obj)
        self.cards[#self.cards + 1] = card_obj
    end
    captured_entry_area = area
    return area
end
_G.Card = function()
    return { set_edition = function() end }
end
_G.UIBox_button = function(args)
    return { n = G.UIT.C, config = args, nodes = {} }
end
_G.create_UIBox_generic_options = function(args) return args end
namespace.loadout_entry_window = { picks = 1, card_ids = { card.id } }
local entry_definition = LoadoutUI.create_entry_definition(namespace)
local function has_entry_area(node)
    if type(node) ~= "table" then return false end
    if node.config and node.config.object == captured_entry_area then return true end
    for _, child in ipairs(node.nodes or {}) do
        if has_entry_area(child) then return true end
    end
    return false
end
local entry_card_row = nil
for _, node in ipairs(entry_definition.contents or {}) do
    if has_entry_area(node) then entry_card_row = node end
end
H.assert_true(captured_entry_area ~= nil, "entry popup creates a card area")
H.assert_true(entry_card_row ~= nil, "entry popup renders a card row")
H.assert_near(captured_entry_area.T.h, 1.02 * _G.G.CARD_H, 0.001, "entry card area is a little taller than a card")
H.assert_equal(entry_card_row.config.padding, 0.07, "entry popup leaves a slightly larger card gap")
namespace.loadout_entry_window = nil
namespace.loadout_entry_area = nil
_G.create_UIBox_generic_options = previous_entry_options
_G.UIBox_button = previous_entry_button
_G.Card = previous_entry_card
_G.CardArea = previous_entry_card_area
_G.G = previous_entry_g

-- ===== run integration =====
local previous_run_g = rawget(_G, "G")
local Proficiency = dofile("src/domain/proficiency.lua")
local run_ns = {
    config = config,
    mod = { id = "Gradelatro", config = {} },
    collection = Storage.normalize({ currency_g = 0 })
}
run_ns.collection.loadout.license = 3
run_ns.collection.loadout.transports.gold = true
run_ns.collection.loadout.active_transport = "gold"
local function run_card(key, status, antes, edition)
    local card = Storage.add_raw_card(run_ns.collection, {
        center_key = key, local_key = key, rarity = "common",
        edition = edition or "negative",
        condition = { centering = 9.8, print_quality = 9.8, corners = 9.8, edges = 9.8, surface = 9.8 },
        acquired_at = 1
    })
    if status then card.status = status end
    if antes then card.proficiency = { antes = antes } end
    return card
end
local graded_novice = run_card("j_gn", "graded", 0)   -- level 0: spawns editionless
local graded_adept = run_card("j_ga", "graded", 40, "holographic")   -- level III + eternal pref
graded_adept.proficiency.eternal = true
local raw_entry = run_card("j_raw", nil, nil)         -- raw: wears, editionless
Loadout.add_card(run_ns.collection, graded_novice.id)
Loadout.add_card(run_ns.collection, graded_adept.id)
Loadout.add_card(run_ns.collection, raw_entry.id)

local spawned = {}
local set_eternal_calls = {}
_G.SMODS.add_card = function(args)
    local joker = {
        ability = {},
        set_eternal = function(self, flag)
            set_eternal_calls[#set_eternal_calls + 1] = flag
            self.ability.eternal = flag
        end
    }
    spawned[#spawned + 1] = { args = args, joker = joker }
    return joker
end

local funcs = { cash_out = function(e)
    -- vanilla cash_out resets the blind states for the next ante before returning
    local resets = _G.G and _G.G.GAME and _G.G.GAME.round_resets or nil
    if resets and resets.blind_states then resets.blind_states.Boss = "Upcoming" end
    return "paid"
end }
local game_class = {}
function game_class.start_run(self, args) return "started" end
local env = { funcs = funcs, game_class = game_class }
H.assert_equal(LoadoutUI.install(run_ns, env), true, "run hooks installed")
H.assert_equal(LoadoutUI.install(run_ns, env), true, "second install is a no-op")

_G.G = {
    GAME = {
        pseudorandom = { seed = "LOADRUN" },
        round_resets = { ante = 2, blind_states = { Boss = "Defeated" } }
    },
    jokers = { cards = {} },
    STATE = 1
}

game_class.start_run({}, {})
local run_state = _G.G.GAME.grdl_loadout
H.assert_true(run_state ~= nil, "run state seeded on start")
H.assert_equal(run_state.run_id, "LOADRUN", "run id captured")
H.assert_equal(run_state.transport, "gold", "transport snapshot taken")

-- boss cash-out for ante 1 (round_resets.ante already eased to 2)
funcs.cash_out({ config = {} })
H.assert_true(run_ns.loadout_entry_window ~= nil, "entry window staged")
H.assert_equal(run_ns.loadout_entry_window.picks, 2, "gold first window allows two")

-- confirm two entries
local result = LoadoutUI.spawn_entries(run_ns, { graded_novice.id, graded_adept.id }, 7777)
H.assert_equal(result.ok, true, "entries spawn")
H.assert_equal(#spawned, 2, "two jokers spawned")
H.assert_equal(spawned[1].args.no_edition, true, "level zero spawns editionless")
H.assert_true(type(spawned[2].args.edition) == "table" and spawned[2].args.edition.holo == true, "level three maps holographic edition for SMODS")
H.assert_equal(set_eternal_calls[1], true, "eternal preference applied")
H.assert_equal(spawned[1].joker.ability.grdl_loadout_id, graded_novice.id, "spawn tagged")
H.assert_equal(#run_state.entered, 2, "entries consumed")

-- proficiency counts on next boss; entry ante itself never counted
_G.G.jokers.cards = { spawned[1].joker, spawned[2].joker }
_G.G.GAME.round_resets.ante = 5
_G.G.GAME.round_resets.blind_states.Boss = "Defeated"
funcs.cash_out({ config = {} })
H.assert_equal(graded_novice.proficiency.antes, 1, "present graded card counts the ante")
H.assert_equal(graded_adept.proficiency.antes, 41, "count accumulates on top")
_G.G.GAME.round_resets.blind_states.Boss = "Defeated"
funcs.cash_out({ config = {} })
H.assert_equal(graded_novice.proficiency.antes, 1, "same ante never double counts")

-- removed joker stops counting
_G.G.jokers.cards = { spawned[2].joker }
_G.G.GAME.round_resets.ante = 7
_G.G.GAME.round_resets.blind_states.Boss = "Defeated"
funcs.cash_out({ config = {} })
H.assert_equal(graded_novice.proficiency.antes, 1, "missing joker stops accruing")
H.assert_equal(graded_adept.proficiency.antes, 42, "surviving joker keeps accruing")

-- raw wear on entry
local surface_before = raw_entry.condition.surface
LoadoutUI.spawn_entries(run_ns, { raw_entry.id }, 8888)
H.assert_equal(#spawned, 3, "raw card spawned")
H.assert_equal(spawned[3].args.no_edition, true, "raw card spawns editionless")
H.assert_true(raw_entry.condition.surface < surface_before, "raw card wears on entry")
H.assert_equal(raw_entry.proficiency, nil, "raw card gains no proficiency block")
H.assert_true(rng.has_call("pseudorandom", "grdl_loadout_wear_"), "loadout ui wear uses native pseudorandom")

-- non-boss cash-out does nothing
run_ns.loadout_entry_window = nil
_G.G.GAME.round_resets.blind_states.Boss = "Upcoming"
funcs.cash_out({ config = {} })
H.assert_equal(run_ns.loadout_entry_window, nil, "small blind opens no window")

_G.G = previous_run_g

_G.SMODS = previous_smods
rng.restore()
print("loadout ui tests ok")
