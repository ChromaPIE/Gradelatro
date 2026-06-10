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
    summary = "grdl_k_binder_summary",
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

local function summary_row(state)
    local summary = state.summary
    return row({
        ui_text(safe_localize(state.text_keys.summary, {
            summary.currency_g,
            summary.owned_cards,
            summary.raw_cards,
            summary.graded_cards,
            summary.grading_queue
        }), 0.32, G.C.WHITE)
    })
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
    return row({
        col({ ui_text(center_name(row_data), 0.3) }, { align = "cl", minw = 2.6 }),
        col({ ui_text(safe_localize("grdl_k_edition_" .. tostring(row_data.edition or "base")), 0.26) }, { align = "cl", minw = 1.2 }),
        col({ ui_text(fee and safe_localize("grdl_k_grading_fee", { fee }) or "", 0.28, G.C.GOLD) }, { align = "cr", minw = 0.9 }),
        UIBox_button({
            button = "grdl_submit_grading",
            label = { safe_localize("grdl_b_grade") },
            ref_table = { id = row_data.id },
            minw = 1.2,
            maxw = 1.2,
            minh = 0.55,
            scale = 0.3,
            colour = G.C.BLUE,
            focus_args = { nav = "wide" }
        })
    })
end

local function queue_row(queue_data)
    return row({
        col({ ui_text(center_name(queue_data), 0.3) }, { align = "cl", minw = 3.0 }),
        col({ ui_text(safe_localize("grdl_k_service_" .. tostring(queue_data.service or "standard")), 0.28) }, { align = "cl", minw = 1.5 }),
        col({ ui_text(eta_text(queue_data.remaining or 0), 0.28, queue_data.ready and G.C.GREEN or G.C.UI.TEXT_LIGHT) }, { align = "cr", minw = 1.4 })
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
