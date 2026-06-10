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

local function font_by_file(fonts, pattern)
    for _, font in ipairs(fonts or {}) do
        if type(font.file) == "string" and font.file:find(pattern) then return font end
    end
    return nil
end

function UICommon.noto_bold(fonts, lang)
    local runtime = rawget(_G, "G")
    fonts = fonts or (runtime and runtime.FONTS) or {}
    lang = lang or (runtime and runtime.LANG) or nil
    if lang and lang.font and type(lang.font.file) == "string" and lang.font.file:find("Noto") then
        return lang.font
    end
    return font_by_file(fonts, "GoNotoCurrent%-Bold") or font_by_file(fonts, "NotoSans%-Bold")
end

function UICommon.noto_regular(fonts)
    local runtime = rawget(_G, "G")
    fonts = fonts or (runtime and runtime.FONTS) or {}
    return font_by_file(fonts, "GoNotoCJKCore") or UICommon.noto_bold(fonts)
end

function UICommon.fit_scale(text, base, budget_bytes)
    local length = #tostring(text or "")
    if budget_bytes and length > budget_bytes then
        return base * budget_bytes / length
    end
    return base
end

function UICommon.stat_chip(text)
    return { n = G.UIT.C, config = { align = "cm", padding = 0.09, r = 0.1, colour = G.C.WHITE, emboss = 0.05 }, nodes = {
        { n = G.UIT.T, config = { text = text, scale = 0.31, colour = G.C.UI.TEXT_DARK } }
    } }
end

function UICommon.stat_chips(summary)
    summary = summary or {}
    return UICommon.row({
        UICommon.stat_chip(UICommon.localize_text("grdl_k_stat_g", { summary.currency_g or 0 })),
        UICommon.stat_chip(UICommon.localize_text("grdl_k_stat_owned") .. " " .. tostring(summary.owned_cards or 0)),
        UICommon.stat_chip(UICommon.localize_text("grdl_k_stat_raw") .. " " .. tostring(summary.raw_cards or 0)),
        UICommon.stat_chip(UICommon.localize_text("grdl_k_stat_graded") .. " " .. tostring(summary.graded_cards or 0)),
        UICommon.stat_chip(UICommon.localize_text("grdl_k_stat_queue") .. " " .. tostring(summary.grading_queue or 0))
    }, { padding = 0.09 })
end

function UICommon.event_ref_id(event)
    return event
        and event.config
        and event.config.ref_table
        and event.config.ref_table.id
        or nil
end

return UICommon
