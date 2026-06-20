local H = dofile("tests/test_helper.lua")
local Config = dofile("src/core/config.lua")
local Rarity = dofile("src/domain/rarity.lua")

local config = Config.normalize({})

H.assert_equal(Rarity.key(1), "common", "numeric common key")
H.assert_equal(Rarity.key("Common"), "common", "string common key")
H.assert_equal(Rarity.key("exotic"), "exotic", "legacy exotic key preserved")
H.assert_equal(Rarity.key("cry_exotic"), "cry_exotic", "cryptid exotic key")
H.assert_equal(Rarity.key("cry_epic"), "cry_epic", "cryptid epic key")
H.assert_equal(Rarity.key("soe_basic"), "soe_basic", "soe basic key")
H.assert_equal(Rarity.key("Mythic"), "unknown_high", "unregistered rarity maps high")
H.assert_equal(Rarity.key("worm_otherworldly"), "unknown_high", "unspecialized external rarity maps high")

H.assert_equal(Rarity.base_value(config, "cry_exotic"), 3000, "cryptid exotic base value")
H.assert_equal(Rarity.base_value(config, "cry_epic"), 1500, "cryptid epic base value")
H.assert_equal(Rarity.base_value(config, "unknown_high"), 1500, "unknown high base value")
H.assert_equal(Rarity.base_value(config, "mystic_unknown"), 1500, "unknown custom base value")
H.assert_equal(Rarity.base_value(config, "worm_otherworldly"), 1500, "unspecialized external base value")
H.assert_equal(Rarity.base_value(config, "soe_basic"), 60, "soe basic base value")
H.assert_equal(Rarity.base_value(config, "soe_unusual"), 150, "soe unusual base value")
H.assert_equal(Rarity.base_value(config, "soe_unique"), 485, "soe unique base value")
H.assert_equal(Rarity.base_value(config, "soe_fabled"), 1250, "soe fabled base value")

H.assert_equal(Rarity.buyout_key("cry_exotic"), "unknown_high", "custom high buyout bucket")
H.assert_equal(Rarity.buyout_key("soe_basic"), "unknown_high", "soe keeps conservative buyout gate")
H.assert_equal(Rarity.label_key("cry_epic"), "k_cry_epic", "external localization key")
H.assert_equal(Rarity.label_key("unknown_high"), "grdl_k_rarity_unknown_high", "internal unknown label key")
H.assert_equal(Rarity.has_specific_base_value(config, "common"), true, "common has a specific base value")
H.assert_equal(Rarity.has_specific_base_value(config, "cry_exotic"), true, "cryptid exotic has a specific base value")
H.assert_equal(Rarity.has_specific_base_value(config, "soe_basic"), true, "soe basic has a specific base value")
H.assert_equal(Rarity.has_specific_base_value(config, "unknown_high"), false, "unknown high is a fallback value")
H.assert_equal(Rarity.has_specific_base_value(config, "worm_otherworldly"), false, "unspecialized external has no specific base value")

Rarity.register({
    key = "test_special",
    aliases = { "TestSpecial" },
    value_key = "unknown_high",
    label_key = "k_test_special",
    buyout_key = "unknown_high"
})
H.assert_equal(Rarity.key("TestSpecial"), "test_special", "runtime registration alias")
H.assert_equal(Rarity.base_value(config, "TestSpecial"), 1500, "runtime registration value fallback")
H.assert_equal(Rarity.has_specific_base_value(config, "TestSpecial"), false, "runtime fallback registration has no specific base value")

print("rarity tests ok")
