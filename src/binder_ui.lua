local BinderUI = {}

local function load_src(path)
    if rawget(_G, "SMODS") and SMODS.load_file then
        return assert(SMODS.load_file("src/" .. path))()
    end
    return dofile("src/" .. path)
end

local Binder = load_src("binder.lua")
local Grading = load_src("grading.lua")
local Persistence = load_src("persistence.lua")

local TEXT_KEYS = {
    title = "grdl_k_binder_title",
    summary = "grdl_k_binder_summary",
    empty = "grdl_k_binder_empty",
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

local function grading_fee_map(config, collection)
    local fees = {}
    for _, card in ipairs((collection and collection.cards) or {}) do
        if (card.status or "raw") == "raw" then
            fees[card.id] = Grading.fee_for(config, card)
        end
    end
    return fees
end

function BinderUI.default_state(collection, extras)
    extras = extras or {}
    return {
        text_keys = copy_text_keys(),
        summary = Binder.summary(collection),
        rows = Binder.card_rows(collection, { limit = 20 }),
        queue_rows = Grading.queue_rows(collection or {}, extras.now or os.time()),
        grading_fees = extras.grading_fees or {},
        revealed_count = extras.revealed_count or 0,
        last_reason = nil
    }
end

function BinderUI.open(namespace, now)
    if not namespace or not namespace.collection then return nil end
    now = now or os.time()

    local revealed_count = 0
    if namespace.config then
        local processed = Grading.process_due(namespace.config, namespace.collection, now)
        revealed_count = #processed.revealed
        if revealed_count > 0 then
            namespace.last_save_ok = Persistence.save(namespace)
        end
    end

    namespace.binder_ui_state = BinderUI.default_state(namespace.collection, {
        now = now,
        revealed_count = revealed_count,
        grading_fees = namespace.config and grading_fee_map(namespace.config, namespace.collection) or {}
    })
    return namespace.binder_ui_state
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
    end

    local state = BinderUI.open(namespace, now)
    if state and not result.ok then
        state.last_reason = result.reason
    end
    return result
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

local function safe_center_name(row)
    if rawget(_G, "localize") then
        local ok, value = pcall(localize, {
            type = "name_text",
            key = row.center_key,
            set = "Joker"
        })
        if ok and value then return value end
    end
    return tostring(row.name_key or row.center_key or row.id)
end

local function edition_text(edition)
    return safe_localize("grdl_k_edition_" .. tostring(edition or "base"))
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

local function card_row(state, row_data)
    local nodes = {
        col({ ui_text(safe_center_name(row_data), 0.32) }, { align = "cl", minw = 3.0 }),
        col({ ui_text(edition_text(row_data.edition), 0.28, G.C.UI.TEXT_LIGHT) }, { align = "cl", minw = 1.5 }),
        col({ ui_text(safe_localize(row_data.status_key), 0.28, G.C.UI.TEXT_LIGHT) }, { align = "cl", minw = 1.2 }),
        col({ ui_text(row_data.grade and tostring(row_data.grade) or "", 0.28, G.C.GOLD) }, { align = "cr", minw = 0.5 })
    }

    local fee = state.grading_fees and state.grading_fees[row_data.id] or nil
    if fee and row_data.status == "raw" then
        nodes[#nodes + 1] = UIBox_button({
            button = "grdl_submit_grading",
            label = {
                safe_localize("grdl_b_grade"),
                safe_localize("grdl_k_grading_fee", { fee })
            },
            ref_table = { id = row_data.id },
            minw = 1.5,
            maxw = 1.5,
            minh = 0.65,
            scale = 0.28,
            colour = G.C.BLUE,
            focus_args = { nav = "wide" }
        })
    end

    return row(nodes, { align = "cm" })
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

local function queue_row(queue_data)
    return row({
        col({ ui_text(safe_center_name(queue_data), 0.3) }, { align = "cl", minw = 3.0 }),
        col({ ui_text(safe_localize("grdl_k_service_" .. tostring(queue_data.service or "standard")), 0.28, G.C.UI.TEXT_LIGHT) }, { align = "cl", minw = 1.5 }),
        col({ ui_text(eta_text(queue_data.remaining or 0), 0.28, queue_data.ready and G.C.GREEN or G.C.UI.TEXT_LIGHT) }, { align = "cr", minw = 1.4 })
    }, { align = "cm" })
end

function BinderUI.create_overlay_definition(namespace)
    namespace = namespace or rawget(_G, "Gradelatro") or {}
    local state = namespace.binder_ui_state or BinderUI.open(namespace) or BinderUI.default_state(namespace.collection)
    local summary = state.summary
    local rows = {
        row({ ui_text(safe_localize(state.text_keys.title), 0.55, G.C.WHITE) }),
        row({
            ui_text(safe_localize(state.text_keys.summary, {
                summary.currency_g,
                summary.owned_cards,
                summary.raw_cards,
                summary.graded_cards,
                summary.grading_queue
            }), 0.32, G.C.WHITE)
        })
    }

    if (state.revealed_count or 0) > 0 then
        rows[#rows + 1] = row({ ui_text(safe_localize(state.text_keys.revealed, { state.revealed_count }), 0.34, G.C.GOLD) })
    end

    if #state.rows == 0 then
        rows[#rows + 1] = row({ ui_text(safe_localize(state.text_keys.empty), 0.34, G.C.UI.TEXT_INACTIVE) })
    else
        for _, card in ipairs(state.rows) do
            rows[#rows + 1] = card_row(state, card)
        end
    end

    if #(state.queue_rows or {}) > 0 then
        rows[#rows + 1] = row({ ui_text(safe_localize(state.text_keys.queue_title), 0.4, G.C.WHITE) })
        for _, entry in ipairs(state.queue_rows) do
            rows[#rows + 1] = queue_row(entry)
        end
    end

    if state.last_reason then
        rows[#rows + 1] = row({ ui_text(safe_localize("grdl_k_reason_" .. tostring(state.last_reason)), 0.3, G.C.RED) })
    end

    return create_UIBox_generic_options({
        back_func = "exit_overlay_menu",
        minw = 7.2,
        padding = 0.12,
        colour = G.C.L_BLACK,
        outline_colour = G.C.RED,
        contents = rows
    })
end

local function event_card_id(event)
    return event
        and event.config
        and event.config.ref_table
        and event.config.ref_table.id
        or nil
end

local function default_adapter(runtime)
    runtime = runtime or rawget(_G, "G")
    return {
        open_overlay = function(namespace)
            if not runtime or not runtime.FUNCS or not runtime.FUNCS.overlay_menu then return end
            if runtime.SETTINGS then runtime.SETTINGS.paused = true end
            runtime.FUNCS.overlay_menu({
                definition = BinderUI.create_overlay_definition(namespace)
            })
        end,
        refresh_overlay = function(namespace)
            if not runtime or not runtime.FUNCS or not runtime.FUNCS.overlay_menu then return end
            runtime.FUNCS.overlay_menu({
                definition = BinderUI.create_overlay_definition(namespace)
            })
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
        if state and adapter.open_overlay then adapter.open_overlay(namespace, state, event) end
    end

    runtime.FUNCS.grdl_submit_grading = function(event)
        BinderUI.submit_grading(namespace, event_card_id(event), os.time())
        if adapter.refresh_overlay then adapter.refresh_overlay(namespace, namespace.binder_ui_state, event) end
    end

    return true
end

return BinderUI
