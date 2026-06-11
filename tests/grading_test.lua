local H = dofile("tests/test_helper.lua")
local Config = dofile("src/config.lua")
local Storage = dofile("src/storage.lua")
local Grading = dofile("src/grading.lua")

local config = Config.normalize({})

H.assert_equal(config.grading.time_scale, "arcade", "default time scale")
H.assert_equal(Grading.duration_for(config, "standard"), 600, "arcade standard duration")
H.assert_equal(Grading.duration_for(config, "express"), 60, "arcade express duration")
H.assert_equal(Grading.duration_for(config), 600, "default service duration")
H.assert_equal(Grading.duration_for(config, "prescreen"), nil, "prescreen is not a grading submission service")

local hobby_config = Config.normalize({ grading = { time_scale = "hobbyist" } })
H.assert_equal(Grading.duration_for(hobby_config, "standard"), 28800, "hobbyist standard duration")

local mint_condition = {
    centering = 9.8,
    print_quality = 9.8,
    corners = 9.8,
    edges = 9.7,
    surface = 9.9
}
local near_mint_condition = {
    centering = 9.2,
    print_quality = 9.1,
    corners = 9.3,
    edges = 9.0,
    surface = 9.4
}

local state = Storage.normalize({ currency_g = 100 })
local card = Storage.add_raw_card(state, {
    center_key = "j_joker",
    local_key = "joker",
    series_key = "BALATRO Series",
    mod_id = "Balatro",
    rarity = "common",
    edition = "base",
    condition = mint_condition
})

H.assert_equal(Grading.fee_for(config, card), 15, "common base fee hits minimum")

local missing = Grading.submit(config, state, { card_id = "grdl_999", now = 1000 })
H.assert_equal(missing.ok, false, "unknown card rejected")
H.assert_equal(missing.reason, "card_not_found", "unknown card reason")
H.assert_equal(state.currency_g, 100, "unknown card does not charge")

local bad_service = Grading.submit(config, state, { card_id = card.id, service = "warp", now = 1000 })
H.assert_equal(bad_service.ok, false, "unknown service rejected")
H.assert_equal(bad_service.reason, "unknown_service", "unknown service reason")
H.assert_equal(state.currency_g, 100, "unknown service does not charge")
H.assert_equal(card.status, "raw", "unknown service keeps card raw")
H.assert_equal(#state.grading_queue, 0, "unknown service keeps queue empty")

local poor_state = Storage.normalize({ currency_g = 5 })
local poor_card = Storage.add_raw_card(poor_state, {
    center_key = "j_joker",
    local_key = "joker",
    rarity = "common",
    edition = "base",
    condition = mint_condition
})
local broke = Grading.submit(config, poor_state, { card_id = poor_card.id, now = 1000 })
H.assert_equal(broke.ok, false, "insufficient funds rejected")
H.assert_equal(broke.reason, "insufficient_funds", "insufficient funds reason")
H.assert_equal(broke.fee, 15, "insufficient funds reports fee")
H.assert_equal(poor_state.currency_g, 5, "insufficient funds keeps currency")
H.assert_equal(poor_card.status, "raw", "insufficient funds keeps card raw")
H.assert_equal(#poor_state.grading_queue, 0, "insufficient funds keeps queue empty")

local submitted = Grading.submit(config, state, { card_id = card.id, now = 1000 })
H.assert_equal(submitted.ok, true, "submit succeeds")
H.assert_equal(submitted.fee, 15, "submit fee charged")
H.assert_equal(state.currency_g, 85, "submit deducts fee")
H.assert_equal(card.status, "queued", "submit queues card")
H.assert_equal(#state.grading_queue, 1, "queue entry stored")
H.assert_equal(state.grading_queue[1].card_id, card.id, "queue entry card id")
H.assert_equal(state.grading_queue[1].service, "standard", "queue entry default service")
H.assert_equal(state.grading_queue[1].submitted_at, 1000, "queue entry submitted time")
H.assert_equal(state.grading_queue[1].due_at, 1600, "queue entry due time")

local resubmit = Grading.submit(config, state, { card_id = card.id, now = 1001 })
H.assert_equal(resubmit.ok, false, "queued card cannot resubmit")
H.assert_equal(resubmit.reason, "not_raw", "queued resubmit reason")
H.assert_equal(state.currency_g, 85, "queued resubmit does not charge")
H.assert_equal(#state.grading_queue, 1, "queued resubmit keeps queue")

local rows = Grading.queue_rows(state, 1300)
H.assert_equal(#rows, 1, "queue row listed")
H.assert_equal(rows[1].card_id, card.id, "queue row card id")
H.assert_equal(rows[1].name_key, "joker", "queue row name key")
H.assert_equal(rows[1].edition, "base", "queue row edition")
H.assert_equal(rows[1].service, "standard", "queue row service")
H.assert_equal(rows[1].remaining, 300, "queue row remaining time")
H.assert_equal(rows[1].ready, false, "queue row not ready")
H.assert_equal(rows[1].submitted_at, 1000, "queue row submitted time")
H.assert_near(rows[1].progress, 0.5, 0.000001, "queue row halfway progress")
H.assert_near(Grading.queue_rows(state, 1000)[1].progress, 0, 0.000001, "queue row zero progress at submit")
local ready_row = Grading.queue_rows(state, 1600)[1]
H.assert_equal(ready_row.ready, true, "queue row ready at due time")
H.assert_near(ready_row.progress, 1, 0.000001, "queue row full progress when ready")
H.assert_near(Grading.queue_rows(state, 9999)[1].progress, 1, 0.000001, "queue row progress clamps at one")

local early = Grading.process_due(config, state, 1599)
H.assert_equal(#early.revealed, 0, "nothing revealed before due")
H.assert_equal(early.remaining, 1, "entry stays before due")
H.assert_equal(card.status, "queued", "card stays queued before due")

local done = Grading.process_due(config, state, 1600)
H.assert_equal(#done.revealed, 1, "due entry revealed")
H.assert_equal(done.remaining, 0, "no entries remain")
H.assert_equal(#state.grading_queue, 0, "queue emptied")
H.assert_equal(card.status, "graded", "card graded")
H.assert_equal(card.grade, 10, "mint condition reveals grade 10")
H.assert_equal(card.cert_number, "000001", "first cert number")
H.assert_equal(card.graded_at, 1600, "graded timestamp uses due time")
H.assert_equal(card.grade_service, "standard", "grade service recorded")

local graded_resubmit = Grading.submit(config, state, { card_id = card.id, now = 1700 })
H.assert_equal(graded_resubmit.ok, false, "graded card cannot resubmit")
H.assert_equal(graded_resubmit.reason, "not_raw", "graded resubmit reason")

Storage.add_currency(state, 1000)
local second = Storage.add_raw_card(state, {
    center_key = "j_rare",
    local_key = "rare_joker",
    rarity = "rare",
    edition = "negative",
    condition = near_mint_condition
})
local express = Grading.submit(config, state, { card_id = second.id, service = "express", now = 2000 })
H.assert_equal(express.ok, true, "express submit succeeds")
H.assert_equal(express.fee, 495, "rare negative express fee")
H.assert_equal(state.grading_queue[1].due_at, 2060, "express due time")

local second_done = Grading.process_due(config, state, 2060)
H.assert_equal(#second_done.revealed, 1, "second reveal")
H.assert_equal(second.grade, 9, "near mint condition reveals grade 9")
H.assert_equal(second.cert_number, "000002", "cert numbers increment")

print("grading tests ok")
