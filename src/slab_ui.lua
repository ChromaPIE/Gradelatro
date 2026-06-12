local SlabUI = {}

local function load_src(path)
    if rawget(_G, "SMODS") and SMODS.load_file then
        return assert(SMODS.load_file("src/" .. path))()
    end
    return dofile("src/" .. path)
end

local Label = load_src("label.lua")
local Proficiency = load_src("proficiency.lua")
local UICommon = load_src("ui_common.lua")

local BASE_LINE_SCALE = 0.27
local LINE_BUDGET_BYTES = 24
local COLUMN_GAP = 0.35
local LINE_HEIGHT = 0.32

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

local function label_line(text, side, font, scale_mult)
    return { n = G.UIT.R, config = { align = side, minh = LINE_HEIGHT * scale_mult, padding = 0.01 * scale_mult }, nodes = {
        { n = G.UIT.T, config = {
            text = text ~= "" and text or " ",
            scale = SlabUI.line_scale(text) * scale_mult,
            colour = G.C.UI.TEXT_DARK,
            font = font
        } }
    } }
end

function SlabUI.slab_box(record, catalog_entry, opts)
    local scale_mult = opts and opts.scale or 1
    local lines = Label.slab_lines(SlabUI.label_args(record, catalog_entry))
    local font = SlabUI.label_font()
    local left_lines = {}
    local right_lines = {}
    for _, line in ipairs(lines) do
        left_lines[#left_lines + 1] = label_line(line.left, "cl", font, scale_mult)
        right_lines[#right_lines + 1] = label_line(line.right, "cr", font, scale_mult)
    end
    return { n = G.UIT.R, config = { align = "cm", padding = 0.07 * scale_mult, r = 0.05, colour = G.C.RED, emboss = 0.05, shadow = true }, nodes = {
        { n = G.UIT.R, config = { align = "cm", padding = 0.06 * scale_mult, r = 0.04, colour = G.C.WHITE }, nodes = {
            { n = G.UIT.C, config = { align = "cl", padding = 0.01 * scale_mult }, nodes = left_lines },
            { n = G.UIT.C, config = { align = "cm", minw = COLUMN_GAP * scale_mult }, nodes = {} },
            { n = G.UIT.C, config = { align = "cr", padding = 0.01 * scale_mult }, nodes = right_lines }
        } }
    } }
end

function SlabUI.attach_above(card, record, catalog_entry, opts)
    if not rawget(_G, "UIBox") then return false end
    if not card or not card.children or card.children.grdl_slab then return false end

    card.children.grdl_slab = UIBox({
        definition = { n = G.UIT.ROOT, config = { align = "cm", colour = G.C.CLEAR, padding = 0.02 }, nodes = {
            SlabUI.slab_box(record, catalog_entry, opts)
        } },
        config = {
            instance_type = "POPUP",
            align = "tm",
            offset = { x = 0, y = (opts and opts.offset_y) or -0.04 },
            major = card,
            bond = "Strong",
            parent = card
        }
    })
    card.children.grdl_slab.states.collide.can = false
    return true
end

local function badge_node(card)
    local record = card.grdl_record
    if record.status == "graded" then
        return create_badge("PSA " .. tostring(record.grade or 0), G.C.RED, G.C.WHITE)
    end
    return create_badge(UICommon.localize_text("grdl_k_badge_ungraded"), G.C.JOKER_GREY, G.C.UI.TEXT_DARK)
end

local function popup_column(popup)
    local level_one = type(popup) == "table" and popup.nodes and popup.nodes[1] or nil
    return type(level_one) == "table" and level_one.nodes or nil
end

local function append_badge(popup, card)
    if not rawget(_G, "create_badge") then return end
    local column = popup_column(popup)
    local level_two = type(column) == "table" and column[#column] or nil
    local level_three = type(level_two) == "table" and level_two.nodes and level_two.nodes[1] or nil
    local inner_rows = type(level_three) == "table" and level_three.nodes or nil
    if type(inner_rows) ~= "table" then return end
    inner_rows[#inner_rows + 1] = {
        n = G.UIT.R,
        config = { align = "cm", padding = 0.03 },
        nodes = { badge_node(card) }
    }
end

local function insert_slab_anchor(namespace, popup, card)
    local column = popup_column(popup)
    if type(column) ~= "table" or not column[1] then return end
    local record = card.grdl_record
    local hover_index = namespace and namespace.binder_hover_index or {}
    local catalog_entry = record.center_key and hover_index[record.center_key] or nil
    table.insert(column, 1, {
        n = G.UIT.R,
        config = {
            align = "cm",
            padding = 0,
            func = "grdl_show_slab",
            object = rawget(_G, "Moveable") and Moveable() or nil,
            ref_table = { SlabUI.slab_box(record, catalog_entry) }
        },
        nodes = {}
    })
end

local function show_slab(e)
    if not rawget(_G, "UIBox") then return end
    if not e or not e.config or not e.config.ref_table or e.children.info then return end
    e.children.info = UIBox({
        definition = { n = G.UIT.ROOT, config = { align = "cm", colour = G.C.CLEAR, padding = 0.02 }, nodes = e.config.ref_table },
        config = { offset = { x = 0, y = -0.04 }, align = "tm", parent = e }
    })
    e.children.info:align_to_major()
    e.config.ref_table = nil
end

local function proficiency_rows(record)
    local level = Proficiency.level(record)
    local rows = {}
    -- composed prefix-key plus value: #1# variable keys fall back to bare
    -- keys without a localize global, which would swallow the values
    rows[#rows + 1] = { { n = G.UIT.T, config = {
        text = UICommon.localize_text("grdl_k_prof_level") .. " " .. Proficiency.level_label(level),
        scale = 0.3, colour = G.C.UI.TEXT_DARK } } }
    local next_threshold = Proficiency.next_threshold(record)
    local progress = next_threshold
        and (UICommon.localize_text("grdl_k_prof_progress") .. " " .. tostring(Proficiency.antes(record)) .. "/" .. tostring(next_threshold))
        or UICommon.localize_text("grdl_k_prof_maxed")
    rows[#rows + 1] = { { n = G.UIT.T, config = { text = progress, scale = 0.27, colour = G.C.UI.TEXT_DARK } } }
    local note = record.proficiency and record.proficiency.note or nil
    if note and level >= 2 then
        rows[#rows + 1] = { { n = G.UIT.T, config = { text = note, scale = 0.27, colour = G.C.UI.TEXT_DARK } } }
    end
    return rows
end

local function fallback_info_box(rows, title)
    local row_nodes = {
        { n = G.UIT.R, config = { align = "cm", padding = 0.03 }, nodes = {
            { n = G.UIT.T, config = { text = title, scale = 0.3, colour = G.C.UI.TEXT_LIGHT } }
        } }
    }
    for _, cells in ipairs(rows) do
        row_nodes[#row_nodes + 1] = { n = G.UIT.R, config = { align = "cm", padding = 0.02 }, nodes = cells }
    end
    return { n = G.UIT.R, config = { align = "cm", padding = 0.05, r = 0.1, colour = G.C.WHITE }, nodes = row_nodes }
end

local function append_proficiency_box(popup, record)
    local column = popup_column(popup)
    if type(column) ~= "table" then return end
    local rows = proficiency_rows(record)
    local title = UICommon.localize_text("grdl_k_prof_title")
    local box
    if rawget(_G, "info_tip_from_rows") then
        box = info_tip_from_rows(rows, title)
    else
        box = fallback_info_box(rows, title)
    end
    box.grdl_prof_box = true
    column[#column + 1] = box
end

local function apply_tooltip_tint(popup, record)
    local hex = record.proficiency and record.proficiency.tooltip_colour or nil
    local colour = hex and Proficiency.parse_hex(hex) or nil
    if not colour then return end
    local column = popup_column(popup)
    local level_two = type(column) == "table" and column[#column] or nil
    if type(level_two) == "table" and level_two.config and level_two.config.colour then
        level_two.config.colour = colour
    end
    local level_three = type(level_two) == "table" and level_two.nodes and level_two.nodes[1] or nil
    if type(level_three) == "table" and level_three.config and level_three.config.colour then
        level_three.config.colour = colour
    end
end

local function resolve_loadout_record(namespace, card)
    local card_id = card and card.ability and card.ability.grdl_loadout_id or nil
    if not card_id or not namespace or not namespace.collection then return nil end
    for _, record in ipairs(namespace.collection.cards or {}) do
        if record.id == card_id then return record end
    end
    return nil
end

function SlabUI.install(namespace, env)
    env = env or {}
    local ui_def = env.ui_def or (rawget(_G, "G") and G.UIDEF) or nil
    local funcs = env.funcs or (rawget(_G, "G") and G.FUNCS) or nil
    if not namespace or not ui_def or not funcs then return false end
    if type(ui_def.card_h_popup) ~= "function" then return false end
    if namespace.slab_hooks_installed then return true end

    funcs.grdl_show_slab = show_slab

    local original_popup = ui_def.card_h_popup
    ui_def.card_h_popup = function(card)
        local popup = original_popup(card)
        if not popup or not card then return popup end
        if card.grdl_record then
            pcall(append_badge, popup, card)
            if card.grdl_record.status == "graded" then
                pcall(insert_slab_anchor, namespace, popup, card)
            end
            -- tint before appending: it targets the column's last node,
            -- which must still be the vanilla frame at that point
            pcall(apply_tooltip_tint, popup, card.grdl_record)
            if card.grdl_record.status == "graded" then
                pcall(append_proficiency_box, popup, card.grdl_record)
            end
        else
            local record = resolve_loadout_record(namespace, card)
            if record then
                pcall(apply_tooltip_tint, popup, record)
                if record.status == "graded" then
                    pcall(append_proficiency_box, popup, record)
                end
            end
        end
        return popup
    end

    namespace.slab_hooks_installed = true
    return true
end

return SlabUI
