local H = dofile("tests/test_helper.lua")
local Config = dofile("src/core/config.lua")
local Storage = dofile("src/core/storage.lua")
local Loadout = dofile("src/domain/loadout.lua")
local rng = H.install_pseudorandom_stub()

local config = Config.normalize({})

H.assert_equal(Loadout.run_identity({ pseudorandom = { seed = "ABC" } }), "ABC", "run identity from seed")
H.assert_equal(Loadout.run_identity({}), "unknown", "run identity fallback")
H.assert_equal(Loadout.run_identity({ run_id = "RX" }), "RX", "explicit run id wins")
H.assert_equal(Loadout.run_identity({ seed = "S" }), "S", "bare seed fallback")

-- config shape
H.assert_equal(#config.loadout.license_prices, 12, "twelve license prices")
H.assert_true(config.loadout.license_prices[12] > config.loadout.license_prices[1], "prices ascend")
H.assert_true(config.loadout.transports.gold.price > config.loadout.transports.blue.price, "gold transport priciest")

-- tier/capacity math
H.assert_equal(Loadout.capacity(0), 0, "no license no capacity")
H.assert_equal(Loadout.capacity(1), 1, "entry x1 capacity")
H.assert_equal(Loadout.capacity(2), 2, "entry x2 capacity")
H.assert_equal(Loadout.capacity(3), 3, "entry x3 capacity")
H.assert_equal(Loadout.capacity(12), 3, "capacity caps at three")
H.assert_equal(Loadout.tier(1), 1, "level one is entry tier")
H.assert_equal(Loadout.tier(12), 4, "level twelve is g-cert tier")
H.assert_equal(Loadout.within(5), 2, "level five is x2")
H.assert_equal(Loadout.rarity_rank("common"), 1, "common rank")
H.assert_equal(Loadout.rarity_rank("legendary"), 4, "legendary rank")
H.assert_equal(Loadout.rarity_rank("cry_exotic"), 4, "modded rarity ranks as top tier")

local mint = { centering = 9.8, print_quality = 9.8, corners = 9.8, edges = 9.8, surface = 9.8 }
local state = Storage.normalize({ currency_g = 100000 })
local add_serial = 0
local function add(rarity, status)
    add_serial = add_serial + 1
    local card = Storage.add_raw_card(state, {
        center_key = "j_" .. rarity .. tostring(add_serial),
        local_key = rarity, rarity = rarity, edition = "base",
        condition = { centering = 9.8, print_quality = 9.8, corners = 9.8, edges = 9.8, surface = 9.8 },
        acquired_at = 1000
    })
    if status then card.status = status end
    return card
end

H.assert_equal(state.loadout.license, 0, "normalize seeds loadout block")

-- sequential license purchase
H.assert_equal(Loadout.purchase_license(config, state).level, 1, "first purchase reaches level one")
local spent = 100000 - state.currency_g
H.assert_equal(spent, config.loadout.license_prices[1], "level one price charged")
local broke = Storage.normalize({ currency_g = 0 })
H.assert_equal(Loadout.purchase_license(config, broke).reason, "insufficient_funds", "broke purchase rejected")
for _ = 2, 12 do Loadout.purchase_license(config, state) end
H.assert_equal(state.loadout.license, 12, "ladder completes")
H.assert_equal(Loadout.purchase_license(config, state).reason, "maxed", "thirteenth purchase rejected")

-- matrix validation: the six spec examples
local function check(level, rarities, expected_reason)
    local probe = Storage.normalize({})
    probe.loadout.license = level
    local ids = {}
    for _, rarity in ipairs(rarities) do
        local card = Storage.add_raw_card(probe, {
            center_key = "j_x" .. tostring(#ids), local_key = "x", rarity = rarity,
            edition = "base", condition = mint, acquired_at = 1
        })
        ids[#ids + 1] = card.id
    end
    local result = Loadout.validate(probe, ids)
    if expected_reason then
        H.assert_equal(result.reason, expected_reason, "level " .. level .. " rejects: " .. expected_reason)
    else
        H.assert_equal(result.ok, true, "level " .. level .. " accepts " .. #rarities .. " cards")
    end
end
check(1, { "common" })                                    -- entry x1: 1 common
check(1, { "uncommon" }, "rarity_locked")                 -- entry x1: no uncommon
check(1, { "common", "common" }, "over_capacity")         -- entry x1: one card only
check(3, { "common", "common", "common" })                -- entry x3: 3 commons
check(4, { "common", "common", "uncommon" })              -- advanced x1: at most 1 uncommon
check(4, { "common", "uncommon", "uncommon" }, "rarity_quota")
check(8, { "uncommon", "rare", "rare" })                  -- pro x2: all-uncommon ok, at most 2 rare
check(8, { "rare", "rare", "rare" }, "rarity_quota")
check(10, { "rare", "rare", "legendary" })                -- g-cert x1: at most 1 legendary
check(10, { "rare", "legendary", "legendary" }, "rarity_quota")
check(12, { "legendary", "legendary", "cry_exotic" })     -- g-cert x3: unlimited

-- membership
state.loadout.card_ids = {}
local c1 = add("common")
local c2 = add("common")
H.assert_equal(Loadout.add_card(state, c1.id).ok, true, "add accepted")
H.assert_equal(Loadout.add_card(state, c1.id).reason, "duplicate", "duplicate rejected")
H.assert_equal(Loadout.contains(state, c1.id), true, "contains reports membership")
local queued = add("common", "queued")
H.assert_equal(Loadout.add_card(state, queued.id).reason, "invalid_status", "queued card rejected")
H.assert_equal(Loadout.add_card(state, "grdl_nope").reason, "unknown_card", "unknown card rejected")
Loadout.add_card(state, c2.id)
c2.status = "sold"
H.assert_equal(Loadout.reconcile(state).removed, 1, "reconcile drops sold members")
H.assert_equal(#state.loadout.card_ids, 1, "membership shrinks after reconcile")
H.assert_equal(Loadout.remove_card(state, c1.id).ok, true, "remove accepted")
H.assert_equal(Loadout.remove_card(state, c1.id).reason, "not_in_loadout", "double remove rejected")

-- transports
H.assert_equal(Loadout.purchase_transport(config, state, "nope").reason, "unknown_transport", "unknown transport rejected")
H.assert_equal(Loadout.purchase_transport(config, state, "blue").ok, true, "blue purchased")
H.assert_equal(state.loadout.active_transport, "blue", "first transport auto-activates")
H.assert_equal(Loadout.purchase_transport(config, state, "blue").reason, "already_owned", "double purchase rejected")
Loadout.purchase_transport(config, state, "gold")
H.assert_equal(Loadout.set_active_transport(state, "gold").ok, true, "owned transport activates")
H.assert_equal(Loadout.set_active_transport(state, "red").reason, "not_owned", "unowned transport rejected")

-- schedule windows
state.loadout.card_ids = {}
local g1 = add("common")
local g2 = add("common")
local g3 = add("common")
Loadout.add_card(state, g1.id); Loadout.add_card(state, g2.id); Loadout.add_card(state, g3.id)
local run_state = Loadout.begin_run(state, "RUN1")
H.assert_equal(run_state.transport, "gold", "run snapshot captures active transport")
H.assert_equal(Loadout.window(config, state, run_state, 2), nil, "gold has no ante-two window")
local window = Loadout.window(config, state, run_state, 1)
H.assert_equal(window.picks, 2, "gold first window allows two")
H.assert_equal(#window.card_ids, 3, "all members offered")
Loadout.mark_entered(run_state, g1.id)
Loadout.mark_entered(run_state, g2.id)
local second = Loadout.window(config, state, run_state, 4)
H.assert_equal(second.picks, 1, "gold second window capped by schedule and remainder")
H.assert_equal(#second.card_ids, 1, "entered cards excluded")
H.assert_equal(second.card_ids[1], g3.id, "remaining card offered")
g3.status = "sold"
H.assert_equal(Loadout.window(config, state, run_state, 4), nil, "mid-run sold member opens no window")
g3.status = "raw"
Loadout.mark_entered(run_state, g3.id)
H.assert_equal(Loadout.window(config, state, run_state, 4), nil, "exhausted loadout opens no window")
local no_transport = Loadout.begin_run(Storage.normalize({}), "RUN2")
H.assert_equal(Loadout.window(config, state, no_transport, 1), nil, "no transport no window")

-- wear roll
local tier, intensity = Loadout.roll_wear(config, 42)
H.assert_true(tier == "minor" or tier == "moderate" or tier == "severe", "wear tier named")
H.assert_true(intensity > 0, "wear intensity positive")
rng.reset()
local tier2, intensity2 = Loadout.roll_wear(config, 42)
H.assert_equal(tier, tier2, "wear roll deterministic")
H.assert_near(intensity, intensity2, 1e-9, "wear intensity deterministic")
H.assert_true(rng.has_call("pseudorandom", "grdl_loadout_wear_"), "wear roll uses native pseudorandom")

rng.restore()
print("loadout tests ok")
