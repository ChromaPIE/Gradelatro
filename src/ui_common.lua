local UICommon = {}

local ERROR_TEXT = "ERROR"

function UICommon.localize_text(key, vars)
    if not rawget(_G, "localize") then return key end
    if vars then
        local ok, value = pcall(localize, { type = "variable", key = key, vars = vars })
        if ok and value and value ~= ERROR_TEXT then return value end
    end
    local ok, value = pcall(localize, key)
    if ok and value and value ~= ERROR_TEXT then return value end
    return key
end

function UICommon.center_name(entry)
    entry = entry or {}
    if rawget(_G, "localize") and entry.center_key then
        local ok, value = pcall(localize, {
            type = "name_text",
            key = entry.center_key,
            set = "Joker"
        })
        if ok and value and value ~= ERROR_TEXT then return value end
    end
    return tostring(entry.name_key or entry.local_key or entry.center_key or entry.id)
end

function UICommon.text_node(text, scale, colour)
    return { n = G.UIT.T, config = { text = text, scale = scale or 0.35, colour = colour or G.C.UI.TEXT_LIGHT } }
end

function UICommon.row(nodes, config)
    config = config or {}
    config.align = config.align or "cm"
    config.padding = config.padding or 0.04
    return { n = G.UIT.R, config = config, nodes = nodes }
end

function UICommon.col(nodes, config)
    config = config or {}
    config.align = config.align or "cm"
    config.padding = config.padding or 0.04
    return { n = G.UIT.C, config = config, nodes = nodes }
end

function UICommon.fit_scale(text, base, budget_bytes)
    local length = #tostring(text or "")
    if budget_bytes and length > budget_bytes then
        return base * budget_bytes / length
    end
    return base
end

function UICommon.event_ref_id(event)
    return event
        and event.config
        and event.config.ref_table
        and event.config.ref_table.id
        or nil
end

return UICommon
