local H = dofile("tests/test_helper.lua")
local Storage = dofile("src/storage.lua")
local BinderUI = dofile("src/binder_ui.lua")

local namespace = {
    collection = Storage.normalize({
        currency_g = 25,
        cards = {
            {
                id = "grdl_1",
                status = "raw",
                center_key = "j_joker",
                local_key = "joker",
                edition = "base",
                acquired_at = 1000
            }
        }
    })
}

local state = BinderUI.default_state(namespace.collection)
H.assert_equal(state.text_keys.title, "grdl_k_binder_title", "title key")
H.assert_equal(state.summary.currency_g, 25, "state summary currency")
H.assert_equal(#state.rows, 1, "state rows")

local runtime = { FUNCS = {} }
local adapter = { opened = 0 }
function adapter.open_overlay()
    adapter.opened = adapter.opened + 1
end

H.assert_true(BinderUI.install_runtime(namespace, runtime, adapter), "runtime callbacks installed")
runtime.FUNCS.grdl_open_binder()
H.assert_true(namespace.binder_ui_state ~= nil, "binder state stored")
H.assert_equal(adapter.opened, 1, "binder overlay opened")

print("binder ui tests ok")
