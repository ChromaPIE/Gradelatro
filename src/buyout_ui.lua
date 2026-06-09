local BuyoutUI = {}

local function load_src(path)
    if rawget(_G, "SMODS") and SMODS.load_file then
        return assert(SMODS.load_file("src/" .. path))()
    end
    return dofile("src/" .. path)
end

local Buyout = load_src("buyout.lua")

local TEXT_KEYS = {
    title = "grdl_k_buyout_title",
    subtitle = "grdl_k_buyout_subtitle",
    currency = "grdl_k_currency",
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
        last_reason = nil,
        confirmed = false
    }
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

local function event_candidate_id(event)
    return event
        and event.config
        and event.config.ref_table
        and event.config.ref_table.id
        or nil
end

local function safe_localize(key, vars)
    if rawget(_G, "localize") then
        if vars then
            local ok, value = pcall(localize, { type = "variable", key = key, vars = vars })
            if ok and value then return value end
        end
        local ok, value = pcall(localize, key)
        if ok and value then return value end
    end
    return key
end

local function safe_center_name(candidate)
    if rawget(_G, "localize") then
        local ok, value = pcall(localize, {
            type = "name_text",
            key = candidate.center_key,
            set = "Joker"
        })
        if ok and value then return value end
    end
    return tostring(candidate.local_key or candidate.center_key or candidate.id)
end

local function reason_key(reason)
    return "grdl_k_reason_" .. tostring(reason or "unknown")
end

local function ui_text(text, scale, colour)
    return { n = G.UIT.T, config = { text = text, scale = scale or 0.35, colour = colour or G.C.UI.TEXT_LIGHT } }
end

local function row(nodes, config)
    config = config or {}
    config.align = config.align or "cm"
    config.padding = config.padding or 0.04
    return { n = G.UIT.R, config = config, nodes = nodes }
end

local function col(nodes, config)
    config = config or {}
    config.align = config.align or "cm"
    config.padding = config.padding or 0.04
    return { n = G.UIT.C, config = config, nodes = nodes }
end

local function candidate_row(state, candidate)
    local selected = BuyoutUI.is_selected(state, candidate.id)
    local button_key = selected and "grdl_b_selected" or "grdl_b_select"
    return row({
        col({ ui_text(safe_center_name(candidate), 0.35) }, { align = "cl", minw = 3.2 }),
        col({ ui_text(safe_localize("grdl_k_buyout_price", { candidate.price or 0 }), 0.32) }, { align = "cr", minw = 1.4 }),
        UIBox_button({
            button = "grdl_toggle_buyout_card",
            label = { safe_localize(button_key) },
            ref_table = { id = candidate.id },
            minw = 1.4,
            maxw = 1.4,
            minh = 0.65,
            scale = 0.32,
            colour = selected and G.C.GREEN or G.C.BLUE,
            focus_args = { nav = "wide" }
        })
    }, { align = "cm" })
end

local function blocked_row(candidate)
    return row({
        col({ ui_text(safe_center_name(candidate), 0.32, G.C.UI.TEXT_INACTIVE) }, { align = "cl", minw = 3.2 }),
        col({ ui_text(safe_localize(reason_key(candidate.reason)), 0.3, G.C.UI.TEXT_INACTIVE) }, { align = "cr", minw = 2.8 })
    }, { align = "cm" })
end

function BuyoutUI.create_overlay_definition(namespace)
    namespace = namespace or rawget(_G, "Gradelatro") or {}
    local state = namespace.buyout_ui_state or BuyoutUI.open(namespace) or BuyoutUI.default_state(namespace.pending_buyout_offer)
    local offer = state.offer or {}
    local summary = BuyoutUI.summary(state, namespace.collection)
    local rows = {
        row({ ui_text(safe_localize(state.text_keys.title), 0.55, G.C.WHITE) }),
        row({ ui_text(safe_localize(state.text_keys.subtitle), 0.32, G.C.UI.TEXT_LIGHT) }),
        row({
            ui_text(safe_localize("grdl_k_buyout_summary", {
                summary.selected_count,
                summary.max_selection,
                summary.total_price,
                summary.currency_g
            }), 0.34, G.C.WHITE)
        })
    }

    if #(offer.eligible or {}) == 0 then
        rows[#rows + 1] = row({ ui_text(safe_localize(state.text_keys.empty), 0.34, G.C.UI.TEXT_INACTIVE) })
    else
        for _, candidate in ipairs(offer.eligible or {}) do
            rows[#rows + 1] = candidate_row(state, candidate)
        end
    end

    if state.last_reason then
        rows[#rows + 1] = row({ ui_text(safe_localize(reason_key(state.last_reason)), 0.32, G.C.RED) })
    end

    if #(offer.blocked or {}) > 0 then
        rows[#rows + 1] = row({ ui_text(safe_localize(state.text_keys.blocked), 0.34, G.C.UI.TEXT_LIGHT) })
        for _, candidate in ipairs(offer.blocked or {}) do
            rows[#rows + 1] = blocked_row(candidate)
        end
    end

    rows[#rows + 1] = row({
        UIBox_button({
            button = "grdl_confirm_buyout",
            label = {
                safe_localize(state.text_keys.confirm),
                safe_localize("grdl_k_buyout_total", { summary.total_price })
            },
            minw = 2.4,
            maxw = 2.4,
            minh = 0.9,
            scale = 0.34,
            colour = G.C.GREEN,
            focus_args = { nav = "wide", snap_to = true }
        }),
        UIBox_button({
            button = "grdl_skip_buyout",
            label = { safe_localize(state.text_keys.skip) },
            minw = 2.4,
            maxw = 2.4,
            minh = 0.9,
            scale = 0.34,
            colour = G.C.RED,
            focus_args = { nav = "wide" }
        })
    }, { align = "cm", padding = 0.08 })

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

    runtime.FUNCS.grdl_open_buyout = function(event)
        local state = BuyoutUI.open(namespace)
        if state and adapter.open_overlay then adapter.open_overlay(namespace, state, event) end
    end

    runtime.FUNCS.grdl_toggle_buyout_card = function(event)
        local state = namespace.buyout_ui_state or BuyoutUI.open(namespace)
        if not state then return end
        BuyoutUI.toggle_selection(state, event_candidate_id(event))
        if adapter.refresh_overlay then adapter.refresh_overlay(namespace, state, event) end
    end

    runtime.FUNCS.grdl_confirm_buyout = function(event)
        local state = namespace.buyout_ui_state
        local result = BuyoutUI.confirm(namespace, state, os.time())
        if result.ok then
            if adapter.close_overlay then adapter.close_overlay(namespace, state, event) end
        elseif adapter.refresh_overlay then
            adapter.refresh_overlay(namespace, state, event)
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
