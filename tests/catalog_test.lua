local H = dofile("tests/test_helper.lua")
local Config = dofile("src/config.lua")
local Catalog = dofile("src/catalog.lua")

local config = Config.normalize({})
local centers = {
    j_joker = { key = "j_joker", set = "Joker", rarity = 1, name = "Joker", order = 1 },
    j_rare = { key = "j_rare", set = "Joker", rarity = 3, name = "Rare Joker", order = 3 },
    j_legendary = { key = "j_legendary", set = "Joker", rarity = 4, name = "Legendary Joker", order = 4 },
    c_fool = { key = "c_fool", set = "Tarot", rarity = 1, name = "The Fool" },
    j_modded = { key = "cry_modded", original_key = "modded", set = "Joker", rarity = "exotic", name = "Modded Joker", order = 1, mod = { id = "Cryptid" } },
    j_direct_mod = { key = "kino_air_freshener", original_key = "air_freshener", set = "Joker", rarity = "Mythic", name = "Direct Mod Joker", order = 12, mod_id = "Kino" },
    j_direct_mod_second = { key = "kino_after", original_key = "after", set = "Joker", rarity = 1, name = "After", order = 13, mod_id = "Kino" }
}
local mods = {
    Balatro = { id = "Balatro", name = "BALATRO" },
    Cryptid = { id = "Cryptid", name = "Cryptid" },
    Kino = { id = "Kino", name = "Kino" },
    NoJokers = { id = "NoJokers", name = "No Jokers" }
}

local catalog = Catalog.discover(config, centers, mods)

local function find(center_key)
    for _, entry in ipairs(catalog) do
        if entry.center_key == center_key then return entry end
    end
    return nil
end

H.assert_equal(#catalog, 6, "only Jokers are cataloged")
H.assert_equal(catalog[1].center_key, "cry_modded", "sorted first key")
H.assert_equal(find("kino_air_freshener").series_key, "Kino Series", "direct mod series")
H.assert_equal(find("kino_air_freshener").mod_name, "Kino", "raw mod name kept for labels")
H.assert_equal(find("j_joker").mod_name, "BALATRO", "vanilla mod name kept for labels")
H.assert_equal(find("kino_air_freshener").local_key, "air_freshener", "original key kept")
H.assert_equal(find("kino_air_freshener").series_index, 1, "series index by order")
H.assert_equal(find("kino_air_freshener").rarity, "unknown_high", "unknown rarity maps high")
H.assert_equal(find("j_joker").series_key, "BALATRO Series", "vanilla series")
H.assert_equal(find("j_joker").rarity, "common", "common rarity")
H.assert_equal(find("j_legendary").rarity, "legendary", "legendary rarity")
H.assert_equal(find("cry_modded").series_key, "Cryptid Series", "mod series")
H.assert_equal(find("cry_modded").rarity, "exotic", "exotic rarity")

local series = Catalog.series(catalog)
H.assert_equal(#series, 3, "only series with jokers are listed")
H.assert_equal(series[1].series_key, "BALATRO Series", "vanilla series listed")
H.assert_equal(series[2].series_key, "Cryptid Series", "cryptid series listed")
H.assert_equal(series[3].series_key, "Kino Series", "kino series listed")

local localized_catalog = Catalog.discover(config, {
    j_joker = { key = "j_joker", set = "Joker", rarity = 1 }
}, mods, { series_format = "Series: #1#" })
H.assert_equal(localized_catalog[1].series_key, "Series: BALATRO", "localized series format")

local duplicate_name_catalog = Catalog.discover(config, {
    j_a = { key = "j_a", set = "Joker", rarity = 1, order = 2, mod_id = "ModA" },
    j_b = { key = "j_b", set = "Joker", rarity = 1, order = 1, mod_id = "ModB" }
}, {
    ModA = { id = "ModA", name = "Shared" },
    ModB = { id = "ModB", name = "Shared" }
})
local function find_duplicate(center_key)
    for _, entry in ipairs(duplicate_name_catalog) do
        if entry.center_key == center_key then return entry end
    end
    return nil
end
H.assert_equal(find_duplicate("j_a").series_index, 1, "series index scoped to ModA")
H.assert_equal(find_duplicate("j_b").series_index, 1, "series index scoped to ModB")
H.assert_equal(#Catalog.series(duplicate_name_catalog), 2, "same display name still tracks two mod series")

H.assert_equal(Catalog.normalize_edition(config, nil), "base", "nil edition")
H.assert_equal(Catalog.normalize_edition(config, "negative"), "negative", "negative edition")
H.assert_equal(Catalog.normalize_edition(config, "cry_oversat"), "base", "custom edition rejected")

H.assert_equal(Catalog.center_key_from_card({ center_key = "j_direct" }), "j_direct", "direct center key")
H.assert_equal(Catalog.center_key_from_card({ config = { center = { key = "j_nested" } } }), "j_nested", "nested center key")
H.assert_equal(Catalog.center_key_from_card({ config = { center_key = "j_flat" } }), "j_flat", "flat config center key")
H.assert_equal(Catalog.center_key_from_card(nil), nil, "nil card has no center key")

H.assert_equal(Catalog.edition_from_card({ edition = { key = "e_negative" } }), "negative", "edition key normalized")
H.assert_equal(Catalog.edition_from_card({ edition = { holo = true } }), "holographic", "holo edition normalized")
H.assert_equal(Catalog.edition_from_card({ edition = { key = "e_cry_oversat" } }), "cry_oversat", "custom edition key preserved before auth")
H.assert_equal(Catalog.edition_from_card({ edition = "foil" }), "foil", "string edition accepted")
H.assert_equal(Catalog.edition_from_card({}), "base", "missing edition defaults to base")

H.assert_equal(Catalog.edition_flags("foil").foil, true, "foil flag")
H.assert_equal(Catalog.edition_flags("holographic").holo, true, "holographic maps to holo flag")
H.assert_equal(Catalog.edition_flags("polychrome").polychrome, true, "polychrome flag")
H.assert_equal(Catalog.edition_flags("negative").negative, true, "negative flag")
H.assert_equal(Catalog.edition_flags("base"), nil, "base has no edition flag")
H.assert_equal(Catalog.edition_flags(nil), nil, "nil edition has no flag")

print("catalog tests ok")
