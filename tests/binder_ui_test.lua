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
        emplace = function(self, card) self.cards[#self.cards + 1] = card end
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
H.assert_equal(captured_card.states.collide.can, false, "preview card does not catch the cursor")
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
local Loadout = dofile("src/loadout.lua")
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
runtime.FUNCS.grdl_prof_eternal({ config = { ref_table = { id = member_card.id } } })
H.assert_equal(member_card.proficiency.eternal, true, "eternal preference flipped")
H.assert_equal(BinderUI.commit_prof_text(namespace, member_card.id, "note", "hello").ok, true, "note commit")
H.assert_equal(member_card.proficiency.note, "hello", "note stored")
H.assert_equal(BinderUI.commit_prof_text(namespace, member_card.id, "badge", "OG").ok, true, "badge commit")
H.assert_equal(member_card.proficiency.badge_text, "OG", "badge stored")
H.assert_equal(BinderUI.commit_prof_text(namespace, member_card.id, "tint", "1A2B3C").ok, true, "tint commit")
H.assert_equal(member_card.proficiency.tooltip_colour, "1A2B3C", "tint stored")
H.assert_equal(BinderUI.commit_prof_text(namespace, member_card.id, "tint", "zzz").reason, "invalid_hex", "bad tint rejected")
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

_G.SMODS = previous_smods_global

print("binder ui tests ok")
