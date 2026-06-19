local H = dofile("tests/test_helper.lua")
local Config = dofile("src/core/config.lua")
local Storage = dofile("src/core/storage.lua")
local BuyoutUI = dofile("src/ui/buyout_ui.lua")
local rng = H.install_pseudorandom_stub()

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
H.assert_equal(state.page, 1, "state starts on page one")
H.assert_equal(state.blocked_page, 1, "state starts blocked list on page one")
H.assert_equal(#state.selected_ids, 0, "state starts empty")
BuyoutUI.set_page(state, 99)
H.assert_equal(state.page, 1, "page clamps within the eligible list")
BuyoutUI.set_blocked_page(state, 99)
H.assert_equal(state.blocked_page, 1, "blocked page clamps within the blocked list")
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

local previous_ui_g = rawget(_G, "G")
local previous_tabs = rawget(_G, "create_tabs")
local previous_cycle = rawget(_G, "create_option_cycle")
local previous_button = rawget(_G, "UIBox_button")
local previous_options = rawget(_G, "create_UIBox_generic_options")
local captured_tabs = nil
_G.G = {
    UIT = { R = "R", C = "C", T = "T", O = "O", ROOT = "ROOT" },
    C = {
        WHITE = "WHITE",
        BLUE = "BLUE",
        GREEN = "GREEN",
        ORANGE = "ORANGE",
        RED = "RED",
        CLEAR = "CLEAR",
        L_BLACK = "L_BLACK",
        UI = { TEXT_LIGHT = "TEXT_LIGHT", TEXT_INACTIVE = "TEXT_INACTIVE", TEXT_DARK = "TEXT_DARK" }
    }
}
_G.create_tabs = function(args)
    captured_tabs = args.tabs
    return { n = "tabs", config = args, nodes = {} }
end
_G.create_option_cycle = function(args)
    return { n = "cycle", config = args, nodes = {} }
end
_G.UIBox_button = function(args)
    return { n = "button", config = args, nodes = {} }
end
_G.create_UIBox_generic_options = function(args) return args end

local function collect_callbacks(node, out)
    if type(node) ~= "table" then return end
    if node.config and node.config.opt_callback then
        out[#out + 1] = node.config.opt_callback
    end
    for _, child in ipairs(node.nodes or {}) do collect_callbacks(child, out) end
    for _, child in ipairs(node.contents or {}) do collect_callbacks(child, out) end
end

local function collect_preview_refs(node, out)
    if type(node) ~= "table" then return end
    if node.config and node.config.func == "grdl_row_preview" then
        out[#out + 1] = node.config.ref_table
    end
    for _, child in ipairs(node.nodes or {}) do collect_preview_refs(child, out) end
    for _, child in ipairs(node.contents or {}) do collect_preview_refs(child, out) end
end

local function collect_buttons(node, out)
    if type(node) ~= "table" then return end
    if node.config and node.config.button then
        out[#out + 1] = node.config
    end
    for _, child in ipairs(node.nodes or {}) do collect_buttons(child, out) end
    for _, child in ipairs(node.contents or {}) do collect_buttons(child, out) end
end

local paged_offer = { eligible = {}, blocked = {}, max_selection = 2 }
for index = 1, 7 do
    paged_offer.eligible[#paged_offer.eligible + 1] = candidate("eligible_" .. tostring(index), 10 + index)
    paged_offer.blocked[#paged_offer.blocked + 1] = candidate("blocked_" .. tostring(index), 0)
    paged_offer.blocked[index].reason = "rarity_locked"
end
local ui_namespace = {
    config = config,
    collection = Storage.normalize({ currency_g = 100 }),
    pending_buyout_offer = paged_offer
}
ui_namespace.buyout_ui_state = BuyoutUI.default_state(paged_offer)
BuyoutUI.create_overlay_definition(ui_namespace)
H.assert_equal(#captured_tabs, 2, "buyout overlay renders eligible and blocked tabs")
H.assert_equal(captured_tabs[1].chosen, true, "eligible tab chosen by default")
H.assert_equal(captured_tabs[2].label, "grdl_k_buyout_blocked", "blocked tab reuses unavailable label")
local blocked_definition = captured_tabs[2].tab_definition_function()
local callbacks = {}
collect_callbacks(blocked_definition, callbacks)
H.assert_equal(callbacks[1], "grdl_buyout_blocked_page", "blocked tab has its own page callback")
local eligible_definition = captured_tabs[1].tab_definition_function()
H.assert_equal(eligible_definition.config.minh, nil, "buyout tab height follows content instead of reserving empty space")
local eligible_previews = {}
collect_preview_refs(eligible_definition, eligible_previews)
H.assert_equal(eligible_previews[1].tooltip, true, "eligible buyout row requests tooltip preview")
local action_row = eligible_definition.nodes[#eligible_definition.nodes]
H.assert_equal(#action_row.nodes, 3, "buyout footer renders three direct columns")
H.assert_equal(action_row.nodes[1].n, "C", "binder footer button is in a horizontal column")
H.assert_equal(action_row.nodes[2].n, "C", "confirm footer button is in a horizontal column")
H.assert_equal(action_row.nodes[3].n, "C", "skip footer button is in a horizontal column")
local eligible_buttons = {}
collect_buttons(eligible_definition, eligible_buttons)
local binder_button = eligible_buttons[#eligible_buttons - 2]
local confirm_button = eligible_buttons[#eligible_buttons - 1]
local skip_button = eligible_buttons[#eligible_buttons]
H.assert_equal(binder_button.button, "grdl_open_buyout_binder", "buyout footer starts with binder button")
H.assert_equal(confirm_button.button, "grdl_confirm_buyout", "buyout footer keeps confirm in the middle")
H.assert_equal(skip_button.button, "grdl_skip_buyout", "buyout footer ends with skip")
H.assert_equal(binder_button.colour, "ORANGE", "buyout binder button is orange")
H.assert_equal(confirm_button.colour, "GREEN", "buyout confirm button stays green")
H.assert_equal(skip_button.colour, "RED", "buyout skip button stays red")
H.assert_equal(#confirm_button.label, 1, "buyout confirm button omits duplicate total line")
H.assert_true((confirm_button.scale or 0) > 0.36, "buyout confirm text scale increased")
H.assert_true((skip_button.scale or 0) > 0.36, "buyout skip text scale increased")
local blocked_previews = {}
collect_preview_refs(blocked_definition, blocked_previews)
H.assert_equal(blocked_previews[1].tooltip, true, "blocked buyout row requests tooltip preview")

local tab_runtime = { FUNCS = {} }
local tab_adapter = { refreshed = 0 }
function tab_adapter.refresh_overlay()
    tab_adapter.refreshed = tab_adapter.refreshed + 1
end
BuyoutUI.install_runtime(ui_namespace, tab_runtime, tab_adapter)
H.assert_true(type(tab_runtime.FUNCS.grdl_buyout_blocked_page) == "function", "blocked page callback registered")
tab_runtime.FUNCS.grdl_buyout_blocked_page({ cycle_config = { current_option = 2 } })
H.assert_equal(ui_namespace.buyout_ui_state.blocked_page, 2, "blocked page callback applies cycle option")
H.assert_equal(tab_adapter.refreshed, 1, "blocked page callback refreshes overlay headless")

local previous_card = rawget(_G, "Card")
local previous_area = rawget(_G, "CardArea")
local previous_uibox = rawget(_G, "UIBox")
local tooltip_info_count = nil
local uibox_calls = {}
_G.G.P_CENTERS = { j_eligible_1 = { key = "j_eligible_1", set = "Joker" } }
_G.G.P_CARDS = { empty = {} }
_G.G.CARD_W = 1.44
_G.G.CARD_H = 1.9
_G.G.UIDEF = {
    card_h_popup = function(card)
        tooltip_info_count = #(card.ability_UIBox_table and card.ability_UIBox_table.info or {})
        return { n = G.UIT.ROOT, config = { id = "main_tooltip" }, nodes = {} }
    end
}
_G.CardArea = function(x, y, w, h)
    return {
        T = { x = x, y = y, w = w, h = h },
        cards = {},
        emplace = function(self, card) self.cards[#self.cards + 1] = card end
    }
end
_G.Card = function(x, y, w, h, front, center)
    return {
        T = { x = x, y = y, w = w, h = h },
        children = {},
        center = center,
        ability_UIBox_table = { info = { "extra_info_queue" } },
        states = { collide = { can = true }, hover = { can = true }, click = { can = true } },
        set_edition = function(self, flags) self.edition_flags = flags end
    }
end
_G.UIBox = function(args)
    uibox_calls[#uibox_calls + 1] = args
    return {
        children = {},
        states = { collide = { can = true } },
        remove = function() end
    }
end
local tooltip_element = {
    config = { ref_table = { center_key = "j_eligible_1", edition = "negative", tooltip = true } },
    states = { hover = { is = true } },
    children = {}
}
tab_runtime.FUNCS.grdl_row_preview(tooltip_element)
H.assert_true(tooltip_element.children.grdl_preview ~= nil, "tooltip row hover still attaches card preview")
H.assert_equal(#uibox_calls, 2, "tooltip preview creates card preview and one tooltip box")
H.assert_equal(uibox_calls[2].config.align, "cl", "main tooltip is forced to the left of the preview card")
H.assert_equal(uibox_calls[2].definition.config.id, "main_tooltip", "tooltip preview uses vanilla card_h_popup definition")
H.assert_equal(tooltip_info_count, 0, "tooltip preview strips info queue extras")
_G.UIBox = previous_uibox
_G.CardArea = previous_area
_G.Card = previous_card

local eligible_only_offer = { eligible = { candidate("solo", 25) }, blocked = {}, max_selection = 1 }
local eligible_only_namespace = {
    config = config,
    collection = Storage.normalize({ currency_g = 100 }),
    pending_buyout_offer = eligible_only_offer
}
captured_tabs = nil
eligible_only_namespace.buyout_ui_state = BuyoutUI.default_state(eligible_only_offer)
BuyoutUI.create_overlay_definition(eligible_only_namespace)
H.assert_equal(#captured_tabs, 1, "buyout overlay hides blocked tab when there are no blocked cards")

_G.create_UIBox_generic_options = previous_options
_G.UIBox_button = previous_button
_G.create_option_cycle = previous_cycle
_G.create_tabs = previous_tabs
_G.G = previous_ui_g

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
    collection = Storage.normalize({ currency_g = 100, pending_buyout_offer = offer }),
    pending_buyout_offer = offer,
    mod = { id = "Gradelatro", config = {} }
}
local previous_smods_global = rawget(_G, "SMODS")
local save_count = 0
_G.SMODS = {
    load_file = previous_smods_global.load_file,
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
H.assert_equal(success_namespace.collection.pending_buyout_offer, nil, "success clears persisted pending offer")
H.assert_equal(success_namespace.last_buyout_result, success_result, "success stores last result")
H.assert_equal(save_count, 1, "success saves collection")
H.assert_true(rng.has_call("pseudorandom", "grdl_condition_"), "buyout ui condition uses native pseudorandom")
_G.SMODS = previous_smods_global

success_namespace.pending_buyout_offer = offer
success_namespace.collection.pending_buyout_offer = offer
success_namespace.buyout_ui_state = success_state
_G.SMODS = {
    load_file = previous_smods_global.load_file,
    save_mod_config = function()
        save_count = save_count + 1
        return true
    end
}
local skip_result = BuyoutUI.skip(success_namespace)
H.assert_equal(skip_result.ok, true, "skip succeeds")
H.assert_equal(success_namespace.pending_buyout_offer, nil, "skip clears pending offer")
H.assert_equal(success_namespace.collection.pending_buyout_offer, nil, "skip clears persisted pending offer")
H.assert_equal(success_namespace.buyout_ui_state, nil, "skip clears ui state")
H.assert_equal(save_count, 2, "skip saves cleared offer")
_G.SMODS = previous_smods_global

local failing_namespace = {
    config = config,
    collection = Storage.normalize({ currency_g = 100, pending_buyout_offer = offer }),
    pending_buyout_offer = offer,
    mod = { id = "Gradelatro", config = {} }
}
local failing_state = BuyoutUI.default_state(offer)
BuyoutUI.toggle_selection(failing_state, "one")
_G.SMODS = {
    load_file = previous_smods_global.load_file,
    save_mod_config = function() return false end
}
local failing_result = BuyoutUI.confirm(failing_namespace, failing_state, 1800000000)
H.assert_equal(failing_result.ok, false, "save failure rejects buyout confirmation")
H.assert_equal(failing_result.reason, "save_failed", "save failure reason returned")
H.assert_equal(failing_namespace.collection.currency_g, 100, "save failure rolls back currency")
H.assert_equal(#failing_namespace.collection.cards, 0, "save failure rolls back cards")
H.assert_equal(failing_namespace.pending_buyout_offer.run_id, offer.run_id, "save failure restores pending offer")
_G.SMODS = previous_smods_global

local runtime_namespace = {
    config = config,
    collection = Storage.normalize({ currency_g = 100, pending_buyout_offer = offer }),
    pending_buyout_offer = offer,
    mod = { id = "Gradelatro", config = {} }
}
_G.SMODS = {
    load_file = previous_smods_global.load_file,
    save_mod_config = function(mod)
        H.assert_equal(mod, runtime_namespace.mod, "runtime buyout saves namespace mod")
        return true
    end
}
local runtime = { FUNCS = {} }
local adapter = {
    opened = 0,
    refreshed = 0,
    closed = 0,
    binder_opened = 0
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
function adapter.open_binder(_, state)
    adapter.binder_opened = adapter.binder_opened + 1
    H.assert_true(state ~= nil, "buyout binder callback receives current buyout state")
end

H.assert_true(BuyoutUI.install_runtime(runtime_namespace, runtime, adapter), "runtime callbacks installed")
runtime.FUNCS.grdl_open_buyout()
H.assert_true(runtime_namespace.buyout_ui_state ~= nil, "open creates ui state")
H.assert_equal(adapter.opened, 1, "open adapter called")

runtime.FUNCS.grdl_toggle_buyout_card({ config = { ref_table = { id = "one" } } })
H.assert_true(BuyoutUI.is_selected(runtime_namespace.buyout_ui_state, "one"), "callback toggles selection")
H.assert_equal(adapter.refreshed, 1, "toggle falls back to overlay refresh headless")

H.assert_true(type(runtime.FUNCS.grdl_open_buyout_binder) == "function", "buyout binder callback registered")
runtime.FUNCS.grdl_open_buyout_binder()
H.assert_equal(adapter.binder_opened, 1, "buyout binder callback opens binder")
H.assert_true(BuyoutUI.is_selected(runtime_namespace.buyout_ui_state, "one"), "buyout binder callback preserves selection state")
runtime.FUNCS.grdl_open_buyout()
H.assert_true(BuyoutUI.is_selected(runtime_namespace.buyout_ui_state, "one"), "returning from binder keeps the existing buyout state")
H.assert_equal(adapter.opened, 2, "returning from binder reopens buyout overlay")

H.assert_true(type(runtime.FUNCS.grdl_buyout_page) == "function", "page callback registered")
runtime.FUNCS.grdl_buyout_page({ cycle_config = { current_option = 1 } })
H.assert_equal(runtime_namespace.buyout_ui_state.page, 1, "page callback applies cycle option")
H.assert_equal(adapter.refreshed, 2, "page callback falls back to overlay refresh")

runtime.FUNCS.grdl_confirm_buyout()
H.assert_equal(#runtime_namespace.collection.cards, 1, "callback confirms selection")
H.assert_equal(runtime_namespace.pending_buyout_offer, nil, "callback success clears offer")
H.assert_equal(adapter.closed, 1, "callback success closes overlay")

runtime_namespace.pending_buyout_offer = offer
runtime_namespace.collection.pending_buyout_offer = offer
runtime_namespace.buyout_ui_state = BuyoutUI.default_state(offer)
runtime.FUNCS.grdl_skip_buyout()
H.assert_equal(runtime_namespace.pending_buyout_offer, nil, "runtime skip clears offer")
H.assert_equal(adapter.closed, 2, "runtime skip closes overlay")
_G.SMODS = previous_smods_global

rng.restore()
print("buyout ui tests ok")
