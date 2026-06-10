local H = dofile("tests/test_helper.lua")
local Storage = dofile("src/storage.lua")
local Condition = dofile("src/condition.lua")
local DebugTools = dofile("src/debug_tools.lua")

for _, grade in ipairs({ 10, 9, 8, 7, 6, 5 }) do
    local condition = DebugTools.condition_for_grade(grade)
    H.assert_equal(Condition.grade(condition), grade, "crafted condition grades to " .. tostring(grade))
end

local state = Storage.normalize({ currency_g = 100 })

local set_result = DebugTools.adjust_currency(state, "set", "250")
H.assert_equal(set_result.ok, true, "set succeeds")
H.assert_equal(state.currency_g, 250, "set applies amount")

local add_result = DebugTools.adjust_currency(state, "add", 50)
H.assert_equal(add_result.ok, true, "add succeeds")
H.assert_equal(state.currency_g, 300, "add applies amount")

local sub_result = DebugTools.adjust_currency(state, "sub", 1000)
H.assert_equal(sub_result.ok, true, "sub succeeds")
H.assert_equal(state.currency_g, 0, "sub clamps at zero")

H.assert_equal(DebugTools.adjust_currency(state, "set", -5).currency_g, 0, "negative set clamps at zero")
H.assert_equal(DebugTools.adjust_currency(state, "set", "abc").ok, false, "invalid amount rejected")
H.assert_equal(DebugTools.adjust_currency(state, "warp", 5).ok, false, "unknown op rejected")
H.assert_equal(DebugTools.adjust_currency(nil, "set", 5).ok, false, "missing collection rejected")

local catalog = {
    { center_key = "j_a1", local_key = "a1", series_key = "Alpha Series", mod_id = "Alpha", rarity = "common" },
    { center_key = "j_a2", local_key = "a2", series_key = "Alpha Series", mod_id = "Alpha", rarity = "rare" },
    { center_key = "j_b1", local_key = "b1", series_key = "Beta Series", mod_id = "Beta", rarity = "uncommon" },
    { center_key = "j_b2", local_key = "b2", series_key = "Beta Series", mod_id = "Beta", rarity = "legendary" }
}

local seed_state = Storage.normalize({})
local seeded = DebugTools.seed_graded(seed_state, catalog, { count = 4, now = 1767225600 })
H.assert_equal(seeded.ok, true, "seeding succeeds")
H.assert_equal(#seeded.cards, 4, "requested count created")
H.assert_equal(#seed_state.cards, 4, "cards stored in collection")

local first = seeded.cards[1]
H.assert_equal(first.status, "graded", "seeded card graded")
H.assert_equal(first.grade, 10, "first seeded grade")
H.assert_equal(first.edition, "base", "first seeded edition")
H.assert_equal(first.cert_number, "000001", "first cert number")
H.assert_equal(first.acquired_year, 2026, "seeded acquired year")
H.assert_equal(first.source, "debug_seed", "seeded source marker")
H.assert_true(first.condition ~= nil and first.condition.surface ~= nil, "seeded condition stored")

H.assert_equal(seeded.cards[2].grade, 9, "grades cycle downward")
H.assert_equal(seeded.cards[2].edition, "foil", "editions cycle")
H.assert_equal(seeded.cards[4].cert_number, "000004", "cert numbers increment")
H.assert_true(seeded.cards[1].mod_id ~= seeded.cards[2].mod_id, "mods alternate round robin")

local exhausted = DebugTools.seed_graded(Storage.normalize({}), catalog, { count = 99, now = 1767225600 })
H.assert_equal(#exhausted.cards, 4, "seeding stops when catalog exhausted")

local pairing = DebugTools.seed_graded(Storage.normalize({}), {
    { center_key = "j_1", local_key = "k1", series_key = "S", mod_id = "M", rarity = "common" },
    { center_key = "j_2", local_key = "k2", series_key = "S", mod_id = "M", rarity = "common" },
    { center_key = "j_3", local_key = "k3", series_key = "S", mod_id = "M", rarity = "common" },
    { center_key = "j_4", local_key = "k4", series_key = "S", mod_id = "M", rarity = "common" },
    { center_key = "j_5", local_key = "k5", series_key = "S", mod_id = "M", rarity = "common" },
    { center_key = "j_6", local_key = "k6", series_key = "S", mod_id = "M", rarity = "common" }
}, { count = 6, now = 1767225600 })
H.assert_equal(pairing.cards[1].edition, "base", "cycle one starts at base")
H.assert_equal(pairing.cards[6].grade, 10, "sixth card wraps grade cycle")
H.assert_true(pairing.cards[6].edition ~= pairing.cards[1].edition, "grade-edition pairing shifts between cycles")

H.assert_equal(DebugTools.seed_graded(Storage.normalize({}), {}, { count = 3 }).ok, false, "empty catalog rejected")

print("debug tools tests ok")
