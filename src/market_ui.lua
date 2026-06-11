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

local HEAT_PAGE_SIZE = 10

local TEXT_KEYS = {
    title = "grdl_k_market_title",
    empty = "grdl_k_market_empty",
    tab_trends = "grdl_k_tab_trends"
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
        heat_rows = heat_rows,
        heat_page = 1
    }
    return namespace.market_ui_state
end

function MarketUI.set_page(namespace, page)
    local state = namespace and namespace.market_ui_state or nil
    if not state then return nil end
    state.heat_page = Binder.page(state.heat_rows, page, HEAT_PAGE_SIZE).page
    return state
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

local function heat_cells(entry)
    return {
        col({ ui_text(entry.series_key, UICommon.fit_scale(entry.series_key, 0.26, 20)) }, { align = "cl", minw = 2.2 }),
        col({ ui_text(safe_localize(entry.label_key), 0.26, heat_colour(entry.label)) }, { align = "cl", minw = 0.9 })
    }
end

local function heat_pair_row(left, right)
    local nodes = heat_cells(left)
    if right then
        for _, cell in ipairs(heat_cells(right)) do
            nodes[#nodes + 1] = cell
        end
    end
    return row(nodes, { padding = 0.04, align = "cl" })
end

local function market_tab_root(nodes)
    return { n = G.UIT.ROOT, config = { align = "tm", colour = G.C.CLEAR, minw = 6.6, minh = 5.0, padding = 0.05 }, nodes = nodes }
end

local function trends_tab_definition(state)
    return function()
        local view = Binder.page(state.heat_rows, state.heat_page, HEAT_PAGE_SIZE)
        state.heat_page = view.page
        local nodes = {}
        if view.total == 0 then
            nodes[#nodes + 1] = row({ ui_text(safe_localize(state.text_keys.empty), 0.34, G.C.UI.TEXT_INACTIVE) })
        else
            for index = 1, #view.items, 2 do
                nodes[#nodes + 1] = heat_pair_row(view.items[index], view.items[index + 1])
            end
        end
        local cycle = UICommon.page_cycle(view, "grdl_market_heat_page")
        if cycle then nodes[#nodes + 1] = row({ cycle }, { padding = 0.05 }) end
        return market_tab_root(nodes)
    end
end

function MarketUI.create_overlay_definition(namespace)
    namespace = namespace or rawget(_G, "Gradelatro") or {}
    local state = namespace.market_ui_state or MarketUI.open(namespace)
    if not state then
        return create_UIBox_generic_options({ back_func = "grdl_open_binder", contents = {} })
    end

    local rows = {
        row({ ui_text(safe_localize(state.text_keys.title), 0.55, G.C.WHITE) }),
        UICommon.stat_chips(state.summary)
    }

    rows[#rows + 1] = row({
        create_tabs({
            tabs = {
                {
                    label = safe_localize(state.text_keys.tab_trends),
                    chosen = true,
                    tab_definition_function = trends_tab_definition(state)
                }
            },
            text_scale = 0.4
        })
    }, { padding = 0.05 })

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

    UICommon.install_preview(runtime.FUNCS)

    runtime.FUNCS.grdl_open_market = function(event)
        local state = MarketUI.open(namespace)
        if state and adapter.open_market then adapter.open_market(namespace, state, event) end
    end

    runtime.FUNCS.grdl_market_heat_page = function(event)
        if not event or not event.cycle_config then return end
        MarketUI.set_page(namespace, event.cycle_config.current_option)
        local state = namespace.market_ui_state
        if not (state and UICommon.swap_tab_contents(trends_tab_definition(state))) then
            if adapter.refresh_market then adapter.refresh_market(namespace, state, event) end
        end
    end

    return true
end

return MarketUI
