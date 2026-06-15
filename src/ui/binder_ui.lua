local BinderUI = {}

local function load_src(path)
    if rawget(_G, "SMODS") and SMODS.load_file then
        return assert(SMODS.load_file("src/" .. path))()
    end
    return dofile("src/" .. path)
end

local Binder = load_src("domain/binder.lua")
local Catalog = load_src("domain/catalog.lua")
local Grading = load_src("domain/grading.lua")
local Label = load_src("domain/label.lua")
local Loadout = load_src("domain/loadout.lua")
local Market = load_src("domain/market.lua")
local Persistence = load_src("core/persistence.lua")
local Proficiency = load_src("domain/proficiency.lua")
local SlabUI = load_src("ui/slab_ui.lua")
local Storage = load_src("core/storage.lua")
local TextInput = load_src("ui/text_input.lua")
local UICommon = load_src("ui/ui_common.lua")

local safe_localize = UICommon.localize_text
local center_name = UICommon.center_name
local ui_text = UICommon.text_node
local row = UICommon.row
local col = UICommon.col
local event_card_id = UICommon.event_ref_id

local PAGE_ROWS = { 5, 5 }

local DESK_PAGE_SIZE = 7

local CARD_INSPECT_SCALE = 2.2
local TRANSIENT_FEEDBACK_SECONDS = 2

local TEXT_KEYS = {
    title = "grdl_k_binder_title",
    empty = "grdl_k_binder_empty",
    hidden = "grdl_k_binder_hidden",
    desk = "grdl_b_desk",
    desk_title = "grdl_k_desk_title",
    queue_empty = "grdl_k_queue_empty",
    tab_progress = "grdl_k_tab_progress",
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

local function runtime_in_run()
    local runtime = rawget(_G, "G")
    return runtime ~= nil
        and runtime.STAGE ~= nil
        and runtime.STAGES ~= nil
        and runtime.STAGE == runtime.STAGES.RUN
end

local function now_seconds()
    local love_obj = rawget(_G, "love")
    if love_obj and love_obj.timer and type(love_obj.timer.getTime) == "function" then
        local ok, value = pcall(love_obj.timer.getTime)
        if ok and type(value) == "number" then return value end
    end
    return os.time()
end

local function clear_feedback(input)
    if type(input) ~= "table" then return end
    input.feedback = ""
    input.feedback_transient = nil
    input.feedback_until = nil
end

local function set_feedback(input, text, transient)
    if type(input) ~= "table" then return end
    input.feedback = text or ""
    if transient then
        input.feedback_transient = true
        input.feedback_until = now_seconds() + TRANSIENT_FEEDBACK_SECONDS
    else
        input.feedback_transient = nil
        input.feedback_until = nil
    end
end

local function clear_transient_feedback(input)
    if type(input) == "table" and input.feedback_transient then
        clear_feedback(input)
    end
end

local function decay_transient_feedback(input)
    if type(input) ~= "table" or not input.feedback_transient then return end
    if input.feedback_until and now_seconds() >= input.feedback_until then
        clear_feedback(input)
    end
end

local function suppress_selection(card)
    return UICommon.suppress_selection(card)
end

function BinderUI.countdown_text(seconds)
    seconds = math.floor(seconds or 0)
    if seconds <= 0 then
        return safe_localize("grdl_k_grading_ready")
    end
    local hours = math.floor(seconds / 3600)
    local minutes = math.floor((seconds % 3600) / 60)
    local secs = seconds % 60
    if hours > 0 then
        return string.format("%d:%02d:%02d", hours, minutes, secs)
    end
    return string.format("%d:%02d", minutes, secs)
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
    local catalog = UICommon.discover_catalog(namespace)
    if #catalog == 0 then return end
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
        queue_rows = Grading.queue_rows(namespace.collection, now),
        revealed_count = revealed_count,
        queue_page = 1
    }
    return namespace.desk_ui_state
end

function BinderUI.set_desk_page(namespace, page)
    local state = namespace and namespace.desk_ui_state or nil
    if not state then return nil end
    state.queue_page = Binder.page(state.queue_rows, page, DESK_PAGE_SIZE).page
    return state
end

function BinderUI.open_inspect(namespace, card_id, now, opts)
    if type(now) == "table" and opts == nil then
        opts = now
        now = nil
    end
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
        text_keys = copy_text_keys(),
        pending_sell = false,
        last_reason_text = "",
        close_func = opts and opts.close_func or "grdl_open_binder"
    }
    return namespace.inspect_ui_state
end

function BinderUI.inspect_from_card(namespace, card, opts)
    local record = card and card.grdl_record or nil
    if not record then return nil end
    opts = opts or {}
    local close_func = opts.close_func
        or card.grdl_inspect_close_func
        or (runtime_in_run() and "exit_overlay_menu" or "grdl_open_binder")
    local state = BinderUI.open_inspect(namespace, record.id, nil, { close_func = close_func })
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

function BinderUI.inspect_offer(namespace, offer)
    if not namespace or not offer or offer.mystery then return nil end
    local entry = {
        id = "grdl_offer_" .. tostring(offer.slot),
        offer_slot = offer.slot,
        center_key = offer.center_key,
        name_key = offer.local_key or offer.center_key,
        local_key = offer.local_key,
        edition = offer.edition or "base",
        rarity = offer.rarity,
        mod_id = offer.mod_id,
        mod_name = offer.mod_name,
        status = offer.graded and "graded" or "raw",
        grade = offer.grade,
        price = offer.price
    }
    namespace.inspect_ui_state = {
        entry = entry,
        text_keys = copy_text_keys(),
        offer_mode = true,
        pending_sell = false,
        last_reason_text = "",
        close_func = "grdl_open_market"
    }

    local runtime = rawget(_G, "G")
    if runtime and runtime.FUNCS and runtime.FUNCS.overlay_menu then
        if runtime.SETTINGS then runtime.SETTINGS.paused = true end
        runtime.FUNCS.overlay_menu({
            definition = BinderUI.create_inspect_definition(namespace)
        })
    end
    return namespace.inspect_ui_state
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
        Loadout.reconcile(namespace.collection)
        namespace.last_save_ok = Persistence.save(namespace)
        BinderUI.open_desk(namespace, now)
    end
    return result
end

function BinderUI.toggle_loadout(namespace, card_id)
    if not namespace or not namespace.collection then return { ok = false, reason = "missing_collection" } end
    local runtime = rawget(_G, "G")
    if runtime and runtime.STAGE ~= nil and runtime.STAGES and runtime.STAGE == runtime.STAGES.RUN then
        return { ok = false, reason = "loadout_locked" }
    end
    local collection = namespace.collection
    if Loadout.contains(collection, card_id) then
        local removed = Loadout.remove_card(collection, card_id)
        if removed.ok then namespace.last_save_ok = Persistence.save(namespace) end
        return removed
    end
    local card = Storage.find_card(collection, card_id)
    if not card then return { ok = false, reason = "unknown_card" } end
    local inspect_state = namespace.inspect_ui_state
    if card.status == "raw" and inspect_state and not inspect_state.pending_loadout_add then
        inspect_state.pending_loadout_add = true
        inspect_state.last_reason_text = safe_localize("grdl_k_loadout_raw_hint")
        return { ok = true, pending = true }
    end
    if inspect_state then inspect_state.pending_loadout_add = nil end
    local added = Loadout.add_card(collection, card_id)
    if added.ok then namespace.last_save_ok = Persistence.save(namespace) end
    return added
end

function BinderUI.commit_prof_text(namespace, card_id, kind, text)
    if not namespace or not namespace.collection then return { ok = false, reason = "missing_collection" } end
    local card = Storage.find_card(namespace.collection, card_id)
    if not card then return { ok = false, reason = "unknown_card" } end
    local result
    if kind == "note" then
        result = Proficiency.set_note(card, text)
    elseif kind == "badge" then
        result = Proficiency.set_badge(card, text)
    elseif kind == "badge_colour" then
        result = Proficiency.set_badge_colour(card, text)
    elseif kind == "tint" then
        result = Proficiency.set_tint(card, text)
    else
        return { ok = false, reason = "unknown_kind" }
    end
    if result.ok then namespace.last_save_ok = Persistence.save(namespace) end
    return result
end

function BinderUI.inspect_loadout(namespace, card_id, opts)
    opts = opts or {}
    local state = BinderUI.open_inspect(namespace, card_id, nil, {
        close_func = opts.close_func or "grdl_open_loadout"
    })
    if state then state.loadout_mode = true end
    return state
end

function BinderUI.open_personalization(namespace, card_id)
    if not namespace or not namespace.collection then return nil end
    local card = Storage.find_card(namespace.collection, card_id)
    if not card or card.status ~= "graded" then return nil end
    namespace.personalization_ui_state = { card_id = card_id, feedback = "" }
    return namespace.personalization_ui_state
end

local function preview_text_rows(text, max_lines, scale)
    local nodes = {}
    for _, line in ipairs(TextInput.split_lines(text, max_lines)) do
        nodes[#nodes + 1] = row({ ui_text(line ~= "" and line or " ", scale or 0.32, G.C.UI.TEXT_DARK) }, { padding = 0.02 })
    end
    return nodes
end

function BinderUI.open_text_input(namespace, card_id, kind)
    local runtime = rawget(_G, "G")
    if not runtime or not runtime.FUNCS or not runtime.FUNCS.overlay_menu then return end
    local card = Storage.find_card(namespace.collection or {}, card_id)
    if not card then return end
    local meta = card.proficiency or {}
    local existing = namespace.prof_text_input
    if not existing or existing.card_id ~= card_id or existing.kind ~= kind then
        local current = kind == "note" and meta.note or ""
        namespace.prof_text_input = { card_id = card_id, kind = kind, text = current or "", feedback = "" }
    end
    local input = namespace.prof_text_input
    clear_transient_feedback(input)
    local nodes = {
        row({ ui_text(safe_localize("grdl_b_prof_inscription"), 0.4, G.C.WHITE) }),
        row({ { n = G.UIT.C, config = { minw = 4.2, minh = 0.9, r = 0.08, colour = G.C.WHITE, emboss = 0.04 }, nodes = preview_text_rows(input.text, 4, 0.32) } }, { padding = 0.06 }),
        row({
            UICommon.outline_button({ button = "grdl_prof_text_paste", solid = true, minw = 1.35, minh = 0.55, lines = { { text = safe_localize("grdl_b_paste"), scale = 0.3 } } }),
            UICommon.outline_button({ button = "grdl_prof_text_clear", solid = true, minw = 1.35, minh = 0.55, lines = { { text = safe_localize("grdl_b_clear"), scale = 0.3 } } }),
            UICommon.outline_button({ button = "grdl_prof_text_commit", solid = true, minw = 1.35, minh = 0.55, lines = { { text = safe_localize("grdl_b_confirm"), scale = 0.3 } } })
        }, { padding = 0.05 }),
        row({ { n = G.UIT.T, config = { ref_table = input, ref_value = "feedback", scale = 0.32, colour = G.C.GOLD, func = "grdl_prof_feedback_decay" } } })
    }
    if runtime.SETTINGS then runtime.SETTINGS.paused = true end
    runtime.FUNCS.overlay_menu({ definition = create_UIBox_generic_options({
        back_func = "grdl_reopen_personalization",
        minw = 5.0,
        padding = 0.12,
        colour = G.C.L_BLACK,
        outline_colour = G.C.RED,
        contents = nodes
    }) })
end

function BinderUI.open_prof_input(namespace, card_id, kind)
    local runtime = rawget(_G, "G")
    if not runtime or not runtime.FUNCS or not runtime.FUNCS.overlay_menu then return end
    if kind == "note" then return BinderUI.open_text_input(namespace, card_id, kind) end
    if not rawget(_G, "create_text_input") then return end
    local card = Storage.find_card(namespace.collection or {}, card_id)
    if not card then return end
    local meta = card.proficiency or {}
    local current = (kind == "note" and meta.note)
        or (kind == "badge" and meta.badge_text)
        or (kind == "badge_colour" and meta.badge_colour)
        or (kind == "tint" and meta.tooltip_colour)
        or ""
    local is_hex = kind == "tint" or kind == "badge_colour"
    namespace.prof_input = { card_id = card_id, kind = kind, text = current or "", feedback = "" }
    local nodes = {
        row({ ui_text(safe_localize("grdl_b_prof_" .. kind), 0.4, G.C.WHITE) }),
        row({ create_text_input({
            ref_table = namespace.prof_input,
            ref_value = "text",
            max_length = is_hex and 6 or 24,
            -- extended_corpus needs all_caps off, or digits remap to shifted symbols.
            all_caps = false,
            extended_corpus = is_hex,
            prompt_text = is_hex and safe_localize("grdl_k_hex_prompt") or nil,
            w = 4
        }) }, { padding = 0.06 })
    }
    if is_hex then
        nodes[#nodes + 1] = row({
            { n = G.UIT.C, config = {
                minw = 1.2,
                minh = 0.4,
                r = 0.1,
                emboss = 0.05,
                colour = Proficiency.parse_hex(namespace.prof_input.text) or { 0.2, 0.2, 0.2, 1 },
                func = "grdl_hex_preview"
            }, nodes = {} }
        }, { padding = 0.05 })
    end
    nodes[#nodes + 1] = row({ UICommon.outline_button({
        button = "grdl_prof_commit",
        solid = true,
        minw = 1.6,
        minh = 0.6,
        lines = { { text = safe_localize("grdl_b_confirm"), scale = 0.34 } }
    }) }, { padding = 0.06 })
    nodes[#nodes + 1] = row({
        { n = G.UIT.T, config = { ref_table = namespace.prof_input, ref_value = "feedback", scale = 0.32, colour = G.C.GOLD } }
    })
    if runtime.SETTINGS then runtime.SETTINGS.paused = true end
    runtime.FUNCS.overlay_menu({ definition = create_UIBox_generic_options({
        back_func = "grdl_reopen_personalization",
        minw = 5.5,
        padding = 0.12,
        colour = G.C.L_BLACK,
        outline_colour = G.C.RED,
        contents = nodes
    }) })
end

function BinderUI.open_badge_input(namespace, card_id)
    local runtime = rawget(_G, "G")
    if not runtime or not runtime.FUNCS or not runtime.FUNCS.overlay_menu then return end
    if not rawget(_G, "create_text_input") then return end
    local card = Storage.find_card(namespace.collection or {}, card_id)
    if not card then return end
    local existing = namespace.prof_badge_input
    if not existing or existing.card_id ~= card_id then
        local meta = card.proficiency or {}
        namespace.prof_badge_input = {
            card_id = card_id,
            badge_text = meta.badge_text or "",
            badge_colour = meta.badge_colour or "",
            feedback = ""
        }
    end
    local input = namespace.prof_badge_input
    clear_transient_feedback(input)
    local nodes = {
        row({ ui_text(safe_localize("grdl_b_prof_badge"), 0.4, G.C.WHITE) }),
        row({ { n = G.UIT.C, config = { minw = 4.2, minh = 0.65, r = 0.08, colour = G.C.WHITE, emboss = 0.04 }, nodes = preview_text_rows(input.badge_text, 2, 0.32) } }, { padding = 0.05 }),
        row({
            UICommon.outline_button({ button = "grdl_prof_badge_paste", solid = true, minw = 1.35, minh = 0.55, lines = { { text = safe_localize("grdl_b_paste"), scale = 0.3 } } }),
            UICommon.outline_button({ button = "grdl_prof_badge_clear", solid = true, minw = 1.35, minh = 0.55, lines = { { text = safe_localize("grdl_b_clear"), scale = 0.3 } } })
        }, { padding = 0.04 }),
        row({ ui_text(safe_localize("grdl_b_prof_badge_colour"), 0.34, G.C.WHITE) }),
        row({ create_text_input({
            ref_table = input,
            ref_value = "badge_colour",
            max_length = 6,
            all_caps = false,
            extended_corpus = true,
            prompt_text = safe_localize("grdl_k_hex_prompt"),
            w = 3.0
        }) }, { padding = 0.04 }),
        row({ { n = G.UIT.C, config = {
            minw = 1.2,
            minh = 0.4,
            r = 0.1,
            emboss = 0.05,
            colour = Proficiency.parse_hex(input.badge_colour) or { 0.2, 0.2, 0.2, 1 },
            func = "grdl_badge_hex_preview"
        }, nodes = {} } }, { padding = 0.04 }),
        row({ UICommon.outline_button({
            button = "grdl_prof_badge_commit",
            solid = true,
            minw = 1.6,
            minh = 0.6,
            lines = { { text = safe_localize("grdl_b_confirm"), scale = 0.34 } }
        }) }, { padding = 0.05 }),
        row({ { n = G.UIT.T, config = { ref_table = input, ref_value = "feedback", scale = 0.32, colour = G.C.GOLD, func = "grdl_prof_feedback_decay" } } })
    }
    if runtime.SETTINGS then runtime.SETTINGS.paused = true end
    runtime.FUNCS.overlay_menu({ definition = create_UIBox_generic_options({
        back_func = "grdl_reopen_personalization",
        minw = 5.2,
        padding = 0.12,
        colour = G.C.L_BLACK,
        outline_colour = G.C.RED,
        contents = nodes
    }) })
end

function BinderUI.sell_from_inspect(namespace, card_id, now)
    if not namespace or not namespace.collection then
        return { ok = false, reason = "missing_collection" }
    end
    if not namespace.config then
        return { ok = false, reason = "missing_config" }
    end
    local state = namespace.inspect_ui_state
    if not state or not state.entry or state.entry.id ~= card_id then
        return { ok = false, reason = "missing_state" }
    end

    if not state.pending_sell then
        state.pending_sell = true
        state.last_reason_text = safe_localize("grdl_k_sell_arm_hint")
        return { ok = true, pending = true }
    end

    local result = Market.sell(namespace.config, namespace.collection, {
        card_id = card_id,
        now = now or os.time()
    })
    namespace.last_market_result = result
    if result.ok then
        Loadout.reconcile(namespace.collection)
        namespace.last_save_ok = Persistence.save(namespace)
    else
        state.pending_sell = false
        state.last_reason_text = safe_localize(reason_key(result.reason))
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
                    local card = Card(area.T.x + area.T.w / 2, area.T.y, G.CARD_W, G.CARD_H, (G.P_CARDS and G.P_CARDS.empty or nil), center)
                    local edition_flag = Catalog.edition_flags(entry.edition)
                    if edition_flag then card:set_edition(edition_flag, true, true) end
                    card.grdl_record = entry
                    suppress_selection(card)
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
    return UICommon.stat_chips(state.summary)
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
        rows[#rows + 1] = row({ ui_text(safe_localize(state.text_keys.hidden, { state.hidden }), 0.32, G.C.UI.TEXT_INACTIVE) })
    end

    local controls = {}
    local grid_cycle = UICommon.page_cycle(state.page_view, "grdl_binder_page")
    if grid_cycle then
        controls[#controls + 1] = col({ grid_cycle })
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
    controls[#controls + 1] = col({
        UIBox_button({
            button = "grdl_open_market",
            label = { safe_localize("grdl_b_market") },
            minw = 2.2,
            maxw = 2.2,
            minh = 0.7,
            scale = 0.34,
            colour = G.C.GREEN,
            focus_args = { nav = "wide" }
        })
    })
    controls[#controls + 1] = col({
        UIBox_button({
            button = "grdl_open_loadout",
            label = { safe_localize("grdl_b_loadout") },
            minw = 2.2,
            maxw = 2.2,
            minh = 0.7,
            scale = 0.34,
            colour = G.C.PURPLE,
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

local QUEUE_BAR_W = 2.2
local QUEUE_BAR_H = 0.3

local function queue_bar(queue_data)
    local info = {
        due_at = queue_data.due_at,
        submitted_at = queue_data.submitted_at,
        progress = math.max(0, math.min(1, queue_data.progress or 0)),
        countdown = ""
    }
    -- the engine's native progress_bar channel redraws the fill from
    -- info.progress every frame; the tick only has to keep info fresh
    return { n = G.UIT.C, config = { align = "cm", padding = 0.05, r = 0.1, colour = G.C.BLACK, emboss = 0.05 }, nodes = {
        { n = G.UIT.C, config = {
            align = "cm",
            minw = QUEUE_BAR_W,
            minh = QUEUE_BAR_H,
            r = 0.07,
            colour = G.C.BLACK,
            collideable = true,
            func = "grdl_queue_tick",
            ref_table = info,
            progress_bar = {
                ref_table = info,
                ref_value = "progress",
                max = 1,
                empty_col = G.C.BLACK,
                filled_col = queue_data.ready and G.C.GREEN or G.C.BLUE
            }
        } }
    } }
end

local function attach_countdown_tip(element, info)
    if not rawget(_G, "UIBox") then return end
    element.children.grdl_tip = UIBox({
        definition = { n = G.UIT.ROOT, config = { align = "cm", colour = G.C.CLEAR, padding = 0.05 }, nodes = {
            { n = G.UIT.R, config = { align = "cm", padding = 0.08, r = 0.1, colour = G.C.BLACK, emboss = 0.05 }, nodes = {
                { n = G.UIT.T, config = { ref_table = info, ref_value = "countdown", scale = 0.34, colour = G.C.WHITE } }
            } }
        } },
        config = { instance_type = "POPUP", align = "tm", offset = { x = 0, y = -0.05 }, major = element, parent = element }
    })
    if element.children.grdl_tip.states and element.children.grdl_tip.states.collide then
        element.children.grdl_tip.states.collide.can = false
    end
end

local function queue_row(queue_data)
    local name = center_name(queue_data)
    return row({
        col({ ui_text(name, UICommon.fit_scale(name, 0.36, 18)) }, {
            align = "cl",
            minw = 2.2,
            collideable = true,
            func = "grdl_row_preview",
            ref_table = { center_key = queue_data.center_key, edition = queue_data.edition }
        }),
        col({ ui_text(safe_localize("grdl_k_service_" .. tostring(queue_data.service or "standard")), 0.32) }, { align = "cl", minw = 1.1 }),
        col({ queue_bar(queue_data) }, { align = "cr", minw = 2.5 })
    }, { padding = 0.05 })
end

local function desk_tab_root(nodes)
    return { n = G.UIT.ROOT, config = { align = "tm", colour = G.C.CLEAR, minw = 6.6, minh = 5.0, padding = 0.05 }, nodes = nodes }
end

local function queue_tab_definition(state)
    return function()
        local view = Binder.page(state.queue_rows, state.queue_page, DESK_PAGE_SIZE)
        state.queue_page = view.page
        local nodes = {}
        if view.total == 0 then
            nodes[#nodes + 1] = row({ ui_text(safe_localize(state.text_keys.queue_empty), 0.34, G.C.UI.TEXT_INACTIVE) })
        else
            for _, entry in ipairs(view.items) do
                nodes[#nodes + 1] = queue_row(entry)
            end
        end
        local cycle = UICommon.page_cycle(view, "grdl_desk_queue_page")
        if cycle then nodes[#nodes + 1] = row({ cycle }, { padding = 0.05 }) end
        return desk_tab_root(nodes)
    end
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

    rows[#rows + 1] = row({
        create_tabs({
            tabs = {
                {
                    label = safe_localize(state.text_keys.tab_progress),
                    chosen = true,
                    tab_definition_function = queue_tab_definition(state)
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
        col({ inspect_text(safe_localize(label_key), 0.38, G.C.UI.TEXT_INACTIVE, regular_font) }, { align = "cl", minw = 2.1 }),
        col({ inspect_text(value, 0.38, G.C.WHITE, regular_font) }, { align = "cl", minw = 3.0 })
    }, { align = "cl", padding = 0.07 })
end

local function build_inspect_card(namespace, entry, catalog_entry)
    if not rawget(_G, "CardArea") or not rawget(_G, "Card") then return nil end
    local centers = G.P_CENTERS or {}
    local center = entry.center_key and centers[entry.center_key] or nil
    if not center then return nil end

    local area = CardArea(
        G.ROOM.T.x + 0.2 * G.ROOM.T.w / 2, G.ROOM.T.h,
        CARD_INSPECT_SCALE * G.CARD_W,
        CARD_INSPECT_SCALE * G.CARD_H,
        { card_limit = 1, type = "title", highlight_limit = 0, collection = true })
    local card = Card(area.T.x + area.T.w / 2, area.T.y, CARD_INSPECT_SCALE * G.CARD_W, CARD_INSPECT_SCALE * G.CARD_H, (G.P_CARDS and G.P_CARDS.empty or nil), center)
    local edition_flag = Catalog.edition_flags(entry.edition)
    if edition_flag then card:set_edition(edition_flag, true, true) end
    suppress_selection(card)
    area:emplace(card)
    if entry.status == "graded" and not entry.offer_slot then
        pcall(SlabUI.attach_above, card, entry, catalog_entry, { scale = CARD_INSPECT_SCALE * 0.52 })
    end
    namespace.inspect_area = area
    return area
end

local function inspect_action_button(button_key, ref_id, lines, regular_font, opts)
    opts = opts or {}
    return UICommon.outline_button({
        button = button_key,
        ref = { id = ref_id },
        lines = lines,
        font = regular_font,
        colour = opts.colour,
        outline_colour = opts.outline_colour,
        solid = opts.solid
    })
end

local function set_state_colour(target, source)
    if type(target) ~= "table" or type(source) ~= "table" then return end
    target[1], target[2], target[3], target[4] = source[1], source[2], source[3], source[4]
end

local PROF_PERSONALIZATION = {
    { key = "inscription", button = "grdl_prof_inscription", label = "grdl_b_prof_inscription", level = 2, gate = Proficiency.can_note },
    { key = "eternal", button = "grdl_prof_eternal", label = "grdl_b_prof_eternal", level = 3, gate = Proficiency.can_eternal },
    { key = "badge", button = "grdl_prof_badge", label = "grdl_b_prof_badge", level = 4, gate = Proficiency.can_badge },
    { key = "tint", button = "grdl_prof_tint", label = "grdl_b_prof_tint", level = 5, gate = Proficiency.can_tint }
}

local function personalization_row(card, state, item, regular_font)
    local unlocked = item.gate(card)
    local fill = G.C.CLEAR
    if item.key == "eternal" then
        state.eternal_button_text = safe_localize("grdl_b_prof_eternal")
        state.eternal_button_colour = state.eternal_button_colour or { 0, 0, 0, 0 }
        set_state_colour(state.eternal_button_colour, (card.proficiency and card.proficiency.eternal) and G.C.GREEN or G.C.CLEAR)
        fill = state.eternal_button_colour
    end

    local lines = {
        { text = safe_localize(item.label), colour = unlocked and G.C.WHITE or G.C.UI.TEXT_INACTIVE }
    }
    if not unlocked then
        lines[#lines + 1] = {
            text = safe_localize("grdl_k_prof_unlocks_at", { Proficiency.level_label(item.level) }),
            scale = 0.26,
            colour = G.C.UI.TEXT_INACTIVE
        }
    end

    return UICommon.outline_button({
        id = item.button,
        button = item.button,
        ref = { id = card.id },
        lines = lines,
        font = regular_font,
        minw = 2.6,
        minh = unlocked and 0.62 or 0.82,
        colour = fill,
        outline_colour = unlocked and G.C.WHITE or G.C.UI.TEXT_INACTIVE,
        disabled = not unlocked
    })
end

local function inspect_action_row(namespace, state, entry, regular_font)
    local actions = {}

    local runtime = rawget(_G, "G")
    local in_run_now = runtime ~= nil
        and runtime.STAGE ~= nil
        and runtime.STAGES ~= nil
        and runtime.STAGE == runtime.STAGES.RUN
        and runtime.GAME ~= nil

    if entry.status == "raw" and not state.loadout_mode then
        local ok_fee, fee = pcall(Grading.fee_for, namespace.config or {}, entry)
        actions[#actions + 1] = inspect_action_button("grdl_inspect_submit", entry.id, {
            { text = safe_localize("grdl_b_grade") },
            { text = safe_localize("grdl_k_grading_fee", { ok_fee and fee or 0 }), scale = 0.3, colour = G.C.GOLD }
        }, regular_font)
    end

    if (entry.status == "raw" or entry.status == "graded") and not state.loadout_mode then
        local ok_quote, quote = pcall(Market.sell_quote, namespace.config or {}, namespace.collection or {}, entry)
        actions[#actions + 1] = inspect_action_button("grdl_inspect_sell", entry.id, {
            { text = safe_localize("grdl_b_sell") },
            { text = safe_localize("grdl_k_grading_fee", { ok_quote and quote or 0 }), scale = 0.3, colour = G.C.GOLD }
        }, regular_font)
    end

    if (entry.status == "raw" or entry.status == "graded") and not state.loadout_mode and not in_run_now then
        local member = Loadout.contains(namespace.collection or {}, entry.id)
        state.loadout_button_text = safe_localize(member and "grdl_b_loadout_remove" or "grdl_b_loadout_add")
        actions[#actions + 1] = inspect_action_button("grdl_loadout_toggle", entry.id, {
            { ref_table = state, ref_value = "loadout_button_text" }
        }, regular_font)
    end

    if entry.status == "graded" then
        actions[#actions + 1] = inspect_action_button("grdl_prof_personalize", entry.id, {
            { text = safe_localize("grdl_b_prof_personalize") }
        }, regular_font)
    end

    if #actions == 0 then return nil end

    local action_cols = {}
    for index, node in ipairs(actions) do
        if index > 1 then
            action_cols[#action_cols + 1] = { n = G.UIT.C, config = { align = "cm", minw = 0.25 }, nodes = {} }
        end
        action_cols[#action_cols + 1] = node
    end
    return action_cols
end

function BinderUI.create_personalization_definition(namespace)
    namespace = namespace or rawget(_G, "Gradelatro") or {}
    local state = namespace.personalization_ui_state
    if not state then
        return create_UIBox_generic_options({ back_func = "grdl_open_binder", contents = {} })
    end

    local card = Storage.find_card(namespace.collection or {}, state.card_id)
    if not card then
        return create_UIBox_generic_options({ back_func = "grdl_open_binder", contents = {} })
    end

    local regular_font = UICommon.noto_regular()
    local dynamic_state = namespace.inspect_ui_state or state
    local rows = {
        row({ ui_text(safe_localize("grdl_b_prof_personalize"), 0.45, G.C.WHITE) }, { padding = 0.05 })
    }
    for _, item in ipairs(PROF_PERSONALIZATION) do
        rows[#rows + 1] = row({ personalization_row(card, dynamic_state, item, regular_font) }, { padding = 0.035 })
    end
    rows[#rows + 1] = row({
        { n = G.UIT.T, config = { ref_table = state, ref_value = "feedback", scale = 0.32, colour = G.C.GOLD } }
    }, { align = "cm", padding = 0.02 })

    return create_UIBox_generic_options({
        back_func = "grdl_reopen_inspect",
        minw = 4.4,
        padding = 0.12,
        colour = G.C.L_BLACK,
        outline_colour = G.C.RED,
        contents = rows
    })
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
    local mod_display = (catalog_entry and catalog_entry.mod_name) or entry.mod_name or entry.mod_id or ""

    local left_nodes = {}
    left_nodes[#left_nodes + 1] = row({}, { minh = entry.status == "graded" and 1.5 or 0.2 })
    local area = build_inspect_card(namespace, entry, catalog_entry)
    if area then
        left_nodes[#left_nodes + 1] = row({ { n = G.UIT.O, config = { object = area } } }, { padding = 0.02 })
    end

    local right_nodes = {
        row({ inspect_text(mod_display, 0.5, G.C.UI.TEXT_LIGHT, regular_font) }, { align = "cl", padding = 0.03 }),
        row({ inspect_text(center_name(entry), 0.8, G.C.WHITE, bold_font) }, { align = "cl", padding = 0.05 }),
        row({}, { minh = 0.4 }),
        inspect_detail_row("grdl_k_detail_source", mod_display, regular_font),
        inspect_detail_row("grdl_k_detail_rarity", safe_localize("grdl_k_rarity_" .. tostring(entry.rarity or "common")), regular_font),
        inspect_detail_row("grdl_k_detail_edition", inspect_edition_text(entry), regular_font)
    }
    if not state.offer_mode then
        right_nodes[#right_nodes + 1] = inspect_detail_row("grdl_k_detail_date", inspect_date_text(entry), regular_font)
        right_nodes[#right_nodes + 1] = inspect_detail_row("grdl_k_detail_price", safe_localize("grdl_k_stat_g", { entry.acquired_price or 0 }), regular_font)
    end
    right_nodes[#right_nodes + 1] = inspect_detail_row("grdl_k_detail_psa", inspect_psa_text(entry), regular_font)
    if not state.offer_mode then
        local inspected_card = Storage.find_card(namespace.collection or {}, entry.id)
        local badge_text = inspected_card and inspected_card.proficiency and inspected_card.proficiency.badge_text or nil
        if badge_text and rawget(_G, "create_badge") then
            right_nodes[#right_nodes + 1] = row({ create_badge(badge_text, Proficiency.badge_colour(inspected_card, G.C.PURPLE), G.C.WHITE) }, { align = "cl", padding = 0.03 })
        end
    end

    local action_cols
    if state.offer_mode then
        action_cols = {
            inspect_action_button("grdl_bm_buy", entry.offer_slot, {
                { text = safe_localize("grdl_b_buy") },
                { text = safe_localize("grdl_k_grading_fee", { entry.price or 0 }), scale = 0.3, colour = G.C.GOLD }
            }, regular_font)
        }
    else
        action_cols = inspect_action_row(namespace, state, entry, regular_font)
    end
    if action_cols then
        right_nodes[#right_nodes + 1] = row({}, { minh = 0.35 })
        right_nodes[#right_nodes + 1] = row(action_cols, { align = "cl", padding = 0.04 })
        right_nodes[#right_nodes + 1] = row({
            { n = G.UIT.T, config = { ref_table = state, ref_value = "last_reason_text", scale = 0.34, colour = G.C.RED } }
        }, { align = "cl" })
    end

    local close_char = "X"
    if regular_font and regular_font.FONT and regular_font.FONT.hasGlyphs and regular_font.FONT:hasGlyphs("✕") then
        close_char = "✕"
    end

    local close_func = state.close_func or (state.offer_mode and "grdl_open_market" or "grdl_open_binder")

    return {
        n = G.UIT.ROOT,
        config = { align = "cm", minw = G.ROOM.T.w * 5, minh = G.ROOM.T.h * 5, padding = 0.1, colour = { 0, 0, 0, 0.75 } },
        nodes = {
            { n = G.UIT.C, config = { align = "cm", minw = G.ROOM.T.w * 0.96, minh = G.ROOM.T.h * 0.92, padding = 0.1 }, nodes = {
                { n = G.UIT.R, config = { align = "cr", padding = 0.04 }, nodes = {
                    { n = G.UIT.C, config = { align = "cm", minw = 0.8, minh = 0.8, r = 0.1, hover = true, colour = G.C.CLEAR, button = close_func, focus_args = { nav = "wide", snap_to = true } }, nodes = {
                        { n = G.UIT.T, config = { text = close_char, scale = 0.55, colour = G.C.WHITE, font = regular_font } }
                    } }
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

    UICommon.install_preview(runtime.FUNCS)

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

    local function reopen_inspect(card_id, opts)
        opts = opts or {}
        local previous_state = namespace.inspect_ui_state
        local close_func = opts.close_func or (previous_state and previous_state.close_func) or nil
        local loadout_mode = opts.loadout_mode
        if loadout_mode == nil then
            loadout_mode = previous_state and previous_state.loadout_mode or nil
        end
        BinderUI.open(namespace)
        local state = BinderUI.open_inspect(namespace, card_id, nil, { close_func = close_func })
        if state and loadout_mode then state.loadout_mode = true end
        if state and runtime.FUNCS.overlay_menu then
            if runtime.SETTINGS then runtime.SETTINGS.paused = true end
            runtime.FUNCS.overlay_menu({
                definition = BinderUI.create_inspect_definition(namespace)
            })
        end
        return state
    end

    local function close_inspect(event)
        local state = namespace.inspect_ui_state
        local close_func = state and state.close_func or "grdl_open_binder"
        if runtime.FUNCS[close_func] then
            runtime.FUNCS[close_func](event or {})
        elseif runtime.FUNCS.grdl_open_binder then
            runtime.FUNCS.grdl_open_binder(event or {})
        end
    end

    runtime.FUNCS.grdl_inspect_submit = function(event)
        local card_id = event_card_id(event)
        local result = BinderUI.submit_grading(namespace, card_id, os.time())
        if result.ok then
            reopen_inspect(card_id)
        else
            local state = namespace.inspect_ui_state
            if state then
                state.last_reason_text = safe_localize(reason_key(result.reason))
            end
            if rawget(_G, "play_sound") then
                pcall(play_sound, "tarot2", 0.76, 0.4)
            end
        end
    end

    runtime.FUNCS.grdl_inspect_sell = function(event)
        local card_id = event_card_id(event)
        local result = BinderUI.sell_from_inspect(namespace, card_id, os.time())
        if result.ok and not result.pending then
            close_inspect(event)
        elseif not result.ok and rawget(_G, "play_sound") then
            pcall(play_sound, "tarot2", 0.76, 0.4)
        end
    end

    runtime.FUNCS.grdl_loadout_toggle = function(event)
        local card_id = event_card_id(event)
        local result = BinderUI.toggle_loadout(namespace, card_id)
        namespace.last_loadout_result = result
        local state = namespace.inspect_ui_state
        if result.ok and not result.pending then
            -- in-place label flip: a full overlay reopen plays the exit and
            -- enter animations and breaks continuity
            if state then
                local member = Loadout.contains(namespace.collection or {}, card_id)
                state.loadout_button_text = safe_localize(member and "grdl_b_loadout_remove" or "grdl_b_loadout_add")
                state.last_reason_text = ""
            end
        elseif not result.ok then
            if state then
                state.last_reason_text = safe_localize(reason_key(result.reason))
            end
            if rawget(_G, "play_sound") then
                pcall(play_sound, "tarot2", 0.76, 0.4)
            end
        end
    end

    runtime.FUNCS.grdl_reopen_inspect = function()
        local personal = namespace.personalization_ui_state
        if personal and personal.card_id then reopen_inspect(personal.card_id) end
    end

    runtime.FUNCS.grdl_reopen_personalization = function()
        local personal = namespace.personalization_ui_state
        if not (personal and personal.card_id) then return end
        local state = BinderUI.open_personalization(namespace, personal.card_id)
        if state and runtime.FUNCS.overlay_menu then
            if runtime.SETTINGS then runtime.SETTINGS.paused = true end
            runtime.FUNCS.overlay_menu({
                definition = BinderUI.create_personalization_definition(namespace)
            })
        end
    end

    runtime.FUNCS.grdl_prof_personalize = function(event)
        local card_id = event_card_id(event)
        local state = BinderUI.open_personalization(namespace, card_id)
        if state and runtime.FUNCS.overlay_menu then
            if runtime.SETTINGS then runtime.SETTINGS.paused = true end
            runtime.FUNCS.overlay_menu({
                definition = BinderUI.create_personalization_definition(namespace)
            })
        end
    end

    runtime.FUNCS.grdl_prof_eternal = function(event)
        local card_id = event_card_id(event)
        local card = Storage.find_card(namespace.collection or {}, card_id)
        if not card then return end
        local enabled = not (card.proficiency and card.proficiency.eternal)
        local result = Proficiency.set_eternal(card, enabled)
        local state = namespace.inspect_ui_state
        if not result.ok then
            if state then state.last_reason_text = safe_localize(reason_key(result.reason)) end
            return
        end
        namespace.last_save_ok = Persistence.save(namespace)
        local game = rawget(_G, "G")
        for _, joker in ipairs((game and game.jokers and game.jokers.cards) or {}) do
            if joker.ability and joker.ability.grdl_loadout_id == card_id then
                if joker.set_eternal then
                    pcall(joker.set_eternal, joker, enabled)
                else
                    joker.ability.eternal = enabled or nil
                end
            end
        end
        if state then
            state.eternal_button_text = safe_localize("grdl_b_prof_eternal")
            state.eternal_button_colour = state.eternal_button_colour or { 0, 0, 0, 0 }
            set_state_colour(state.eternal_button_colour, enabled and G.C.GREEN or G.C.CLEAR)
        end
        local personal_state = namespace.personalization_ui_state
        if personal_state then
            personal_state.eternal_button_text = safe_localize("grdl_b_prof_eternal")
            personal_state.eternal_button_colour = personal_state.eternal_button_colour or { 0, 0, 0, 0 }
            set_state_colour(personal_state.eternal_button_colour, enabled and G.C.GREEN or G.C.CLEAR)
        end
    end

    runtime.FUNCS.grdl_prof_inscription = function(event)
        BinderUI.open_prof_input(namespace, event_card_id(event), "note")
    end
    runtime.FUNCS.grdl_prof_note = function(event)
        BinderUI.open_prof_input(namespace, event_card_id(event), "note")
    end
    runtime.FUNCS.grdl_prof_badge = function(event)
        BinderUI.open_badge_input(namespace, event_card_id(event))
    end
    runtime.FUNCS.grdl_prof_tint = function(event)
        BinderUI.open_prof_input(namespace, event_card_id(event), "tint")
    end

    runtime.FUNCS.grdl_prof_feedback_decay = function(element)
        local input = element and element.config and element.config.ref_table or nil
        decay_transient_feedback(input)
    end

    runtime.FUNCS.grdl_prof_text_paste = function()
        local input = namespace.prof_text_input
        local result = TextInput.apply_paste(input)
        if result.ok then
            clear_feedback(input)
            BinderUI.open_text_input(namespace, input.card_id, input.kind)
        elseif input then
            set_feedback(input, safe_localize(reason_key(result.reason)), result.reason == "empty_clipboard")
        end
    end

    runtime.FUNCS.grdl_prof_text_clear = function()
        local input = namespace.prof_text_input
        if input then
            TextInput.clear(input)
            clear_feedback(input)
            BinderUI.open_text_input(namespace, input.card_id, input.kind)
        end
    end

    runtime.FUNCS.grdl_prof_text_commit = function()
        local input = namespace.prof_text_input
        if not input then return end
        local result = BinderUI.commit_prof_text(namespace, input.card_id, input.kind, input.text)
        if result.ok then
            if namespace.inspect_ui_state and namespace.inspect_ui_state.loadout_mode then
                BinderUI.inspect_loadout(namespace, input.card_id, {
                    close_func = namespace.inspect_ui_state.close_func
                })
            else
                reopen_inspect(input.card_id)
            end
        else
            set_feedback(input, safe_localize(reason_key(result.reason)))
        end
    end

    runtime.FUNCS.grdl_prof_badge_paste = function()
        local input = namespace.prof_badge_input
        if not input then return end
        local temp = { text = input.badge_text }
        local result = TextInput.apply_paste(temp)
        if result.ok then
            input.badge_text = temp.text
            clear_feedback(input)
            BinderUI.open_badge_input(namespace, input.card_id)
        else
            set_feedback(input, safe_localize(reason_key(result.reason)), result.reason == "empty_clipboard")
        end
    end

    runtime.FUNCS.grdl_prof_badge_clear = function()
        local input = namespace.prof_badge_input
        if input then
            input.badge_text = ""
            clear_feedback(input)
            BinderUI.open_badge_input(namespace, input.card_id)
        end
    end

    runtime.FUNCS.grdl_prof_badge_commit = function()
        local input = namespace.prof_badge_input
        if not input then return end
        if input.badge_colour ~= "" and not Proficiency.parse_hex(input.badge_colour) then
            set_feedback(input, safe_localize(reason_key("invalid_hex")))
            return
        end
        local text_result = BinderUI.commit_prof_text(namespace, input.card_id, "badge", input.badge_text)
        local colour_result = text_result.ok and BinderUI.commit_prof_text(namespace, input.card_id, "badge_colour", input.badge_colour) or text_result
        if colour_result.ok then
            if namespace.inspect_ui_state and namespace.inspect_ui_state.loadout_mode then
                BinderUI.inspect_loadout(namespace, input.card_id, {
                    close_func = namespace.inspect_ui_state.close_func
                })
            else
                reopen_inspect(input.card_id)
            end
        else
            set_feedback(input, safe_localize(reason_key(colour_result.reason)))
        end
    end

    runtime.FUNCS.grdl_prof_commit = function(event)
        local input = namespace.prof_input
        if not input then return end
        local result = BinderUI.commit_prof_text(namespace, input.card_id, input.kind, input.text)
        if result.ok then
            if namespace.inspect_ui_state and namespace.inspect_ui_state.loadout_mode then
                BinderUI.inspect_loadout(namespace, input.card_id, {
                    close_func = namespace.inspect_ui_state.close_func
                })
            else
                reopen_inspect(input.card_id)
            end
        else
            set_feedback(input, safe_localize(reason_key(result.reason)))
            if rawget(_G, "play_sound") then
                pcall(play_sound, "tarot2", 0.76, 0.4)
            end
        end
    end

    runtime.FUNCS.grdl_hex_preview = function(element)
        local input = namespace.prof_input
        if not input or not element or not element.config then return end
        local parsed = Proficiency.parse_hex(input.text)
        local target = element.config.colour
        if parsed and type(target) == "table" then
            target[1], target[2], target[3], target[4] = parsed[1], parsed[2], parsed[3], 1
        end
    end

    runtime.FUNCS.grdl_badge_hex_preview = function(element)
        local input = namespace.prof_badge_input
        if not input or not element or not element.config then return end
        local parsed = Proficiency.parse_hex(input.badge_colour)
        local target = element.config.colour
        if parsed and type(target) == "table" then
            target[1], target[2], target[3], target[4] = parsed[1], parsed[2], parsed[3], 1
        end
    end

    runtime.FUNCS.grdl_desk_queue_page = function(event)
        if not event or not event.cycle_config then return end
        BinderUI.set_desk_page(namespace, event.cycle_config.current_option)
        local state = namespace.desk_ui_state
        if not (state and UICommon.swap_tab_contents(queue_tab_definition(state))) then
            if adapter.refresh_desk then adapter.refresh_desk(namespace, state, event) end
        end
    end

    runtime.FUNCS.grdl_queue_tick = function(element)
        local info = element and element.config and element.config.ref_table or nil
        if not info then return end
        local now = os.time()
        local remaining = (info.due_at or 0) - now
        info.countdown = BinderUI.countdown_text(remaining)
        local duration = math.max(1, (info.due_at or now) - (info.submitted_at or info.due_at or now))
        info.progress = math.max(0, math.min(1, 1 - math.max(0, remaining) / duration))
        local bar = element.config.progress_bar
        if bar then
            bar.filled_col = remaining <= 0 and G.C.GREEN or G.C.BLUE
        end

        if element.states and element.states.hover and element.states.hover.is then
            if element.children and not element.children.grdl_tip then
                pcall(attach_countdown_tip, element, info)
            end
        elseif element.children and element.children.grdl_tip then
            element.children.grdl_tip:remove()
            element.children.grdl_tip = nil
        end
    end

    return true
end

return BinderUI
