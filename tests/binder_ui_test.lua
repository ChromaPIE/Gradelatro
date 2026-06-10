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

local state = BinderUI.default_state(namespace.collection)
H.assert_equal(state.text_keys.title, "grdl_k_binder_title", "title key")
H.assert_equal(state.summary.currency_g, 25, "state summary currency")
H.assert_equal(#state.rows, 1, "state rows")
H.assert_equal(#state.queue_rows, 0, "no queue rows for empty queue")
H.assert_equal(state.revealed_count, 0, "no revealed count by default")

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
local adapter = { opened = 0, refreshed = 0 }
function adapter.open_overlay()
    adapter.opened = adapter.opened + 1
end
function adapter.refresh_overlay()
    adapter.refreshed = adapter.refreshed + 1
end

H.assert_true(BinderUI.install_runtime(namespace, runtime, adapter), "runtime callbacks installed")
runtime.FUNCS.grdl_open_binder()
H.assert_true(namespace.binder_ui_state ~= nil, "binder state stored")
H.assert_equal(adapter.opened, 1, "binder overlay opened")
H.assert_equal(namespace.binder_ui_state.grading_fees[raw_card.id], 15, "raw card grading fee exposed")

runtime.FUNCS.grdl_submit_grading({ config = { ref_table = { id = raw_card.id } } })
H.assert_equal(raw_card.status, "queued", "submit callback queues card")
H.assert_equal(namespace.collection.currency_g, 10, "submit callback charges fee")
H.assert_equal(save_count, 1, "successful submit saves config")
H.assert_equal(adapter.refreshed, 1, "submit refreshes overlay")
H.assert_equal(#namespace.binder_ui_state.queue_rows, 1, "queue row visible after submit")
H.assert_equal(namespace.binder_ui_state.queue_rows[1].card_id, raw_card.id, "queue row card id")
H.assert_equal(namespace.binder_ui_state.grading_fees[raw_card.id], nil, "queued card no longer offers a fee")

local expensive_card = Storage.add_raw_card(namespace.collection, {
    center_key = "j_rare",
    local_key = "rare_joker",
    rarity = "rare",
    edition = "negative",
    condition = mint_condition,
    acquired_at = 1001
})
runtime.FUNCS.grdl_submit_grading({ config = { ref_table = { id = expensive_card.id } } })
H.assert_equal(expensive_card.status, "raw", "failed submit keeps card raw")
H.assert_equal(namespace.collection.currency_g, 10, "failed submit keeps currency")
H.assert_equal(save_count, 1, "failed submit does not save")
H.assert_equal(adapter.refreshed, 2, "failed submit still refreshes overlay")
H.assert_equal(namespace.binder_ui_state.last_reason, "insufficient_funds", "failure reason surfaced")

namespace.collection.grading_queue[1].due_at = 900
local opened = BinderUI.open(namespace, 1000)
H.assert_equal(opened.revealed_count, 1, "due grading revealed on open")
H.assert_equal(raw_card.status, "graded", "card graded on binder open")
H.assert_equal(raw_card.grade, 10, "grade derived from hidden condition")
H.assert_equal(raw_card.cert_number, "000001", "cert number assigned on reveal")
H.assert_equal(raw_card.graded_at, 900, "graded timestamp uses due time")
H.assert_equal(#opened.queue_rows, 0, "queue cleared after reveal")
H.assert_equal(save_count, 2, "reveal saves config")

local reopened = BinderUI.open(namespace, 1001)
H.assert_equal(reopened.revealed_count, 0, "reopen reveals nothing new")
H.assert_equal(save_count, 2, "reopen without reveals does not save")

_G.SMODS = previous_smods_global

print("binder ui tests ok")
