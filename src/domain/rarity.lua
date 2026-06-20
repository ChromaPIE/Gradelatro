local Rarity = {}

local STATE_KEY = "__GradelatroRarityRegistry"
local UNKNOWN_HIGH = "unknown_high"

local state = rawget(_G, STATE_KEY)
if type(state) ~= "table" then
    state = {
        definitions = {},
        aliases = {}
    }
    rawset(_G, STATE_KEY, state)
end

local function normalized_alias(value)
    if type(value) == "number" then return value end
    if type(value) ~= "string" then return nil end
    return value:lower()
end

local function register_alias(alias, key)
    local alias_key = normalized_alias(alias)
    if alias_key ~= nil then
        state.aliases[alias_key] = key
    end
end

function Rarity.register(definition)
    if type(definition) ~= "table" or type(definition.key) ~= "string" or definition.key == "" then
        return nil
    end

    local key = definition.key
    local current = state.definitions[key] or {}
    for field, value in pairs(definition) do
        if field ~= "aliases" then current[field] = value end
    end
    current.key = key
    current.value_key = current.value_key or key
    current.buyout_key = current.buyout_key or key
    current.label_key = current.label_key or ("grdl_k_rarity_" .. key)
    state.definitions[key] = current

    register_alias(key, key)
    for _, alias in ipairs(definition.aliases or {}) do
        register_alias(alias, key)
    end
    return current
end

local function register_base(key, aliases)
    return Rarity.register({
        key = key,
        aliases = aliases,
        value_key = key,
        buyout_key = key,
        label_key = "grdl_k_rarity_" .. key,
        builtin = true
    })
end

local function register_external(key, value_key, aliases)
    return Rarity.register({
        key = key,
        aliases = aliases,
        value_key = value_key or UNKNOWN_HIGH,
        buyout_key = UNKNOWN_HIGH,
        label_key = "k_" .. key,
        external = true
    })
end

register_base("common", { 1, "1", "Common" })
register_base("uncommon", { 2, "2", "Uncommon" })
register_base("rare", { 3, "3", "Rare" })
register_base("legendary", { 4, "4", "Legendary" })
register_base("exotic", { "Exotic" })
register_base(UNKNOWN_HIGH, { "Unknown High", "unknown high" })

register_external("cry_exotic", "cry_exotic")
register_external("cry_epic", "cry_epic")
register_external("soe_basic", "soe_basic", { "soe_base" })
register_external("soe_unusual", "soe_unusual")
register_external("soe_unique", "soe_unique")
register_external("soe_fabled", "soe_fabled")

function Rarity.key(raw)
    local alias_key = normalized_alias(raw)
    return state.aliases[alias_key] or UNKNOWN_HIGH
end

function Rarity.is_registered(raw)
    local alias_key = normalized_alias(raw)
    return state.aliases[alias_key] ~= nil
end

function Rarity.definition(raw)
    return state.definitions[Rarity.key(raw)] or state.definitions[UNKNOWN_HIGH]
end

local function rarity_base_map(config)
    return config and config.economy and config.economy.rarity_base or {}
end

function Rarity.base_value(config, raw)
    local map = rarity_base_map(config)
    local key = Rarity.key(raw)
    local definition = state.definitions[key] or state.definitions[UNKNOWN_HIGH]
    local value_key = definition and definition.value_key or UNKNOWN_HIGH
    return map[key] or map[value_key] or map[UNKNOWN_HIGH] or 0
end

function Rarity.has_specific_base_value(config, raw)
    if not Rarity.is_registered(raw) then return false end
    local key = Rarity.key(raw)
    if key == UNKNOWN_HIGH then return false end
    return rarity_base_map(config)[key] ~= nil
end

function Rarity.buyout_key(raw)
    local definition = Rarity.definition(raw)
    return definition and definition.buyout_key or UNKNOWN_HIGH
end

function Rarity.label_key(raw)
    local definition = Rarity.definition(raw)
    return definition and definition.label_key or "grdl_k_rarity_" .. UNKNOWN_HIGH
end

function Rarity.is_external(raw)
    local definition = Rarity.definition(raw)
    return definition and definition.external == true or false
end

return Rarity
