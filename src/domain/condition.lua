local Condition = {}

local WEAR = {
    base = { corners = 1.00, edges = 1.00, surface = 1.00 },
    foil = { corners = 0.90, edges = 0.90, surface = 1.30 },
    holographic = { corners = 1.00, edges = 1.00, surface = 1.50 },
    polychrome = { corners = 1.10, edges = 1.10, surface = 1.70 },
    negative = { corners = 1.25, edges = 1.25, surface = 1.40 }
}

local GRADE_MULT = {
    [10] = 6.0,
    [9] = 2.2,
    [8] = 1.2,
    [7] = 0.85,
    [6] = 0.65,
    [5] = 0.50,
    [4] = 0.40,
    [3] = 0.32,
    [2] = 0.26,
    [1] = 0.20
}

local function clamp(value, min_value, max_value)
    if value < min_value then return min_value end
    if value > max_value then return max_value end
    return value
end

local function average(condition)
    return (
        condition.centering +
        condition.print_quality +
        condition.corners +
        condition.edges +
        condition.surface
    ) / 5
end

local function min_mutable(condition)
    return math.min(condition.corners, condition.edges, condition.surface)
end

function Condition.generate(seed, edition)
    local rand_key = "grdl_condition_" .. tostring(seed or os.time())
    local function rand() return pseudorandom(rand_key) end
    local edition_surface_penalty = edition == "polychrome" and 0.20 or edition == "negative" and 0.15 or edition == "holographic" and 0.10 or 0
    return {
        centering = clamp(8.4 + rand() * 1.6, 6.0, 10.0),
        print_quality = clamp(8.2 + rand() * 1.8 - edition_surface_penalty, 6.0, 10.0),
        corners = clamp(8.1 + rand() * 1.9, 6.0, 10.0),
        edges = clamp(8.1 + rand() * 1.9, 6.0, 10.0),
        surface = clamp(8.0 + rand() * 2.0 - edition_surface_penalty, 6.0, 10.0)
    }
end

function Condition.apply_wear(condition, edition, intensity)
    intensity = intensity or 0.25
    local wear = WEAR[edition or "base"] or WEAR.base
    return {
        centering = condition.centering,
        print_quality = condition.print_quality,
        corners = clamp(condition.corners - intensity * wear.corners, 1.0, 10.0),
        edges = clamp(condition.edges - intensity * wear.edges, 1.0, 10.0),
        surface = clamp(condition.surface - intensity * wear.surface, 1.0, 10.0)
    }
end

function Condition.grade(condition)
    local avg = average(condition)
    local min_part = math.min(condition.centering, condition.print_quality, min_mutable(condition))
    if avg >= 9.65 and min_part >= 9.4 then return 10 end
    if avg >= 9.00 and min_part >= 8.5 then return 9 end
    if avg >= 8.00 and min_part >= 7.5 then return 8 end
    if avg >= 7.00 and min_part >= 6.5 then return 7 end
    if avg >= 6.00 and min_part >= 5.5 then return 6 end
    if avg >= 5.00 then return 5 end
    if avg >= 4.00 then return 4 end
    if avg >= 3.00 then return 3 end
    if avg >= 2.00 then return 2 end
    return 1
end

function Condition.grade_multiplier(grade)
    return GRADE_MULT[grade] or 0
end

return Condition
