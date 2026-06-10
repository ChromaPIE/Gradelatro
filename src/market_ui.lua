local MarketUI = {}

local function load_src(path)
    if rawget(_G, "SMODS") and SMODS.load_file then
        return assert(SMODS.load_file("src/" .. path))()
    end
    return dofile("src/" .. path)
end

local Binder = load_src("binder.lua")
local Catalog = load_src("catalog.lua")
local Market = load_src("market.lua")
local Persistence = load_src("persistence.lua")
local UICommon = load_src("ui_common.lua")

local safe_localize = UICommon.localize_text
local center_name = UICommon.center_name
local ui_text = UICommon.text_node
local row = UICommon.row
local col = UICommon.col
local event_card_id = UICommon.event_ref_id

local TEXT_KEYS = {
    title = "grdl_k_market_title",
    empty = "grdl_k_market_empty",
    heat_title = "grdl_k_market_heat_title",
    sell = "grdl_b_sell",
    confirm = "grdl_b_confirm_sell"
}

local function copy_text_keys()
    local out = {}
    for key, value in pairs(TEXT_KEYS) do
        out[key] = value
    end
    return out
end

local function runtime_series(namespace)
    local runtime = rawget(_G, "G")
    if not runtime or not runtime.P_CENTERS or not namespace.config then return {} end
    local smods = rawget(_G, "SMODS")
    local ok, catalog = pcall(Catalog.discover, namespace.config, runtime.P_CENTERS, smods and smods.Mods or nil)
    if not ok then return {} end
    return Catalog.series(catalog)
end

function MarketUI.open(namespace, now)
    if not namespace or not namespace.collection then return nil end
    now = now or os.time()

    local series = runtime_series(namespace)
    if namespace.config and #series > 0 then
        local series_ids = {}
        for _, entry in ipairs(series) do
            series_ids[#series_ids + 1] = entry.series_id
        end
        local refresh = Market.refresh(namespace.config, namespace.collection, { series_ids = series_ids, now = now })
        if refresh.refreshed then
            namespace.last_save_ok = Persistence.save(namespace)
        end
    end

    local heat_rows = {}
    for _, entry in ipairs(series) do
        heat_rows[#heat_rows + 1] = {
            series_key = entry.series_key,
            label = Market.trend_label(Market.heat_for(namespace.collection, entry.series_id)),
            label_key = "grdl_k_heat_" .. Market.trend_label(Market.heat_for(namespace.collection, entry.series_id))
        }
    end

    namespace.market_ui_state = {
        text_keys = copy_text_keys(),
        summary = Binder.summary(namespace.collection),
        rows = namespace.config and Market.sell_rows(namespace.config, namespace.collection) or {},
        heat_rows = heat_rows,
        pending_sell_id = nil,
        last_reason = nil,
        last_reason_text = "",
        sold_text = ""
    }
    return namespace.market_ui_state
end

function MarketUI.request_sell(namespace, card_id, now)
    if not namespace or not namespace.collection then
        return { ok = false, reason = "missing_collection" }
    end
    if not namespace.config then
        return { ok = false, reason = "missing_config" }
    end
    now = now or os.time()

    local state = namespace.market_ui_state or MarketUI.open(namespace, now)
    if not state then return { ok = false, reason = "missing_state" } end
    if not card_id then
        return { ok = false, reason = "card_not_found" }
    end

    if state.pending_sell_id ~= card_id then
        state.pending_sell_id = card_id
        state.last_reason = nil
        state.last_reason_text = ""
        return { ok = true, pending = true }
    end

    local result = Market.sell(namespace.config, namespace.collection, { card_id = card_id, now = now })
    namespace.last_market_result = result

    if result.ok then
        namespace.last_save_ok = Persistence.save(namespace)
        local sold_text = safe_localize("grdl_k_market_sold", { result.price })
        MarketUI.open(namespace, now)
        namespace.market_ui_state.sold_text = sold_text
    else
        state.pending_sell_id = nil
        state.last_reason = result.reason
        state.last_reason_text = safe_localize("grdl_k_reason_" .. tostring(result.reason))
    end
    return result
end

local HEAT_COLOURS = {
    hot = "RED",
    rising = "GOLD",
    stable = "WHITE",
    cooling = "BLUE"
}

local function heat_colour(label)
    return G.C[HEAT_COLOURS[label] or "WHITE"] or G.C.WHITE
end

local function heat_row(entry)
    return row({
        col({ ui_text(entry.series_key, 0.3) }, { align = "cl", minw = 3.2 }),
        col({ ui_text(safe_localize(entry.label_key), 0.3, heat_colour(entry.label)) }, { align = "cr", minw = 1.4 })
    }, { padding = 0.04 })
end

local function status_text(row_data)
    if row_data.status == "graded" and row_data.grade then
        return "PSA " .. tostring(row_data.grade)
    end
    return safe_localize("grdl_k_status_raw")
end

local function sell_row(state, row_data)
    local pending = state.pending_sell_id == row_data.id
    local name = center_name(row_data)
    return row({
        col({ ui_text(name, UICommon.fit_scale(name, 0.32, 18)) }, { align = "cl", minw = 2.2 }),
        col({ ui_text(status_text(row_data), 0.28) }, { align = "cl", minw = 1.0 }),
        col({ ui_text(safe_localize("grdl_k_grading_fee", { row_data.quote }), 0.3, G.C.GOLD) }, { align = "cr", minw = 0.9 }),
        col({
            UIBox_button({
                button = "grdl_market_sell",
                label = { safe_localize(pending and state.text_keys.confirm or state.text_keys.sell) },
                ref_table = { id = row_data.id },
                minw = 1.1,
                maxw = 1.1,
                minh = 0.55,
                scale = 0.3,
                colour = pending and G.C.RED or G.C.BLUE,
                focus_args = { nav = "wide" }
            })
        }, { align = "cm", minw = 1.2 })
    }, { padding = 0.05 })
end

function MarketUI.create_overlay_definition(namespace)
    namespace = namespace or rawget(_G, "Gradelatro") or {}
    local state = namespace.market_ui_state or MarketUI.open(namespace)
    if not state then
        return create_UIBox_generic_options({ back_func = "grdl_open_binder", contents = {} })
    end

    local rows = {
        row({ ui_text(safe_localize(state.text_keys.title), 0.55, G.C.WHITE) }),
        UICommon.stat_chips(state.summary),
        row({ { n = G.UIT.T, config = { ref_table = state, ref_value = "sold_text", scale = 0.32, colour = G.C.GOLD } } })
    }

    if #state.rows == 0 then
        rows[#rows + 1] = row({ ui_text(safe_localize(state.text_keys.empty), 0.34, G.C.UI.TEXT_INACTIVE) })
    else
        for _, entry in ipairs(state.rows) do
            rows[#rows + 1] = sell_row(state, entry)
        end
    end

    if #state.heat_rows > 0 then
        rows[#rows + 1] = row({ ui_text(safe_localize(state.text_keys.heat_title), 0.4, G.C.WHITE) }, { padding = 0.08 })
        for _, entry in ipairs(state.heat_rows) do
            rows[#rows + 1] = heat_row(entry)
        end
    end

    rows[#rows + 1] = row({ { n = G.UIT.T, config = { ref_table = state, ref_value = "last_reason_text", scale = 0.3, colour = G.C.RED } } })

    return create_UIBox_generic_options({
        back_func = "grdl_open_binder",
        minw = 7.2,
        padding = 0.12,
        colour = G.C.L_BLACK,
        outline_colour = G.C.RED,
        contents = rows
    })
end

local function default_adapter(runtime)
    runtime = runtime or rawget(_G, "G")
    local function show(definition)
        if not runtime or not runtime.FUNCS or not runtime.FUNCS.overlay_menu then return end
        if runtime.SETTINGS then runtime.SETTINGS.paused = true end
        runtime.FUNCS.overlay_menu({ definition = definition })
    end
    return {
        open_market = function(namespace)
            show(MarketUI.create_overlay_definition(namespace))
        end,
        refresh_market = function(namespace)
            show(MarketUI.create_overlay_definition(namespace))
        end,
        notify_failure = function()
            if rawget(_G, "play_sound") then
                pcall(play_sound, "tarot2", 0.76, 0.4)
            end
        end
    }
end

function MarketUI.install_runtime(namespace, runtime, adapter)
    namespace = namespace or rawget(_G, "Gradelatro")
    runtime = runtime or rawget(_G, "G")
    if not namespace or not runtime or not runtime.FUNCS then return false end
    adapter = adapter or default_adapter(runtime)

    runtime.FUNCS.grdl_open_market = function(event)
        local state = MarketUI.open(namespace)
        if state and adapter.open_market then adapter.open_market(namespace, state, event) end
    end

    runtime.FUNCS.grdl_market_sell = function(event)
        local result = MarketUI.request_sell(namespace, event_card_id(event), os.time())
        if result.ok then
            if adapter.refresh_market then adapter.refresh_market(namespace, namespace.market_ui_state, event) end
        elseif adapter.notify_failure then
            adapter.notify_failure(namespace, namespace.market_ui_state, event)
        end
    end

    return true
end

return MarketUI
