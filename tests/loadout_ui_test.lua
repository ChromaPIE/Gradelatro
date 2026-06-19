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
H.assert_equal(#namespace.loadout_ui_state.entries, 0, "open hides dead members")
H.assert_equal(#namespace.collection.loadout.card_ids, 1, "open does not rewrite loadout membership")
card.status = "raw"
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

_G.SMODS = {
    load_file = previous_smods.load_file,
    save_mod_config = function() return false end
}
namespace.collection.currency_g = 5000
namespace.collection.loadout.license = 4
runtime.FUNCS.grdl_license_buy()
H.assert_equal(namespace.collection.loadout.license, 4, "save failure rolls back license purchase")
H.assert_equal(namespace.collection.currency_g, 5000, "save failure rolls back license cost")
H.assert_equal(namespace.loadout_ui_state.feedback, "grdl_k_reason_save_failed", "save failure feedback bound")
_G.SMODS = {
    load_file = previous_smods.load_file,
    save_mod_config = function() save_count = save_count + 1 return true end
}

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

local previous_fee_g = rawget(_G, "G")
local previous_fee_options = rawget(_G, "create_UIBox_generic_options")
local previous_attention_text = rawget(_G, "attention_text")
local previous_fee_dynatext = rawget(_G, "DynaText")
local attention_calls = {}
_G.attention_text = function(args)
    attention_calls[#attention_calls + 1] = args
end
local dynatext_objects = {}
_G.DynaText = function(args)
    local object = {
        args = args,
        T = { x = 0, y = 0, w = 0, h = 0 },
        VT = { x = 0, y = 0, w = 0, h = 0 }
    }
    function object:remove() self.removed = true end
    function object:move_with_major() self.moved = true end
    function object:align_to_major() self.aligned = true end
    dynatext_objects[#dynatext_objects + 1] = object
    return object
end
_G.create_UIBox_generic_options = function(args) return args end
_G.G = {
    UIT = { R = "R", C = "C", T = "T", O = "O" },
    C = {
        WHITE = { 1, 1, 1, 1 },
        RED = { 1, 0, 0, 1 },
        GREEN = { 0, 1, 0, 1 },
        BLUE = { 0, 0, 1, 1 },
        GREY = { 0.5, 0.5, 0.5, 1 },
        GOLD = { 1, 0.8, 0, 1 },
        ORANGE = { 1, 0.5, 0, 1 },
        BLACK = { 0, 0, 0, 1 },
        L_BLACK = { 0.2, 0.2, 0.2, 1 },
        UI = {
            TEXT_LIGHT = { 1, 1, 1, 1 },
            TEXT_INACTIVE = { 0.5, 0.5, 0.5, 1 }
        }
    }
}
namespace.entry_fee_warning = { balance = 7, fee = 83, enabled = false }
local fee_definition = LoadoutUI.create_entry_fee_definition(namespace)
H.assert_equal(fee_definition.no_back, true, "entry fee dialog has no back action")
H.assert_equal(fee_definition.contents[1].config.colour, _G.G.C.L_BLACK, "entry fee dialog uses modal outer panel")
H.assert_equal(fee_definition.contents[1].nodes[1].config.colour, _G.G.C.BLACK, "entry fee dialog uses modal inner panel")
H.assert_equal(fee_definition.contents[2].nodes[1].config.button, "grdl_entry_fee_reselect", "entry fee dialog has direct reselect button")
H.assert_equal(fee_definition.contents[2].nodes[3].config.button, "grdl_entry_fee_continue", "entry fee dialog has direct continue button")
H.assert_equal(fee_definition.contents[2].nodes[1].config.colour, _G.G.C.GREEN, "entry fee reselect button is green")
H.assert_equal(fee_definition.contents[2].nodes[3].config.colour, _G.G.C.RED, "entry fee continue button is red")
local fee_ui = namespace.entry_fee_warning_ui
H.assert_equal(#fee_definition.contents[1].nodes[1].nodes, 4, "insufficient entry fee keeps disabled notice row")
H.assert_equal(fee_ui.lines[1].text, "grdl_k_entry_fee_insufficient_title", "insufficient entry fee title")
H.assert_equal(fee_ui.lines[2].text, "grdl_k_entry_fee_balance", "entry fee balance uses its own line")
H.assert_equal(fee_ui.lines[3].text, "grdl_k_entry_fee_required", "entry fee threshold uses its own line")
H.assert_equal(fee_ui.lines[4].text, "grdl_k_entry_fee_blocked", "insufficient entry fee shows disabled feature notice")
H.assert_equal(fee_definition.contents[1].nodes[1].nodes[1].nodes[1].config.ref_table, fee_ui.lines[1], "entry fee title line is live-bound")
H.assert_equal(fee_definition.contents[1].nodes[1].nodes[2].nodes[1].config.ref_table, fee_ui.lines[2], "entry fee body line is live-bound")
H.assert_equal(fee_definition.contents[1].nodes[1].nodes[3].nodes[1].config.ref_table, fee_ui.lines[3], "entry fee footer line is live-bound")
H.assert_equal(fee_definition.contents[1].nodes[1].nodes[4].nodes[1].config.ref_table, fee_ui.lines[4], "entry fee disabled line is live-bound")
H.assert_equal(fee_definition.contents[2].nodes[1].config.func, "grdl_entry_fee_button_tick", "reselect button can grey out during animation")
H.assert_equal(fee_definition.contents[2].nodes[3].config.func, "grdl_entry_fee_button_tick", "continue button can grey out during animation")
H.assert_equal(LoadoutUI.begin_entry_fee_continue(namespace, { TIMERS = { REAL = 10 }, FUNCS = { exit_overlay_menu = function() fee_ui.closed = true end } }), true, "insufficient continue exits immediately")
H.assert_equal(namespace.entry_fee_warning, nil, "insufficient continue clears warning immediately")
H.assert_equal(namespace.entry_fee_warning_ui, nil, "insufficient continue does not keep animation state")
H.assert_equal(fee_ui.closed, true, "insufficient continue closes overlay immediately")

namespace.entry_fee_warning = { balance = 100, fee = 30, enabled = true, paid = true, charged = true }
local paid_definition = LoadoutUI.create_entry_fee_definition(namespace)
local paid_ui = namespace.entry_fee_warning_ui
H.assert_equal(#paid_definition.contents[1].nodes[1].nodes, 3, "paid entry fee has no empty disabled notice row")
H.assert_equal(paid_ui.lines[1].text, "grdl_k_entry_fee_title", "paid entry fee title")
H.assert_equal(paid_ui.lines[2].text, "grdl_k_entry_fee_balance", "paid entry fee balance line")
H.assert_equal(paid_ui.lines[3].text, "grdl_k_entry_fee_required", "paid entry fee threshold line")
H.assert_equal(paid_ui.lines[4].text, " ", "paid entry fee omits disabled feature notice")
H.assert_equal(paid_definition.contents[1].nodes[1].nodes[2].config.minw, 5.65, "paid amount row spans the inner panel")
H.assert_equal(#paid_definition.contents[1].nodes[1].nodes[2].nodes, 1, "paid amount row has one centered object node")
local paid_amount_node = paid_definition.contents[1].nodes[1].nodes[2].nodes[1]
H.assert_equal(paid_amount_node.n, _G.G.UIT.O, "paid amount row uses an embedded text object")
H.assert_equal(paid_amount_node.config.ref_table, paid_ui.lines[2], "paid amount object is live-bound")
H.assert_equal(paid_amount_node.config.object.args.float, nil, "paid amount object does not float before GLHF")
H.assert_equal(paid_amount_node.config.object.args.string[1].ref_table, paid_ui.lines[2], "paid amount object reads live text")
H.assert_equal(paid_amount_node.config.object.args.string[1].ref_value, "text", "paid amount object reads the line text key")
H.assert_equal(LoadoutUI.entry_fee_final_balance(namespace.entry_fee_warning), 70, "paid entry visual deducts fee from starting balance")
H.assert_equal(LoadoutUI.entry_fee_balance_text(7), "Ⓖ 7", "entry fee balance text")
H.assert_equal(LoadoutUI.begin_entry_fee_continue(namespace, { TIMERS = { REAL = 10 } }), true, "continue starts entry fee visual")
H.assert_equal(paid_ui.buttons_disabled, true, "continue visual disables buttons")
H.assert_equal(paid_ui.roll_duration, 1.5, "continue visual roll duration is fixed")
H.assert_equal(paid_ui.final_hold, 0.875, "continue visual final balance hold is extended")
H.assert_equal(paid_ui.greeting_hold, 1.625, "continue visual greeting hold is extended")
H.assert_equal(paid_ui.lines[1].text, " ", "continue visual clears top warning line")
H.assert_equal(paid_ui.lines[2].text, "Ⓖ 100", "continue visual starts at current balance")
H.assert_equal(paid_ui.lines[2].scale, 0.74, "continue visual amount text is larger")
H.assert_equal(paid_ui.lines[3].text, " ", "continue visual clears threshold line")
H.assert_equal(paid_ui.lines[4].text, " ", "continue visual clears disabled line")
local amount_element = { config = paid_amount_node.config, T = { x = 1, y = 2, w = 3, h = 4 } }
runtime.TIMERS = { REAL = 10 }
runtime.FUNCS.grdl_entry_fee_text_tick(amount_element)
runtime.TIMERS = nil
local amount_object = paid_amount_node.config.object
H.assert_equal(amount_object.args.scale, 0.74, "paid amount object scale follows the running amount view")
H.assert_equal(amount_object.args.colours[1], _G.G.C.GOLD, "paid amount object uses gold")
H.assert_equal(amount_object.args.float, nil, "paid amount object still does not float while rolling")
LoadoutUI.update_entry_fee_continue(namespace, { TIMERS = { REAL = 10.75 } })
H.assert_true(paid_ui.lines[2].text ~= "Ⓖ 100", "continue visual rolls balance before completion")
LoadoutUI.update_entry_fee_continue(namespace, { TIMERS = { REAL = 11.5 } })
H.assert_equal(paid_ui.lines[2].text, "Ⓖ 70", "continue visual reaches final balance")
LoadoutUI.update_entry_fee_continue(namespace, { TIMERS = { REAL = 12.4 } })
H.assert_equal(paid_ui.lines[2].text, "grdl_k_entry_fee_glhf", "continue visual switches to GLHF text")
H.assert_equal(paid_ui.lines[2].scale, 0.58, "continue visual greeting text is larger")
H.assert_equal(paid_ui.lines[2].colour, _G.G.C.ORANGE, "continue visual greeting is orange")
runtime.TIMERS = { REAL = 12.4 }
runtime.FUNCS.grdl_entry_fee_text_tick(amount_element)
runtime.TIMERS = nil
local glhf_object = paid_amount_node.config.object
H.assert_true(glhf_object ~= amount_object, "GLHF replaces the embedded object to start pop-in")
H.assert_equal(glhf_object.args.float, true, "GLHF object uses vanilla float effect")
H.assert_equal(glhf_object.args.pop_in, 0, "GLHF object uses vanilla pop-in entry")
H.assert_equal(glhf_object.args.colours[1], _G.G.C.ORANGE, "GLHF embedded object is orange")
H.assert_equal(glhf_object.args.string[1].ref_table, paid_ui.lines[2], "GLHF object stays bound to the dialog line")
H.assert_equal(#attention_calls, 0, "GLHF does not use a detached attention text overlay")
LoadoutUI.update_entry_fee_continue(namespace, { TIMERS = { REAL = 14.1 }, FUNCS = { exit_overlay_menu = function() paid_ui.closed = true end } })
H.assert_equal(namespace.entry_fee_warning, nil, "continue visual clears warning only after exit timing")
H.assert_equal(paid_ui.closed, true, "continue visual exits overlay after GLHF hold")
namespace.entry_fee_warning = nil
namespace.entry_fee_warning_ui = nil
_G.G = previous_fee_g
_G.create_UIBox_generic_options = previous_fee_options
_G.attention_text = previous_attention_text
_G.DynaText = previous_fee_dynatext

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
local notify_reselect_calls = 0
local setup_reselect_calls = 0
local reselect_order = {}
funcs.notify_then_setup_run = function(event)
    notify_reselect_calls = notify_reselect_calls + 1
    if not (_G.G and _G.G.OVERLAY_MENU) then error("notify requires overlay") end
end
funcs.setup_run = function(event)
    reselect_order[#reselect_order + 1] = "setup"
    setup_reselect_calls = setup_reselect_calls + 1
    return "setup"
end
local game_class = {}
function game_class.start_run(self, args)
    local game = rawget(_G, "G")
    local base_queue = game and game.E_MANAGER and game.E_MANAGER.queues and game.E_MANAGER.queues.base
    if type(base_queue) == "table" then
        table.insert(base_queue, { kind = "inner_start_run_popup", func = function()
            reselect_order[#reselect_order + 1] = "inner"
            return true
        end })
    end
    return "started"
end
local env = { funcs = funcs, game_class = game_class }
H.assert_equal(LoadoutUI.install(run_ns, env), true, "run hooks installed")
H.assert_equal(LoadoutUI.install(run_ns, env), true, "second install is a no-op")
H.assert_equal(LoadoutUI.install_runtime(run_ns, { FUNCS = funcs }), true, "run fee callbacks installed")

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

local queued_entry_events = {}
local overlay_calls = {}
local reselect_events = {}
local base_events = { { kind = "preexisting_start_run_event" } }
local previous_run_event = rawget(_G, "Event")
local previous_run_options = rawget(_G, "create_UIBox_generic_options")
_G.Event = function(args) return args end
_G.create_UIBox_generic_options = function(args) return args end
funcs.overlay_menu = function(args) overlay_calls[#overlay_calls + 1] = args end
local function set_entry_fee_runtime(seed, started_at, existing_entry)
    _G.G = {
        GAME = {
            stake = 8,
            pseudorandom = { seed = seed },
            grdl_run_started_at = started_at,
            grdl_entry = existing_entry,
            round_resets = { ante = 2, blind_states = { Boss = "Defeated" } }
        },
        P_STAKES = { stake_gold = { stake_level = 8 } },
        FUNCS = funcs,
        SETTINGS = {},
        E_MANAGER = {
            queues = { base = base_events },
            add_event = function(self, event)
                if event and event.grdl_reselect then
                    reselect_events[#reselect_events + 1] = event
                else
                    queued_entry_events[#queued_entry_events + 1] = event
                end
            end
        },
        UIT = { R = "R", C = "C", T = "T" },
        C = {
            WHITE = { 1, 1, 1, 1 },
            RED = { 1, 0, 0, 1 },
            GREEN = { 0, 1, 0, 1 },
            BLUE = { 0, 0, 1, 1 },
            BLACK = { 0, 0, 0, 1 },
            L_BLACK = { 0.2, 0.2, 0.2, 1 },
            UI = {
                TEXT_LIGHT = { 1, 1, 1, 1 },
                TEXT_INACTIVE = { 0.5, 0.5, 0.5, 1 }
            }
        },
        jokers = { cards = {} },
        STATE = 1
    }
end

-- paid entry fee still shows the run-start entry fee dialog
run_ns.collection.currency_g = 200
run_ns.loadout_entry_window = nil
set_entry_fee_runtime("PAIDLOAD", 1767225500)
game_class.start_run({}, {})
H.assert_equal(_G.G.GAME.grdl_entry.enabled, true, "paid entry state keeps run enabled")
H.assert_true(_G.G.GAME.grdl_loadout ~= nil, "paid entry still seeds loadout")
H.assert_equal(run_ns.collection.currency_g, 117, "paid entry fee is charged")
H.assert_equal(base_events[2].grdl_entry_fee_warning, true, "paid entry warning is inserted before start-run post events")
H.assert_equal(base_events[3].kind, "inner_start_run_popup", "paid entry warning precedes later start-run events")
H.assert_equal(base_events[2].func(), false, "paid entry warning remains active until player continues")
H.assert_equal(#overlay_calls, 1, "scheduled paid entry warning opens overlay")
H.assert_equal(run_ns.entry_fee_warning_ui.lines[1].text, "grdl_k_entry_fee_title", "paid run-start warning uses entry fee title")

-- paid reselect refunds the already-charged entry fee before rerolling the run
queued_entry_events = {}
overlay_calls = {}
base_events = { { kind = "preexisting_start_run_event" } }
reselect_order = {}
setup_reselect_calls = 0
run_ns.collection.currency_g = 200
run_ns.entry_fee_warning = nil
run_ns.entry_fee_warning_ui = nil
set_entry_fee_runtime("REFUNDLOAD", 1767225525)
game_class.start_run({}, {})
local refund_run_key = _G.G.GAME.grdl_entry.run_key
H.assert_equal(run_ns.collection.currency_g, 117, "refund scenario starts charged")
H.assert_true(run_ns.collection.entry_fees[refund_run_key] ~= nil, "refund scenario records entry fee ledger")
H.assert_equal(base_events[2].func(), false, "refund warning opens before reselect")
funcs.grdl_entry_fee_reselect({ config = {} })
H.assert_equal(run_ns.collection.currency_g, 200, "paid entry reselect refunds the charged fee")
H.assert_equal(run_ns.collection.entry_fees[refund_run_key], nil, "paid entry reselect removes the fee ledger")
H.assert_equal(setup_reselect_calls, 0, "paid reselect still waits for the blocking warning event to release")
H.assert_equal(base_events[2].func(), true, "paid entry warning releases after reselect")
H.assert_equal(setup_reselect_calls, 1, "paid reselect reruns setup after refund")
base_events[3].func()
H.assert_equal(table.concat(reselect_order, ","), "setup,inner", "paid reselect setup precedes deferred start-run events")

-- restoring an already-paid run from vanilla savetext must not replay the entry fee dialog
queued_entry_events = {}
overlay_calls = {}
base_events = { { kind = "preexisting_start_run_event" } }
local restored_entry = {
    run_key = "RESTORELOAD:1767225515",
    run_id = "RESTORELOAD",
    run_started_at = 1767225515,
    stake_index = 8,
    stake_level = 8,
    fee = 83,
    balance = 200,
    paid = true,
    enabled = true,
    charged = true
}
run_ns.collection.currency_g = 117
run_ns.collection.entry_fees[restored_entry.run_key] = {
    run_key = restored_entry.run_key,
    fee = restored_entry.fee
}
run_ns.entry_fee_warning = nil
run_ns.entry_fee_warning_ui = nil
run_ns.entry_fee_warning_run_key = nil
set_entry_fee_runtime("RESTORELOAD", 1767225515, restored_entry)
game_class.start_run({}, { savetext = { GAME = {} } })
H.assert_equal(run_ns.collection.currency_g, 117, "restored paid entry is not charged again")
H.assert_equal(base_events[2].kind, "inner_start_run_popup", "restored paid entry skips entry fee warning")
H.assert_equal(#overlay_calls, 0, "restored paid entry does not open entry fee overlay")

-- legacy warned flags on the run state must not suppress a fresh dialog
queued_entry_events = {}
overlay_calls = {}
base_events = { { kind = "preexisting_start_run_event" } }
local legacy_warned_entry = {
    run_key = "LEGACYPAID:1767225550",
    run_id = "LEGACYPAID",
    run_started_at = 1767225550,
    stake_index = 8,
    stake_level = 8,
    fee = 83,
    balance = 200,
    paid = true,
    enabled = true,
    charged = true,
    warned = true
}
run_ns.collection.currency_g = 200
run_ns.entry_fee_warning = nil
run_ns.entry_fee_warning_ui = nil
set_entry_fee_runtime("LEGACYPAID", 1767225550, legacy_warned_entry)
game_class.start_run({}, {})
H.assert_equal(base_events[2].grdl_entry_fee_warning, true, "legacy warned flag does not block paid entry warning")

-- unpaid entry fee disables all loadout run features
queued_entry_events = {}
overlay_calls = {}
reselect_events = {}
reselect_order = {}
setup_reselect_calls = 0
base_events = { { kind = "preexisting_start_run_event" } }
set_entry_fee_runtime("POORLOAD", 1767225600)
run_ns.collection.currency_g = 0
run_ns.loadout_entry_window = nil
game_class.start_run({}, {})
H.assert_equal(_G.G.GAME.grdl_entry.enabled, false, "unpaid entry state disables run")
H.assert_equal(_G.G.GAME.grdl_loadout, nil, "unpaid entry does not seed loadout")
H.assert_equal(#overlay_calls, 0, "unpaid entry warning waits for scheduled overlay")
H.assert_equal(#queued_entry_events, 0, "unpaid entry warning uses base queue when available")
H.assert_equal(base_events[2].grdl_entry_fee_warning, true, "unpaid entry warning is inserted before start-run post events")
H.assert_equal(base_events[3].kind, "inner_start_run_popup", "existing start-run post events remain queued after warning")
H.assert_equal(base_events[2].delay, nil, "unpaid entry warning follows one-frame event with no fixed delay")
H.assert_equal(base_events[2].trigger, nil, "unpaid entry warning follows one-frame event")
H.assert_equal(base_events[2].blocking, true, "unpaid entry warning blocks later start-run events while open")
H.assert_equal(base_events[2].func(), false, "unpaid entry warning remains active until the player chooses")
H.assert_equal(#overlay_calls, 1, "scheduled unpaid entry warning opens overlay")
H.assert_equal(overlay_calls[1].config.no_esc, true, "unpaid entry overlay uses modal config")
_G.G.OVERLAY_MENU = nil
funcs.grdl_entry_fee_reselect({ config = {} })
H.assert_equal(notify_reselect_calls, 0, "reselect avoids notify callback without overlay")
H.assert_equal(setup_reselect_calls, 0, "reselect waits for the blocking warning event to release")
H.assert_equal(#reselect_events, 0, "reselect does not append setup behind deferred start-run events")
H.assert_equal(base_events[2].func(), true, "unpaid entry warning releases later events after player choice")
H.assert_equal(setup_reselect_calls, 1, "reselect runs setup before releasing deferred start-run events")
base_events[3].func()
H.assert_equal(table.concat(reselect_order, ","), "setup,inner", "reselect setup precedes deferred start-run events")
funcs.cash_out({ config = {} })
H.assert_equal(run_ns.loadout_entry_window, nil, "unpaid entry opens no loadout window")
local blocked_spawn = LoadoutUI.spawn_entries(run_ns, { graded_novice.id }, 9999)
H.assert_equal(blocked_spawn.ok, false, "unpaid entry blocks spawn")
H.assert_equal(blocked_spawn.reason, "entry_fee_unpaid", "spawn reports entry fee gate")
_G.create_UIBox_generic_options = previous_run_options
_G.Event = previous_run_event

_G.G = previous_run_g

_G.SMODS = previous_smods
rng.restore()
print("loadout ui tests ok")
