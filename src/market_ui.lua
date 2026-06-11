local MarketUI = {}

local function load_src(path)
    if rawget(_G, "SMODS") and SMODS.load_file then
        return assert(SMODS.load_file("src/" .. path))()
    end
    return dofile("src/" .. path)
end

local Binder = load_src("binder.lua")
local BlackMarket = load_src("black_market.lua")
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
    tab_blackmarket = "grdl_k_tab_blackmarket",
    tab_trends = "grdl_k_tab_trends",
    bm_locked = "grdl_k_bm_locked",
    buy = "grdl_b_buy"
}

local function pick_quip(seed)
    local quips = {}
    for index = 1, 30 do
        local key = "grdl_quip_bm_" .. tostring(index)
        local text = safe_localize(key)
        if text == key then break end
        quips[#quips + 1] = text
    end
    if #quips == 0 then return "" end
    return quips[(math.floor(seed or 0) % #quips) + 1]
end

local function copy_text_keys()
    local out = {}
    for key, value in pairs(TEXT_KEYS) do
        out[key] = value
    end
    return out
end

local function runtime_catalog(namespace)
    return UICommon.discover_catalog(namespace)
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

    local offers = BlackMarket.offers(namespace.collection)
    namespace.market_ui_state = {
        text_keys = copy_text_keys(),
        summary = Binder.summary(namespace.collection),
        trend_slots = Market.trend_slots(namespace.collection, catalog),
        heat_page = 1,
        market_tab = "blackmarket",
        bm_locked = offers == nil,
        bm_offers = offers,
        bm_boss_key = BlackMarket.boss_key(namespace.collection),
        bm_quip = pick_quip(now),
        bm_text = ""
    }
    return namespace.market_ui_state
end

function MarketUI.buy(namespace, slot, now)
    if not namespace or not namespace.collection then
        return { ok = false, reason = "missing_collection" }
    end
    if not namespace.config then
        return { ok = false, reason = "missing_config" }
    end

    local result = BlackMarket.purchase(namespace.config, namespace.collection, { slot = slot, now = now or os.time() })
    namespace.last_bm_result = result
    local state = namespace.market_ui_state
    if result.ok then
        namespace.last_save_ok = Persistence.save(namespace)
        if state then state.bm_text = safe_localize("grdl_k_bm_bought") end
    elseif state then
        state.bm_text = safe_localize("grdl_k_reason_" .. tostring(result.reason))
    end
    return result
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

local function trend_line_cell(text, side, colour)
    return { n = G.UIT.R, config = { align = side, minh = 0.36, padding = 0.01 }, nodes = {
        ui_text(text, 0.32, colour or G.C.UI.TEXT_DARK)
    } }
end

local function trends_popup(slot)
    local labels = {
        trend_line_cell(safe_localize("grdl_k_trend_heat"), "cl"),
        trend_line_cell(safe_localize("grdl_k_trend_owned"), "cl"),
        trend_line_cell(safe_localize("grdl_k_trend_pool"), "cl")
    }
    local values = {
        trend_line_cell(safe_localize(slot.label_key), "cr", attention_colour()),
        trend_line_cell(safe_localize("grdl_k_trend_owned_v", { slot.owned, slot.graded }), "cr"),
        trend_line_cell(safe_localize("grdl_k_trend_pool_v", { slot.pool_size }), "cr")
    }
    if slot.event_active then
        labels[#labels + 1] = trend_line_cell(safe_localize("grdl_k_trend_event"), "cl")
        values[#values + 1] = trend_line_cell(safe_localize("grdl_k_trend_event_on"), "cr", G.C.RED)
    end

    return { n = G.UIT.ROOT, config = { align = "cm", colour = G.C.CLEAR }, nodes = {
        { n = G.UIT.R, config = { align = "cm", padding = 0.05, r = 0.12, colour = rawget(_G, "lighten") and lighten(G.C.JOKER_GREY, 0.5) or G.C.JOKER_GREY, emboss = 0.07 }, nodes = {
            { n = G.UIT.R, config = { align = "cm", padding = 0.07, r = 0.1, colour = G.C.L_BLACK }, nodes = {
                row({ ui_text(slot.mod_name, 0.44, G.C.WHITE) }, { padding = 0.02 }),
                row({ ui_text(slot.series_key, 0.34, G.C.UI.TEXT_LIGHT) }, { padding = 0.02 }),
                { n = G.UIT.R, config = { align = "cm", padding = 0.06, r = 0.06, colour = G.C.WHITE }, nodes = {
                    { n = G.UIT.C, config = { align = "cl", padding = 0.01 }, nodes = labels },
                    { n = G.UIT.C, config = { align = "cm", minw = 0.35 }, nodes = {} },
                    { n = G.UIT.C, config = { align = "cr", padding = 0.01 }, nodes = values }
                } }
            } }
        } }
    } }
end

local function build_trend_card(area, slot, delay_flag)
    local centers = G.P_CENTERS or {}
    local center = centers[slot.center_keys[1]]
    if not center then return nil end

    local card = Card(area.T.x + area.T.w / 2, area.T.y, G.CARD_W, G.CARD_H, (G.P_CARDS and G.P_CARDS.empty or nil), center)
    UICommon.suppress_selection(card)

    card.grdl_carousel = { keys = slot.center_keys, index = 1 }

    card.hover = function(self)
        self.config.h_popup = trends_popup(slot)
        self.config.h_popup_config = self:align_h_popup()
        if rawget(_G, "Node") then Node.hover(self) end
    end
    card.stop_hover = function(self)
        if rawget(_G, "Node") then Node.stop_hover(self) end
    end

    area:emplace(card)
    if card.start_materialize then
        pcall(card.start_materialize, card, nil, delay_flag)
    end
    return card
end

local function market_tab_root(nodes)
    return { n = G.UIT.ROOT, config = { align = "tm", colour = G.C.CLEAR, minw = 6.6, minh = 5.0, padding = 0.05 }, nodes = nodes }
end

local function trends_tab_definition(state)
    return function()
        state.market_tab = "trends"
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
                    if slot then build_trend_card(area, slot, slot_index > 1) end
                end
                deck_tables[#deck_tables + 1] = row({ { n = G.UIT.O, config = { object = area, func = "grdl_trend_tick", ref_table = area } } }, { padding = 0.05, no_fill = true })
            end
            nodes[#nodes + 1] = { n = G.UIT.R, config = { align = "cm", r = 0.1, colour = G.C.BLACK, emboss = 0.05 }, nodes = deck_tables }
        end
        local cycle = UICommon.page_cycle(view, "grdl_market_heat_page")
        if cycle then nodes[#nodes + 1] = row({ cycle }, { padding = 0.05 }) end
        return market_tab_root(nodes)
    end
end

local function build_offer_card(area, offer)
    local centers = G.P_CENTERS or {}
    local center = centers[offer.center_key]
    if not center then return nil end

    local display_center = center
    if offer.mystery then
        display_center = {}
        for key, value in pairs(center) do display_center[key] = value end
        display_center.discovered = false
    end

    local card = Card(area.T.x + area.T.w / 2, area.T.y, G.CARD_W, G.CARD_H, (G.P_CARDS and G.P_CARDS.empty or nil), display_center)
    UICommon.suppress_selection(card)
    if offer.mystery then
        card.hover = function(self)
            if rawget(_G, "Node") then Node.hover(self) end
        end
        card.stop_hover = function(self)
            if rawget(_G, "Node") then Node.stop_hover(self) end
        end
    else
        local flags = Catalog.edition_flags(offer.edition)
        if flags then card:set_edition(flags, true, true) end
        card.grdl_offer = offer
    end
    area:emplace(card)
    return card
end

local function blackmarket_tab_definition(namespace, state)
    return function()
        state.market_tab = "blackmarket"
        local nodes = {}
        if state.bm_locked then
            nodes[#nodes + 1] = row({ ui_text(safe_localize(state.text_keys.bm_locked), 0.4, G.C.UI.TEXT_INACTIVE) }, { padding = 0.5 })
            return market_tab_root(nodes)
        end

        local runtime = rawget(_G, "G")
        local dealer_nodes = {}
        local blind = runtime and runtime.P_BLINDS and state.bm_boss_key and runtime.P_BLINDS[state.bm_boss_key] or nil
        if blind and rawget(_G, "SMODS") and SMODS.create_sprite then
            local ok_sprite, sprite = pcall(SMODS.create_sprite, 0, 0, 1.3, 1.3, blind.atlas or "blind_chips", blind.pos)
            if ok_sprite and sprite then
                dealer_nodes[#dealer_nodes + 1] = row({ { n = G.UIT.O, config = { object = sprite } } }, { padding = 0.06 })
            end
        end
        if state.bm_quip ~= "" and rawget(_G, "DynaText") then
            local ok_quip, quip_object = pcall(DynaText, {
                string = { state.bm_quip },
                colours = { G.C.UI.TEXT_DARK },
                scale = 0.3,
                float = true,
                bump = true,
                silent = true,
                pop_in = 0.2,
                maxw = 2.3
            })
            if ok_quip and quip_object then
                dealer_nodes[#dealer_nodes + 1] = row({
                    { n = G.UIT.R, config = { align = "cm", padding = 0.08, r = 0.2, colour = G.C.WHITE, shadow = true }, nodes = {
                        { n = G.UIT.O, config = { object = quip_object } }
                    } }
                }, { padding = 0.05 })
            end
        end

        local offer_nodes = {}
        if rawget(_G, "CardArea") and rawget(_G, "Card") and runtime and runtime.P_CENTERS then
            local area = CardArea(
                runtime.ROOM.T.x + 0.2 * runtime.ROOM.T.w / 2, runtime.ROOM.T.h,
                3.25 * runtime.CARD_W,
                0.95 * runtime.CARD_H,
                { card_limit = 3, type = "title", highlight_limit = 0, collection = true })
            local buttons = {}
            for _, offer in ipairs(state.bm_offers or {}) do
                if not offer.sold then
                    build_offer_card(area, offer)
                end
                local cell
                if offer.sold then
                    cell = ui_text(safe_localize("grdl_k_status_sold"), 0.3, G.C.UI.TEXT_INACTIVE)
                else
                    cell = UICommon.outline_button({
                        button = "grdl_bm_buy",
                        ref = { id = offer.slot },
                        minw = 1.4,
                        minh = 0.8,
                        lines = {
                            { text = safe_localize(state.text_keys.buy) },
                            { text = safe_localize("grdl_k_grading_fee", { offer.price }), scale = 0.26, colour = G.C.GOLD }
                        }
                    })
                end
                buttons[#buttons + 1] = col({ cell }, { align = "cm", minw = 1.55 })
            end
            offer_nodes[#offer_nodes + 1] = row({ { n = G.UIT.O, config = { object = area } } }, { padding = 0.05, no_fill = true })
            offer_nodes[#offer_nodes + 1] = row(buttons, { padding = 0.04 })
        end
        offer_nodes[#offer_nodes + 1] = row({
            { n = G.UIT.T, config = { ref_table = state, ref_value = "bm_text", scale = 0.3, colour = G.C.GOLD } }
        })

        nodes[#nodes + 1] = row({
            col(dealer_nodes, { align = "cm", minw = 2.4 }),
            col(offer_nodes, { align = "cm", minw = 4.8 })
        }, { padding = 0.05 })
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
                    label = safe_localize(state.text_keys.tab_blackmarket),
                    chosen = state.market_tab ~= "trends",
                    tab_definition_function = blackmarket_tab_definition(namespace, state)
                },
                {
                    label = safe_localize(state.text_keys.tab_trends),
                    chosen = state.market_tab == "trends",
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

    runtime.FUNCS.grdl_trend_tick = function(element)
        local area = element and element.config and element.config.ref_table or nil
        if not area or not area.cards then return end
        local clock = (rawget(_G, "love") and love.timer and love.timer.getTime and love.timer.getTime()) or os.clock()
        for _, card in ipairs(area.cards) do
            local carousel = card.grdl_carousel
            if carousel and #carousel.keys > 1 then
                carousel.last = carousel.last or clock
                if clock - carousel.last >= CAROUSEL_INTERVAL then
                    carousel.last = clock
                    carousel.index = carousel.index % #carousel.keys + 1
                    local centers = rawget(_G, "G") and G.P_CENTERS or {}
                    local next_center = centers[carousel.keys[carousel.index]]
                    if next_center then
                        pcall(card.set_sprites, card, next_center)
                    end
                end
            end
        end
    end

    runtime.FUNCS.grdl_open_market = function(event)
        local state = MarketUI.open(namespace)
        if state and adapter.open_market then adapter.open_market(namespace, state, event) end
    end

    runtime.FUNCS.grdl_bm_buy = function(event)
        local slot = event_card_id(event)
        local result = MarketUI.buy(namespace, slot, os.time())
        if result.ok then
            local inspect_state = namespace.inspect_ui_state
            if inspect_state and inspect_state.offer_mode and namespace.BinderUI then
                namespace.inspect_ui_state = nil
                namespace.BinderUI.open(namespace)
                local card_state = namespace.BinderUI.open_inspect(namespace, result.card.id)
                if card_state and runtime.FUNCS.overlay_menu then
                    if runtime.SETTINGS then runtime.SETTINGS.paused = true end
                    runtime.FUNCS.overlay_menu({ definition = namespace.BinderUI.create_inspect_definition(namespace) })
                end
            else
                local state = namespace.market_ui_state
                if not (state and UICommon.swap_tab_contents(blackmarket_tab_definition(namespace, state))) then
                    if adapter.refresh_market then adapter.refresh_market(namespace, state, event) end
                end
            end
        elseif rawget(_G, "play_sound") then
            pcall(play_sound, "tarot2", 0.76, 0.4)
        end
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
