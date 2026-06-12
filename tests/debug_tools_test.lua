local H = dofile("tests/test_helper.lua")
local Storage = dofile("src/core/storage.lua")
local Condition = dofile("src/domain/condition.lua")
local DebugTools = dofile("src/debug/debug_tools.lua")

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
local Config = dofile("src/core/config.lua")
local seed_config = Config.normalize({})
local seeded = DebugTools.seed_cards(seed_state, catalog, { count = 4, now = 1767225600, rng_seed = 42, config = seed_config })
H.assert_equal(seeded.ok, true, "seeding succeeds")
H.assert_equal(#seeded.cards, 4, "requested count created")
H.assert_equal(#seed_state.cards, 4, "cards stored in collection")

local GRADE_SET = { [10] = true, [9] = true, [8] = true, [7] = true, [6] = true }
local EDITION_SET = { base = true, foil = true, holographic = true, polychrome = true, negative = true }
local distinct_grades = {}
local distinct_editions = {}
for _, card in ipairs(seeded.cards) do
    H.assert_equal(card.status, "graded", "seeded card graded")
    H.assert_true(GRADE_SET[card.grade] == true, "seeded grade within cycle set")
    H.assert_true(EDITION_SET[card.edition] == true, "seeded edition within authenticated set")
    H.assert_equal(card.acquired_year, 2026, "seeded acquired year")
    H.assert_equal(card.acquired_month, 1, "seeded acquired month")
    H.assert_equal(card.acquired_day, 1, "seeded acquired day")
    H.assert_equal(card.source, "debug_seed", "seeded source marker")
    H.assert_true(card.condition ~= nil and card.condition.surface ~= nil, "seeded condition stored")
    local expected_price = math.floor(seed_config.economy.rarity_base[card.rarity] * seed_config.economy.edition_mult[card.edition])
    H.assert_equal(card.acquired_price, expected_price, "seeded price follows anchor value")
    distinct_grades[card.grade] = true
    distinct_editions[card.edition] = true
end
local grade_count, edition_count = 0, 0
for _ in pairs(distinct_grades) do grade_count = grade_count + 1 end
for _ in pairs(distinct_editions) do edition_count = edition_count + 1 end
H.assert_true(grade_count >= 2, "grades vary within a batch")
H.assert_true(edition_count >= 2, "editions vary within a batch")

H.assert_equal(seeded.cards[1].cert_number, "000001", "first cert number")
H.assert_equal(seeded.cards[4].cert_number, "000004", "cert numbers increment")
H.assert_true(seeded.cards[1].mod_id ~= seeded.cards[2].mod_id, "mods alternate round robin")

local function batch_signature(cards)
    local parts = {}
    for _, card in ipairs(cards) do
        parts[#parts + 1] = tostring(card.center_key) .. ":" .. tostring(card.grade) .. ":" .. tostring(card.edition)
    end
    return table.concat(parts, "|")
end

local replay = DebugTools.seed_cards(Storage.normalize({}), catalog, { count = 4, now = 1767225600, rng_seed = 42, config = seed_config })
H.assert_equal(batch_signature(replay.cards), batch_signature(seeded.cards), "same seed reproduces the batch")

local different = false
for seed = 43, 47 do
    local other = DebugTools.seed_cards(Storage.normalize({}), catalog, { count = 4, now = 1767225600, rng_seed = seed, config = seed_config })
    if batch_signature(other.cards) ~= batch_signature(seeded.cards) then
        different = true
        break
    end
end
H.assert_true(different, "different seeds change the batch")

local grown_state = Storage.normalize({})
DebugTools.seed_cards(grown_state, catalog, { count = 2, now = 1767225600, config = seed_config })
local second_run = DebugTools.seed_cards(grown_state, catalog, { count = 2, now = 1767225600, config = seed_config })
H.assert_equal(#grown_state.cards, 4, "consecutive runs accumulate")
H.assert_equal(second_run.ok, true, "second unseeded run succeeds")

local exhausted = DebugTools.seed_cards(Storage.normalize({}), catalog, { count = 99, now = 1767225600 })
H.assert_equal(#exhausted.cards, 4, "seeding stops when catalog exhausted")

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

-- ===== grdl parent command helpers =====
local loadout_state = Storage.normalize({})
H.assert_equal(DebugTools.set_license(loadout_state, 7).ok, true, "license set")
H.assert_equal(loadout_state.loadout.license, 7, "license stored")
H.assert_equal(DebugTools.set_license(loadout_state, 99).level, 12, "license clamps high")
H.assert_equal(DebugTools.set_license(loadout_state, -3).level, 0, "license clamps low")
H.assert_equal(DebugTools.set_license(nil, 3).ok, false, "license without collection rejected")
H.assert_equal(DebugTools.set_license(loadout_state, "abc").ok, false, "license needs a number")

local granted = DebugTools.grant_transports(seed_config, loadout_state, "all")
H.assert_equal(granted.ok, true, "grant all succeeds")
H.assert_equal(loadout_state.loadout.transports.gold, true, "gold granted")
H.assert_equal(loadout_state.loadout.transports.blue, true, "blue granted")
H.assert_true(loadout_state.loadout.active_transport ~= nil, "a transport activates")
local single_state = Storage.normalize({})
H.assert_equal(DebugTools.grant_transports(seed_config, single_state, "red").ok, true, "single grant succeeds")
H.assert_equal(single_state.loadout.transports.red, true, "red granted")
H.assert_equal(single_state.loadout.active_transport, "red", "single grant activates")
H.assert_equal(DebugTools.grant_transports(seed_config, single_state, "warp").ok, false, "unknown transport rejected")

local prof_state = Storage.normalize({})
DebugTools.seed_cards(prof_state, catalog, { count = 3, now = 1767225600, config = seed_config })
prof_state.cards[3].status = "raw"
local prof_set = DebugTools.set_proficiency(prof_state, 89)
H.assert_equal(prof_set.ok, true, "proficiency set")
H.assert_equal(prof_set.updated, 2, "only graded cards updated")
H.assert_equal(prof_state.cards[1].proficiency.antes, 89, "antes applied")
H.assert_equal(prof_state.cards[3].proficiency, nil, "raw card untouched")
H.assert_equal(DebugTools.set_proficiency(prof_state, "abc").ok, false, "proficiency needs a number")

local queue_state = Storage.normalize({})
DebugTools.seed_cards(queue_state, catalog, { count = 1, graded = false, now = 1767225600 })
queue_state.grading_queue[1] = { card_id = queue_state.cards[1].id, submitted_at = 100, due_at = 99999 }
local finished = DebugTools.finish_queue(queue_state, 5000)
H.assert_equal(finished.ok, true, "queue finish succeeds")
H.assert_equal(finished.finished, 1, "queue entries fast-forwarded")
H.assert_true(queue_state.grading_queue[1].due_at <= 5000, "due time pulled to now")

-- ===== dispatch routing (headless paths) =====
local ns = { config = seed_config, mod = { id = "Gradelatro", config = {} }, collection = Storage.normalize({ currency_g = 5 }) }
local previous_dispatch_smods = rawget(_G, "SMODS")
_G.SMODS = { save_mod_config = function() return true end }
local message = DebugTools.dispatch(ns, {})
H.assert_true(message:find("grdl", 1, true) ~= nil, "bare command prints help")
message = DebugTools.dispatch(ns, { "help" })
H.assert_true(message:find("license", 1, true) ~= nil, "help lists subcommands")
message = DebugTools.dispatch(ns, { "g" })
H.assert_true(message:find("5", 1, true) ~= nil, "g shows balance")
DebugTools.dispatch(ns, { "g", "set", "123" })
H.assert_equal(ns.collection.currency_g, 123, "g set applies")
DebugTools.dispatch(ns, { "license", "4" })
H.assert_equal(ns.collection.loadout.license, 4, "license dispatch applies")
DebugTools.dispatch(ns, { "transport", "all" })
H.assert_equal(ns.collection.loadout.transports.purple, true, "transport dispatch grants")
local _, unknown_err = DebugTools.dispatch(ns, { "warp" })
H.assert_equal(unknown_err, "ERROR", "unknown subcommand errors")
local _, seed_err = DebugTools.dispatch(ns, { "seed", "g", "2" })
H.assert_equal(seed_err, "ERROR", "seed without game centers errors headless")
local _, bm_err = DebugTools.dispatch(ns, { "bm" })
H.assert_equal(bm_err, "ERROR", "bm without game runtime errors headless")
DebugTools.seed_cards(ns.collection, catalog, { count = 2, now = 1767225600, config = seed_config })
DebugTools.dispatch(ns, { "prof", "34" })
H.assert_equal(ns.collection.cards[1].proficiency.antes, 34, "prof dispatch applies")
ns.collection.grading_queue[1] = { card_id = ns.collection.cards[1].id, submitted_at = 1, due_at = 1e12 }
DebugTools.dispatch(ns, { "queue" })
H.assert_true(ns.collection.grading_queue[1].due_at < 1e12, "queue dispatch fast-forwards")
DebugTools.dispatch(ns, { "clear" })
H.assert_equal(#ns.collection.cards, 0, "clear dispatch wipes")
_G.SMODS = previous_dispatch_smods

print("debug tools tests ok")
