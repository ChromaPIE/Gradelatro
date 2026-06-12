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

local Grading = load_src("grading.lua")
Bootstrap.attach(Gradelatro, "Grading", Grading)

local Market = load_src("market.lua")
Bootstrap.attach(Gradelatro, "Market", Market)

local BlackMarket = load_src("black_market.lua")
Bootstrap.attach(Gradelatro, "BlackMarket", BlackMarket)

local Loadout = load_src("loadout.lua")
Bootstrap.attach(Gradelatro, "Loadout", Loadout)

local Label = load_src("label.lua")
Bootstrap.attach(Gradelatro, "Label", Label)

local UICommon = load_src("ui_common.lua")
Bootstrap.attach(Gradelatro, "UICommon", UICommon)

local SlabUI = load_src("slab_ui.lua")
Bootstrap.attach(Gradelatro, "SlabUI", SlabUI)

local Binder = load_src("binder.lua")
Bootstrap.attach(Gradelatro, "Binder", Binder)

local BinderUI = load_src("binder_ui.lua")
Bootstrap.attach(Gradelatro, "BinderUI", BinderUI)
BinderUI.install_runtime(Gradelatro, rawget(_G, "G"))

local MarketUI = load_src("market_ui.lua")
Bootstrap.attach(Gradelatro, "MarketUI", MarketUI)
MarketUI.install_runtime(Gradelatro, rawget(_G, "G"))

if SMODS and SMODS.Keybind then
    pcall(SMODS.Keybind, {
        key_pressed = "g",
        event = "pressed",
        action = function()
            local runtime = rawget(_G, "G")
            local target = runtime and runtime.CONTROLLER and runtime.CONTROLLER.hovering and runtime.CONTROLLER.hovering.target or nil
            if target and target.grdl_record then
                BinderUI.inspect_from_card(Gradelatro, target)
            elseif target and target.grdl_offer then
                BinderUI.inspect_offer(Gradelatro, target.grdl_offer)
            end
        end
    })
end

local Buyout = load_src("buyout.lua")
Bootstrap.attach(Gradelatro, "Buyout", Buyout)

local Settlement = load_src("settlement.lua")
Bootstrap.attach(Gradelatro, "Settlement", Settlement)

local Persistence = load_src("persistence.lua")
Bootstrap.attach(Gradelatro, "Persistence", Persistence)

local BuyoutUI = load_src("buyout_ui.lua")
Bootstrap.attach(Gradelatro, "BuyoutUI", BuyoutUI)
BuyoutUI.install_runtime(Gradelatro, rawget(_G, "G"))

local RunEnd = load_src("run_end.lua")
Bootstrap.attach(Gradelatro, "RunEnd", RunEnd)

local DebugTools = load_src("debug_tools.lua")
Bootstrap.attach(Gradelatro, "DebugTools", DebugTools)
pcall(DebugTools.install, Gradelatro)

return Gradelatro
