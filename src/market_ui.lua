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

local TREND_PAGE_SIZE = 10
local TREND_ROWS = { 5, 5 }
local CAROUSEL_INTERVAL = 2

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

local function runtime_catalog(namespace)
    local runtime = rawget(_G, "G")
    if not runtime or not runtime.P_CENTERS or not namespace.config then return {} end
    local smods = rawget(_G, "SMODS")
    local ok, catalog = pcall(Catalog.discover, namespace.config, runtime.P_CENTERS, smods and smods.Mods or nil)
    if not ok then return {} end
    return catalog
end

function MarketUI.open(namespace, now)
    if not namespace or not namespace.collection then return nil end
    now = now or os.time()

    local catalog = runtime_catalog(namespace)
    if namespace.config and #catalog > 0 then
        local series_ids = {}
        local seen = {}
        for _, entry in ipairs(catalog) do
            if not seen[entry.series_id] then
                seen[entry.series_id] = true
                series_ids[#series_ids + 1] = entry.series_id
            end
        end
        local refresh = Market.refresh(namespace.config, namespace.collection, { series_ids = series_ids, now = now })
        if refresh.refreshed then
            namespace.last_save_ok = Persistence.save(namespace)
        end
    end

    namespace.market_ui_state = {
        text_keys = copy_text_keys(),
        summary = Binder.summary(namespace.collection),
        trend_slots = Market.trend_slots(namespace.collection, catalog),
        heat_page = 1
    }
    return namespace.market_ui_state
end

function MarketUI.set_page(namespace, page)
    local state = namespace and namespace.market_ui_state or nil
    if not state then return nil end
    state.heat_page = Binder.page(state.trend_slots, page, TREND_PAGE_SIZE).page
    return state
end

local function attention_colour()
    local runtime = rawget(_G, "G")
    if runtime and runtime.ARGS and runtime.ARGS.LOC_COLOURS and runtime.ARGS.LOC_COLOURS.attention then
        return runtime.ARGS.LOC_COLOURS.attention
    end
    return G.C.GOLD
end

local function trend_info_line(label_text, value_text, value_colour)
    return row({
        col({ ui_text(label_text, 0.28, G.C.UI.TEXT_DARK) }, { align = "cl", minw = 1.2 }),
        col({ ui_text(value_text, 0.28, value_colour or G.C.UI.TEXT_DARK) }, { align = "cr", minw = 1.3 })
    }, { padding = 0.02 })
end

local function trends_popup(slot)
    local desc_lines = {
        trend_info_line(safe_localize("grdl_k_trend_heat"), safe_localize(slot.label_key), attention_colour()),
        trend_info_line(safe_localize("grdl_k_trend_owned"), safe_localize("grdl_k_trend_owned_v", { slot.owned, slot.graded })),
        trend_info_line(safe_localize("grdl_k_trend_pool"), safe_localize("grdl_k_trend_pool_v", { slot.pool_size }))
    }
    if slot.event_active then
        desc_lines[#desc_lines + 1] = trend_info_line(safe_localize("grdl_k_trend_event"), safe_localize("grdl_k_trend_event_on"), G.C.RED)
    end

    return { n = G.UIT.ROOT, config = { align = "cm", colour = G.C.CLEAR }, nodes = {
        { n = G.UIT.R, config = { align = "cm", padding = 0.05, r = 0.12, colour = rawget(_G, "lighten") and lighten(G.C.JOKER_GREY, 0.5) or G.C.JOKER_GREY, emboss = 0.07 }, nodes = {
            { n = G.UIT.R, config = { align = "cm", padding = 0.07, r = 0.1, colour = G.C.L_BLACK }, nodes = {
                row({ ui_text(slot.mod_name, 0.4, G.C.WHITE) }, { padding = 0.02 }),
                row({ ui_text(slot.series_key, 0.3, G.C.UI.TEXT_LIGHT) }, { padding = 0.02 }),
                { n = G.UIT.R, config = { align = "cm", padding = 0.06, r = 0.06, colour = G.C.WHITE }, nodes = desc_lines }
            } }
        } }
    } }
end

local function build_trend_card(area, slot)
    local centers = G.P_CENTERS or {}
    local center = centers[slot.center_keys[1]]
    if not center then return nil end

    local card = Card(area.T.x + area.T.w / 2, area.T.y, G.CARD_W, G.CARD_H, (G.P_CARDS and G.P_CARDS.empty or nil), center)
    UICommon.suppress_selection(card)

    card.grdl_carousel = { keys = slot.center_keys, index = 1, timer = 0 }
    local original_update = card.update
    card.update = function(self, dt)
        original_update(self, dt)
        local carousel = self.grdl_carousel
        if not carousel or #carousel.keys < 2 then return end
        carousel.timer = (carousel.timer or 0) + (dt or 0)
        if carousel.timer >= CAROUSEL_INTERVAL then
            carousel.timer = carousel.timer - CAROUSEL_INTERVAL
            carousel.index = carousel.index % #carousel.keys + 1
            local next_center = centers[carousel.keys[carousel.index]]
            if next_center then
                pcall(self.set_sprites, self, next_center)
            end
        end
    end

    card.hover = function(self)
        self.config.h_popup = trends_popup(slot)
        self.config.h_popup_config = self:align_h_popup()
        if rawget(_G, "Node") then Node.hover(self) end
    end
    card.stop_hover = function(self)
        if rawget(_G, "Node") then Node.stop_hover(self) end
    end

    area:emplace(card)
    return card
end

local function market_tab_root(nodes)
    return { n = G.UIT.ROOT, config = { align = "tm", colour = G.C.CLEAR, minw = 6.6, minh = 5.0, padding = 0.05 }, nodes = nodes }
end

local function trends_tab_definition(state)
    return function()
        local view = Binder.page(state.trend_slots, state.heat_page, TREND_PAGE_SIZE)
        state.heat_page = view.page
        local nodes = {}
        if view.total == 0 then
            nodes[#nodes + 1] = row({ ui_text(safe_localize(state.text_keys.empty), 0.34, G.C.UI.TEXT_INACTIVE) })
        elseif rawget(_G, "CardArea") and rawget(_G, "Card") and rawget(_G, "G") and G.P_CENTERS then
            local deck_tables = {}
            local slot_index = 0
            for row_index = 1, #TREND_ROWS do
                local count = TREND_ROWS[row_index]
                local area = CardArea(
                    G.ROOM.T.x + 0.2 * G.ROOM.T.w / 2, G.ROOM.T.h,
                    (count + 0.25) * G.CARD_W,
                    0.95 * G.CARD_H,
                    { card_limit = count, type = "title", highlight_limit = 0, collection = true })
                for _ = 1, count do
                    slot_index = slot_index + 1
                    local slot = view.items[slot_index]
                    if slot then build_trend_card(area, slot) end
                end
                deck_tables[#deck_tables + 1] = row({ { n = G.UIT.O, config = { object = area } } }, { padding = 0.05, no_fill = true })
            end
            nodes[#nodes + 1] = { n = G.UIT.R, config = { align = "cm", r = 0.1, colour = G.C.BLACK, emboss = 0.05 }, nodes = deck_tables }
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
