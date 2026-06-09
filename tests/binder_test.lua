local H = dofile("tests/test_helper.lua")
local Storage = dofile("src/storage.lua")
local Binder = dofile("src/binder.lua")

local state = Storage.normalize({
    currency_g = 123,
    grading_queue = {
        { card_id = "grdl_2" }
    },
    cards = {
        {
            id = "grdl_1",
            status = "raw",
            center_key = "j_joker",
            local_key = "joker",
            edition = "base",
            acquired_at = 1000
        },
        {
            id = "grdl_2",
            status = "graded",
            center_key = "j_greedy_joker",
            local_key = "greedy_joker",
            edition = "negative",
            grade = 10,
            acquired_at = 2000
        },
        {
            id = "grdl_3",
            status = "lost",
            center_key = "j_lost",
            local_key = "lost",
            edition = "foil",
            acquired_at = 1500
        }
    }
})

local summary = Binder.summary(state)
H.assert_equal(summary.currency_g, 123, "summary currency")
H.assert_equal(summary.total_cards, 3, "summary total")
H.assert_equal(summary.owned_cards, 2, "summary owned count")
H.assert_equal(summary.raw_cards, 1, "summary raw count")
H.assert_equal(summary.graded_cards, 1, "summary graded count")
H.assert_equal(summary.grading_queue, 1, "summary grading queue")

local rows = Binder.card_rows(state, { include_lost = false })
H.assert_equal(#rows, 2, "lost cards hidden by default")
H.assert_equal(rows[1].id, "grdl_2", "newer acquired card first")
H.assert_equal(rows[1].name_key, "greedy_joker", "row name key")
H.assert_equal(rows[1].edition, "negative", "row edition")
H.assert_equal(rows[1].status_key, "grdl_k_status_graded", "graded status key")
H.assert_equal(rows[2].status_key, "grdl_k_status_raw", "raw status key")

local limited = Binder.card_rows(state, { limit = 1 })
H.assert_equal(#limited, 1, "limit applied")

local empty = Binder.summary(Storage.normalize({}))
H.assert_equal(empty.total_cards, 0, "empty total")
H.assert_equal(#Binder.card_rows(Storage.normalize({})), 0, "empty rows")

print("binder tests ok")
