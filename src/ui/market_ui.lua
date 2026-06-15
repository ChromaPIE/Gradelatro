local MarketUI = {}

local function load_src(path)
    return assert(SMODS.load_file("src/" .. path))()
end

local Binder = load_src("domain/binder.lua")
local BlackMarket = load_src("domain/black_market.lua")
local Catalog = load_src("domain/catalog.lua")
local Market = load_src("domain/market.lua")
local Persistence = load_src("core/persistence.lua")
local UICommon = load_src("ui/ui_common.lua")

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

-- quip keys may hold a plain string or an array of line strings
function MarketUI.quip_lines(value)
    if type(value) == "table" then
        local lines = {}
        for _, line in ipairs(value) do lines[#lines + 1] = tostring(line) end
        return lines
    end
    return { tostring(value) }
end

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
        ui_text(text, 0.35, colour or G.C.UI.TEXT_DARK)
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
                row({ ui_text(slot.mod_name, 0.46, G.C.WHITE) }, { padding = 0.02 }),
                row({ ui_text(slot.series_key, 0.36, G.C.UI.TEXT_LIGHT) }, { padding = 0.02 }),
                { n = G.UIT.R, config = { align = "cm", padding = 0.06, r = 0.06, colour = G.C.WHITE }, nodes = {
                    { n = G.UIT.C, config = { align = "cl", padding = 0.01 }, nodes = labels },
                    { n = G.UIT.C, config = { align = "cm", minw = 0.35 }, nodes = {} },
                    { n = G.UIT.C, config = { align = "cr", padding = 0.01 }, nodes = values }
                } }
            } }
        } }
    } }
end

local function build_trend_card(area, slot, slot_index)
    local centers = G.P_CENTERS or {}
    local center = centers[slot.center_keys[1]]
    if not center then return nil end

    local card = Card(area.T.x + area.T.w / 2, area.T.y, G.CARD_W, G.CARD_H, (G.P_CARDS and G.P_CARDS.empty or nil), center)
    UICommon.suppress_selection(card)

    -- per-slot phase staggers the swaps so the page never flickers in unison
    card.grdl_carousel = { keys = slot.center_keys, index = 1, phase = ((slot_index or 1) - 1) * 0.37 }

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
        pcall(card.start_materialize, card, nil, (slot_index or 1) > 1)
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
                    if slot then build_trend_card(area, slot, slot_index) end
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

function MarketUI.mystery_display_center(center)
    local copy = {}
    for key, value in pairs(center) do copy[key] = value end
    setmetatable(copy, getmetatable(center))
    copy.discovered = false
    copy.unlocked = true
    return copy
end

function MarketUI.intel_rows(offer)
    local unknown = safe_localize("grdl_k_intel_unknown")
    local intel = offer.intel or {}
    local rarity_value = unknown
    if intel.rarity then
        local rarity_key = "grdl_k_rarity_" .. tostring(offer.rarity)
        rarity_value = safe_localize(rarity_key)
        if rarity_value == rarity_key then rarity_value = tostring(offer.rarity) end
    end
    return {
        { label = safe_localize("grdl_k_intel_mod"), value = intel.mod and tostring(offer.mod_name) or unknown },
        { label = safe_localize("grdl_k_intel_rarity"), value = rarity_value },
        { label = safe_localize("grdl_k_intel_edition"), value = intel.edition and safe_localize(offer.edition ~= "base" and "grdl_k_intel_edition_yes" or "grdl_k_intel_edition_no") or unknown },
        { label = safe_localize("grdl_k_intel_graded"), value = intel.graded and safe_localize(offer.graded and "grdl_k_intel_graded_yes" or "grdl_k_intel_graded_no") or unknown }
    }
end

local function mystery_popup(offer)
    local labels = {}
    local values = {}
    for _, entry in ipairs(MarketUI.intel_rows(offer)) do
        labels[#labels + 1] = trend_line_cell(entry.label, "cl")
        values[#values + 1] = trend_line_cell(entry.value, "cr", attention_colour())
    end
    return { n = G.UIT.ROOT, config = { align = "cm", colour = G.C.CLEAR }, nodes = {
        { n = G.UIT.R, config = { align = "cm", padding = 0.05, r = 0.12, colour = rawget(_G, "lighten") and lighten(G.C.JOKER_GREY, 0.5) or G.C.JOKER_GREY, emboss = 0.07 }, nodes = {
            { n = G.UIT.R, config = { align = "cm", padding = 0.07, r = 0.1, colour = G.C.L_BLACK }, nodes = {
                row({ ui_text(safe_localize("grdl_k_intel_unknown"), 0.46, G.C.WHITE) }, { padding = 0.02 }),
                { n = G.UIT.R, config = { align = "cm", padding = 0.06, r = 0.06, colour = G.C.WHITE }, nodes = {
                    { n = G.UIT.C, config = { align = "cl", padding = 0.01 }, nodes = labels },
                    { n = G.UIT.C, config = { align = "cm", minw = 0.35 }, nodes = {} },
                    { n = G.UIT.C, config = { align = "cr", padding = 0.01 }, nodes = values }
                } }
            } }
        } }
    } }
end

local function attach_buy_button(card, offer)
    if not rawget(_G, "UIBox") then return end
    -- children.use_button only draws while the card is highlighted, so the
    -- buy button appears under the selected offer and never overlaps others
    card.children.use_button = UIBox({
        definition = { n = G.UIT.ROOT, config = { align = "cm", colour = G.C.CLEAR, padding = 0.03 }, nodes = {
            UICommon.outline_button({
                button = "grdl_bm_buy",
                ref = { id = offer.slot },
                solid = true,
                minw = 1.15,
                minh = 0.6,
                lines = {
                    { text = safe_localize(TEXT_KEYS.buy), scale = 0.32 },
                    { text = safe_localize("grdl_k_grading_fee", { offer.price }), scale = 0.28, colour = G.C.GOLD }
                }
            })
        } },
        config = { align = "bm", offset = { x = 0, y = 0.06 }, major = card, bond = "Strong", parent = card }
    })
end

local function build_offer_card(area, offer)
    local centers = G.P_CENTERS or {}
    local center = centers[offer.center_key]
    if not center then return nil end

    local display_center = center
    if offer.mystery then
        display_center = MarketUI.mystery_display_center(center)
    end

    local card = Card(area.T.x + area.T.w / 2, area.T.y, G.CARD_W, G.CARD_H, (G.P_CARDS and G.P_CARDS.empty or nil), display_center)
    card.click = function(self)
        if self.highlighted then
            self.highlighted = false
        else
            for _, other in ipairs(area.cards) do other.highlighted = false end
            self.highlighted = true
        end
        if self.juice_up then self:juice_up(0.3, 0.3) end
    end
    if offer.mystery then
        card.grdl_mystery_slot = offer.slot
        card.hover = function(self)
            self.config.h_popup = mystery_popup(offer)
            self.config.h_popup_config = self:align_h_popup()
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
    attach_buy_button(card, offer)
    return card
end

-- the bought mystery lifts forward, flips to its real face, jiggles, and
-- waits for the collect click before dissolving out of the strip
function MarketUI.reveal_mystery(namespace, result)
    local runtime = rawget(_G, "G")
    local state = namespace.market_ui_state
    local area = namespace.bm_area
    if not runtime or not runtime.E_MANAGER or not rawget(_G, "Event") or not area or not state then return false end
    local offer = result.offer
    local target = nil
    for _, card in ipairs(area.cards or {}) do
        if card.grdl_mystery_slot == offer.slot then
            target = card
            break
        end
    end
    if not target then return false end

    state.bm_revealing = true
    for _, card in ipairs(area.cards) do
        card.click = function() end
        if card ~= target then card.highlighted = false end
    end
    if target.children.use_button then
        target.children.use_button:remove()
        target.children.use_button = nil
    end
    target.highlighted = true

    local real_center = runtime.P_CENTERS and runtime.P_CENTERS[result.card.center_key] or nil
    -- blockable=false events time independently from enqueue, so the
    -- sequence is staged with cumulative delays; the collect button must
    -- attach AFTER set_ability, whose clean_up_children would destroy it
    runtime.E_MANAGER:add_event(Event({ trigger = "after", delay = 0.25, blockable = false, func = function()
        if target.REMOVED then return true end
        if target.flip then pcall(target.flip, target) end
        if rawget(_G, "play_sound") then pcall(play_sound, "card1", 1, 0.5) end
        return true
    end }))
    runtime.E_MANAGER:add_event(Event({ trigger = "after", delay = 0.7, blockable = false, func = function()
        if target.REMOVED then return true end
        local keep_x, keep_y, keep_r = target.T.x, target.T.y, target.T.r
        if target.original_T then
            target.original_T.x, target.original_T.y, target.original_T.r = keep_x, keep_y, keep_r
        end
        if real_center then pcall(target.set_ability, target, real_center, true) end
        target.T.x, target.T.y, target.T.r = keep_x, keep_y, keep_r
        local flags = Catalog.edition_flags(result.card.edition)
        if flags then pcall(target.set_edition, target, flags, true, true) end
        target.hover = nil
        target.stop_hover = nil
        return true
    end }))
    runtime.E_MANAGER:add_event(Event({ trigger = "after", delay = 1.05, blockable = false, func = function()
        if target.REMOVED then return true end
        if target.flip then pcall(target.flip, target) end
        if target.juice_up then pcall(target.juice_up, target, 0.6, 0.4) end
        if rawget(_G, "play_sound") then pcall(play_sound, "polychrome1", 1.2, 0.7) end
        return true
    end }))
    runtime.E_MANAGER:add_event(Event({ trigger = "after", delay = 1.35, blockable = false, func = function()
        if target.REMOVED then return true end
        if rawget(_G, "UIBox") then
            target.children.grdl_collect = UIBox({
                definition = { n = G.UIT.ROOT, config = { align = "cm", colour = G.C.CLEAR, padding = 0.03 }, nodes = {
                    UICommon.outline_button({
                        button = "grdl_bm_collect",
                        solid = true,
                        colour = G.C.GREEN,
                        minw = 1.3,
                        minh = 0.6,
                        lines = { { text = safe_localize("grdl_b_collect"), scale = 0.32 } }
                    })
                } },
                config = { align = "bm", offset = { x = 0, y = 0.06 }, major = target, bond = "Strong", parent = target }
            })
        end
        return true
    end }))
    return true
end

local function dealer_jiggle(sprite, ticks)
    if not sprite or sprite.REMOVED or ticks <= 0 then return end
    if sprite.juice_up then pcall(sprite.juice_up, sprite) end
    if rawget(_G, "play_sound") then
        local speed = (rawget(_G, "G") and G.SPEEDFACTOR or 1) * (math.random() * 0.2 + 1)
        pcall(play_sound, "voice" .. math.random(1, 11), speed, 0.5)
    end
    local runtime = rawget(_G, "G")
    if runtime and runtime.E_MANAGER and rawget(_G, "Event") then
        runtime.E_MANAGER:add_event(Event({
            trigger = "after",
            delay = 0.13,
            blockable = false,
            blocking = false,
            func = function()
                dealer_jiggle(sprite, ticks - 1)
                return true
            end
        }))
    end
end

local function attach_dealer_bubble(sprite, quip)
    if not rawget(_G, "UIBox") or not rawget(_G, "DynaText") then return end
    local lines = MarketUI.quip_lines(quip)
    local line_rows = {}
    for _, line in ipairs(lines) do
        local ok_line, line_object = pcall(DynaText, {
            string = { line },
            colours = { G.C.UI.TEXT_DARK },
            scale = 0.34,
            float = true,
            bump = true,
            silent = true,
            pop_in = 0.2,
            maxw = 2.6
        })
        if ok_line and line_object then
            line_rows[#line_rows + 1] = { n = G.UIT.R, config = { align = "cl", padding = 0.01 }, nodes = {
                { n = G.UIT.O, config = { object = line_object } }
            } }
        end
    end
    if #line_rows == 0 then return end

    -- vanilla speech bubble shell: grey ring around a white core (G.UIDEF.speech_bubble)
    local ok_bubble, bubble = pcall(UIBox, {
        definition = { n = G.UIT.ROOT, config = { align = "cm", minh = 1, r = 0.3, padding = 0.07, minw = 1, colour = G.C.JOKER_GREY, shadow = true }, nodes = {
            { n = G.UIT.C, config = { align = "cm", minh = 1, r = 0.2, padding = 0.1, minw = 1, colour = G.C.WHITE }, nodes = line_rows }
        } },
        config = {
            instance_type = "POPUP",
            align = "bm",
            offset = { x = 0, y = 0.06 },
            major = sprite,
            parent = sprite
        }
    })
    if not ok_bubble or not bubble then return end
    if bubble.set_role then
        pcall(bubble.set_role, bubble, { role_type = "Minor", xy_bond = "Weak", r_bond = "Strong", major = sprite })
    end
    if bubble.states and bubble.states.collide then bubble.states.collide.can = false end
    sprite.children = sprite.children or {}
    sprite.children.speech_bubble = bubble

    local runtime = rawget(_G, "G")
    local flat = table.concat(lines, " ")
    local ticks = math.max(6, math.min(14, math.floor(#flat / 6)))
    if runtime and runtime.E_MANAGER and rawget(_G, "Event") then
        bubble.states.visible = false
        runtime.E_MANAGER:add_event(Event({
            trigger = "after",
            delay = 0.1,
            blockable = false,
            blocking = false,
            func = function()
                bubble.states.visible = true
                dealer_jiggle(sprite, ticks)
                return true
            end
        }))
    end
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
        if blind then
            local ok_sprite, sprite = pcall(SMODS.create_sprite, 0, 0, 1.3, 1.3, blind.atlas or "blind_chips", blind.pos)
            if ok_sprite and sprite then
                -- fidget flags copied from the in-run blind chip
                if sprite.states then
                    if sprite.states.drag then sprite.states.drag.can = true end
                    if sprite.states.collide then sprite.states.collide.can = true end
                end
                dealer_nodes[#dealer_nodes + 1] = row({ { n = G.UIT.O, config = { object = sprite } } }, { padding = 0.06 })
                if state.bm_quip ~= "" then
                    pcall(attach_dealer_bubble, sprite, state.bm_quip)
                    -- reserve room below the chip for the hanging bubble
                    dealer_nodes[#dealer_nodes + 1] = row({}, { minh = 1.5, padding = 0 })
                end
            end
        end

        local offer_nodes = {}
        if rawget(_G, "CardArea") and rawget(_G, "Card") and runtime and runtime.P_CENTERS then
            local area = CardArea(
                runtime.ROOM.T.x + 0.2 * runtime.ROOM.T.w / 2, runtime.ROOM.T.h,
                3.25 * runtime.CARD_W,
                0.95 * runtime.CARD_H,
                { card_limit = 3, type = "title", highlight_limit = 1, collection = true })
            namespace.bm_area = area
            for _, offer in ipairs(state.bm_offers or {}) do
                if not offer.sold then
                    build_offer_card(area, offer)
                end
            end
            offer_nodes[#offer_nodes + 1] = row({ { n = G.UIT.O, config = { object = area } } }, { padding = 0.05, no_fill = true })
            -- the highlight-gated buy button hangs under the selected card
            offer_nodes[#offer_nodes + 1] = row({}, { minh = 0.7, padding = 0 })
        end
        offer_nodes[#offer_nodes + 1] = row({
            { n = G.UIT.T, config = { ref_table = state, ref_value = "bm_text", scale = 0.34, colour = G.C.GOLD } }
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
                carousel.last = carousel.last or (clock + (carousel.phase or 0))
                if clock - carousel.last >= CAROUSEL_INTERVAL then
                    carousel.last = clock
                    carousel.index = carousel.index % #carousel.keys + 1
                    local centers = rawget(_G, "G") and G.P_CENTERS or {}
                    local next_center = centers[carousel.keys[carousel.index]]
                    if next_center then
                        -- full morph: per-frame center hooks (center.update) and the soul
                        -- draw gate both expect ability and config.center to match the face.
                        -- set_ability resets T from original_T BEFORE rebuilding the sprites,
                        -- so original_T must be re-anchored to the live slot first or the
                        -- fresh center sprite is born at the build position offscreen and
                        -- visibly flies in
                        local keep_x, keep_y, keep_r = card.T.x, card.T.y, card.T.r
                        if card.original_T then
                            card.original_T.x, card.original_T.y, card.original_T.r = keep_x, keep_y, keep_r
                        end
                        pcall(card.set_ability, card, next_center, true)
                        card.T.x, card.T.y, card.T.r = keep_x, keep_y, keep_r
                        -- soft pulse reads as a deliberate transition instead of a hard cut
                        if card.juice_up then pcall(card.juice_up, card, 0.05, 0.03) end
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
            elseif result.offer and result.offer.mystery and MarketUI.reveal_mystery(namespace, result) then
                -- the reveal sequence owns the strip until the collect click
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

    runtime.FUNCS.grdl_bm_collect = function(event)
        local state = namespace.market_ui_state
        local area = namespace.bm_area
        local target = nil
        for _, card in ipairs((area and area.cards) or {}) do
            if card.children and card.children.grdl_collect then
                target = card
                break
            end
        end
        if target then
            target.children.grdl_collect:remove()
            target.children.grdl_collect = nil
            if target.start_dissolve then pcall(target.start_dissolve, target) end
        end
        if state then state.bm_revealing = nil end
        local function rebuild()
            if not (state and UICommon.swap_tab_contents(blackmarket_tab_definition(namespace, state))) then
                if adapter.refresh_market then adapter.refresh_market(namespace, state, event) end
            end
        end
        local game = rawget(_G, "G")
        if game and game.E_MANAGER and rawget(_G, "Event") then
            game.E_MANAGER:add_event(Event({ trigger = "after", delay = 0.45, blockable = false, func = function()
                pcall(rebuild)
                return true
            end }))
        else
            rebuild()
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
