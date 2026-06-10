local BinderUI = {}

local function load_src(path)
    if rawget(_G, "SMODS") and SMODS.load_file then
        return assert(SMODS.load_file("src/" .. path))()
    end
    return dofile("src/" .. path)
end

local Binder = load_src("binder.lua")
local Catalog = load_src("catalog.lua")
local Grading = load_src("grading.lua")
local Label = load_src("label.lua")
local Persistence = load_src("persistence.lua")
local SlabUI = load_src("slab_ui.lua")
local UICommon = load_src("ui_common.lua")

local safe_localize = UICommon.localize_text
local center_name = UICommon.center_name
local ui_text = UICommon.text_node
local row = UICommon.row
local col = UICommon.col
local event_card_id = UICommon.event_ref_id

local PAGE_ROWS = { 5, 5 }

local EDITION_FLAGS = {
    foil = { foil = true },
    holographic = { holo = true },
    polychrome = { polychrome = true },
    negative = { negative = true }
}

local TEXT_KEYS = {
    title = "grdl_k_binder_title",
    empty = "grdl_k_binder_empty",
    hidden = "grdl_k_binder_hidden",
    desk = "grdl_b_desk",
    desk_title = "grdl_k_desk_title",
    desk_empty = "grdl_k_desk_empty",
    queue_title = "grdl_k_queue_title",
    revealed = "grdl_k_grading_revealed"
}

local function copy_text_keys()
    local out = {}
    for key, value in pairs(TEXT_KEYS) do
        out[key] = value
    end
    return out
end

local function per_page()
    local total = 0
    for _, count in ipairs(PAGE_ROWS) do
        total = total + count
    end
    return total
end

local function reason_key(reason)
    return "grdl_k_reason_" .. tostring(reason or "unknown")
end

local function runtime_centers()
    local runtime = rawget(_G, "G")
    return runtime and runtime.P_CENTERS or nil
end

local function grading_fee_map(config, collection)
    local fees = {}
    for _, card in ipairs((collection and collection.cards) or {}) do
        if (card.status or "raw") == "raw" then
            fees[card.id] = Grading.fee_for(config, card)
        end
    end
    return fees
end

local function process_due(namespace, now)
    if not namespace.config then return 0 end
    local processed = Grading.process_due(namespace.config, namespace.collection, now)
    if #processed.revealed > 0 then
        namespace.last_save_ok = Persistence.save(namespace)
    end
    return #processed.revealed
end

local function refresh_hover_index(namespace)
    local centers = runtime_centers()
    if not centers or not namespace.config then return end
    local smods = rawget(_G, "SMODS")
    local ok, catalog = pcall(Catalog.discover, namespace.config, centers, smods and smods.Mods or nil)
    if not ok then return end
    local index = {}
    for _, entry in ipairs(catalog) do
        index[entry.center_key] = entry
    end
    namespace.binder_hover_index = index
end

function BinderUI.open(namespace, now)
    if not namespace or not namespace.collection then return nil end
    now = now or os.time()

    local revealed_count = process_due(namespace, now)
    refresh_hover_index(namespace)
    SlabUI.install(namespace)

    local view = Binder.entries(namespace.collection, { centers = runtime_centers() })
    namespace.binder_ui_state = {
        text_keys = copy_text_keys(),
        summary = Binder.summary(namespace.collection),
        entries = view.entries,
        hidden = view.hidden,
        page = 1,
        page_view = Binder.page(view.entries, 1, per_page()),
        revealed_count = revealed_count
    }
    return namespace.binder_ui_state
end

function BinderUI.set_page(namespace, page)
    local state = namespace and namespace.binder_ui_state or nil
    if not state then return nil end
    state.page_view = Binder.page(state.entries, page, per_page())
    state.page = state.page_view.page
    return state
end

function BinderUI.open_desk(namespace, now)
    if not namespace or not namespace.collection then return nil end
    now = now or os.time()

    local revealed_count = process_due(namespace, now)
    namespace.desk_ui_state = {
        text_keys = copy_text_keys(),
        summary = Binder.summary(namespace.collection),
        rows = Binder.desk_rows(namespace.collection),
        fees = namespace.config and grading_fee_map(namespace.config, namespace.collection) or {},
        queue_rows = Grading.queue_rows(namespace.collection, now),
        revealed_count = revealed_count,
        last_reason = nil,
        last_reason_text = ""
    }
    return namespace.desk_ui_state
end

function BinderUI.open_inspect(namespace, card_id, now)
    if not namespace or not namespace.collection or not card_id then return nil end

    local entries = namespace.binder_ui_state and namespace.binder_ui_state.entries or nil
    if not entries then
        entries = Binder.entries(namespace.collection, { centers = runtime_centers() }).entries
    end

    local entry = nil
    for _, candidate in ipairs(entries) do
        if candidate.id == card_id then
            entry = candidate
            break
        end
    end
    if not entry then return nil end

    namespace.inspect_ui_state = {
        entry = entry,
        text_keys = copy_text_keys()
    }
    return namespace.inspect_ui_state
end

function BinderUI.inspect_from_card(namespace, card)
    local record = card and card.grdl_record or nil
    if not record then return nil end
    local state = BinderUI.open_inspect(namespace, record.id)
    if not state then return nil end

    local runtime = rawget(_G, "G")
    if runtime and runtime.FUNCS and runtime.FUNCS.overlay_menu then
        if runtime.SETTINGS then runtime.SETTINGS.paused = true end
        runtime.FUNCS.overlay_menu({
            definition = BinderUI.create_inspect_definition(namespace)
        })
    end
    return state
end

function BinderUI.submit_grading(namespace, card_id, now)
    if not namespace or not namespace.collection then
        return { ok = false, reason = "missing_collection" }
    end
    if not namespace.config then
        return { ok = false, reason = "missing_config" }
    end
    now = now or os.time()

    local result = Grading.submit(namespace.config, namespace.collection, {
        card_id = card_id,
        now = now
    })
    namespace.last_grading_result = result

    if result.ok then
        namespace.last_save_ok = Persistence.save(namespace)
        BinderUI.open_desk(namespace, now)
    else
        local state = namespace.desk_ui_state or BinderUI.open_desk(namespace, now)
        if state then
            state.last_reason = result.reason
            state.last_reason_text = safe_localize(reason_key(result.reason))
        end
    end
    return result
end

function BinderUI.fill_card_areas(namespace)
    local state = namespace and namespace.binder_ui_state or nil
    local areas = namespace and namespace.binder_areas or nil
    if not state or not areas then return end

    for j = 1, #areas do
        local area = areas[j]
        for i = #area.cards, 1, -1 do
            local card = area:remove_card(area.cards[i])
            if card then card:remove() end
        end
    end

    local items = state.page_view and state.page_view.items or {}
    local slot = 0
    for j = 1, #areas do
        local area = areas[j]
        for _ = 1, (PAGE_ROWS[j] or 0) do
            slot = slot + 1
            local entry = items[slot]
            if entry then
                local center = G.P_CENTERS and G.P_CENTERS[entry.center_key] or nil
                if center then
                    local card = Card(area.T.x + area.T.w / 2, area.T.y, G.CARD_W, G.CARD_H, G.P_CARDS.empty, center)
                    local edition_flag = EDITION_FLAGS[entry.edition]
                    if edition_flag then card:set_edition(edition_flag, true, true) end
                    card.grdl_record = entry
                    area:emplace(card)
                end
            end
        end
    end
end

local function build_card_grid(namespace)
    local areas = {}
    local deck_tables = {}
    for j = 1, #PAGE_ROWS do
        local area = CardArea(
            G.ROOM.T.x + 0.2 * G.ROOM.T.w / 2, G.ROOM.T.h,
            (PAGE_ROWS[j] + 0.25) * G.CARD_W,
            0.95 * G.CARD_H,
            { card_limit = PAGE_ROWS[j], type = "title", highlight_limit = 0, collection = true })
        areas[j] = area
        deck_tables[#deck_tables + 1] = row({ { n = G.UIT.O, config = { object = area } } }, { padding = 0.07, no_fill = true })
    end
    namespace.binder_areas = areas
    BinderUI.fill_card_areas(namespace)
    return deck_tables
end

local function stat_chip(text)
    return { n = G.UIT.C, config = { align = "cm", padding = 0.09, r = 0.1, colour = G.C.WHITE, emboss = 0.05 }, nodes = {
        { n = G.UIT.T, config = { text = text, scale = 0.31, colour = G.C.UI.TEXT_DARK } }
    } }
end

local function summary_row(state)
    local summary = state.summary
    return row({
        stat_chip(safe_localize("grdl_k_stat_g", { summary.currency_g })),
        stat_chip(safe_localize("grdl_k_stat_owned") .. " " .. tostring(summary.owned_cards)),
        stat_chip(safe_localize("grdl_k_stat_raw") .. " " .. tostring(summary.raw_cards)),
        stat_chip(safe_localize("grdl_k_stat_graded") .. " " .. tostring(summary.graded_cards)),
        stat_chip(safe_localize("grdl_k_stat_queue") .. " " .. tostring(summary.grading_queue))
    }, { padding = 0.09 })
end

local function revealed_row(state)
    if (state.revealed_count or 0) <= 0 then return nil end
    return row({ ui_text(safe_localize(state.text_keys.revealed, { state.revealed_count }), 0.34, G.C.GOLD) })
end

function BinderUI.create_overlay_definition(namespace)
    namespace = namespace or rawget(_G, "Gradelatro") or {}
    local state = namespace.binder_ui_state or BinderUI.open(namespace)
    if not state then
        return create_UIBox_generic_options({ back_func = "options", contents = {} })
    end

    local rows = {
        row({ ui_text(safe_localize(state.text_keys.title), 0.55, G.C.WHITE) }),
        summary_row(state),
        revealed_row(state)
    }

    if state.page_view.total == 0 then
        rows[#rows + 1] = row({ ui_text(safe_localize(state.text_keys.empty), 0.34, G.C.UI.TEXT_INACTIVE) })
    else
        rows[#rows + 1] = { n = G.UIT.R, config = { align = "cm", r = 0.1, colour = G.C.BLACK, emboss = 0.05 }, nodes = build_card_grid(namespace) }
    end

    if (state.hidden or 0) > 0 then
        rows[#rows + 1] = row({ ui_text(safe_localize(state.text_keys.hidden, { state.hidden }), 0.28, G.C.UI.TEXT_INACTIVE) })
    end

    local controls = {}
    if state.page_view.pages > 1 then
        local options = {}
        for i = 1, state.page_view.pages do
            options[#options + 1] = safe_localize("k_page") .. " " .. tostring(i) .. "/" .. tostring(state.page_view.pages)
        end
        controls[#controls + 1] = col({
            create_option_cycle({
                options = options,
                w = 4.5,
                cycle_shoulders = true,
                opt_callback = "grdl_binder_page",
                current_option = state.page,
                colour = G.C.RED,
                no_pips = true,
                focus_args = { snap_to = true, nav = "wide" }
            })
        })
    end
    controls[#controls + 1] = col({
        UIBox_button({
            button = "grdl_open_desk",
            label = { safe_localize(state.text_keys.desk) },
            minw = 2.8,
            maxw = 2.8,
            minh = 0.7,
            scale = 0.34,
            colour = G.C.BLUE,
            focus_args = { nav = "wide" }
        })
    })
    rows[#rows + 1] = row(controls, { padding = 0.08 })

    return create_UIBox_generic_options({
        back_func = "options",
        minw = 7.2,
        padding = 0.12,
        colour = G.C.L_BLACK,
        outline_colour = G.C.RED,
        contents = rows
    })
end

local function eta_text(remaining)
    if remaining <= 0 then
        return safe_localize("grdl_k_grading_ready")
    end
    if remaining < 5400 then
        return safe_localize("grdl_k_eta_minutes", { math.max(1, math.ceil(remaining / 60)) })
    end
    if remaining < 172800 then
        return safe_localize("grdl_k_eta_hours", { math.ceil(remaining / 3600) })
    end
    return safe_localize("grdl_k_eta_days", { math.ceil(remaining / 86400) })
end

local function desk_card_row(state, row_data)
    local fee = state.fees and state.fees[row_data.id] or nil
    local name = center_name(row_data)
    return row({
        col({ ui_text(name, UICommon.fit_scale(name, 0.3, 18)) }, { align = "cl", minw = 2.0 }),
        col({ ui_text(safe_localize("grdl_k_edition_" .. tostring(row_data.edition or "base")), 0.26) }, { align = "cl", minw = 0.9 }),
        col({ ui_text(fee and safe_localize("grdl_k_grading_fee", { fee }) or "", 0.28, G.C.GOLD) }, { align = "cr", minw = 0.8 }),
        col({
            UIBox_button({
                button = "grdl_submit_grading",
                label = { safe_localize("grdl_b_grade") },
                ref_table = { id = row_data.id },
                minw = 1.0,
                maxw = 1.0,
                minh = 0.5,
                scale = 0.28,
                colour = G.C.BLUE,
                focus_args = { nav = "wide" }
            })
        }, { align = "cm", minw = 1.1 })
    })
end

local function queue_row(queue_data)
    local name = center_name(queue_data)
    return row({
        col({ ui_text(name, UICommon.fit_scale(name, 0.28, 18)) }, { align = "cl", minw = 2.0 }),
        col({ ui_text(safe_localize("grdl_k_service_" .. tostring(queue_data.service or "standard")), 0.26) }, { align = "cl", minw = 0.9 }),
        col({ ui_text(eta_text(queue_data.remaining or 0), 0.28, queue_data.ready and G.C.GREEN or G.C.UI.TEXT_LIGHT) }, { align = "cr", minw = 0.9 })
    })
end

function BinderUI.create_desk_definition(namespace)
    namespace = namespace or rawget(_G, "Gradelatro") or {}
    local state = namespace.desk_ui_state or BinderUI.open_desk(namespace)
    if not state then
        return create_UIBox_generic_options({ back_func = "grdl_open_binder", contents = {} })
    end

    local rows = {
        row({ ui_text(safe_localize(state.text_keys.desk_title), 0.55, G.C.WHITE) }),
        summary_row(state),
        revealed_row(state)
    }

    if #state.rows == 0 then
        rows[#rows + 1] = row({ ui_text(safe_localize(state.text_keys.desk_empty), 0.34, G.C.UI.TEXT_INACTIVE) })
    else
        for _, entry in ipairs(state.rows) do
            rows[#rows + 1] = desk_card_row(state, entry)
        end
    end

    if #(state.queue_rows or {}) > 0 then
        rows[#rows + 1] = row({ ui_text(safe_localize(state.text_keys.queue_title), 0.4, G.C.WHITE) })
        for _, entry in ipairs(state.queue_rows) do
            rows[#rows + 1] = queue_row(entry)
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

local CARD_INSPECT_SCALE = 1.8

local function inspect_text(text, scale, colour, font)
    return { n = G.UIT.T, config = { text = text, scale = scale, colour = colour, font = font } }
end

local function inspect_date_text(entry)
    local year = entry.acquired_year
    local month = entry.acquired_month
    local day = entry.acquired_day
    if (not year or not month or not day) and (entry.acquired_at or 0) > 0 then
        local parts = os.date("*t", entry.acquired_at)
        year = year or parts.year
        month = month or parts.month
        day = day or parts.day
    end
    if not year then return "-" end
    return table.concat({ year, month or 1, day or 1 }, "/")
end

local function inspect_psa_text(entry)
    if entry.status == "graded" and entry.grade then
        return Label.grade_full(entry.grade)
    end
    return safe_localize("grdl_k_badge_ungraded")
end

local function inspect_edition_text(entry)
    local edition = tostring(entry.edition or "base")
    if rawget(_G, "localize") then
        local ok, value = pcall(localize, { type = "name_text", key = "e_" .. edition, set = "Edition" })
        if ok and value and value ~= "ERROR" then return value end
    end
    return safe_localize("grdl_k_edition_" .. edition)
end

local function inspect_detail_row(label_key, value, regular_font)
    return row({
        col({ inspect_text(safe_localize(label_key), 0.36, G.C.UI.TEXT_INACTIVE, regular_font) }, { align = "cl", minw = 2.0 }),
        col({ inspect_text(value, 0.36, G.C.WHITE, regular_font) }, { align = "cl", minw = 2.9 })
    }, { align = "cl", padding = 0.07 })
end

local function build_inspect_card(namespace, entry)
    if not rawget(_G, "CardArea") or not rawget(_G, "Card") then return nil end
    local centers = G.P_CENTERS or {}
    local center = entry.center_key and centers[entry.center_key] or nil
    if not center then return nil end

    local area = CardArea(
        G.ROOM.T.x + 0.2 * G.ROOM.T.w / 2, G.ROOM.T.h,
        CARD_INSPECT_SCALE * G.CARD_W * 1.1,
        CARD_INSPECT_SCALE * G.CARD_H,
        { card_limit = 1, type = "title", highlight_limit = 0, collection = true })
    local card = Card(area.T.x, area.T.y, CARD_INSPECT_SCALE * G.CARD_W, CARD_INSPECT_SCALE * G.CARD_H, G.P_CARDS.empty, center)
    local edition_flag = EDITION_FLAGS[entry.edition]
    if edition_flag then card:set_edition(edition_flag, true, true) end
    card.hover = function(self)
        if rawget(_G, "Node") then Node.hover(self) end
    end
    card.stop_hover = function(self)
        if rawget(_G, "Node") then Node.stop_hover(self) end
    end
    area:emplace(card)
    namespace.inspect_area = area
    return area
end

function BinderUI.create_inspect_definition(namespace)
    namespace = namespace or rawget(_G, "Gradelatro") or {}
    local state = namespace.inspect_ui_state
    if not state then
        return create_UIBox_generic_options({ back_func = "grdl_open_binder", contents = {} })
    end

    local entry = state.entry
    local bold_font = UICommon.noto_bold()
    local regular_font = UICommon.noto_regular()
    local hover_index = namespace.binder_hover_index or {}
    local catalog_entry = entry.center_key and hover_index[entry.center_key] or nil
    local mod_display = (catalog_entry and catalog_entry.mod_name) or entry.mod_id or ""

    local left_nodes = {}
    if entry.status == "graded" then
        left_nodes[#left_nodes + 1] = row({ SlabUI.slab_box(entry, catalog_entry, { scale = CARD_INSPECT_SCALE * 0.8 }) }, { padding = 0.06 })
    end
    local area = build_inspect_card(namespace, entry)
    if area then
        left_nodes[#left_nodes + 1] = row({ { n = G.UIT.O, config = { object = area } } }, { padding = 0.06 })
    end

    local right_nodes = {
        row({ inspect_text(mod_display, 0.5, G.C.UI.TEXT_LIGHT, regular_font) }, { align = "cl", padding = 0.03 }),
        row({ inspect_text(center_name(entry), 0.8, G.C.WHITE, bold_font) }, { align = "cl", padding = 0.05 }),
        row({}, { minh = 0.4 }),
        inspect_detail_row("grdl_k_detail_source", mod_display, regular_font),
        inspect_detail_row("grdl_k_detail_rarity", safe_localize("grdl_k_rarity_" .. tostring(entry.rarity or "common")), regular_font),
        inspect_detail_row("grdl_k_detail_edition", inspect_edition_text(entry), regular_font),
        inspect_detail_row("grdl_k_detail_date", inspect_date_text(entry), regular_font),
        inspect_detail_row("grdl_k_detail_price", safe_localize("grdl_k_stat_g", { entry.acquired_price or 0 }), regular_font),
        inspect_detail_row("grdl_k_detail_psa", inspect_psa_text(entry), regular_font)
    }

    local close_char = "X"
    if bold_font and bold_font.FONT and bold_font.FONT.hasGlyphs and bold_font.FONT:hasGlyphs("✕") then
        close_char = "✕"
    end

    return {
        n = G.UIT.ROOT,
        config = { align = "cm", minw = G.ROOM.T.w * 5, minh = G.ROOM.T.h * 5, padding = 0.1, colour = { 0, 0, 0, 0.62 } },
        nodes = {
            { n = G.UIT.C, config = { align = "cm", minw = G.ROOM.T.w * 0.96, minh = G.ROOM.T.h * 0.92, padding = 0.1 }, nodes = {
                { n = G.UIT.R, config = { align = "cr", padding = 0.04 }, nodes = {
                    UIBox_button({
                        button = "grdl_open_binder",
                        label = { close_char },
                        colour = G.C.CLEAR,
                        shadow = false,
                        minw = 0.8,
                        maxw = 0.8,
                        minh = 0.8,
                        scale = 0.55,
                        focus_args = { nav = "wide", snap_to = true }
                    })
                } },
                { n = G.UIT.R, config = { align = "cm", padding = 0.15, minh = G.ROOM.T.h * 0.75 }, nodes = {
                    { n = G.UIT.C, config = { align = "cm", padding = 0.1 }, nodes = left_nodes },
                    { n = G.UIT.C, config = { align = "cm", minw = 1.0 }, nodes = {} },
                    { n = G.UIT.C, config = { align = "tl", padding = 0.1 }, nodes = right_nodes }
                } }
            } }
        }
    }
end

local function default_adapter(runtime)
    runtime = runtime or rawget(_G, "G")
    local function show(definition)
        if not runtime or not runtime.FUNCS or not runtime.FUNCS.overlay_menu then return end
        if runtime.SETTINGS then runtime.SETTINGS.paused = true end
        runtime.FUNCS.overlay_menu({ definition = definition })
    end
    return {
        open_binder = function(namespace)
            show(BinderUI.create_overlay_definition(namespace))
        end,
        open_desk = function(namespace)
            show(BinderUI.create_desk_definition(namespace))
        end,
        refresh_desk = function(namespace)
            show(BinderUI.create_desk_definition(namespace))
        end,
        notify_failure = function()
            if rawget(_G, "play_sound") then
                pcall(play_sound, "tarot2", 0.76, 0.4)
            end
        end
    }
end

function BinderUI.install_runtime(namespace, runtime, adapter)
    namespace = namespace or rawget(_G, "Gradelatro")
    runtime = runtime or rawget(_G, "G")
    if not namespace or not runtime or not runtime.FUNCS then return false end
    adapter = adapter or default_adapter(runtime)

    runtime.FUNCS.grdl_open_binder = function(event)
        local state = BinderUI.open(namespace)
        if state and adapter.open_binder then adapter.open_binder(namespace, state, event) end
    end

    runtime.FUNCS.grdl_open_desk = function(event)
        local state = BinderUI.open_desk(namespace)
        if state and adapter.open_desk then adapter.open_desk(namespace, state, event) end
    end

    runtime.FUNCS.grdl_binder_page = function(event)
        if not event or not event.cycle_config then return end
        BinderUI.set_page(namespace, event.cycle_config.current_option)
        BinderUI.fill_card_areas(namespace)
    end

    runtime.FUNCS.grdl_submit_grading = function(event)
        local result = BinderUI.submit_grading(namespace, event_card_id(event), os.time())
        if result.ok then
            if adapter.refresh_desk then adapter.refresh_desk(namespace, namespace.desk_ui_state, event) end
        elseif adapter.notify_failure then
            adapter.notify_failure(namespace, namespace.desk_ui_state, event)
        end
    end

    return true
end

return BinderUI
