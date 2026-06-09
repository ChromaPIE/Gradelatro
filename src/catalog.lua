local Catalog = {}

local function rarity_name(raw)
    if raw == 1 or raw == "common" or raw == "Common" then return "common" end
    if raw == 2 or raw == "uncommon" or raw == "Uncommon" then return "uncommon" end
    if raw == 3 or raw == "rare" or raw == "Rare" then return "rare" end
    if raw == 4 or raw == "legendary" or raw == "Legendary" then return "legendary" end
    if raw == "exotic" or raw == "Exotic" then return "exotic" end
    return "unknown_high"
end

local function mod_id_for_center(center)
    if center.mod and center.mod.id then return center.mod.id end
    if center.mod_id then return center.mod_id end
    return "Balatro"
end

local function format_series_name(config, mod_name, text)
    config = config or {}
    local format = text and text.series_format or config.catalog and config.catalog.series_format or "#1# Series"
    return (format:gsub("#1#", tostring(mod_name)))
end

local function mod_name_for_id(mod_id, mods)
    local mod = mods and mods[mod_id] or nil
    return mod and mod.name or mod_id
end

local function series_for_mod(config, mod_id, mods, text)
    return format_series_name(config, mod_name_for_id(mod_id, mods), text)
end

local function sort_for_series(a, b)
    local order_a = a.order or 0
    local order_b = b.order or 0
    if order_a ~= order_b then return order_a < order_b end
    return a.center_key < b.center_key
end

local function assign_series_indexes(entries)
    local grouped = {}
    for _, entry in ipairs(entries) do
        grouped[entry.series_id] = grouped[entry.series_id] or {}
        grouped[entry.series_id][#grouped[entry.series_id] + 1] = entry
    end
    for _, series_entries in pairs(grouped) do
        table.sort(series_entries, sort_for_series)
        for index, entry in ipairs(series_entries) do
            entry.series_index = index
        end
    end
end

function Catalog.normalize_edition(config, edition)
    local key = edition or "base"
    if config.authenticated_editions[key] then return key end
    return "base"
end

function Catalog.discover(config, centers, mods, text)
    mods = mods or (rawget(_G, "SMODS") and SMODS.Mods) or {}
    local out = {}
    for _, center in pairs(centers or {}) do
        if center.set == "Joker" then
            local mod_id = mod_id_for_center(center)
            out[#out + 1] = {
                center_key = center.key,
                local_key = center.original_key or center.key,
                name = center.name or center.key,
                mod_id = mod_id,
                series_id = mod_id,
                series_key = series_for_mod(config, mod_id, mods, text),
                rarity = rarity_name(center.rarity),
                order = center.order or 0
            }
        end
    end
    assign_series_indexes(out)
    table.sort(out, function(a, b) return a.center_key < b.center_key end)
    return out
end

function Catalog.series(catalog)
    local seen = {}
    local out = {}
    for _, entry in ipairs(catalog or {}) do
        local series_id = entry.series_id or entry.mod_id or entry.series_key
        if not seen[series_id] then
            seen[series_id] = true
            out[#out + 1] = {
                series_id = series_id,
                series_key = entry.series_key,
                mod_id = entry.mod_id
            }
        end
    end
    table.sort(out, function(a, b)
        if a.series_key ~= b.series_key then return a.series_key < b.series_key end
        return tostring(a.series_id) < tostring(b.series_id)
    end)
    return out
end

return Catalog
