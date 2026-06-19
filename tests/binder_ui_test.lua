local H = dofile("tests/test_helper.lua")
local Config = dofile("src/core/config.lua")
local Storage = dofile("src/core/storage.lua")
local BinderUI = dofile("src/ui/binder_ui.lua")

local config = Config.normalize({})

local mint_condition = {
    centering = 9.8,
    print_quality = 9.8,
    corners = 9.8,
    edges = 9.7,
    surface = 9.9
}

local namespace = {
    config = config,
    mod = { id = "Gradelatro", config = {} },
    collection = Storage.normalize({ currency_g = 25 })
}
local raw_card = Storage.add_raw_card(namespace.collection, {
    center_key = "j_joker",
    local_key = "joker",
    rarity = "common",
    edition = "base",
    condition = mint_condition,
    acquired_at = 1000
})

local previous_smods_global = rawget(_G, "SMODS")
local save_count = 0
_G.SMODS = {
    load_file = previous_smods_global.load_file,
    save_mod_config = function(mod)
        H.assert_equal(mod, namespace.mod, "binder saves namespace mod")
        save_count = save_count + 1
        return true
    end
}

local runtime = { FUNCS = {} }
local adapter = { binder_opened = 0, desk_opened = 0, desk_refreshed = 0 }
function adapter.open_binder()
    adapter.binder_opened = adapter.binder_opened + 1
end
function adapter.open_desk()
    adapter.desk_opened = adapter.desk_opened + 1
end
function adapter.refresh_desk()
    adapter.desk_refreshed = adapter.desk_refreshed + 1
end

H.assert_true(BinderUI.install_runtime(namespace, runtime, adapter), "runtime callbacks installed")

runtime.FUNCS.grdl_open_binder()
local binder_state = namespace.binder_ui_state
H.assert_true(binder_state ~= nil, "binder state stored")
H.assert_equal(adapter.binder_opened, 1, "binder overlay opened")
H.assert_equal(binder_state.text_keys.title, "grdl_k_binder_title", "binder title key")
H.assert_equal(binder_state.summary.currency_g, 25, "binder summary currency")
H.assert_equal(binder_state.page, 1, "binder starts at page one")
H.assert_equal(binder_state.page_view.total, 1, "binder page total")
H.assert_equal(binder_state.page_view.items[1].id, raw_card.id, "binder page item")
H.assert_equal(binder_state.hidden, 0, "no hidden cards without centers")
H.assert_equal(binder_state.revealed_count, 0, "no reveals yet")

for i = 1, 12 do
    Storage.add_raw_card(namespace.collection, {
        center_key = "j_extra_" .. tostring(i),
        local_key = "extra_" .. tostring(i),
        rarity = "common",
        edition = "base",
        condition = mint_condition,
        acquired_at = 1000 + i
    })
end
BinderUI.open(namespace, 2000)
binder_state = namespace.binder_ui_state
H.assert_equal(binder_state.page_view.total, 13, "all cards counted")
H.assert_equal(binder_state.page_view.pages, 2, "two pages at ten per page")
H.assert_equal(#binder_state.page_view.items, 10, "first page full")

BinderUI.set_page(namespace, 2)
H.assert_equal(namespace.binder_ui_state.page, 2, "page switched")
H.assert_equal(#namespace.binder_ui_state.page_view.items, 3, "second page remainder")
BinderUI.set_page(namespace, 99)
H.assert_equal(namespace.binder_ui_state.page, 2, "page clamps to max")
local binder_opened_before_page = adapter.binder_opened
runtime.FUNCS.grdl_binder_page({ cycle_config = { current_option = 1 } })
H.assert_equal(namespace.binder_ui_state.page, 1, "binder page callback switches page")
H.assert_equal(adapter.binder_opened, binder_opened_before_page, "binder page callback keeps the overlay open")
BinderUI.open(namespace, { close_func = "grdl_open_buyout" })
runtime.FUNCS.grdl_open_binder()
H.assert_equal(namespace.binder_ui_state.close_func, "grdl_open_buyout", "reopening binder from inspect keeps buyout return context")

local previous_grid_g = rawget(_G, "G")
local previous_grid_card = rawget(_G, "Card")
local previous_grid_area = rawget(_G, "CardArea")
local previous_grid_button = rawget(_G, "UIBox_button")
local previous_grid_cycle = rawget(_G, "create_option_cycle")
local previous_grid_options = rawget(_G, "create_UIBox_generic_options")
local previous_grid_dynatext = rawget(_G, "DynaText")
local grid_areas = {}
_G.G = {
    ROOM = { T = { x = 0, y = 0, w = 10, h = 10 } },
    P_CENTERS = {
        j_short_name = { key = "j_short_name", set = "Joker" },
        j_very_long_name = { key = "j_very_long_name", set = "Joker" }
    },
    P_CARDS = { empty = {} },
    CARD_W = 1.44,
    CARD_H = 1.9,
    UIT = { R = "R", C = "C", T = "T", O = "O", ROOT = "ROOT" },
    C = {
        WHITE = "WHITE",
        BLACK = "BLACK",
        CLEAR = "CLEAR",
        L_BLACK = "L_BLACK",
        RED = "RED",
        BLUE = "BLUE",
        GREEN = "GREEN",
        PURPLE = "PURPLE",
        UI = { TEXT_LIGHT = "TEXT_LIGHT", TEXT_INACTIVE = "TEXT_INACTIVE", TEXT_DARK = "TEXT_DARK" }
    }
}
_G.CardArea = function(x, y, w, h, args)
    local area = {
        T = { x = x, y = y, w = w, h = h },
        cards = {},
        config = args,
        remove_card = function(self, card)
            for index, value in ipairs(self.cards) do
                if value == card then
                    table.remove(self.cards, index)
                    return card
                end
            end
        end,
        emplace = function(self, card) self.cards[#self.cards + 1] = card end
    }
    grid_areas[#grid_areas + 1] = area
    return area
end
_G.Card = function(x, y, w, h, front, center)
    return {
        center = center,
        children = {},
        states = {},
        set_edition = function() end,
        remove = function() end
    }
end
_G.UIBox_button = function(args) return { n = "button", config = args, nodes = {} } end
_G.create_option_cycle = function(args) return { n = "cycle", config = args, nodes = {} } end
_G.create_UIBox_generic_options = function(args) return args end
local previous_grid_localize = rawget(_G, "localize")
_G.localize = function(arg)
    if type(arg) == "table" and arg.type == "name_text" and arg.key == "j_short_name" then return "Short" end
    if type(arg) == "table" and arg.type == "name_text" and arg.key == "j_very_long_name" then return "ExtremelyLongLocalizedJokerName" end
    if type(arg) == "table" then return "ERROR" end
    return arg
end

local grid_namespace = {
    config = config,
    collection = Storage.normalize({ currency_g = 0 })
}
Storage.add_raw_card(grid_namespace.collection, {
    center_key = "j_short_name", local_key = "short", rarity = "common",
    edition = "base", condition = mint_condition, acquired_at = 3001
})
Storage.add_raw_card(grid_namespace.collection, {
    center_key = "j_very_long_name", local_key = "long", rarity = "common",
    edition = "base", condition = mint_condition, acquired_at = 3002
})
BinderUI.open(grid_namespace, 3003, { close_func = "grdl_open_buyout" })
local buyout_back_definition = BinderUI.create_overlay_definition(grid_namespace)
H.assert_equal(buyout_back_definition.back_func, "grdl_open_buyout", "binder overlay can return to buyout context")
BinderUI.open(grid_namespace, 3003)
local grid_definition = BinderUI.create_overlay_definition(grid_namespace)
H.assert_equal(grid_definition.back_func, "options", "regular binder overlay returns to options")
local function collect_text_nodes(node, out)
    if type(node) ~= "table" then return end
    if node.n == _G.G.UIT.T and node.config and type(node.config.text) == "string" then
        out[#out + 1] = node.config
    end
    for _, child in ipairs(node.nodes or {}) do collect_text_nodes(child, out) end
    for _, child in ipairs(node.contents or {}) do collect_text_nodes(child, out) end
end
local grid_texts = {}
collect_text_nodes(grid_definition, grid_texts)
local function collect_button_configs(node, out)
    if type(node) ~= "table" then return end
    if node.config and node.config.button then out[#out + 1] = node.config end
    for _, child in ipairs(node.nodes or {}) do collect_button_configs(child, out) end
    for _, child in ipairs(node.contents or {}) do collect_button_configs(child, out) end
end
local buyout_back_buttons = {}
collect_button_configs(buyout_back_definition, buyout_back_buttons)
for _, button in ipairs(buyout_back_buttons) do
    H.assert_true(button.button ~= "grdl_open_desk", "buyout binder hides grading desk button")
    H.assert_true(button.button ~= "grdl_open_market", "buyout binder hides market button")
    H.assert_true(button.button ~= "grdl_open_loadout", "buyout binder hides loadout button")
end
local short_text, long_text = nil, nil
local empty_texts = 0
for _, text in ipairs(grid_texts) do
    if text.text == "Short" then short_text = text end
    if text.text == "ExtremelyLongLocalizedJokerName" then long_text = text end
    if text.text == "空" then
        empty_texts = empty_texts + 1
        H.assert_equal(text.colour, _G.G.C.UI.TEXT_INACTIVE, "empty binder slot label is inactive")
    end
end
H.assert_true(short_text ~= nil, "binder card tile shows localized card name")
H.assert_true(long_text ~= nil, "binder card tile shows long localized card name")
H.assert_true(long_text.scale < short_text.scale, "long binder card names shrink instead of widening the tile")
H.assert_equal(empty_texts, 8, "binder grid keeps empty slots with placeholder titles")
H.assert_equal(#grid_namespace.binder_areas, 10, "binder grid creates one fixed slot area per page slot")
H.assert_equal(grid_namespace.binder_areas[1].config.card_limit, 1, "each binder tile card area holds one card")
H.assert_equal(#grid_namespace.binder_areas[1].cards, 1, "first binder tile receives a card")
H.assert_equal(#grid_namespace.binder_areas[2].cards, 1, "second binder tile receives a card")
H.assert_equal(#grid_namespace.binder_areas[3].cards, 0, "empty binder tile receives no card")
H.assert_equal(grid_namespace.binder_areas[1].T.w, grid_namespace.binder_areas[2].T.w, "binder tile card areas keep fixed width")
H.assert_equal(#grid_namespace.binder_title_slots, 10, "binder grid tracks one live title per page slot")
H.assert_equal(grid_namespace.binder_title_slots[1].name, "ExtremelyLongLocalizedJokerName", "first live title follows sorted first card")
grid_namespace.binder_ui_state.entries = {
    {
        id = "later",
        center_key = "j_short_name",
        local_key = "short",
        rarity = "common",
        edition = "base",
        condition = mint_condition,
        acquired_at = 4000
    }
}
BinderUI.set_page(grid_namespace, 1)
BinderUI.refresh_card_grid(grid_namespace)
H.assert_equal(grid_namespace.binder_title_slots[1].name, "Short", "binder page refresh updates live slot title text")
H.assert_equal(grid_namespace.binder_title_slots[2].name, "空", "binder page refresh updates empty slot title text")
H.assert_equal(grid_namespace.binder_title_slots[2].colour, _G.G.C.UI.TEXT_INACTIVE, "binder page refresh marks empty slot inactive")
H.assert_equal(#grid_namespace.binder_areas[1].cards, 1, "binder page refresh refills first slot")
H.assert_equal(#grid_namespace.binder_areas[2].cards, 0, "binder page refresh clears stale second slot")

local dyna_objects = {}
_G.DynaText = function(args)
    local object = {
        args = args,
        T = {},
        VT = {},
        removed = false,
        remove = function(self) self.removed = true end,
        hard_set_T = function(self, x, y, w, h)
            self.synced_to = { x = x, y = y, w = w, h = h }
            self.T.x, self.T.y, self.T.w, self.T.h = x, y, w, h
            self.VT.x, self.VT.y, self.VT.w, self.VT.h = x, y, w, h
        end,
        move_with_major = function(self) self.moved_with_major = true end,
        align_to_major = function(self) self.aligned_to_major = true end
    }
    dyna_objects[#dyna_objects + 1] = object
    return object
end
local dyna_namespace = {
    config = config,
    collection = Storage.normalize({ currency_g = 0 })
}
Storage.add_raw_card(dyna_namespace.collection, {
    center_key = "j_short_name", local_key = "short", rarity = "common",
    edition = "base", condition = mint_condition, acquired_at = 5001
})
BinderUI.open(dyna_namespace, 5002)
BinderUI.create_overlay_definition(dyna_namespace)
local dyna_slot = dyna_namespace.binder_title_slots[1]
local first_object = dyna_slot.object
dyna_slot.object_node.T = { x = 1.25, y = 2.5, w = 1.75, h = 0.4 }
dyna_namespace.binder_ui_state.entries = {
    {
        id = "later-long",
        center_key = "j_very_long_name",
        local_key = "long",
        rarity = "common",
        edition = "base",
        condition = mint_condition,
        acquired_at = 5003
    }
}
BinderUI.set_page(dyna_namespace, 1)
BinderUI.refresh_card_grid(dyna_namespace, { animate_titles = true })
H.assert_true(first_object.removed, "animated binder title refresh removes the old DynaText object")
H.assert_equal(dyna_slot.object.args.string[1], "ExtremelyLongLocalizedJokerName", "animated binder title refresh creates the new DynaText text")
H.assert_equal(dyna_slot.object.synced_to.x, 1.25, "animated binder title refresh keeps the title object on its UI node")
H.assert_true(dyna_slot.object.moved_with_major, "animated binder title refresh runs vanilla movement sync")
H.assert_true(dyna_slot.object.aligned_to_major, "animated binder title refresh runs vanilla alignment sync")
_G.DynaText = previous_grid_dynatext
_G.localize = previous_grid_localize
_G.create_UIBox_generic_options = previous_grid_options
_G.create_option_cycle = previous_grid_cycle
_G.UIBox_button = previous_grid_button
_G.CardArea = previous_grid_area
_G.Card = previous_grid_card
_G.G = previous_grid_g

runtime.FUNCS.grdl_open_desk()
local desk_state = namespace.desk_ui_state
H.assert_true(desk_state ~= nil, "desk state stored")
H.assert_equal(adapter.desk_opened, 1, "desk overlay opened")
H.assert_equal(#desk_state.queue_rows, 0, "queue empty before submit")
H.assert_equal(desk_state.queue_page, 1, "queue page starts at one")

H.assert_true(type(runtime.FUNCS.grdl_inspect_submit) == "function", "inspect submit callback registered")
runtime.FUNCS.grdl_inspect_submit({ config = { ref_table = { id = raw_card.id } } })
H.assert_equal(raw_card.status, "queued", "inspect submit queues card")
H.assert_equal(namespace.collection.currency_g, 10, "inspect submit charges fee")
H.assert_equal(save_count, 1, "successful submit saves config")
H.assert_true(namespace.desk_ui_state ~= desk_state, "success rebuilds desk state")
desk_state = namespace.desk_ui_state
H.assert_equal(#desk_state.queue_rows, 1, "queue row visible after submit")
H.assert_equal(desk_state.queue_rows[1].card_id, raw_card.id, "queue row card id")

local expensive_card = Storage.add_raw_card(namespace.collection, {
    center_key = "j_rare",
    local_key = "rare_joker",
    rarity = "rare",
    edition = "negative",
    condition = mint_condition,
    acquired_at = 2001
})
local stable_state = namespace.desk_ui_state
BinderUI.open_inspect(namespace, expensive_card.id)
runtime.FUNCS.grdl_inspect_submit({ config = { ref_table = { id = expensive_card.id } } })
H.assert_equal(expensive_card.status, "raw", "failed submit keeps card raw")
H.assert_equal(namespace.collection.currency_g, 10, "failed submit keeps currency")
H.assert_equal(save_count, 1, "failed submit does not save")
H.assert_true(namespace.desk_ui_state == stable_state, "failed submit leaves desk state alone")
H.assert_equal(namespace.inspect_ui_state.last_reason_text, "grdl_k_reason_insufficient_funds", "failure text surfaced in inspect")

namespace.collection.grading_queue[1].due_at = 900
local opened = BinderUI.open(namespace, 1000)
H.assert_equal(opened.revealed_count, 1, "due grading revealed on binder open")
H.assert_equal(raw_card.status, "graded", "card graded on binder open")
H.assert_equal(raw_card.grade, 10, "grade derived from hidden condition")
H.assert_equal(raw_card.cert_number, "000001", "cert number assigned on reveal")
H.assert_equal(save_count, 2, "reveal saves config")

local reopened_desk = BinderUI.open_desk(namespace, 1001)
H.assert_equal(reopened_desk.revealed_count, 0, "desk reopen reveals nothing new")
H.assert_equal(save_count, 2, "reopen without reveals does not save")

local inspect_state = BinderUI.open_inspect(namespace, raw_card.id)
H.assert_true(inspect_state ~= nil, "inspect state opens for known card")
H.assert_equal(inspect_state.entry.id, raw_card.id, "inspect entry resolved by id")
H.assert_equal(inspect_state.entry.grade, 10, "inspect entry carries grade")
H.assert_equal(inspect_state.entry.status, "graded", "inspect entry carries status")
H.assert_equal(namespace.inspect_ui_state, inspect_state, "inspect state stored on namespace")
H.assert_equal(BinderUI.open_inspect(namespace, "grdl_unknown"), nil, "unknown card cannot be inspected")
H.assert_equal(BinderUI.open_inspect(nil, raw_card.id), nil, "missing namespace rejected")

local previous_fill_g = rawget(_G, "G")
local previous_fill_card = rawget(_G, "Card")
_G.G = {
    P_CENTERS = {
        j_joker = { key = "j_joker", set = "Joker" },
        j_other = { key = "j_other", set = "Joker" }
    },
    CARD_W = 1.44,
    CARD_H = 1.9
}
_G.Card = function(x, y, w, h, front, center)
    return {
        center = center,
        config = { center = center },
        T = { x = x, y = y, r = 0.2 },
        original_T = { x = -99, y = -99, r = 0 },
        children = {},
        morphs = {},
        materializes = 0,
        set_ability = function(self, next_center, initial)
            self.morphs[#self.morphs + 1] = { center = next_center, initial = initial }
            self.center = next_center
            self.config.center = next_center
            self.T.x, self.T.y, self.T.r = self.original_T.x, self.original_T.y, self.original_T.r
        end,
        start_materialize = function(self) self.materializes = self.materializes + 1 end,
        set_edition = function(self, flag) self.edition_flag = flag end,
        juice_up = function(self) self.juiced = (self.juiced or 0) + 1 end,
        remove = function(self) self.removed = true end
    }
end
local function fake_area()
    return {
        cards = {},
        T = { x = 0, y = 0, w = 7.2, h = 1.9 },
        remove_card = function(self, card)
            for index, value in ipairs(self.cards) do
                if value == card then
                    table.remove(self.cards, index)
                    return card
                end
            end
        end,
        emplace = function(self, card) self.cards[#self.cards + 1] = card end
    }
end
local fill_namespace = {
    binder_areas = { fake_area(), fake_area() },
    binder_ui_state = {
        page_view = {
            items = {
                { id = "f1", center_key = "j_joker", edition = "negative", status = "graded" },
                { id = "f2", center_key = "j_missing", edition = "base", status = "raw" }
            }
        }
    }
}
BinderUI.fill_card_areas(fill_namespace)
local filled = fill_namespace.binder_areas[1].cards
H.assert_equal(#filled, 1, "only loaded centers become cards")
H.assert_equal(filled[1].grdl_record.id, "f1", "grid card carries record")
H.assert_equal(filled[1].grdl_inspect_close_func, "grdl_open_binder", "grid card G inspect returns to binder")
H.assert_true(filled[1].edition_flag ~= nil and filled[1].edition_flag.negative == true, "edition applied to grid card")
H.assert_true(type(filled[1].click) == "function", "grid card click overridden")
filled[1]:click()
H.assert_equal(filled[1].juiced, 1, "click keeps juice feedback")
H.assert_equal(filled[1].highlighted, nil, "click never selects the card")
local reused_card = filled[1]
BinderUI.fill_card_areas(fill_namespace)
H.assert_equal(fill_namespace.binder_areas[1].cards[1], reused_card, "refill reuses matching visible cards")
H.assert_equal(reused_card.removed, nil, "matching visible card is not removed during refill")
fill_namespace.binder_ui_state.page_view.items[1] = { id = "f3", center_key = "j_other", edition = "base", status = "graded" }
reused_card.T.x, reused_card.T.y, reused_card.T.r = 4, 5, 0.4
BinderUI.fill_card_areas(fill_namespace, { animate = true })
H.assert_equal(fill_namespace.binder_areas[1].cards[1], reused_card, "refill morphs changed centers in place")
H.assert_equal(#reused_card.morphs, 1, "changed center uses set_ability instead of hard replacement")
H.assert_equal(reused_card.morphs[1].center, _G.G.P_CENTERS.j_other, "morph targets the new center")
H.assert_near(reused_card.T.x, 4, 0.000001, "morph keeps the live x position")
H.assert_near(reused_card.T.y, 5, 0.000001, "morph keeps the live y position")
H.assert_near(reused_card.T.r, 0.4, 0.000001, "morph keeps the live rotation")
H.assert_near(reused_card.original_T.x, 4, 0.000001, "morph re-anchors original_T before set_ability")
H.assert_equal(reused_card.grdl_record.id, "f3", "morphed card carries the new record")
H.assert_equal(reused_card.grdl_inspect_close_func, "grdl_open_binder", "morphed grid card G inspect still returns to binder")
H.assert_true((reused_card.juiced or 0) >= 2, "animated morph gives a soft pulse")
fill_namespace.binder_ui_state.page_view.items = {}
BinderUI.fill_card_areas(fill_namespace)
H.assert_equal(#fill_namespace.binder_areas[1].cards, 0, "empty refresh clears stale visible cards")
H.assert_equal(reused_card.removed, true, "stale visible card is removed only when slot becomes empty")
_G.G = previous_fill_g
_G.Card = previous_fill_card

local previous_inspect_g = rawget(_G, "G")
local previous_inspect_card = rawget(_G, "Card")
local previous_inspect_area = rawget(_G, "CardArea")
local previous_inspect_uibox = rawget(_G, "UIBox")
local captured_inspect_card = nil
local inspect_area = {
    cards = {},
    T = { x = 2.0, y = 3.0, w = 3.168, h = 4.18 },
    emplace = function(self, card) self.cards[#self.cards + 1] = card end
}
_G.G = {
    ROOM = { T = { x = 0, y = 0, w = 10, h = 10 } },
    P_CENTERS = { j_joker = { key = "j_joker", set = "Joker" } },
    P_CARDS = { empty = {} },
    CARD_W = 1.44,
    CARD_H = 1.9,
    UIT = { R = "R", C = "C", T = "T", O = "O", ROOT = "ROOT" },
    C = {
        WHITE = { 1, 1, 1, 1 },
        CLEAR = { 0, 0, 0, 0 },
        L_BLACK = { 0.2, 0.2, 0.2, 1 },
        RED = { 1, 0, 0, 1 },
        GOLD = { 1, 0.8, 0, 1 },
        PURPLE = { 0.5, 0, 1, 1 },
        UI = {
            TEXT_LIGHT = { 1, 1, 1, 1 },
            TEXT_INACTIVE = { 0.5, 0.5, 0.5, 1 },
            TEXT_DARK = { 0, 0, 0, 1 }
        }
    },
    FONTS = {}
}
_G.CardArea = function()
    return inspect_area
end
_G.Card = function(x, y, w, h, front, center)
    captured_inspect_card = {
        x = x,
        y = y,
        w = w,
        h = h,
        front = front,
        center = center,
        children = {},
        states = {},
        set_edition = function() end,
        juice_up = function() end
    }
    return captured_inspect_card
end
_G.UIBox = function()
    return {
        states = { collide = { can = true } },
        remove = function() end
    }
end
BinderUI.open_inspect(namespace, raw_card.id)
BinderUI.create_inspect_definition(namespace)
H.assert_near(captured_inspect_card.x, inspect_area.T.x + inspect_area.T.w / 2, 0.000001, "inspect card starts at CardArea center")
H.assert_near(captured_inspect_card.y, inspect_area.T.y, 0.000001, "inspect card keeps CardArea y")
H.assert_equal(captured_inspect_card.w, 2.2 * _G.G.CARD_W, "inspect card width follows inspect scale")
H.assert_equal(captured_inspect_card.h, 2.2 * _G.G.CARD_H, "inspect card height follows inspect scale")
H.assert_equal(captured_inspect_card.mouse_damping, 2.2, "inspect card damps vanilla mouse tilt for its display scale")
H.assert_equal(captured_inspect_card.ambient_tilt, 0, "inspect card disables default ambient tilt while preserving hover")
_G.UIBox = previous_inspect_uibox
_G.CardArea = previous_inspect_area
_G.Card = previous_inspect_card
_G.G = previous_inspect_g

H.assert_equal(BinderUI.countdown_text(0), "grdl_k_grading_ready", "zero countdown falls back to ready key")
H.assert_equal(BinderUI.countdown_text(95), "1:35", "minute countdown format")
H.assert_equal(BinderUI.countdown_text(3725), "1:02:05", "hour countdown format")
H.assert_equal(BinderUI.countdown_text(-5), "grdl_k_grading_ready", "negative countdown treated as ready")

H.assert_true(type(runtime.FUNCS.grdl_queue_tick) == "function", "queue tick func registered")
local previous_tick_g = rawget(_G, "G")
local previous_tick_uibox = rawget(_G, "UIBox")
_G.G = {
    UIT = { R = "R", C = "C", T = "T", O = "O", ROOT = "ROOT" },
    C = { CLEAR = "CLEAR", BLACK = "BLACK", WHITE = "WHITE", GREEN = "GREEN", BLUE = "BLUE" }
}
local tip_args = nil
local tip_removed = 0
_G.UIBox = function(args)
    tip_args = args
    return { states = { collide = { can = true } }, remove = function() tip_removed = tip_removed + 1 end }
end
local tick_now = os.time()
local tick_info = { due_at = tick_now + 50, submitted_at = tick_now - 50, progress = 0, countdown = "" }
local bar_element = {
    config = {
        ref_table = tick_info,
        progress_bar = { ref_table = tick_info, ref_value = "progress", max = 1, filled_col = "BLUE" }
    },
    children = {},
    states = { hover = { is = false } }
}
runtime.FUNCS.grdl_queue_tick(bar_element)
H.assert_true(tick_info.countdown:find("^0:[45]") ~= nil, "tick refreshes countdown text every frame")
H.assert_near(tick_info.progress, 0.5, 0.02, "tick recomputes progress from the wall clock")
H.assert_equal(bar_element.config.progress_bar.filled_col, "BLUE", "running bar stays blue")
H.assert_equal(bar_element.children.grdl_tip, nil, "no tooltip while not hovered")

bar_element.states.hover.is = true
runtime.FUNCS.grdl_queue_tick(bar_element)
H.assert_true(bar_element.children.grdl_tip ~= nil, "hover attaches the live tooltip")
H.assert_equal(tip_args.config.instance_type, "POPUP", "tooltip draws on the popup layer")
H.assert_equal(tip_args.definition.nodes[1].nodes[1].config.ref_value, "countdown", "tooltip text bound to the live countdown")
H.assert_equal(tip_args.definition.nodes[1].nodes[1].config.ref_table, tick_info, "tooltip bound to the bar state")
runtime.FUNCS.grdl_queue_tick(bar_element)
H.assert_equal(tip_removed, 0, "steady hover keeps the tooltip")

tick_info.due_at = tick_now - 1
runtime.FUNCS.grdl_queue_tick(bar_element)
H.assert_equal(tick_info.countdown, "grdl_k_grading_ready", "tick reports ready when due passed")
H.assert_near(tick_info.progress, 1, 0.001, "ready bar fills completely")
H.assert_equal(bar_element.config.progress_bar.filled_col, "GREEN", "ready bar turns green")

bar_element.states.hover.is = false
runtime.FUNCS.grdl_queue_tick(bar_element)
H.assert_equal(tip_removed, 1, "unhover removes the tooltip")
H.assert_equal(bar_element.children.grdl_tip, nil, "tooltip reference cleared")
_G.G = previous_tick_g
_G.UIBox = previous_tick_uibox

local tab_desk = BinderUI.open_desk(namespace, 3000)
H.assert_equal(tab_desk.queue_page, 1, "queue page starts at one")
BinderUI.set_desk_page(namespace, 99)
H.assert_equal(namespace.desk_ui_state.queue_page, 1, "queue page clamps on empty queue")

local refreshed_before = adapter.desk_refreshed
runtime.FUNCS.grdl_desk_queue_page({ cycle_config = { current_option = 1 } })
H.assert_equal(namespace.desk_ui_state.queue_page, 1, "page callback applies cycle option")
H.assert_equal(adapter.desk_refreshed, refreshed_before + 1, "page callback falls back to overlay refresh")

H.assert_true(type(runtime.FUNCS.grdl_row_preview) == "function", "row preview func registered")
local previous_preview_g = rawget(_G, "G")
local previous_preview_card = rawget(_G, "Card")
local previous_preview_area = rawget(_G, "CardArea")
local previous_preview_uibox = rawget(_G, "UIBox")
_G.G = {
    P_CENTERS = { j_joker = { key = "j_joker", set = "Joker" } },
    CARD_W = 1.44,
    CARD_H = 1.9,
    UIT = { R = "R", C = "C", T = "T", O = "O", ROOT = "ROOT" },
    C = { CLEAR = { 0, 0, 0, 0 } }
}
local captured_card = nil
_G.Card = function(x, y, w, h, front, center)
    captured_card = {
        w = w,
        h = h,
        center = center,
        states = { collide = { can = true } },
        set_edition = function(self, flags) self.edition_flags = flags end
    }
    return captured_card
end
_G.CardArea = function(x, y, w, h, args)
    return {
        T = { x = x, y = y, w = w, h = h },
        cards = {},
        emplace = function(self, card)
            self.cards[#self.cards + 1] = card
            -- vanilla emplace re-enables collision when an area takes the card
            if card.states and card.states.collide then card.states.collide.can = true end
        end
    }
end
local preview_box_removed = 0
local preview_box_args = nil
_G.UIBox = function(args)
    preview_box_args = args
    return {
        states = { collide = { can = true } },
        remove = function() preview_box_removed = preview_box_removed + 1 end
    }
end

local preview_element = {
    config = { ref_table = { center_key = "j_joker", edition = "negative" } },
    states = { hover = { is = true } },
    children = {}
}
runtime.FUNCS.grdl_row_preview(preview_element)
H.assert_true(preview_element.children.grdl_preview ~= nil, "hover attaches card preview")
H.assert_near(captured_card.w, 0.8 * 1.44, 0.000001, "preview card at point eight scale")
H.assert_true(captured_card.edition_flags ~= nil and captured_card.edition_flags.negative == true, "preview applies edition")
H.assert_equal(captured_card.states.collide.can, false, "preview card does not catch the cursor even after emplace")
H.assert_equal(captured_card.no_ui, true, "preview card never spawns its own tooltip")
H.assert_equal(preview_box_args.config.instance_type, "POPUP", "preview draws on popup layer")
H.assert_equal(preview_box_args.config.align, "cl", "preview floats beside the row")
H.assert_equal(preview_box_args.config.parent, preview_element, "preview parented for cascade cleanup")

runtime.FUNCS.grdl_row_preview(preview_element)
H.assert_equal(preview_box_removed, 0, "steady hover keeps the preview")

preview_element.states.hover.is = false
runtime.FUNCS.grdl_row_preview(preview_element)
H.assert_equal(preview_box_removed, 1, "unhover removes the preview")
H.assert_equal(preview_element.children.grdl_preview, nil, "preview reference cleared")

local missing_element = {
    config = { ref_table = { center_key = "j_unknown", edition = "base" } },
    states = { hover = { is = true } },
    children = {}
}
runtime.FUNCS.grdl_row_preview(missing_element)
H.assert_equal(missing_element.children.grdl_preview, nil, "missing center attaches nothing")

_G.G = previous_preview_g
_G.Card = previous_preview_card
_G.CardArea = previous_preview_area
_G.UIBox = previous_preview_uibox

H.assert_true(type(runtime.FUNCS.grdl_inspect_sell) == "function", "inspect sell callback registered")
H.assert_equal(BinderUI.sell_from_inspect(namespace, "grdl_unknown", 6000).reason, "missing_state", "sell requires matching inspect state")
BinderUI.open_inspect(namespace, raw_card.id)
local armed = BinderUI.sell_from_inspect(namespace, raw_card.id, 6000)
H.assert_equal(armed.ok, true, "first sell click arms confirmation")
H.assert_equal(armed.pending, true, "first sell click is pending")
H.assert_equal(namespace.inspect_ui_state.pending_sell, true, "pending flag stored")
H.assert_equal(namespace.inspect_ui_state.last_reason_text, "grdl_k_sell_arm_hint", "arm hint bound in place")
local currency_before_sale = namespace.collection.currency_g
local sold = BinderUI.sell_from_inspect(namespace, raw_card.id, 6001)
H.assert_equal(sold.ok, true, "second sell click sells")
H.assert_equal(sold.price, 159, "gem mint common quote paid")
H.assert_equal(raw_card.status, "sold", "card sold from inspect")
H.assert_equal(namespace.collection.currency_g, currency_before_sale + 159, "sale credits the quote")

local sell_exit_card = Storage.add_raw_card(namespace.collection, {
    center_key = "j_sell_exit", local_key = "sell_exit", rarity = "common",
    edition = "base", condition = mint_condition, acquired_at = 6002
})
BinderUI.open(namespace, 6002)
BinderUI.open_inspect(namespace, sell_exit_card.id, { close_func = "exit_overlay_menu" })
local previous_exit_overlay = runtime.FUNCS.exit_overlay_menu
local exited_inspect = 0
runtime.FUNCS.exit_overlay_menu = function()
    exited_inspect = exited_inspect + 1
end
runtime.FUNCS.grdl_inspect_sell({ config = { ref_table = { id = sell_exit_card.id } } })
H.assert_equal(exited_inspect, 0, "first sell confirmation stays in inspect")
runtime.FUNCS.grdl_inspect_sell({ config = { ref_table = { id = sell_exit_card.id } } })
H.assert_equal(sell_exit_card.status, "sold", "runtime sell confirms sale")
H.assert_equal(exited_inspect, 1, "successful runtime sell exits inspect")
runtime.FUNCS.exit_overlay_menu = previous_exit_overlay

local offer_state = BinderUI.inspect_offer(namespace, {
    slot = 2,
    center_key = "j_offer",
    local_key = "offer_joker",
    mod_id = "Alpha",
    mod_name = "Alpha",
    series_key = "Alpha Series",
    rarity = "rare",
    edition = "negative",
    graded = true,
    grade = 9,
    mystery = false,
    price = 321
})
H.assert_true(offer_state ~= nil, "offer inspect opens")
H.assert_equal(offer_state.offer_mode, true, "offer mode flagged")
H.assert_equal(offer_state.entry.offer_slot, 2, "offer slot mapped")
H.assert_equal(offer_state.entry.status, "graded", "graded offer status mapped")
H.assert_equal(offer_state.entry.grade, 9, "offer grade mapped")
H.assert_equal(offer_state.entry.price, 321, "offer price mapped")
H.assert_equal(BinderUI.inspect_offer(namespace, { slot = 3, mystery = true }), nil, "mystery offer cannot be inspected")

-- ===== loadout membership and proficiency perks from inspect =====
local Loadout = dofile("src/domain/loadout.lua")
namespace.collection.loadout.license = 3
local member_card = Storage.add_raw_card(namespace.collection, {
    center_key = "j_member", local_key = "member", rarity = "common",
    edition = "base", condition = mint_condition, acquired_at = 9000
})
member_card.status = "graded"
member_card.grade = 9
BinderUI.open(namespace, 9001)

H.assert_true(type(runtime.FUNCS.grdl_loadout_toggle) == "function", "loadout toggle registered")
BinderUI.open_inspect(namespace, member_card.id)
local added = BinderUI.toggle_loadout(namespace, member_card.id)
H.assert_equal(added.ok, true, "graded card joins loadout in one click")
H.assert_equal(Loadout.contains(namespace.collection, member_card.id), true, "membership stored")
local removed = BinderUI.toggle_loadout(namespace, member_card.id)
H.assert_equal(removed.ok, true, "second toggle removes")
H.assert_equal(Loadout.contains(namespace.collection, member_card.id), false, "membership cleared")

-- raw card needs the armed second click
local raw_member = Storage.add_raw_card(namespace.collection, {
    center_key = "j_rawm", local_key = "rawm", rarity = "common",
    edition = "base", condition = mint_condition, acquired_at = 9002
})
BinderUI.open(namespace, 9003)
BinderUI.open_inspect(namespace, raw_member.id)
local armed_add = BinderUI.toggle_loadout(namespace, raw_member.id)
H.assert_equal(armed_add.pending, true, "raw add arms first")
H.assert_equal(Loadout.contains(namespace.collection, raw_member.id), false, "raw not yet added")
H.assert_equal(namespace.inspect_ui_state.last_reason_text, "grdl_k_loadout_raw_hint", "raw warning bound")
local confirmed_add = BinderUI.toggle_loadout(namespace, raw_member.id)
H.assert_equal(confirmed_add.ok, true, "raw add confirms second click")
H.assert_equal(Loadout.contains(namespace.collection, raw_member.id), true, "raw added")

-- in-run lock
local previous_lock_g = rawget(_G, "G")
_G.G = { STAGE = 1, STAGES = { RUN = 1 } }
H.assert_equal(BinderUI.toggle_loadout(namespace, member_card.id).reason, "loadout_locked", "membership locked in run")
_G.G = previous_lock_g

-- selling a member auto-removes it from the loadout
BinderUI.open(namespace, 9004)
BinderUI.open_inspect(namespace, raw_member.id)
BinderUI.sell_from_inspect(namespace, raw_member.id, 9005)
BinderUI.sell_from_inspect(namespace, raw_member.id, 9006)
H.assert_equal(raw_member.status, "sold", "member sold from inspect")
H.assert_equal(Loadout.contains(namespace.collection, raw_member.id), false, "sale removes loadout membership")

-- perk handlers
member_card.proficiency = { antes = 100 }
BinderUI.open(namespace, 9007)
BinderUI.open_inspect(namespace, member_card.id)
H.assert_true(type(runtime.FUNCS.grdl_prof_eternal) == "function", "eternal toggle registered")
local eternal_identity = namespace.inspect_ui_state
local previous_eternal_g = rawget(_G, "G")
local previous_eternal_generic_options = rawget(_G, "create_UIBox_generic_options")
local previous_localize = rawget(_G, "localize")
_G.G = {
    ROOM = { T = { w = 10, h = 10 } },
    UIT = { R = "R", C = "C", T = "T", O = "O", ROOT = "ROOT" },
    C = {
        WHITE = { 1, 1, 1, 1 },
        GREEN = { 0, 1, 0, 1 },
        CLEAR = { 0, 0, 0, 0 },
        L_BLACK = { 0.2, 0.2, 0.2, 1 },
        RED = { 1, 0, 0, 1 },
        GOLD = { 1, 0.8, 0, 1 },
        PURPLE = { 0.5, 0, 1, 1 },
        UI = {
            TEXT_LIGHT = { 1, 1, 1, 1 },
            TEXT_INACTIVE = { 0.5, 0.5, 0.5, 1 },
            TEXT_DARK = { 0, 0, 0, 1 }
        }
    },
    FONTS = {}
}
_G.create_UIBox_generic_options = function(args) return args end
local localization_stub = {
    grdl_b_prof_personalize = "Personalization",
    grdl_b_prof_inscription = "Inscription",
    grdl_b_prof_badge = "Badge",
    grdl_b_prof_tint = "Tooltip Colour",
    grdl_b_prof_eternal = "Eternal",
    grdl_k_prof_unlocks_at = "Unlocks at proficiency level #1#"
}
_G.localize = function(arg)
    if type(arg) == "table" then return "ERROR" end
    return localization_stub[arg] or arg
end
local function find_button(node, button)
    if type(node) ~= "table" then return nil end
    if node.config and (node.config.button == button or node.config.id == button) then return node end
    for _, child in ipairs(node.nodes or {}) do
        local found = find_button(child, button)
        if found then return found end
    end
    for _, child in ipairs(node.contents or {}) do
        local found = find_button(child, button)
        if found then return found end
    end
    return nil
end
local function collect_text(node, out)
    if type(node) ~= "table" then return end
    if node.config and type(node.config.text) == "string" then
        out[#out + 1] = node.config.text
    end
    for _, child in ipairs(node.nodes or {}) do collect_text(child, out) end
    for _, child in ipairs(node.contents or {}) do collect_text(child, out) end
end
local function joined_text(node)
    local out = {}
    collect_text(node, out)
    return table.concat(out, "\n")
end
local inspect_definition = BinderUI.create_inspect_definition(namespace)
local personalize_button = find_button(inspect_definition, "grdl_prof_personalize")
H.assert_true(personalize_button ~= nil, "graded inspect renders one personalization button")
H.assert_equal(find_button(inspect_definition, "grdl_prof_note"), nil, "note button removed from main inspect")
H.assert_equal(find_button(inspect_definition, "grdl_prof_badge"), nil, "badge button removed from main inspect")
H.assert_equal(find_button(inspect_definition, "grdl_prof_tint"), nil, "tint button removed from main inspect")

member_card.proficiency = { antes = 5 }
BinderUI.open_personalization(namespace, member_card.id)
local personal_definition = BinderUI.create_personalization_definition(namespace)
local inscription_locked = find_button(personal_definition, "grdl_prof_inscription")
local eternal_locked = find_button(personal_definition, "grdl_prof_eternal")
H.assert_true(inscription_locked ~= nil, "inscription row rendered")
H.assert_true(eternal_locked ~= nil, "eternal row rendered")
H.assert_equal(inscription_locked.config.button, nil, "locked inscription has no click action")
H.assert_equal(eternal_locked.config.button, nil, "locked eternal has no click action")
H.assert_equal(inscription_locked.config.outline_colour, _G.G.C.UI.TEXT_INACTIVE, "locked row grey outline")
local locked_inscription_text = joined_text(inscription_locked)
H.assert_true(locked_inscription_text:find("II", 1, true) ~= nil, "locked inscription names the unlock level")
H.assert_true(locked_inscription_text:find("#1#", 1, true) == nil, "locked inscription interpolates unlock text")
_G.localize = previous_localize

member_card.proficiency.antes = 100
BinderUI.open_personalization(namespace, member_card.id)
local unlocked_personal_definition = BinderUI.create_personalization_definition(namespace)
local unlocked_inscription = find_button(unlocked_personal_definition, "grdl_prof_inscription")
local eternal_button = find_button(unlocked_personal_definition, "grdl_prof_eternal")
local unlocked_badge = find_button(unlocked_personal_definition, "grdl_prof_badge")
local unlocked_tint = find_button(unlocked_personal_definition, "grdl_prof_tint")
H.assert_true(unlocked_inscription ~= nil, "unlocked inscription row rendered")
H.assert_true(eternal_button ~= nil, "unlocked eternal row rendered")
H.assert_true(unlocked_badge ~= nil, "unlocked badge row rendered")
H.assert_true(unlocked_tint ~= nil, "unlocked tint row rendered")
H.assert_equal(unlocked_inscription.config.button, "grdl_prof_inscription", "unlocked inscription clickable")
H.assert_equal(eternal_identity.eternal_button_text, "grdl_b_prof_eternal", "eternal button uses neutral label")
H.assert_equal(eternal_button.config.outline_colour, _G.G.C.WHITE, "eternal off keeps white outline")
H.assert_equal(eternal_button.config.colour[4], 0, "eternal off has transparent fill")
runtime.FUNCS.grdl_prof_eternal({ config = { ref_table = { id = member_card.id } } })
H.assert_equal(member_card.proficiency.eternal, true, "eternal preference flipped")
H.assert_equal(namespace.inspect_ui_state, eternal_identity, "eternal toggle keeps inspect state in place")
H.assert_equal(eternal_identity.eternal_button_text, "grdl_b_prof_eternal", "eternal label stays neutral")
H.assert_equal(eternal_identity.eternal_button_colour[4], 1, "eternal on fills button")
H.assert_near(eternal_identity.eternal_button_colour[2], 1, 0.001, "eternal on fill is green")
_G.create_UIBox_generic_options = previous_eternal_generic_options
_G.G = previous_eternal_g

-- in-place loadout toggle keeps the overlay state and flips the label
local toggle_identity = namespace.inspect_ui_state
runtime.FUNCS.grdl_loadout_toggle({ config = { ref_table = { id = member_card.id } } })
H.assert_equal(namespace.inspect_ui_state, toggle_identity, "loadout toggle keeps inspect state in place")
H.assert_equal(toggle_identity.loadout_button_text, "grdl_b_loadout_remove", "label flips to remove")
runtime.FUNCS.grdl_loadout_toggle({ config = { ref_table = { id = member_card.id } } })
H.assert_equal(toggle_identity.loadout_button_text, "grdl_b_loadout_add", "label flips back to add")
H.assert_equal(BinderUI.commit_prof_text(namespace, member_card.id, "note", "hello").ok, true, "note commit")
H.assert_equal(member_card.proficiency.note, "hello", "note stored")
H.assert_equal(BinderUI.commit_prof_text(namespace, member_card.id, "badge", "OG").ok, true, "badge commit")
H.assert_equal(member_card.proficiency.badge_text, "OG", "badge stored")
H.assert_equal(BinderUI.commit_prof_text(namespace, member_card.id, "badge_colour", "00ff80").ok, true, "badge colour commit")
H.assert_equal(member_card.proficiency.badge_colour, "00FF80", "badge colour stored")
H.assert_equal(BinderUI.commit_prof_text(namespace, member_card.id, "tint", "1A2B3C").ok, true, "tint commit")
H.assert_equal(member_card.proficiency.tooltip_colour, "1A2B3C", "tint stored")
H.assert_equal(BinderUI.commit_prof_text(namespace, member_card.id, "tint", "zzz").reason, "invalid_hex", "bad tint rejected")

local previous_prof_g = rawget(_G, "G")
local previous_text_input = rawget(_G, "create_text_input")
local previous_generic_options = rawget(_G, "create_UIBox_generic_options")
local previous_overlay_menu = runtime.FUNCS.overlay_menu
local previous_love = rawget(_G, "love")
local captured_text_input = nil
local captured_overlay = nil
_G.G = {
    ROOM = { T = { w = 10, h = 10 } },
    FUNCS = runtime.FUNCS,
    SETTINGS = {},
    UIT = { R = "R", C = "C", T = "T", O = "O", ROOT = "ROOT" },
    C = {
        WHITE = { 1, 1, 1, 1 },
        GOLD = { 1, 0.8, 0, 1 },
        L_BLACK = { 0.2, 0.2, 0.2, 1 },
        RED = { 1, 0, 0, 1 },
        CLEAR = { 0, 0, 0, 0 },
        UI = {
            TEXT_LIGHT = { 1, 1, 1, 1 },
            TEXT_INACTIVE = { 0.5, 0.5, 0.5, 1 },
            TEXT_DARK = { 0, 0, 0, 1 }
        }
    }
}
_G.create_text_input = function(args)
    captured_text_input = args
    return { n = G.UIT.C, config = { ref_table = args.ref_table, ref_value = args.ref_value }, nodes = {} }
end
_G.create_UIBox_generic_options = function(args) return args end
runtime.FUNCS.overlay_menu = function(args) captured_overlay = args end
BinderUI.open_prof_input(namespace, member_card.id, "tint")
H.assert_true(captured_overlay ~= nil, "tint input opens an overlay")
H.assert_equal(captured_text_input.extended_corpus, true, "tint input allows zeroes for RGB hex")
H.assert_true(captured_text_input.all_caps ~= true, "tint input keeps digits from remapping to shifted symbols")
namespace.prof_input.text = "FF8000"
local swatch = { config = { colour = { 0, 0, 0, 1 } } }
runtime.FUNCS.grdl_hex_preview(swatch)
H.assert_near(swatch.config.colour[1], 1, 0.001, "hex preview red channel")
H.assert_near(swatch.config.colour[2], 0.502, 0.001, "hex preview green channel")
H.assert_near(swatch.config.colour[3], 0, 0.001, "hex preview blue channel can be zero")

captured_overlay = nil
_G.love = { system = { getClipboardText = function() return "刻字\n第二行" end } }
BinderUI.open_prof_input(namespace, member_card.id, "note")
H.assert_true(captured_overlay ~= nil, "inscription editor opens")
local inscription_clear = find_button(captured_overlay.definition, "grdl_prof_text_clear")
H.assert_true(inscription_clear ~= nil, "inscription editor has a clear button")
H.assert_equal(inscription_clear.config.colour, _G.G.C.RED, "inscription clear uses regular red button fill")
H.assert_equal(inscription_clear.config.outline, nil, "inscription clear has no white outline")
H.assert_equal(namespace.prof_text_input.kind, "note", "inscription editor uses text input state")

local feedback_now = 100
_G.love = {
    timer = { getTime = function() return feedback_now end },
    system = { getClipboardText = function() return "" end }
}
H.assert_true(type(runtime.FUNCS.grdl_prof_feedback_decay) == "function", "transient feedback decay callback registered")
runtime.FUNCS.grdl_prof_text_paste()
H.assert_equal(namespace.prof_text_input.feedback, "grdl_k_reason_empty_clipboard", "empty inscription paste shows feedback")
H.assert_equal(namespace.prof_text_input.feedback_transient, true, "empty inscription paste is transient feedback")
feedback_now = 102.1
runtime.FUNCS.grdl_prof_feedback_decay({ config = { ref_table = namespace.prof_text_input } })
H.assert_equal(namespace.prof_text_input.feedback, "", "empty inscription paste feedback decays after two seconds")

runtime.FUNCS.grdl_prof_text_paste()
H.assert_equal(namespace.prof_text_input.feedback, "grdl_k_reason_empty_clipboard", "empty inscription feedback can be shown again")
BinderUI.open_prof_input(namespace, member_card.id, "note")
H.assert_equal(namespace.prof_text_input.feedback, "", "reopening inscription editor clears transient feedback")

_G.love = {
    timer = { getTime = function() return feedback_now end },
    system = { getClipboardText = function() return "刻字\n第二行" end }
}
runtime.FUNCS.grdl_prof_text_paste()
H.assert_equal(namespace.prof_text_input.text, "刻字\n第二行", "inscription paste preserves unicode newline")
runtime.FUNCS.grdl_prof_text_commit()
H.assert_equal(member_card.proficiency.note, "刻字\n第二行", "inscription commit stores pasted text")

captured_text_input = nil
captured_overlay = nil
_G.love = { system = { getClipboardText = function() return "徽标中文" end } }
BinderUI.open_badge_input(namespace, member_card.id)
H.assert_true(captured_overlay ~= nil, "combined badge editor opens")
local badge_clear = find_button(captured_overlay.definition, "grdl_prof_badge_clear")
H.assert_true(badge_clear ~= nil, "badge editor has a clear button")
H.assert_equal(badge_clear.config.colour, _G.G.C.RED, "badge clear uses regular red button fill")
H.assert_equal(badge_clear.config.outline, nil, "badge clear has no white outline")
H.assert_true(captured_text_input ~= nil, "badge colour still uses vanilla text input")
H.assert_equal(captured_text_input.ref_value, "badge_colour", "badge colour field bound")
H.assert_equal(captured_text_input.extended_corpus, true, "badge colour keeps extended corpus")

_G.love = {
    timer = { getTime = function() return feedback_now end },
    system = { getClipboardText = function() return "" end }
}
runtime.FUNCS.grdl_prof_badge_paste()
H.assert_equal(namespace.prof_badge_input.feedback, "grdl_k_reason_empty_clipboard", "empty badge paste shows feedback")
H.assert_equal(namespace.prof_badge_input.feedback_transient, true, "empty badge paste is transient feedback")
runtime.FUNCS.grdl_prof_badge_clear()
H.assert_equal(namespace.prof_badge_input.feedback, "", "badge clear removes transient feedback")
runtime.FUNCS.grdl_prof_badge_paste()
BinderUI.open_badge_input(namespace, member_card.id)
H.assert_equal(namespace.prof_badge_input.feedback, "", "reopening badge editor clears transient feedback")

_G.love = {
    timer = { getTime = function() return feedback_now end },
    system = { getClipboardText = function() return "徽标中文" end }
}
runtime.FUNCS.grdl_prof_badge_paste()
H.assert_equal(namespace.prof_badge_input.badge_text, "徽标中文", "badge text paste stores unicode")
namespace.prof_badge_input.badge_colour = "00FF80"
local badge_swatch = { config = { colour = { 0, 0, 0, 1 } } }
runtime.FUNCS.grdl_badge_hex_preview(badge_swatch)
H.assert_near(badge_swatch.config.colour[1], 0, 0.001, "badge colour preview red channel")
H.assert_near(badge_swatch.config.colour[2], 1, 0.001, "badge colour preview green channel")
H.assert_near(badge_swatch.config.colour[3], 0.502, 0.001, "badge colour preview blue channel")
runtime.FUNCS.grdl_prof_badge_commit()
H.assert_equal(member_card.proficiency.badge_text, "徽标中文", "badge text committed")
H.assert_equal(member_card.proficiency.badge_colour, "00FF80", "badge colour committed")
runtime.FUNCS.overlay_menu = previous_overlay_menu
_G.create_UIBox_generic_options = previous_generic_options
_G.create_text_input = previous_text_input
_G.love = previous_love
_G.G = previous_prof_g

local low_card = Storage.add_raw_card(namespace.collection, {
    center_key = "j_low", local_key = "low", rarity = "common",
    edition = "base", condition = mint_condition, acquired_at = 9008
})
low_card.status = "graded"
H.assert_equal(BinderUI.commit_prof_text(namespace, low_card.id, "note", "x").reason, "locked", "perk gate enforced")

-- in-run loadout inspect variant
BinderUI.open(namespace, 9009)
local loadout_state = BinderUI.inspect_loadout(namespace, member_card.id)
H.assert_true(loadout_state ~= nil, "loadout inspect opens")
H.assert_equal(loadout_state.loadout_mode, true, "loadout mode flagged")
local previous_context_g = rawget(_G, "G")
_G.G = {
    ROOM = { T = { w = 10, h = 10 } },
    STAGE = 1,
    STAGES = { RUN = 1 },
    UIT = { R = "R", C = "C", T = "T", O = "O", ROOT = "ROOT" },
    C = {
        WHITE = { 1, 1, 1, 1 },
        GREEN = { 0, 1, 0, 1 },
        CLEAR = { 0, 0, 0, 0 },
        L_BLACK = { 0.2, 0.2, 0.2, 1 },
        RED = { 1, 0, 0, 1 },
        GOLD = { 1, 0.8, 0, 1 },
        PURPLE = { 0.5, 0, 1, 1 },
        UI = {
            TEXT_LIGHT = { 1, 1, 1, 1 },
            TEXT_INACTIVE = { 0.5, 0.5, 0.5, 1 },
            TEXT_DARK = { 0, 0, 0, 1 }
        }
    },
    FONTS = {}
}
local run_context_state = BinderUI.inspect_from_card(namespace, { grdl_record = member_card })
H.assert_equal(run_context_state.close_func, "exit_overlay_menu", "run inspect closes back to the run")
local run_context_definition = BinderUI.create_inspect_definition(namespace)
H.assert_true(find_button(run_context_definition, "exit_overlay_menu") ~= nil, "run inspect X exits overlay")
H.assert_equal(find_button(run_context_definition, "grdl_open_binder"), nil, "run inspect X does not open binder")
namespace.personalization_ui_state = { card_id = member_card.id }
runtime.FUNCS.grdl_reopen_inspect()
H.assert_equal(namespace.inspect_ui_state.close_func, "exit_overlay_menu", "reopened run inspect keeps close context")

local loadout_context_state = BinderUI.inspect_from_card(namespace, {
    grdl_record = member_card,
    grdl_inspect_close_func = "grdl_open_loadout"
})
H.assert_equal(loadout_context_state.close_func, "grdl_open_loadout", "marked loadout card returns to loadout")
local loadout_context_definition = BinderUI.create_inspect_definition(namespace)
H.assert_true(find_button(loadout_context_definition, "grdl_open_loadout") ~= nil, "loadout inspect X returns to loadout")
H.assert_equal(find_button(loadout_context_definition, "grdl_open_binder"), nil, "loadout inspect X does not open binder")

local runtime_loadout_state = BinderUI.inspect_loadout(namespace, member_card.id, { close_func = "exit_overlay_menu" })
H.assert_equal(runtime_loadout_state.close_func, "exit_overlay_menu", "run loadout inspect starts with run close context")
namespace.prof_input = { card_id = member_card.id, kind = "tint", text = "112233" }
runtime.FUNCS.grdl_prof_commit()
H.assert_equal(namespace.inspect_ui_state.close_func, "exit_overlay_menu", "loadout personalization commit keeps close context")
H.assert_equal(namespace.inspect_ui_state.loadout_mode, true, "loadout personalization commit keeps loadout mode")
_G.G = previous_context_g

_G.SMODS = previous_smods_global

print("binder ui tests ok")
