local H = dofile("tests/test_helper.lua")
local Config = dofile("src/core/config.lua")
local Economy = dofile("src/domain/economy.lua")

local config = Config.normalize({})

local rav = Economy.raw_anchor_value(config, {
    rarity = "rare",
    edition = "polychrome",
    series_heat = 1.10,
    availability_mult = 1.0
})

H.assert_near(rav, 677.6, 0.000001, "rare polychrome RAV")
H.assert_equal(Economy.raw_anchor_value(config, { rarity = "cry_exotic", edition = "base" }), 3000, "cryptid exotic RAV")
H.assert_equal(Economy.raw_anchor_value(config, { rarity = "cry_epic", edition = "base" }), 1500, "cryptid epic RAV")
H.assert_equal(Economy.raw_anchor_value(config, { rarity = "soe_basic", edition = "base" }), 60, "soe basic RAV")
H.assert_equal(Economy.raw_anchor_value(config, { rarity = "soe_unusual", edition = "base" }), 150, "soe unusual RAV")
H.assert_equal(Economy.raw_anchor_value(config, { rarity = "soe_unique", edition = "base" }), 485, "soe unique RAV")
H.assert_equal(Economy.raw_anchor_value(config, { rarity = "soe_fabled", edition = "base" }), 1250, "soe fabled RAV")
H.assert_equal(Economy.raw_anchor_value(config, { rarity = "worm_otherworldly", edition = "base" }), 1500, "unspecialized external fallback high RAV")
H.assert_equal(Economy.raw_anchor_value(config, { rarity = "mystic_unknown", edition = "base" }), 1500, "unregistered fallback high RAV")
H.assert_equal(Economy.buyout_price(config, { rav = 100, owned_count = 0 }), 85, "first copy discount")
H.assert_equal(Economy.buyout_price(config, { rav = 100, owned_count = 1 }), 100, "second copy base")
H.assert_equal(Economy.buyout_price(config, { rav = 100, owned_count = 3 }), 115, "hoard multiplier")
H.assert_equal(Economy.grading_fee(config, 100, "standard"), 16, "standard fee")
H.assert_equal(Economy.grading_fee(config, 50, "prescreen"), 15, "minimum fee")
H.assert_equal(Economy.settlement_g(config, { stake_level = 8, won = true, dollars = 1000 }), 258, "gold win curve settlement")
H.assert_equal(Economy.settlement_g(config, { gate = "blue", won = false, dollars = 100 }), 10, "loss settlement")

print("economy tests ok")
