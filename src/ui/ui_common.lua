local UICommon = {}

local function load_src(path)
    if rawget(_G, "SMODS") and SMODS.load_file then
        return assert(SMODS.load_file("src/" .. path))()
    end
    return dofile("src/" .. path)
end

local Catalog = load_src("domain/catalog.lua")

local ERROR_TEXT = "ERROR"

local PREVIEW_SCALE = 0.8

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
        { n = G.UIT.T, config = { text = text, scale = 0.34, colour = G.C.UI.TEXT_DARK } }
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

function UICommon.discover_catalog(namespace)
    local runtime = rawget(_G, "G")
    if not runtime or not runtime.P_CENTERS or not namespace or not namespace.config then return {} end
    local smods = rawget(_G, "SMODS")
    local ok, catalog = pcall(Catalog.discover, namespace.config, runtime.P_CENTERS, smods and smods.Mods or nil, {
        series_format = UICommon.localize_text("grdl_k_series_format")
    })
    if not ok then return {} end
    return catalog
end

function UICommon.page_cycle(view, callback)
    if not view or (view.pages or 1) <= 1 then return nil end
    local options = {}
    for index = 1, view.pages do
        options[#options + 1] = UICommon.localize_text("k_page") .. " " .. tostring(index) .. "/" .. tostring(view.pages)
    end
    return create_option_cycle({
        options = options,
        w = 4.5,
        cycle_shoulders = true,
        opt_callback = callback,
        current_option = view.page,
        colour = G.C.RED,
        no_pips = true,
        focus_args = { snap_to = true, nav = "wide" }
    })
end

function UICommon.attach_card_preview(element, info)
    if not rawget(_G, "UIBox") or not rawget(_G, "CardArea") or not rawget(_G, "Card") then return false end
    if not element or not element.children or element.children.grdl_preview then return false end
    local runtime = rawget(_G, "G")
    local center = runtime and runtime.P_CENTERS and info and info.center_key and runtime.P_CENTERS[info.center_key] or nil
    if not center then return false end

    local width = PREVIEW_SCALE * runtime.CARD_W
    local height = PREVIEW_SCALE * runtime.CARD_H
    local area = CardArea(0, 0, width, height, { card_limit = 1, type = "title", highlight_limit = 0, collection = true })
    local card = Card(area.T.x, area.T.y, width, height, (runtime.P_CARDS and runtime.P_CARDS.empty or nil), center)
    local flags = Catalog.edition_flags(info.edition)
    if flags then card:set_edition(flags, true, true) end
    area:emplace(card)
    -- interaction must be muted AFTER emplace: the area re-enables collision
    -- when it takes the card, and a hoverable preview spawns its own tooltip
    card.no_ui = true
    if card.states then
        if card.states.collide then card.states.collide.can = false end
        if card.states.hover then card.states.hover.can = false end
        if card.states.click then card.states.click.can = false end
    end

    element.children.grdl_preview = UIBox({
        definition = { n = runtime.UIT.ROOT, config = { align = "cm", colour = runtime.C.CLEAR, padding = 0.05 }, nodes = {
            { n = runtime.UIT.O, config = { object = area } }
        } },
        config = {
            instance_type = "POPUP",
            align = "cl",
            offset = { x = -0.08, y = 0 },
            major = element,
            bond = "Strong",
            parent = element
        }
    })
    if element.children.grdl_preview.states and element.children.grdl_preview.states.collide then
        element.children.grdl_preview.states.collide.can = false
    end
    return true
end

function UICommon.detach_card_preview(element)
    local box = element and element.children and element.children.grdl_preview or nil
    if not box then return false end
    box:remove()
    element.children.grdl_preview = nil
    return true
end

function UICommon.install_preview(funcs)
    funcs = funcs or (rawget(_G, "G") and G.FUNCS) or nil
    if not funcs then return false end
    funcs.grdl_row_preview = function(element)
        if not element or not element.config then return end
        if element.states and element.states.hover and element.states.hover.is then
            if not (element.children and element.children.grdl_preview) then
                pcall(UICommon.attach_card_preview, element, element.config.ref_table)
            end
        elseif element.children and element.children.grdl_preview then
            pcall(UICommon.detach_card_preview, element)
        end
    end
    return true
end

function UICommon.swap_tab_contents(definition_fn)
    local runtime = rawget(_G, "G")
    if not runtime or not runtime.OVERLAY_MENU or not rawget(_G, "UIBox") then return false end
    if type(runtime.OVERLAY_MENU.get_UIE_by_ID) ~= "function" then return false end
    local tab_contents = runtime.OVERLAY_MENU:get_UIE_by_ID("tab_contents")
    if not tab_contents or not tab_contents.config or not tab_contents.config.object then return false end

    tab_contents.config.object:remove()
    tab_contents.config.object = UIBox({
        definition = definition_fn(),
        config = { offset = { x = 0, y = 0 }, parent = tab_contents, type = "cm" }
    })
    if tab_contents.UIBox and tab_contents.UIBox.recalculate then
        tab_contents.UIBox:recalculate()
    end
    return true
end

function UICommon.outline_button(args)
    args = args or {}
    local solid = args.solid
    local button = args.button
    local ref = args.ref
    local focus_args = { nav = "wide" }
    if args.disabled then
        button = nil
        ref = nil
        focus_args = nil
    end
    local nodes = {}
    for _, line in ipairs(args.lines or {}) do
        nodes[#nodes + 1] = { n = G.UIT.R, config = { align = "cm", padding = 0.01 }, nodes = {
            { n = G.UIT.T, config = {
                text = line.text,
                ref_table = line.ref_table,
                ref_value = line.ref_value,
                scale = line.scale or 0.34,
                colour = line.colour or G.C.WHITE,
                font = args.font
            } }
        } }
    end
    return { n = G.UIT.C, config = {
        align = "cm",
        minw = args.minw or 1.6,
        minh = args.minh or 0.9,
        padding = 0.08,
        r = solid and 0.1 or 0.06,
        colour = solid and (args.colour or G.C.RED) or (args.colour or G.C.CLEAR),
        outline = not solid and 1.2 or nil,
        outline_colour = not solid and (args.outline_colour or G.C.WHITE) or nil,
        shadow = solid and true or false,
        id = args.id or args.button,
        button = button,
        ref_table = ref,
        focus_args = focus_args,
        hover = args.disabled and false or true
    }, nodes = nodes }
end

function UICommon.suppress_selection(card)
    card.click = function(self)
        if self.juice_up then self:juice_up(0.3, 0.3) end
    end
end

function UICommon.event_ref_id(event)
    return event
        and event.config
        and event.config.ref_table
        and event.config.ref_table.id
        or nil
end

return UICommon
