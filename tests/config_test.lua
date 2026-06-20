local H = dofile("tests/test_helper.lua")
local Config = dofile("src/core/config.lua")

local normalized = Config.normalize({
    economy = { buyout_mult = 1.25 },
    grading = { default_service = "priority" }
})

H.assert_equal(normalized.schema_version, 1, "schema version")
H.assert_near(normalized.economy.buyout_mult, 1.25, 0.000001, "override buyout mult")
H.assert_near(normalized.economy.rarity_base.common, 35, 0.000001, "default common base")
H.assert_near(normalized.economy.rarity_base.unknown_high, 1500, 0.000001, "unknown high base")
H.assert_near(normalized.economy.rarity_base.cry_exotic, 3000, 0.000001, "cryptid exotic base")
H.assert_near(normalized.economy.rarity_base.cry_epic, 1500, 0.000001, "cryptid epic base")
H.assert_near(normalized.economy.rarity_base.soe_basic, 60, 0.000001, "soe basic base")
H.assert_near(normalized.economy.rarity_base.soe_unusual, 150, 0.000001, "soe unusual base")
H.assert_near(normalized.economy.rarity_base.soe_unique, 485, 0.000001, "soe unique base")
H.assert_near(normalized.economy.rarity_base.soe_fabled, 1250, 0.000001, "soe fabled base")
H.assert_equal(normalized.grading.default_service, "priority", "override grading service")
H.assert_near(normalized.market.heat_min, 0.75, 0.000001, "market heat min")

local empty = Config.normalize(nil)
H.assert_equal(empty.carry, nil, "carry config renamed to wear")
H.assert_near(empty.wear.minor_chance, 0.70, 0.000001, "wear minor chance default")
H.assert_near(empty.wear.severe_max, 1.50, 0.000001, "wear severe max default")
H.assert_true(empty.wear.severe_max > empty.wear.moderate_max and empty.wear.moderate_max > empty.wear.minor_max, "wear tiers escalate")
H.assert_equal(empty.authenticated_editions.negative, true, "negative edition accepted")
H.assert_equal(empty.authenticated_editions.cry_exotic, nil, "unknown custom edition not accepted")
H.assert_equal(empty.catalog.series_format, "#1# Series", "series format is localizable config")

print("config tests ok")
