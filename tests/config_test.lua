local H = dofile("tests/test_helper.lua")
local Config = dofile("src/config.lua")

local normalized = Config.normalize({
    economy = { buyout_mult = 1.25 },
    grading = { default_service = "priority" }
})

H.assert_equal(normalized.schema_version, 1, "schema version")
H.assert_near(normalized.economy.buyout_mult, 1.25, 0.000001, "override buyout mult")
H.assert_near(normalized.economy.rarity_base.common, 35, 0.000001, "default common base")
H.assert_equal(normalized.grading.default_service, "priority", "override grading service")
H.assert_near(normalized.market.heat_min, 0.75, 0.000001, "market heat min")

local empty = Config.normalize(nil)
H.assert_equal(empty.authenticated_editions.negative, true, "negative edition accepted")
H.assert_equal(empty.authenticated_editions.cry_exotic, nil, "unknown custom edition not accepted")
H.assert_equal(empty.catalog.series_format, "#1# Series", "series format is localizable config")

print("config tests ok")
