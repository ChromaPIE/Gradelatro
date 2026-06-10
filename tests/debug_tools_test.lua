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
local Config = dofile("src/config.lua")
local seed_config = Config.normalize({})
local seeded = DebugTools.seed_cards(seed_state, catalog, { count = 4, now = 1767225600, config = seed_config })
H.assert_equal(seeded.ok, true, "seeding succeeds")
H.assert_equal(#seeded.cards, 4, "requested count created")
H.assert_equal(#seed_state.cards, 4, "cards stored in collection")

local first = seeded.cards[1]
H.assert_equal(first.status, "graded", "seeded card graded")
H.assert_equal(first.grade, 10, "first seeded grade")
H.assert_equal(first.edition, "base", "first seeded edition")
H.assert_equal(first.cert_number, "000001", "first cert number")
H.assert_equal(first.acquired_year, 2026, "seeded acquired year")
H.assert_equal(first.acquired_month, 1, "seeded acquired month")
H.assert_equal(first.acquired_day, 1, "seeded acquired day")
H.assert_equal(first.acquired_price, 35, "seeded price from anchor value")
H.assert_equal(first.source, "debug_seed", "seeded source marker")
H.assert_true(first.condition ~= nil and first.condition.surface ~= nil, "seeded condition stored")

H.assert_equal(seeded.cards[2].grade, 9, "grades cycle downward")
H.assert_equal(seeded.cards[2].edition, "foil", "editions cycle")
H.assert_equal(seeded.cards[4].cert_number, "000004", "cert numbers increment")
H.assert_true(seeded.cards[1].mod_id ~= seeded.cards[2].mod_id, "mods alternate round robin")

local exhausted = DebugTools.seed_cards(Storage.normalize({}), catalog, { count = 99, now = 1767225600 })
H.assert_equal(#exhausted.cards, 4, "seeding stops when catalog exhausted")

local pairing = DebugTools.seed_cards(Storage.normalize({}), {
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

H.assert_equal(DebugTools.seed_cards(Storage.normalize({}), {}, { count = 3 }).ok, false, "empty catalog rejected")

local raw_state = Storage.normalize({})
local raw_seeded = DebugTools.seed_cards(raw_state, catalog, { count = 2, graded = false, now = 1767225600 })
H.assert_equal(raw_seeded.ok, true, "ungraded seeding succeeds")
H.assert_equal(#raw_seeded.cards, 2, "ungraded count created")
H.assert_equal(raw_seeded.cards[1].status, "raw", "ungraded card stays raw")
H.assert_equal(raw_seeded.cards[1].grade, nil, "ungraded card has no grade")
H.assert_equal(raw_seeded.cards[1].cert_number, nil, "ungraded card has no cert")
H.assert_equal(raw_state.next_cert_id, 1, "ungraded seeding keeps cert counter")
H.assert_true(raw_seeded.cards[1].condition ~= nil, "ungraded card carries hidden condition")

local parsed_default = DebugTools.parse_seed_args({})
H.assert_equal(parsed_default.graded, true, "default mode graded")
H.assert_equal(parsed_default.count, 10, "default count ten")
local parsed_count = DebugTools.parse_seed_args({ "7" })
H.assert_equal(parsed_count.graded, true, "numeric arg keeps graded mode")
H.assert_equal(parsed_count.count, 7, "numeric arg sets count")
local parsed_ug = DebugTools.parse_seed_args({ "ug", "5" })
H.assert_equal(parsed_ug.graded, false, "ug selects ungraded")
H.assert_equal(parsed_ug.count, 5, "ug count")
local parsed_g = DebugTools.parse_seed_args({ "g", "3" })
H.assert_equal(parsed_g.graded, true, "g selects graded")
H.assert_equal(parsed_g.count, 3, "g count")
H.assert_equal(DebugTools.parse_seed_args({ "ug" }).count, 10, "mode without count defaults to ten")
H.assert_equal(DebugTools.parse_seed_args({ "warp" }).ok, false, "unknown mode rejected")

local clear_state = Storage.normalize({ currency_g = 77 })
DebugTools.seed_cards(clear_state, catalog, { count = 3, now = 1767225600 })
clear_state.grading_queue[#clear_state.grading_queue + 1] = { card_id = clear_state.cards[1].id, due_at = 99 }
local cert_before_clear = clear_state.next_cert_id
local cleared = DebugTools.clear_collection(clear_state)
H.assert_equal(cleared.ok, true, "clear succeeds")
H.assert_equal(cleared.cards_removed, 3, "clear reports card count")
H.assert_equal(cleared.queue_removed, 1, "clear reports queue count")
H.assert_equal(#clear_state.cards, 0, "cards wiped")
H.assert_equal(#clear_state.grading_queue, 0, "queue wiped")
H.assert_equal(clear_state.currency_g, 77, "clear keeps currency")
H.assert_equal(clear_state.next_cert_id, cert_before_clear, "clear keeps cert counter")
H.assert_equal(DebugTools.clear_collection(nil).ok, false, "clear without collection rejected")

print("debug tools tests ok")
