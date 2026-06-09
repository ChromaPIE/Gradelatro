local current_mod = SMODS and SMODS.current_mod or {
    path = ".",
    version = "0.1.0",
    config = {}
}

local function load_src(path)
    if SMODS and SMODS.load_file then
        return assert(SMODS.load_file("src/" .. path))()
    end
    return dofile("src/" .. path)
end

local Bootstrap = load_src("bootstrap.lua")
local Gradelatro = Bootstrap.init(current_mod)

local Config = load_src("config.lua")
Bootstrap.attach(Gradelatro, "Config", Config)

Gradelatro.config = Config.normalize(current_mod.config or {})
current_mod.config = Gradelatro.config

local Economy = load_src("economy.lua")
Bootstrap.attach(Gradelatro, "Economy", Economy)

local Stakes = load_src("stakes.lua")
Bootstrap.attach(Gradelatro, "Stakes", Stakes)

local Condition = load_src("condition.lua")
Bootstrap.attach(Gradelatro, "Condition", Condition)

local Storage = load_src("storage.lua")
Bootstrap.attach(Gradelatro, "Storage", Storage)

current_mod.config.collection = Storage.normalize(current_mod.config.collection)
Gradelatro.collection = current_mod.config.collection

local Catalog = load_src("catalog.lua")
Bootstrap.attach(Gradelatro, "Catalog", Catalog)

local Label = load_src("label.lua")
Bootstrap.attach(Gradelatro, "Label", Label)

return Gradelatro
