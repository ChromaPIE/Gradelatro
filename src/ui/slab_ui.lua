local SlabUI = {}

local function load_src(path)
    if rawget(_G, "SMODS") and SMODS.load_file then
        return assert(SMODS.load_file("src/" .. path))()
    end
    return dofile("src/" .. path)
end

local Label = load_src("domain/label.lua")
local Proficiency = load_src("domain/proficiency.lua")
local TextInput = load_src("ui/text_input.lua")
local UICommon = load_src("ui/ui_common.lua")

local BASE_LINE_SCALE = 0.27
local LINE_BUDGET_BYTES = 24
local COLUMN_GAP = 0.35
local LINE_HEIGHT = 0.32
local SIDE_OFFSET_X = 0.03
local SCREEN_MARGIN = 0.02

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

local function room_rect()
    local runtime = rawget(_G, "G")
    return runtime and runtime.ROOM and runtime.ROOM.T or nil
end

local function overflows_top(box, margin)
    local room = room_rect()
    if not room or not box or not box.T then return false end
    return (box.T.y or 0) < ((room.y or 0) + (margin or SCREEN_MARGIN))
end

local function side_alignment(major, box, margin)
    local room = room_rect()
    local major_t = major and major.T or {}
    local box_t = box and box.T or {}
    local room_x = room and (room.x or 0) or 0
    local room_w = room and (room.w or 0) or 0
    local major_x = major_t.x or 0
    local major_w = major_t.w or 0
    local box_w = box_t.w or 0
    local left_space = major_x - room_x
    local right_space = room_x + room_w - (major_x + major_w)
    local needed = box_w + (margin or SCREEN_MARGIN)

    if left_space >= needed and left_space >= right_space then
        return "cl", { x = -SIDE_OFFSET_X, y = 0 }
    end
    if right_space >= needed then
        return "cr", { x = SIDE_OFFSET_X, y = 0 }
    end
    if left_space > right_space then
        return "cl", { x = -SIDE_OFFSET_X, y = 0 }
    end
    return "cr", { x = SIDE_OFFSET_X, y = 0 }
end

local function realign_box(box, major, align, offset, bond)
    if not box then return end
    if box.config then
        box.config.align = align
        box.config.type = align
        box.config.offset = offset
        box.config.major = major
    end
    if box.set_alignment then
        pcall(box.set_alignment, box, {
            major = major,
            type = align,
            bond = bond or "Strong",
            offset = offset
        })
    elseif box.alignment then
        box.alignment.type = align
        box.alignment.offset = offset
    end
    if box.align_to_major then pcall(box.align_to_major, box) end
end

local function alignment_type(alignment)
    return type(alignment) == "table" and (alignment.type or alignment.align) or nil
end

local function copy_offset(offset)
    return { x = offset and offset.x or 0, y = offset and offset.y or 0 }
end

local function sync_visual_transform(box)
    if not box or not box.T or not box.VT then return end
    for _, key in ipairs({ "x", "y", "w", "h", "r", "scale" }) do
        if box.T[key] ~= nil then box.VT[key] = box.T[key] end
    end
end

local move_child_tree

local function sync_attached_object(node, seen)
    local object = node and node.config and node.config.object or nil
    if not object then return end
    if object.hard_set_T and node.T then
        pcall(object.hard_set_T, object, node.T.x, node.T.y, node.T.w, node.T.h)
    else
        if object.T and node.T then
            for _, key in ipairs({ "x", "y", "w", "h", "r", "scale" }) do
                if node.T[key] ~= nil then object.T[key] = node.T[key] end
            end
        end
        sync_visual_transform(object)
    end
    if object.move_with_major then pcall(object.move_with_major, object, 0) end
    if object.alignment then object.alignment.prev_type = "" end
    if object.align_to_major then pcall(object.align_to_major, object) end
    sync_visual_transform(object)
    if object.UIRoot then move_child_tree(object.UIRoot, seen) end
end

function move_child_tree(node, seen)
    if type(node) ~= "table" then return end
    seen = seen or {}
    if seen[node] then return end
    seen[node] = true
    if node.config and node.config.parent and node.align_to_major then
        pcall(node.align_to_major, node)
    end
    if node.move_with_major then pcall(node.move_with_major, node, 0) end
    sync_visual_transform(node)
    sync_attached_object(node, seen)
    if node.UIRoot then move_child_tree(node.UIRoot, seen) end
    for _, child in pairs(node.children or {}) do
        move_child_tree(child, seen)
    end
end

local function apply_alignment_now(box)
    if not box then return end
    if box.align_to_major then pcall(box.align_to_major, box) end
    if box.move_with_major then pcall(box.move_with_major, box, 0) end
    sync_visual_transform(box)
end

local function adapt_if_top_overflow(box, major, opts)
    opts = opts or {}
    local margin = opts.screen_margin or SCREEN_MARGIN
    if not overflows_top(box, margin) then return end
    local align, offset = side_alignment(major, box, margin)
    realign_box(box, major, align, offset, opts.bond or "Strong")
    apply_alignment_now(box)
    if box.UIRoot then move_child_tree(box.UIRoot) end
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
    adapt_if_top_overflow(card.children.grdl_slab, card, opts)
    card.children.grdl_slab.states.collide.can = false
    return true
end

local function badge_nodes(record)
    local nodes = {}
    if record.status == "graded" then
        nodes[#nodes + 1] = create_badge("PSA " .. tostring(record.grade or 0), G.C.RED, G.C.WHITE)
        local badge_text = record.proficiency and record.proficiency.badge_text or nil
        if badge_text then
            nodes[#nodes + 1] = create_badge(badge_text, Proficiency.badge_colour(record, G.C.PURPLE), G.C.WHITE)
        end
    else
        nodes[#nodes + 1] = create_badge(UICommon.localize_text("grdl_k_badge_ungraded"), G.C.JOKER_GREY, G.C.UI.TEXT_DARK)
    end
    return nodes
end

local function popup_column(popup)
    local level_one = type(popup) == "table" and popup.nodes and popup.nodes[1] or nil
    return type(level_one) == "table" and level_one.nodes or nil
end

local function append_badge(popup, record)
    if not rawget(_G, "create_badge") then return end
    local column = popup_column(popup)
    local level_two = type(column) == "table" and column[#column] or nil
    local level_three = type(level_two) == "table" and level_two.nodes and level_two.nodes[1] or nil
    local inner_rows = type(level_three) == "table" and level_three.nodes or nil
    if type(inner_rows) ~= "table" then return end
    inner_rows[#inner_rows + 1] = {
        n = G.UIT.R,
        config = { align = "cm", padding = 0.03 },
        nodes = badge_nodes(record)
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
            grdl_side_with_hover = true,
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
    if not e.config.grdl_side_with_hover then
        adapt_if_top_overflow(e.children.info, e)
    end
    e.children.info:align_to_major()
    e.config.ref_table = nil
end

local function find_slab_anchor(node, seen)
    if type(node) ~= "table" then return nil end
    seen = seen or {}
    if seen[node] then return nil end
    seen[node] = true
    if node.config and node.config.func == "grdl_show_slab" then return node end
    for _, child in pairs(node.children or {}) do
        local found = find_slab_anchor(child, seen)
        if found then return found end
    end
    return nil
end

local function adapt_hover_popup_for_slab(card, funcs)
    local popup = card and card.children and card.children.h_popup or nil
    local anchor = popup and popup.UIRoot and find_slab_anchor(popup.UIRoot) or nil
    if card then card.grdl_slab_hover_alignment = nil end
    if not anchor or not anchor.config or not anchor.config.grdl_side_with_hover then return end

    if anchor.config.ref_table and funcs and type(funcs.grdl_show_slab) == "function" then
        pcall(funcs.grdl_show_slab, anchor)
    end

    local planned_alignment = card and card.config and card.config.h_popup_config or nil
    if alignment_type(planned_alignment) ~= "tm" then return end

    local slab = anchor.children and anchor.children.info or nil
    local margin = SCREEN_MARGIN
    if not overflows_top(slab, margin) then return end

    local major = planned_alignment.major
        or planned_alignment.parent
        or (popup.config and (popup.config.major or popup.config.parent))
        or card
    local align, offset = side_alignment(major, popup, margin)
    if card then card.grdl_slab_hover_alignment = { type = align, offset = copy_offset(offset) } end
    realign_box(popup, major, align, offset, "Strong")
    apply_alignment_now(popup)
    if popup.UIRoot then move_child_tree(popup.UIRoot) end
    apply_alignment_now(slab)
    if slab and slab.UIRoot then move_child_tree(slab.UIRoot) end
end

local function apply_slab_alignment_override(card, alignment)
    if type(alignment) ~= "table" then return alignment end
    if not card or not card.children or not card.children.h_popup then
        if card then card.grdl_slab_hover_alignment = nil end
        return alignment
    end
    if alignment_type(alignment) ~= "tm" then
        card.grdl_slab_hover_alignment = nil
        return alignment
    end
    local override = card.grdl_slab_hover_alignment
    if not override then return alignment end
    alignment.type = override.type
    alignment.align = override.type
    alignment.offset = copy_offset(override.offset)
    return alignment
end

local function proficiency_rows(record)
    local level = Proficiency.level(record)
    local rows = {}
    -- composed prefix-key plus value: #1# variable keys fall back to bare
    -- keys without a localize global, which would swallow the values
    rows[#rows + 1] = { { n = G.UIT.T, config = {
        text = UICommon.localize_text("grdl_k_prof_level") .. " " .. Proficiency.level_label(level),
        scale = 0.33, colour = G.C.UI.TEXT_DARK } } }
    local next_threshold = Proficiency.next_threshold(record)
    local progress = next_threshold
        and (UICommon.localize_text("grdl_k_prof_progress") .. " " .. tostring(Proficiency.antes(record)) .. "/" .. tostring(next_threshold))
        or UICommon.localize_text("grdl_k_prof_maxed")
    rows[#rows + 1] = { { n = G.UIT.T, config = { text = progress, scale = 0.3, colour = G.C.UI.TEXT_DARK } } }
    return rows
end

local function remove_tagged_info(aut, tag)
    for index = #(aut.info or {}), 1, -1 do
        if aut.info[index] and aut.info[index][tag] then
            table.remove(aut.info, index)
        end
    end
end

local function inscription_rows(record)
    local note = record.proficiency and record.proficiency.note or nil
    if not note or note == "" or Proficiency.level(record) < 2 then return nil end
    local rows = {}
    for _, line in ipairs(TextInput.split_lines(note, 4)) do
        rows[#rows + 1] = { { n = G.UIT.T, config = {
            text = line,
            scale = 0.3,
            colour = G.C.UI.TEXT_DARK
        } } }
    end
    rows.grdl_inscription = true
    rows.grdl_hide_title = true
    rows.background_colour = G.C.WHITE
    return rows
end

local function inject_inscription_info(card, record)
    local aut = card.ability_UIBox_table
    if type(aut) ~= "table" then return end
    local entry = inscription_rows(record)
    if not entry then return end
    aut.info = aut.info or {}
    remove_tagged_info(aut, "grdl_inscription")
    table.insert(aut.info, 1, entry)
end

-- rides the vanilla info_queue path: entries in ability_UIBox_table.info
-- render as the same side boxes tarot cards use for related effects
local function inject_proficiency_info(card, record)
    local aut = card.ability_UIBox_table
    if type(aut) ~= "table" then return end
    aut.info = aut.info or {}
    remove_tagged_info(aut, "grdl_prof")
    local entry = proficiency_rows(record)
    entry.name = UICommon.localize_text("grdl_k_prof_title")
    entry.grdl_prof = true
    aut.info[#aut.info + 1] = entry
end

local function apply_tooltip_tint(popup, record)
    local hex = record.proficiency and record.proficiency.tooltip_colour or nil
    local colour = hex and Proficiency.parse_hex(hex) or nil
    if not colour then return end
    local column = popup_column(popup)
    local frame = type(column) == "table" and column[#column] or nil
    local background = type(frame) == "table" and frame.nodes and frame.nodes[1] or nil
    if type(background) == "table" and background.config and background.config.colour then
        background.config.colour = colour
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
    local node = env.node or rawget(_G, "Node")
    local card_class = env.card or rawget(_G, "Card")
    if not namespace or not ui_def or not funcs then return false end
    if type(ui_def.card_h_popup) ~= "function" then return false end
    if namespace.slab_hooks_installed then return true end

    funcs.grdl_show_slab = show_slab

    local original_popup = ui_def.card_h_popup
    ui_def.card_h_popup = function(card)
        if card then
            local record = card.grdl_record or resolve_loadout_record(namespace, card)
            if record and record.status == "graded" then
                pcall(inject_inscription_info, card, record)
                pcall(inject_proficiency_info, card, record)
            end
        end
        local popup = original_popup(card)
        if not popup or not card then return popup end
        if card.grdl_record then
            pcall(append_badge, popup, card.grdl_record)
            if card.grdl_record.status == "graded" then
                pcall(insert_slab_anchor, namespace, popup, card)
            end
            pcall(apply_tooltip_tint, popup, card.grdl_record)
        else
            local record = resolve_loadout_record(namespace, card)
            if record then
                pcall(append_badge, popup, record)
                pcall(apply_tooltip_tint, popup, record)
            end
        end
        return popup
    end

    if node and type(node.hover) == "function" and not node.grdl_slab_hover_hook_installed then
        local original_hover = node.hover
        node.hover = function(self, ...)
            local result = original_hover(self, ...)
            pcall(adapt_hover_popup_for_slab, self, funcs)
            return result
        end
        node.grdl_slab_hover_hook_installed = true
    end

    if card_class and type(card_class.align_h_popup) == "function" and not card_class.grdl_slab_align_hook_installed then
        local original_align_h_popup = card_class.align_h_popup
        card_class.align_h_popup = function(self, ...)
            return apply_slab_alignment_override(self, original_align_h_popup(self, ...))
        end
        card_class.grdl_slab_align_hook_installed = true
    end

    namespace.slab_hooks_installed = true
    return true
end

return SlabUI
