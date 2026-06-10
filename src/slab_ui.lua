local SlabUI = {}

local function load_src(path)
    if rawget(_G, "SMODS") and SMODS.load_file then
        return assert(SMODS.load_file("src/" .. path))()
    end
    return dofile("src/" .. path)
end

local Label = load_src("label.lua")

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

function SlabUI.inject(popup, node)
    if type(popup) ~= "table" or type(node) ~= "table" then return false end
    local outer = popup.nodes
    if type(outer) ~= "table" or type(outer[1]) ~= "table" then return false end
    local column = outer[1].nodes
    if type(column) ~= "table" or not column[1] then return false end
    table.insert(column, 1, node)
    return true
end

local function label_line(line)
    return { n = G.UIT.R, config = { align = "cm" }, nodes = {
        { n = G.UIT.C, config = { align = "cl", minw = 1.7 }, nodes = {
            { n = G.UIT.T, config = { text = line.left ~= "" and line.left or " ", scale = 0.24, colour = G.C.UI.TEXT_DARK } }
        } },
        { n = G.UIT.C, config = { align = "cr", minw = 1.1 }, nodes = {
            { n = G.UIT.T, config = { text = line.right ~= "" and line.right or " ", scale = 0.24, colour = G.C.UI.TEXT_DARK } }
        } }
    } }
end

function SlabUI.label_box(record, catalog_entry)
    local lines = Label.slab_lines(SlabUI.label_args(record, catalog_entry))
    local rows = {}
    for _, line in ipairs(lines) do
        rows[#rows + 1] = label_line(line)
    end
    return { n = G.UIT.R, config = { align = "cm", padding = 0.06, r = 0.05, colour = G.C.RED, emboss = 0.05 }, nodes = {
        { n = G.UIT.R, config = { align = "cm", padding = 0.06, r = 0.03, colour = G.C.WHITE }, nodes = rows }
    } }
end

function SlabUI.install(namespace, ui_def)
    ui_def = ui_def or (rawget(_G, "G") and G.UIDEF) or nil
    if not namespace or not ui_def or type(ui_def.card_h_popup) ~= "function" then return false end
    if namespace.slab_popup_installed then return true end

    local original = ui_def.card_h_popup
    ui_def.card_h_popup = function(card)
        local popup = original(card)
        local record = card and card.grdl_record or nil
        if popup and record and record.status == "graded" then
            pcall(function()
                local hover_index = namespace.binder_hover_index or {}
                local catalog_entry = record.center_key and hover_index[record.center_key] or nil
                SlabUI.inject(popup, SlabUI.label_box(record, catalog_entry))
            end)
        end
        return popup
    end

    namespace.slab_popup_installed = true
    return true
end

return SlabUI
