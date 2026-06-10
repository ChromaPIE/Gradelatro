local H = dofile("tests/test_helper.lua")
local Config = dofile("src/config.lua")
local Storage = dofile("src/storage.lua")
local BinderUI = dofile("src/binder_ui.lua")

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
    save_mod_config = function(mod)
        H.assert_equal(mod, namespace.mod, "binder saves namespace mod")
        save_count = save_count + 1
        return true
    end
}

local runtime = { FUNCS = {} }
local adapter = { binder_opened = 0, desk_opened = 0, desk_refreshed = 0, fail_notified = 0 }
function adapter.open_binder()
    adapter.binder_opened = adapter.binder_opened + 1
end
function adapter.open_desk()
    adapter.desk_opened = adapter.desk_opened + 1
end
function adapter.refresh_desk()
    adapter.desk_refreshed = adapter.desk_refreshed + 1
end
function adapter.notify_failure()
    adapter.fail_notified = adapter.fail_notified + 1
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

runtime.FUNCS.grdl_open_desk()
local desk_state = namespace.desk_ui_state
H.assert_true(desk_state ~= nil, "desk state stored")
H.assert_equal(adapter.desk_opened, 1, "desk overlay opened")
H.assert_equal(#desk_state.rows, 13, "desk lists raw cards")
H.assert_equal(desk_state.fees[raw_card.id], 15, "desk fee exposed")
H.assert_equal(#desk_state.queue_rows, 0, "queue empty before submit")
H.assert_equal(desk_state.last_reason_text, "", "no failure text initially")

runtime.FUNCS.grdl_submit_grading({ config = { ref_table = { id = raw_card.id } } })
H.assert_equal(raw_card.status, "queued", "submit callback queues card")
H.assert_equal(namespace.collection.currency_g, 10, "submit callback charges fee")
H.assert_equal(save_count, 1, "successful submit saves config")
H.assert_equal(adapter.desk_refreshed, 1, "submit refreshes desk overlay")
H.assert_true(namespace.desk_ui_state ~= desk_state, "success rebuilds desk state")
desk_state = namespace.desk_ui_state
H.assert_equal(#desk_state.queue_rows, 1, "queue row visible after submit")
H.assert_equal(desk_state.queue_rows[1].card_id, raw_card.id, "queue row card id")
H.assert_equal(desk_state.fees[raw_card.id], nil, "queued card no longer offers a fee")

local expensive_card = Storage.add_raw_card(namespace.collection, {
    center_key = "j_rare",
    local_key = "rare_joker",
    rarity = "rare",
    edition = "negative",
    condition = mint_condition,
    acquired_at = 2001
})
local stable_state = namespace.desk_ui_state
runtime.FUNCS.grdl_submit_grading({ config = { ref_table = { id = expensive_card.id } } })
H.assert_equal(expensive_card.status, "raw", "failed submit keeps card raw")
H.assert_equal(namespace.collection.currency_g, 10, "failed submit keeps currency")
H.assert_equal(save_count, 1, "failed submit does not save")
H.assert_equal(adapter.desk_refreshed, 1, "failed submit does not rebuild overlay")
H.assert_equal(adapter.fail_notified, 1, "failed submit notifies failure")
H.assert_true(namespace.desk_ui_state == stable_state, "failed submit keeps desk state in place")
H.assert_equal(stable_state.last_reason, "insufficient_funds", "failure reason surfaced")
H.assert_equal(stable_state.last_reason_text, "grdl_k_reason_insufficient_funds", "failure text bound for live update")

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
    P_CENTERS = { j_joker = { key = "j_joker", set = "Joker" } },
    CARD_W = 1.44,
    CARD_H = 1.9
}
_G.Card = function(x, y, w, h, front, center)
    return {
        center = center,
        children = {},
        set_edition = function(self, flag) self.edition_flag = flag end,
        juice_up = function(self) self.juiced = (self.juiced or 0) + 1 end,
        remove = function() end
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
H.assert_true(filled[1].edition_flag ~= nil and filled[1].edition_flag.negative == true, "edition applied to grid card")
H.assert_true(type(filled[1].click) == "function", "grid card click overridden")
filled[1]:click()
H.assert_equal(filled[1].juiced, 1, "click keeps juice feedback")
H.assert_equal(filled[1].highlighted, nil, "click never selects the card")
BinderUI.fill_card_areas(fill_namespace)
H.assert_equal(#fill_namespace.binder_areas[1].cards, 1, "refill replaces cards without stacking")
_G.G = previous_fill_g
_G.Card = previous_fill_card

_G.SMODS = previous_smods_global

print("binder ui tests ok")
