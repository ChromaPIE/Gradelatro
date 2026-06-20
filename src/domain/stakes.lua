local Stakes = {}

local function load_src(path)
    return assert(SMODS.load_file("src/" .. path))()
end

local Rarity = load_src("domain/rarity.lua")

local ALLOWED = {
    red = { common = true },
    blue = { common = true, uncommon = true },
    pre_gold = { common = true, uncommon = true, rare = true },
    gold_plus = {
        common = true,
        uncommon = true,
        rare = true,
        legendary = true,
        exotic = true,
        unknown_high = true
    }
}

function Stakes.gate_for_level(anchors, stake_level)
    anchors = anchors or {}
    stake_level = stake_level or 1
    local red = anchors.stake_red or 2
    local blue = anchors.stake_blue or 5
    local gold = anchors.stake_gold or 8
    if stake_level <= red then return "red" end
    if stake_level <= blue then return "blue" end
    if stake_level < gold then return "pre_gold" end
    return "gold_plus"
end

function Stakes.can_buyout(gate, rarity)
    local allowed = ALLOWED[gate] or ALLOWED.red
    return allowed[Rarity.buyout_key(rarity)] == true
end

return Stakes
