local BinderUI = {}

local function load_src(path)
    if rawget(_G, "SMODS") and SMODS.load_file then
        return assert(SMODS.load_file("src/" .. path))()
    end
    return dofile("src/" .. path)
end

local Binder = load_src("binder.lua")

local TEXT_KEYS = {
    title = "grdl_k_binder_title",
    summary = "grdl_k_binder_summary",
    empty = "grdl_k_binder_empty"
}

local function copy_text_keys()
    local out = {}
    for key, value in pairs(TEXT_KEYS) do
        out[key] = value
    end
    return out
end

function BinderUI.default_state(collection)
    return {
        text_keys = copy_text_keys(),
        summary = Binder.summary(collection),
        rows = Binder.card_rows(collection, { limit = 20 })
    }
end

function BinderUI.open(namespace)
    if not namespace or not namespace.collection then return nil end
    namespace.binder_ui_state = BinderUI.default_state(namespace.collection)
    return namespace.binder_ui_state
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

local function card_row(card_row)
    return row({
        col({ ui_text(safe_center_name(card_row), 0.32) }, { align = "cl", minw = 3.0 }),
        col({ ui_text(edition_text(card_row.edition), 0.28, G.C.UI.TEXT_LIGHT) }, { align = "cl", minw = 1.5 }),
        col({ ui_text(safe_localize(card_row.status_key), 0.28, G.C.UI.TEXT_LIGHT) }, { align = "cl", minw = 1.2 }),
        col({ ui_text(card_row.grade and tostring(card_row.grade) or "", 0.28, G.C.GOLD) }, { align = "cr", minw = 0.5 })
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

    if #state.rows == 0 then
        rows[#rows + 1] = row({ ui_text(safe_localize(state.text_keys.empty), 0.34, G.C.UI.TEXT_INACTIVE) })
    else
        for _, card in ipairs(state.rows) do
            rows[#rows + 1] = card_row(card)
        end
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

local function default_adapter(runtime)
    runtime = runtime or rawget(_G, "G")
    return {
        open_overlay = function(namespace)
            if not runtime or not runtime.FUNCS or not runtime.FUNCS.overlay_menu then return end
            if runtime.SETTINGS then runtime.SETTINGS.paused = true end
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

    return true
end

return BinderUI
