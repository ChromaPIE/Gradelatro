local Label = {}

local GRADE_TEXT = {
    [10] = "GEM MT",
    [9] = "MINT",
    [8] = "NM-MT",
    [7] = "NM",
    [6] = "EX-MT",
    [5] = "EX",
    [4] = "VG-EX",
    [3] = "VG",
    [2] = "GOOD",
    [1] = "PR"
}

local GRADE_FULL = {
    [10] = "Gem Mint",
    [9] = "Mint",
    [8] = "Near Mint-Mint",
    [7] = "Near Mint",
    [6] = "Excellent-Mint",
    [5] = "Excellent",
    [4] = "Very Good-Excellent",
    [3] = "Very Good",
    [2] = "Good",
    [1] = "Poor"
}

local EDITION_TEXT = {
    base = "BASE",
    foil = "FOIL",
    holographic = "HOLOGRAPHIC",
    polychrome = "POLYCHROME",
    negative = "NEGATIVE"
}

local function upper(value)
    return string.upper(tostring(value or ""))
end

local function card_key_text(key)
    return upper((tostring(key or ""):gsub("_", " ")))
end

local function padded_number(value, width)
    if type(value) == "number" then
        return string.format("%0" .. tostring(width) .. "d", value)
    end
    local text = tostring(value or "")
    if #text >= width then return text end
    return string.rep("0", width - #text) .. text
end

function Label.grade_text(grade, text)
    if text and text.grade_text and text.grade_text[grade] then
        return text.grade_text[grade]
    end
    return GRADE_TEXT[grade] or (text and text.unknown_grade) or "AUTH"
end

function Label.grade_full(grade)
    local full = GRADE_FULL[grade]
    if not full then return "AUTH" end
    return tostring(grade) .. " - " .. full
end

function Label.edition_text(edition, text)
    edition = edition or "base"
    if text and text.edition_text and text.edition_text[edition] then
        return text.edition_text[edition]
    end
    return EDITION_TEXT[edition] or upper(edition)
end

function Label.slab_lines(args)
    args = args or {}
    local grade = args.grade or 0
    local text = args.text or {}
    return {
        {
            left = upper((args.year or "") .. " " .. (args.mod_name or "")),
            right = "#" .. padded_number(args.series_index or 0, 3)
        },
        {
            left = card_key_text(args.local_key),
            right = Label.grade_text(grade, text)
        },
        {
            left = Label.edition_text(args.edition, text),
            right = tostring(grade)
        },
        {
            left = "",
            right = padded_number(args.cert_number or 0, 6)
        }
    }
end

return Label
