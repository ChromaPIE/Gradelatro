local BuyoutUI = {}

local function load_src(path)
    return assert(SMODS.load_file("src/" .. path))()
end

local Binder = load_src("domain/binder.lua")
local Buyout = load_src("domain/buyout.lua")
local Persistence = load_src("core/persistence.lua")
local UICommon = load_src("ui/ui_common.lua")

local safe_localize = UICommon.localize_text
local safe_center_name = UICommon.center_name
local ui_text = UICommon.text_node
local row = UICommon.row
local col = UICommon.col
local event_candidate_id = UICommon.event_ref_id

local BUYOUT_PAGE_SIZE = 6

local TEXT_KEYS = {
    title = "grdl_k_buyout_title",
    subtitle = "grdl_k_buyout_subtitle",
    tab = "grdl_k_buyout_tab",
    selected = "grdl_k_selected_count",
    total = "grdl_k_buyout_total",
    price = "grdl_k_buyout_price",
    confirm = "grdl_b_confirm_buyout",
    skip = "grdl_b_skip_buyout",
    empty = "grdl_k_buyout_empty",
    blocked = "grdl_k_buyout_blocked"
}

local function copy_text_keys()
    local out = {}
    for key, value in pairs(TEXT_KEYS) do
        out[key] = value
    end
    return out
end

local function candidate_index(offer)
    local out = {}
    for _, candidate in ipairs((offer and offer.eligible) or {}) do
        out[candidate.id] = candidate
    end
    return out
end

local function remove_selected_id(state, id)
    for index, selected_id in ipairs(state.selected_ids) do
        if selected_id == id then
            table.remove(state.selected_ids, index)
            state.selected[id] = nil
            return true
        end
    end
    return false
end

function BuyoutUI.has_offer(offer)
    if not offer then return false end
    return #((offer and offer.eligible) or {}) > 0 or #((offer and offer.blocked) or {}) > 0
end

function BuyoutUI.default_state(offer)
    return {
        offer = offer or { eligible = {}, blocked = {} },
        selected_ids = {},
        selected = {},
        max_selection = (offer and offer.max_selection) or 5,
        text_keys = copy_text_keys(),
        page = 1,
        blocked_page = 1,
        buyout_tab = "eligible",
        last_reason = nil,
        confirmed = false
    }
end

function BuyoutUI.set_page(state, page)
    if not state then return nil end
    state.page = Binder.page((state.offer and state.offer.eligible) or {}, page, BUYOUT_PAGE_SIZE).page
    return state
end

function BuyoutUI.set_blocked_page(state, page)
    if not state then return nil end
    state.blocked_page = Binder.page((state.offer and state.offer.blocked) or {}, page, BUYOUT_PAGE_SIZE).page
    return state
end

function BuyoutUI.open(namespace)
    if not namespace or not BuyoutUI.has_offer(namespace.pending_buyout_offer) then return nil end
    namespace.buyout_ui_state = BuyoutUI.default_state(namespace.pending_buyout_offer)
    return namespace.buyout_ui_state
end

function BuyoutUI.is_selected(state, id)
    return not not (state and state.selected and state.selected[id])
end

function BuyoutUI.toggle_selection(state, id)
    if not state or not id then return false end
    if BuyoutUI.is_selected(state, id) then
        state.last_reason = nil
        return remove_selected_id(state, id)
    end

    local candidates = candidate_index(state.offer)
    if not candidates[id] then
        state.last_reason = "not_in_offer"
        return false
    end

    if #state.selected_ids >= state.max_selection then
        state.last_reason = "selection_limit"
        return false
    end

    state.selected[id] = true
    state.selected_ids[#state.selected_ids + 1] = id
    state.last_reason = nil
    return true
end

function BuyoutUI.total_selected_price(state)
    if not state then return 0 end
    local candidates = candidate_index(state.offer)
    local total = 0
    for _, id in ipairs(state.selected_ids or {}) do
        local candidate = candidates[id]
        total = total + math.floor((candidate and candidate.price) or 0)
    end
    return total
end

function BuyoutUI.summary(state, collection)
    return {
        selected_count = #(state and state.selected_ids or {}),
        max_selection = (state and state.max_selection) or 5,
        total_price = BuyoutUI.total_selected_price(state),
        currency_g = (collection and collection.currency_g) or 0
    }
end

local function reason_key(reason)
    return "grdl_k_reason_" .. tostring(reason or "unknown")
end

local function candidate_row(state, candidate)
    local selected = BuyoutUI.is_selected(state, candidate.id)
    local button_key = selected and "grdl_b_selected" or "grdl_b_select"
    local name = safe_center_name(candidate)
    return row({
        col({ ui_text(name, UICommon.fit_scale(name, 0.38, 18)) }, {
            align = "cl",
            minw = 3.2,
            collideable = true,
            func = "grdl_row_preview",
            ref_table = { center_key = candidate.center_key, edition = candidate.edition, tooltip = true }
        }),
        col({ ui_text(safe_localize("grdl_k_buyout_price", { candidate.price or 0 }), 0.36) }, { align = "cr", minw = 1.4 }),
        col({ UIBox_button({
            button = "grdl_toggle_buyout_card",
            label = { safe_localize(button_key) },
            ref_table = { id = candidate.id },
            minw = 1.5,
            maxw = 1.5,
            minh = 0.65,
            scale = 0.34,
            colour = selected and G.C.GREEN or G.C.BLUE,
            focus_args = { nav = "wide" }
        }) }, { align = "cr", minw = 1.7 })
    }, { align = "cm", padding = 0.05 })
end

local function blocked_row(candidate)
    return row({
        col({ ui_text(safe_center_name(candidate), 0.34, G.C.UI.TEXT_INACTIVE) }, {
            align = "cl",
            minw = 3.2,
            collideable = true,
            func = "grdl_row_preview",
            ref_table = { center_key = candidate.center_key, edition = candidate.edition, tooltip = true }
        }),
        col({ ui_text(safe_localize(reason_key(candidate.reason)), 0.32, G.C.UI.TEXT_INACTIVE) }, { align = "cr", minw = 2.8 })
    }, { align = "cm", padding = 0.03 })
end

local function action_buttons(state, summary)
    return row({
        UIBox_button({
            button = "grdl_confirm_buyout",
            label = {
                safe_localize(state.text_keys.confirm),
                safe_localize(state.text_keys.total, { summary.total_price })
            },
            minw = 2.6,
            maxw = 2.6,
            minh = 0.9,
            scale = 0.36,
            colour = G.C.GREEN,
            focus_args = { nav = "wide", snap_to = true }
        }),
        UIBox_button({
            button = "grdl_skip_buyout",
            label = { safe_localize(state.text_keys.skip) },
            minw = 2.6,
            maxw = 2.6,
            minh = 0.9,
            scale = 0.36,
            colour = G.C.RED,
            focus_args = { nav = "wide" }
        })
    }, { align = "cm", padding = 0.08 })
end

local function summary_row(state, summary)
    return row({
        UICommon.stat_chip(safe_localize(state.text_keys.selected, { summary.selected_count, summary.max_selection })),
        UICommon.stat_chip(safe_localize(state.text_keys.total, { summary.total_price })),
        UICommon.stat_chip(safe_localize("grdl_k_stat_g", { summary.currency_g }))
    }, { padding = 0.08 })
end

local function tab_root(nodes)
    return { n = G.UIT.ROOT, config = { align = "tm", colour = G.C.CLEAR, minw = 7.0, minh = 5.4, padding = 0.05 }, nodes = nodes }
end

local function eligible_tab_definition(namespace, state)
    return function()
        state.buyout_tab = "eligible"
        local offer = state.offer or {}
        local summary = BuyoutUI.summary(state, namespace.collection)
        local nodes = { summary_row(state, summary) }

        local view = Binder.page(offer.eligible or {}, state.page or 1, BUYOUT_PAGE_SIZE)
        state.page = view.page
        if view.total == 0 then
            nodes[#nodes + 1] = row({ ui_text(safe_localize(state.text_keys.empty), 0.36, G.C.UI.TEXT_INACTIVE) }, { padding = 0.3 })
        else
            for _, candidate in ipairs(view.items) do
                nodes[#nodes + 1] = candidate_row(state, candidate)
            end
        end
        local cycle = UICommon.page_cycle(view, "grdl_buyout_page")
        if cycle then nodes[#nodes + 1] = row({ cycle }, { padding = 0.04 }) end

        if state.last_reason then
            nodes[#nodes + 1] = row({ ui_text(safe_localize(reason_key(state.last_reason)), 0.34, G.C.RED) })
        end

        nodes[#nodes + 1] = action_buttons(state, summary)

        return tab_root(nodes)
    end
end

local function blocked_tab_definition(namespace, state)
    return function()
        state.buyout_tab = "blocked"
        local offer = state.offer or {}
        local summary = BuyoutUI.summary(state, namespace.collection)
        local nodes = { summary_row(state, summary) }
        local view = Binder.page(offer.blocked or {}, state.blocked_page or 1, BUYOUT_PAGE_SIZE)
        state.blocked_page = view.page
        if view.total == 0 then
            nodes[#nodes + 1] = row({ ui_text(safe_localize(state.text_keys.empty), 0.36, G.C.UI.TEXT_INACTIVE) }, { padding = 0.3 })
        else
            for _, candidate in ipairs(view.items) do
                nodes[#nodes + 1] = blocked_row(candidate)
            end
        end
        local cycle = UICommon.page_cycle(view, "grdl_buyout_blocked_page")
        if cycle then nodes[#nodes + 1] = row({ cycle }, { padding = 0.04 }) end
        nodes[#nodes + 1] = action_buttons(state, summary)
        return tab_root(nodes)
    end
end

function BuyoutUI.create_overlay_definition(namespace)
    namespace = namespace or rawget(_G, "Gradelatro") or {}
    local state = namespace.buyout_ui_state or BuyoutUI.open(namespace) or BuyoutUI.default_state(namespace.pending_buyout_offer)
    local rows = {
        row({ ui_text(safe_localize(state.text_keys.title), 0.55, G.C.WHITE) }),
        row({ ui_text(safe_localize(state.text_keys.subtitle), 0.34, G.C.UI.TEXT_LIGHT) }),
        row({
            create_tabs({
                tabs = {
                    {
                        label = safe_localize(state.text_keys.tab),
                        chosen = state.buyout_tab ~= "blocked",
                        tab_definition_function = eligible_tab_definition(namespace, state)
                    },
                    {
                        label = safe_localize(state.text_keys.blocked),
                        chosen = state.buyout_tab == "blocked",
                        tab_definition_function = blocked_tab_definition(namespace, state)
                    }
                },
                text_scale = 0.4
            })
        }, { padding = 0.05 })
    }

    return create_UIBox_generic_options({
        no_back = true,
        no_esc = true,
        minw = 7.2,
        padding = 0.12,
        colour = G.C.L_BLACK,
        outline_colour = G.C.RED,
        contents = rows
    })
end

local function default_adapter(runtime)
    runtime = runtime or rawget(_G, "G")
    return {
        open_overlay = function(namespace)
            if not runtime or not runtime.FUNCS or not runtime.FUNCS.overlay_menu then return end
            if runtime.SETTINGS then runtime.SETTINGS.paused = true end
            runtime.FUNCS.overlay_menu({
                definition = BuyoutUI.create_overlay_definition(namespace),
                config = { no_esc = true }
            })
        end,
        refresh_overlay = function(namespace)
            if not runtime or not runtime.FUNCS or not runtime.FUNCS.overlay_menu then return end
            runtime.FUNCS.overlay_menu({
                definition = BuyoutUI.create_overlay_definition(namespace),
                config = { no_esc = true }
            })
        end,
        close_overlay = function()
            if runtime and runtime.FUNCS and runtime.FUNCS.overlay_menu and rawget(_G, "create_UIBox_win") then
                runtime.FUNCS.overlay_menu({
                    definition = create_UIBox_win(),
                    config = { no_esc = true }
                })
            elseif runtime and runtime.FUNCS and runtime.FUNCS.exit_overlay_menu then
                runtime.FUNCS.exit_overlay_menu()
            end
        end
    }
end

function BuyoutUI.install_runtime(namespace, runtime, adapter)
    namespace = namespace or rawget(_G, "Gradelatro")
    runtime = runtime or rawget(_G, "G")
    if not namespace or not runtime or not runtime.FUNCS then return false end
    adapter = adapter or default_adapter(runtime)

    UICommon.install_preview(runtime.FUNCS)

    local function refresh_tab(state, event)
        local definition = state and state.buyout_tab == "blocked" and blocked_tab_definition(namespace, state) or eligible_tab_definition(namespace, state)
        if not UICommon.swap_tab_contents(definition) then
            if adapter.refresh_overlay then adapter.refresh_overlay(namespace, state, event) end
        end
    end

    runtime.FUNCS.grdl_open_buyout = function(event)
        local state = BuyoutUI.open(namespace)
        if state and adapter.open_overlay then adapter.open_overlay(namespace, state, event) end
    end

    runtime.FUNCS.grdl_toggle_buyout_card = function(event)
        local state = namespace.buyout_ui_state or BuyoutUI.open(namespace)
        if not state then return end
        BuyoutUI.toggle_selection(state, event_candidate_id(event))
        refresh_tab(state, event)
    end

    runtime.FUNCS.grdl_buyout_page = function(event)
        if not event or not event.cycle_config then return end
        local state = namespace.buyout_ui_state
        if not state then return end
        BuyoutUI.set_page(state, event.cycle_config.current_option)
        refresh_tab(state, event)
    end

    runtime.FUNCS.grdl_buyout_blocked_page = function(event)
        if not event or not event.cycle_config then return end
        local state = namespace.buyout_ui_state
        if not state then return end
        BuyoutUI.set_blocked_page(state, event.cycle_config.current_option)
        state.buyout_tab = "blocked"
        refresh_tab(state, event)
    end

    runtime.FUNCS.grdl_confirm_buyout = function(event)
        local state = namespace.buyout_ui_state
        local result = BuyoutUI.confirm(namespace, state, os.time())
        if result.ok then
            if adapter.close_overlay then adapter.close_overlay(namespace, state, event) end
        else
            refresh_tab(state, event)
        end
    end

    runtime.FUNCS.grdl_skip_buyout = function(event)
        BuyoutUI.skip(namespace)
        if adapter.close_overlay then adapter.close_overlay(namespace, nil, event) end
    end

    return true
end

function BuyoutUI.confirm(namespace, state, now)
    if not namespace then return { ok = false, reason = "missing_namespace" } end
    state = state or namespace.buyout_ui_state
    if not state then return { ok = false, reason = "missing_state" } end
    if #state.selected_ids == 0 then
        state.last_reason = "no_selection"
        return { ok = false, reason = "no_selection" }
    end
    if not namespace.collection then
        state.last_reason = "missing_collection"
        return { ok = false, reason = "missing_collection" }
    end

    local offer = state.offer or namespace.pending_buyout_offer or {}
    local result = Buyout.purchase(namespace.config or {}, namespace.collection, {
        candidates = offer.eligible or {},
        selected_ids = state.selected_ids,
        max_selection = state.max_selection,
        now = now or os.time(),
        acquired_year = offer.acquired_year,
        run_id = offer.run_id,
        run_started_at = offer.run_started_at
    })

    namespace.last_buyout_result = result
    if result.ok then
        namespace.pending_buyout_offer = nil
        namespace.buyout_ui_state = nil
        namespace.last_save_ok = Persistence.save(namespace)
        state.confirmed = true
        state.last_reason = nil
    else
        state.last_reason = result.reason
    end
    return result
end

function BuyoutUI.skip(namespace)
    if not namespace then return { ok = false, reason = "missing_namespace" } end
    namespace.pending_buyout_offer = nil
    namespace.buyout_ui_state = nil
    return { ok = true, skipped = true }
end

return BuyoutUI
