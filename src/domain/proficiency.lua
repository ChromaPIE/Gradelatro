local Proficiency = {}

local THRESHOLDS = { 5, 13, 34, 89, 100 }
local LABELS = { "0", "I", "II", "III", "IV", "G" }

function Proficiency.ensure(card)
    card.proficiency = type(card.proficiency) == "table" and card.proficiency or {}
    card.proficiency.antes = tonumber(card.proficiency.antes) or 0
    return card.proficiency
end

function Proficiency.antes(card)
    return (card and card.proficiency and tonumber(card.proficiency.antes)) or 0
end

function Proficiency.level(card)
    if not card or card.status ~= "graded" then return 0 end
    local antes = Proficiency.antes(card)
    local level = 0
    for index, threshold in ipairs(THRESHOLDS) do
        if antes >= threshold then level = index end
    end
    return level
end

function Proficiency.level_label(level)
    return LABELS[(level or 0) + 1] or "0"
end

function Proficiency.next_threshold(card)
    local antes = Proficiency.antes(card)
    for _, threshold in ipairs(THRESHOLDS) do
        if antes < threshold then return threshold end
    end
    return nil
end

function Proficiency.record_ante(card)
    if not card or card.status ~= "graded" then return false end
    local meta = Proficiency.ensure(card)
    meta.antes = meta.antes + 1
    return true
end

function Proficiency.allows_edition(card) return Proficiency.level(card) >= 1 end
function Proficiency.can_note(card) return Proficiency.level(card) >= 2 end
function Proficiency.can_eternal(card) return Proficiency.level(card) >= 3 end
function Proficiency.can_badge(card) return Proficiency.level(card) >= 4 end
function Proficiency.can_tint(card) return Proficiency.level(card) >= 5 end

function Proficiency.parse_hex(text)
    local hex = tostring(text or ""):gsub("^#", "")
    if not hex:match("^%x%x%x%x%x%x$") then return nil end
    return {
        tonumber(hex:sub(1, 2), 16) / 255,
        tonumber(hex:sub(3, 4), 16) / 255,
        tonumber(hex:sub(5, 6), 16) / 255,
        1
    }
end

local function gated_set(card, gate, apply)
    if not gate(card) then return { ok = false, reason = "locked" } end
    apply(Proficiency.ensure(card))
    return { ok = true }
end

function Proficiency.set_note(card, text)
    return gated_set(card, Proficiency.can_note, function(meta)
        meta.note = (text and text ~= "") and tostring(text) or nil
    end)
end

function Proficiency.set_badge(card, text)
    return gated_set(card, Proficiency.can_badge, function(meta)
        meta.badge_text = (text and text ~= "") and tostring(text) or nil
    end)
end

function Proficiency.set_badge_colour(card, text)
    if not Proficiency.can_badge(card) then return { ok = false, reason = "locked" } end
    local meta = Proficiency.ensure(card)
    if text == nil or text == "" then
        meta.badge_colour = nil
        return { ok = true }
    end
    local hex = tostring(text):gsub("^#", ""):upper()
    if not Proficiency.parse_hex(hex) then return { ok = false, reason = "invalid_hex" } end
    meta.badge_colour = hex
    return { ok = true }
end

function Proficiency.badge_colour(card, fallback)
    local hex = card and card.proficiency and card.proficiency.badge_colour or nil
    return (hex and Proficiency.parse_hex(hex)) or fallback
end

function Proficiency.set_eternal(card, enabled)
    return gated_set(card, Proficiency.can_eternal, function(meta)
        meta.eternal = enabled and true or false
    end)
end

function Proficiency.set_tint(card, text)
    if not Proficiency.can_tint(card) then return { ok = false, reason = "locked" } end
    local meta = Proficiency.ensure(card)
    if text == nil or text == "" then
        meta.tooltip_colour = nil
        return { ok = true }
    end
    local hex = tostring(text):gsub("^#", ""):upper()
    if not Proficiency.parse_hex(hex) then return { ok = false, reason = "invalid_hex" } end
    meta.tooltip_colour = hex
    return { ok = true }
end

return Proficiency
