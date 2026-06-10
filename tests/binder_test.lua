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
            rarity = "rare",
            grade = 10,
            cert_number = "000001",
            acquired_at = 2000,
            acquired_year = 2026,
            acquired_month = 6,
            acquired_day = 10,
            acquired_price = 149
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

local view = Binder.entries(state)
H.assert_equal(#view.entries, 2, "lost cards hidden")
H.assert_equal(view.hidden, 0, "nothing hidden without centers")
H.assert_equal(view.entries[1].id, "grdl_2", "newer acquired card first")
H.assert_equal(view.entries[1].name_key, "greedy_joker", "entry name key")
H.assert_equal(view.entries[1].edition, "negative", "entry edition")
H.assert_equal(view.entries[1].status_key, "grdl_k_status_graded", "graded status key")
H.assert_equal(view.entries[1].grade, 10, "entry grade")
H.assert_equal(view.entries[1].cert_number, "000001", "entry cert number")
H.assert_equal(view.entries[1].acquired_year, 2026, "entry acquired year")
H.assert_equal(view.entries[1].acquired_month, 6, "entry acquired month")
H.assert_equal(view.entries[1].acquired_day, 10, "entry acquired day")
H.assert_equal(view.entries[1].acquired_price, 149, "entry acquired price")
H.assert_equal(view.entries[1].rarity, "rare", "entry rarity")
H.assert_equal(view.entries[2].status_key, "grdl_k_status_raw", "raw status key")

local filtered = Binder.entries(state, {
    centers = { j_joker = { key = "j_joker" } }
})
H.assert_equal(#filtered.entries, 1, "missing centers excluded")
H.assert_equal(filtered.entries[1].id, "grdl_1", "loaded center kept")
H.assert_equal(filtered.hidden, 1, "hidden count reported")

local many = {}
for i = 1, 13 do
    many[#many + 1] = { id = "e" .. tostring(i) }
end
local page_one = Binder.page(many, 1, 5)
H.assert_equal(page_one.pages, 3, "page count")
H.assert_equal(page_one.total, 13, "page total")
H.assert_equal(#page_one.items, 5, "first page full")
H.assert_equal(page_one.items[1].id, "e1", "first page starts at one")
local page_three = Binder.page(many, 3, 5)
H.assert_equal(#page_three.items, 3, "last page remainder")
H.assert_equal(page_three.items[1].id, "e11", "last page offset")
H.assert_equal(Binder.page(many, 99, 5).page, 3, "page clamps high")
H.assert_equal(Binder.page(many, 0, 5).page, 1, "page clamps low")
local empty_page = Binder.page({}, 1, 5)
H.assert_equal(empty_page.pages, 1, "empty collection still one page")
H.assert_equal(empty_page.total, 0, "empty total")

local desk = Binder.desk_rows(state)
H.assert_equal(#desk, 1, "desk lists raw cards only")
H.assert_equal(desk[1].id, "grdl_1", "desk raw card id")
H.assert_equal(desk[1].name_key, "joker", "desk name key")

local empty = Binder.summary(Storage.normalize({}))
H.assert_equal(empty.total_cards, 0, "empty total")
H.assert_equal(#Binder.entries(Storage.normalize({})).entries, 0, "empty entries")

print("binder tests ok")
