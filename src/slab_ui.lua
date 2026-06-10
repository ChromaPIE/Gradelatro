local SlabUI = {}

local function load_src(path)
    if rawget(_G, "SMODS") and SMODS.load_file then
        return assert(SMODS.load_file("src/" .. path))()
    end
    return dofile("src/" .. path)
end

local Label = load_src("label.lua")
local UICommon = load_src("ui_common.lua")

-- vertical room the tooltip leaves for the card-mounted slab when it opens above the card
local SLAB_LIFT = 0.85
local SLAB_OFFSET_Y = -0.04
local BASE_LINE_SCALE = 0.2
local LINE_BUDGET_BYTES = 20

function SlabUI.label_args(record, catalog_entry)
    record = record or {}
    catalog_entry = catalog_entry or {}
    return {
        year = record.acquired_year,
        mod_name = catalog_entry.mod_name or record.mod_id,
        series_index = catalog_entry.series_index or 0,
        local_key = record.local_key or record.center_key,
        grade = record.grade,
        edition = record.edition,
        cert_number = record.cert_number
    }
end

function SlabUI.line_scale(text, base, budget_bytes)
    return UICommon.fit_scale(text, base or BASE_LINE_SCALE, budget_bytes or LINE_BUDGET_BYTES)
end

function SlabUI.label_font(fonts)
    fonts = fonts or (rawget(_G, "G") and G.FONTS) or {}
    for _, font in ipairs(fonts) do
        if type(font.file) == "string" and font.file:find("NotoSans%-Bold") then
            return font
        end
    end
    return nil
end

local function label_text(text, font)
    return { n = G.UIT.T, config = {
        text = text ~= "" and text or " ",
        scale = SlabUI.line_scale(text),
        colour = G.C.UI.TEXT_DARK,
        font = font
    } }
end

local function label_line(line, font)
    return { n = G.UIT.R, config = { align = "cm" }, nodes = {
        { n = G.UIT.C, config = { align = "cl", minw = 1.2, padding = 0.02 }, nodes = { label_text(line.left, font) } },
        { n = G.UIT.C, config = { align = "cr", minw = 0.6, padding = 0.02 }, nodes = { label_text(line.right, font) } }
    } }
end

function SlabUI.slab_definition(record, catalog_entry)
    local lines = Label.slab_lines(SlabUI.label_args(record, catalog_entry))
    local font = SlabUI.label_font()
    local rows = {}
    for _, line in ipairs(lines) do
        rows[#rows + 1] = label_line(line, font)
    end
    return { n = G.UIT.ROOT, config = { align = "cm", padding = 0.05, r = 0.04, colour = G.C.RED, emboss = 0.05, shadow = true }, nodes = {
        { n = G.UIT.R, config = { align = "cm", padding = 0.04, r = 0.03, colour = G.C.WHITE }, nodes = rows }
    } }
end

function SlabUI.attach(namespace, card)
    if not rawget(_G, "UIBox") then return false end
    if not card or card.children.grdl_slab then return false end
    local record = card.grdl_record
    if not record or record.status ~= "graded" then return false end

    local hover_index = namespace and namespace.binder_hover_index or {}
    local catalog_entry = record.center_key and hover_index[record.center_key] or nil
    card.children.grdl_slab = UIBox({
        definition = SlabUI.slab_definition(record, catalog_entry),
        config = {
            instance_type = "POPUP",
            align = "tm",
            offset = { x = 0, y = SLAB_OFFSET_Y },
            major = card,
            bond = "Strong",
            parent = card
        }
    })
    card.children.grdl_slab.states.collide.can = false
    return true
end

function SlabUI.detach(card)
    if not card or not card.children or not card.children.grdl_slab then return false end
    card.children.grdl_slab:remove()
    card.children.grdl_slab = nil
    return true
end

local function badge_row(card)
    local record = card.grdl_record
    if record.status == "graded" then
        return create_badge("PSA " .. tostring(record.grade or 0), G.C.RED, G.C.WHITE)
    end
    return create_badge(UICommon.localize_text("grdl_k_badge_ungraded"), G.C.JOKER_GREY, G.C.UI.TEXT_DARK)
end

local function append_badge(popup, card)
    if not rawget(_G, "create_badge") then return end
    local level_one = type(popup) == "table" and popup.nodes and popup.nodes[1] or nil
    local level_two = type(level_one) == "table" and level_one.nodes and level_one.nodes[1] or nil
    local level_three = type(level_two) == "table" and level_two.nodes and level_two.nodes[1] or nil
    local inner_rows = type(level_three) == "table" and level_three.nodes or nil
    if type(inner_rows) ~= "table" then return end
    inner_rows[#inner_rows + 1] = {
        n = G.UIT.R,
        config = { align = "cm", padding = 0.03 },
        nodes = { badge_row(card) }
    }
end

function SlabUI.install(namespace, env)
    env = env or {}
    local ui_def = env.ui_def or (rawget(_G, "G") and G.UIDEF) or nil
    local card_class = env.card_class or rawget(_G, "Card") or nil
    if not namespace or not ui_def or not card_class then return false end
    if type(ui_def.card_h_popup) ~= "function" then return false end
    if namespace.slab_hooks_installed then return true end

    local original_popup = ui_def.card_h_popup
    ui_def.card_h_popup = function(card)
        local popup = original_popup(card)
        if popup and card and card.grdl_record then
            pcall(append_badge, popup, card)
        end
        return popup
    end

    local original_align = card_class.align_h_popup
    if type(original_align) == "function" then
        card_class.align_h_popup = function(card, ...)
            local popup_config = original_align(card, ...)
            local record = card and card.grdl_record or nil
            if popup_config and popup_config.offset and record and record.status == "graded" and popup_config.type == "tm" then
                popup_config.offset.y = (popup_config.offset.y or 0) - SLAB_LIFT
            end
            return popup_config
        end
    end

    local original_hover = card_class.hover
    if type(original_hover) == "function" then
        card_class.hover = function(card, ...)
            original_hover(card, ...)
            if card and card.grdl_record then
                pcall(SlabUI.attach, namespace, card)
            end
        end
    end

    local original_stop_hover = card_class.stop_hover
    if type(original_stop_hover) == "function" then
        card_class.stop_hover = function(card, ...)
            original_stop_hover(card, ...)
            if card and card.children and card.children.grdl_slab then
                pcall(SlabUI.detach, card)
            end
        end
    end

    namespace.slab_hooks_installed = true
    return true
end

return SlabUI
